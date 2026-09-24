package ptyhost

import (
	"bytes"
	"context"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

func newMirror(t *testing.T, cols, rows int) *vtwasm.Parser {
	t.Helper()
	parser, err := vtwasm.New(context.Background(), vtwasm.Module, uint32(cols), uint32(rows), vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	t.Cleanup(func() { _ = parser.Close() })
	return parser
}

func startServeWithHistory(t *testing.T, pid, cols, rows int, parser *vtwasm.Parser, path string, interval time.Duration, maxBytes int) *serveFixture {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	pty := newFakePTY(pid)
	ring := NewRing()
	ctx, cancel := context.WithCancel(context.Background())
	h := newHost(ctx, ServeConfig{
		SessionID:       fmt.Sprintf("test-%d", pid),
		Listener:        ln,
		PTY:             pty,
		Ring:            ring,
		Parser:          parser,
		InitialCols:     cols,
		InitialRows:     rows,
		HistoryPath:     path,
		PersistInterval: interval,
		HistoryMaxBytes: maxBytes,
	})
	done := make(chan error, 1)
	go func() {
		done <- h.run(ctx)
	}()
	t.Cleanup(cancel)
	return &serveFixture{pty: pty, ring: ring, ln: ln, addr: ln.Addr().String(), cancel: cancel, done: done, host: h}
}

func waitForHistoryFile(t *testing.T, path, want string) []byte {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		data, err := os.ReadFile(path)
		if err == nil && bytes.Contains(data, []byte(want)) {
			return data
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("history file %s never contained %q", path, want)
	return nil
}

func renderedRows(t *testing.T, stream string, cols, rows int) []string {
	t.Helper()
	mirror := newMirror(t, cols, rows)
	if err := mirror.Feed([]byte(stream)); err != nil {
		t.Fatalf("feed: %v", err)
	}
	rendered, err := mirror.RenderTail(200_000)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	return strings.Split(strings.TrimRight(rendered, "\n"), "\n")
}

func TestAPeriodicallyPersistedHistoryReopensInAFreshHost(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sess.vt")
	first := startServeWithHistory(t, 4201, 20, 4, newMirror(t, 20, 4), path, 20*time.Millisecond, 0)
	for i := 0; i < 1500; i++ {
		writeOutput(t, first, fmt.Sprintf("old %04d\r\n", i))
	}
	waitForParsedOutput(t, first, "old 1499")
	crashed := waitForHistoryFile(t, path, "old 1499")
	saved := filepath.Join(dir, "saved.vt")
	if err := os.WriteFile(saved, crashed, 0o600); err != nil {
		t.Fatalf("copy the file the host left behind: %v", err)
	}
	first.cancel()
	first.waitDone(t)

	parser := newMirror(t, 20, 4)
	seeded, err := seedMirror(parser, saved)
	if err != nil || !seeded {
		t.Fatalf("seedMirror = (%v, %v), want (true, nil)", seeded, err)
	}
	second := startServeWithHistory(t, 4202, 20, 4, parser, filepath.Join(dir, "second.vt"), 0, 0)
	writeOutput(t, second, "new child\r\n")
	waitForParsedOutput(t, second, "new child")

	c := newTestClient(t, second.addr)
	defer c.close()
	sendResizeWithHistory(t, c, 20, 4, true)
	stream := ""
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) && !strings.Contains(stream, "old 0000") {
		typ, payload := c.readFrame(t)
		if typ == MsgTerminalData {
			stream += string(payload)
		}
	}
	rows := renderedRows(t, stream, 20, 4)
	if !strings.Contains(rows[0], "old 0000") {
		t.Fatalf("the reopened pane does not start with the oldest saved row; first row = %q", rows[0])
	}
	joined := strings.Join(rows, "\n")
	oldest := strings.Index(joined, "old 1499")
	newest := strings.Index(joined, "new child")
	if oldest < 0 || newest < 0 || oldest > newest {
		t.Fatalf("want the saved history above the new child's output; rows:\n%s", joined)
	}
}

func TestAPersistedHistoryStaysUnderItsByteCap(t *testing.T) {
	const limit = 40 << 10
	path := filepath.Join(t.TempDir(), "sess.vt")
	f := startServeWithHistory(t, 4203, 80, 24, newMirror(t, 80, 24), path, 0, limit)
	for i := 0; i < 3000; i++ {
		writeOutput(t, f, fmt.Sprintf("line %04d\r\n", i))
	}
	waitForParsedOutput(t, f, "line 2999")
	f.host.persistHistory()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read history: %v", err)
	}
	if len(data) > limit {
		t.Fatalf("history file is %d bytes, over the %d-byte cap", len(data), limit)
	}
	if !bytes.HasPrefix(data, []byte(historyMagic)) {
		t.Fatalf("history file does not start with %q", historyMagic)
	}
	if !bytes.Contains(data, []byte("line 2999")) {
		t.Fatal("the cap dropped the newest row")
	}
	if bytes.Contains(data, []byte("line 0000")) {
		t.Fatal("the cap kept the oldest row; it must drop the oldest history first")
	}
}

func TestPersistWritesOnlyWhenTheMirrorChanged(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sess.vt")
	f := startServeWithHistory(t, 4204, 20, 4, newMirror(t, 20, 4), path, 0, 0)
	writeOutput(t, f, "first\r\n")
	waitForParsedOutput(t, f, "first")
	f.host.persistHistory()
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("first persist wrote nothing: %v", err)
	}
	if err := os.Remove(path); err != nil {
		t.Fatalf("remove: %v", err)
	}
	f.host.persistHistory()
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("persist rewrote an unchanged mirror (stat err = %v)", err)
	}
	writeOutput(t, f, "second\r\n")
	waitForParsedOutput(t, f, "second")
	f.host.persistHistory()
	waitForHistoryFile(t, path, "second")
}

func TestShutdownPersistsTheLatestHistory(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sess.vt")
	f := startServeWithHistory(t, 4205, 20, 4, newMirror(t, 20, 4), path, 0, 0)
	writeOutput(t, f, "last words\r\n")
	waitForParsedOutput(t, f, "last words")
	f.cancel()
	f.waitDone(t)
	waitForHistoryFile(t, path, "last words")
}

func TestSeedMirrorWithoutAFileIsANoOp(t *testing.T) {
	parser := newMirror(t, 20, 4)
	seeded, err := seedMirror(parser, filepath.Join(t.TempDir(), "missing.vt"))
	if seeded || err != nil {
		t.Fatalf("seedMirror(missing) = (%v, %v), want (false, nil)", seeded, err)
	}
}

func TestSeedMirrorRejectsAFileWithoutTheHeader(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sess.vt")
	if err := os.WriteFile(path, []byte("not a history file\r\n"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	parser := newMirror(t, 20, 4)
	seeded, err := seedMirror(parser, path)
	if seeded || err == nil {
		t.Fatalf("seedMirror(no header) = (%v, %v), want (false, error)", seeded, err)
	}
	tail, err := parser.RenderTail(10)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if strings.Contains(tail, "not a history file") {
		t.Fatalf("a file without the header reached the mirror: %q", tail)
	}
}

func TestPrepareHistorySeedsTheMirrorFromTheSessionFile(t *testing.T) {
	isolateRegistry(t)
	path, err := historyPath("sess-seed")
	if err != nil {
		t.Fatalf("historyPath: %v", err)
	}
	if err := writeHistoryFile(path, []byte(historyMagic+"hello from before\r\n")); err != nil {
		t.Fatalf("write history: %v", err)
	}
	parser := newMirror(t, 40, 5)
	if got := prepareHistory("sess-seed", parser); got != path {
		t.Fatalf("prepareHistory path = %q, want %q", got, path)
	}
	tail, err := parser.RenderTail(10)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if !strings.Contains(tail, "hello from before") {
		t.Fatalf("the mirror was not seeded; tail = %q", tail)
	}
	if got := prepareHistory("sess-seed", nil); got != "" {
		t.Fatalf("prepareHistory without a parser = %q, want no persistence", got)
	}
}

func TestPruneHistoryRemovesOnlyOldFilesOfGoneHosts(t *testing.T) {
	isolateRegistry(t)
	dir, err := historyDir()
	if err != nil {
		t.Fatalf("historyDir: %v", err)
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	now := time.Now()
	old := now.Add(-historyRetention - time.Hour)
	files := map[string]time.Time{
		"gone-old.vt":     old,
		"live-old.vt":     old,
		"gone-new.vt":     now,
		"gone-old.vt.tmp": old,
		"notes.txt":       old,
	}
	for name, mtime := range files {
		full := filepath.Join(dir, name)
		if err := os.WriteFile(full, []byte(historyMagic), 0o600); err != nil {
			t.Fatalf("write %s: %v", name, err)
		}
		if err := os.Chtimes(full, mtime, mtime); err != nil {
			t.Fatalf("chtimes %s: %v", name, err)
		}
	}
	if err := pruneHistory(now, func(id string) bool { return id == "live-old" }); err != nil {
		t.Fatalf("pruneHistory: %v", err)
	}
	for name, wantKept := range map[string]bool{
		"gone-old.vt":     false,
		"gone-old.vt.tmp": false,
		"live-old.vt":     true,
		"gone-new.vt":     true,
		"notes.txt":       true,
	} {
		_, err := os.Stat(filepath.Join(dir, name))
		if kept := err == nil; kept != wantKept {
			t.Fatalf("%s kept = %v, want %v", name, kept, wantKept)
		}
	}
}
