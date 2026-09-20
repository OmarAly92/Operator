package ptyhost

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

const readyMark = "\x1b]7000;v=1;ready=1\x1b\\"

// startServeParsed is startServe with a live vt parser, which is what a real
// session always has. The parser's grid — not the output ring — is what a
// connecting client is replayed from.
func startServeParsed(t *testing.T, pid, cols, rows int) *serveFixture {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	parser, err := vtwasm.New(context.Background(), vtwasm.Module, uint32(cols), uint32(rows), vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	t.Cleanup(func() { _ = parser.Close() })

	pty := newFakePTY(pid)
	ring := NewRing()
	ctx, cancel := context.WithCancel(context.Background())
	h := newHost(ctx, ServeConfig{
		SessionID:   fmt.Sprintf("test-%d", pid),
		Listener:    ln,
		PTY:         pty,
		Ring:        ring,
		Parser:      parser,
		InitialCols: cols,
		InitialRows: rows,
	})
	done := make(chan error, 1)
	go func() {
		done <- h.run(ctx)
	}()
	return &serveFixture{pty: pty, ring: ring, ln: ln, addr: ln.Addr().String(), cancel: cancel, done: done, host: h}
}

// writeOutput pushes PTY output and waits for the host to have parsed it.
func writeOutput(t *testing.T, f *serveFixture, s string) {
	t.Helper()
	if _, err := f.pty.WriteOutput([]byte(s)); err != nil {
		t.Fatalf("write pty output: %v", err)
	}
}

// readReplay returns the payload of the first MsgTerminalData frame.
func readReplay(t *testing.T, c *testClient) string {
	t.Helper()
	for {
		typ, payload := c.readFrame(t)
		if typ == MsgTerminalData {
			return string(payload)
		}
	}
}

// A client that attaches at a DIFFERENT grid than the one the session last ran
// at must be replayed the current screen once. Replaying the raw output ring
// re-emitted every in-place redraw the child had ever done; at the new
// geometry those redraws no longer overwrote each other, so each stale frame
// survived on screen — the duplicated-output bug when reopening an old session.
func TestAttachReplayDoesNotDuplicateRedrawnFrames(t *testing.T) {
	f := startServeParsed(t, 700, 40, 10)
	defer f.cancel()

	// A child that draws a banner, then redraws its footer in place — the
	// shape of every TUI agent UI.
	writeOutput(t, f, "banner\r\nfooter one")
	writeOutput(t, f, "\r\x1b[Kfooter two")
	waitForParsedOutput(t, f, "footer two")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 100, 30)

	replay := readReplay(t, c)
	if strings.Contains(replay, "footer one") {
		t.Fatalf("replay re-emitted an overwritten frame:\n%q", replay)
	}
	if n := strings.Count(replay, "footer two"); n != 1 {
		t.Fatalf("want one copy of the live footer, got %d:\n%q", n, replay)
	}
	if n := strings.Count(replay, "banner"); n != 1 {
		t.Fatalf("want one copy of the banner, got %d:\n%q", n, replay)
	}
}

// The replay is only faithful at the geometry it was rendered for, so the
// client's opening grid must reach the PTY (and the parser) before the
// snapshot is taken — never after, which is what left the client holding a
// stale-geometry paint plus the child's SIGWINCH repaint of the same screen.
func TestAttachAppliesOpeningGridBeforeReplaying(t *testing.T) {
	f := startServeParsed(t, 701, 40, 10)
	defer f.cancel()

	writeOutput(t, f, "hello\r\n")
	waitForParsedOutput(t, f, "hello")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 100, 30)

	_ = readReplay(t, c)
	resizes := f.pty.resizeSnapshot()
	if len(resizes) == 0 {
		t.Fatal("the opening grid never reached the PTY")
	}
	if got := resizes[0]; got.Cols != 100 || got.Rows != 30 {
		t.Fatalf("first PTY resize = %dx%d, want 100x30", got.Cols, got.Rows)
	}
}

// A client that never states a grid still has to be replayed; it just gets the
// host's current one.
func TestAttachReplaysAClientThatNeverResizes(t *testing.T) {
	f := startServeParsed(t, 702, 40, 10)
	defer f.cancel()

	writeOutput(t, f, "quiet client\r\n")
	waitForParsedOutput(t, f, "quiet client")

	c := newTestClient(t, f.addr)
	defer c.close()

	if replay := readReplay(t, c); !strings.Contains(replay, "quiet client") {
		t.Fatalf("replay = %q, want the current screen", replay)
	}
}

func sendResize(t *testing.T, c *testClient, cols, rows int) {
	t.Helper()
	payload, err := json.Marshal(ResizePayload{Cols: cols, Rows: rows})
	if err != nil {
		t.Fatalf("marshal resize: %v", err)
	}
	if err := c.send(MsgResize, payload); err != nil {
		t.Fatalf("send resize: %v", err)
	}
}

func sendResizeWithHistory(t *testing.T, c *testClient, cols, rows int, history bool) {
	t.Helper()
	payload, err := json.Marshal(ResizePayload{Cols: cols, Rows: rows, History: history})
	if err != nil {
		t.Fatalf("marshal resize: %v", err)
	}
	if err := c.send(MsgResize, payload); err != nil {
		t.Fatalf("send resize: %v", err)
	}
}

// A reattaching client must be able to paint as soon as it has the frame.
// The handshake therefore returns at READY, and the history that follows
// arrives on the live stream behind it.
func TestClientPaintsAtReadyBeforeHistory(t *testing.T) {
	f := startServeParsed(t, 710, 20, 4)
	defer f.cancel()

	const rowCount = 1010
	for i := 0; i < rowCount; i++ {
		writeOutput(t, f, fmt.Sprintf("row %04d\r\n", i))
	}
	lastRow := fmt.Sprintf("row %04d", rowCount-1)
	firstRow := fmt.Sprintf("row %04d", 0)
	waitForParsedOutput(t, f, lastRow)

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResizeWithHistory(t, c, 20, 4, true)

	first := readReplay(t, c)
	if !strings.HasPrefix(first, "\x1b]7000;v=1;origin=") {
		t.Fatalf("the first terminal frame does not open with the origin mark:\n%q", first)
	}
	if !strings.HasSuffix(first, readyMark) {
		t.Fatalf("the first terminal frame is not a READY-terminated replay:\n%q", first)
	}
	if strings.Contains(first, "history=") {
		t.Fatalf("history was packed into the frame the client paints:\n%q", first)
	}

	stream := first
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) && !strings.Contains(stream, firstRow) {
		typ, payload := c.readFrame(t)
		if typ == MsgTerminalData {
			stream += string(payload)
		}
	}
	if !strings.Contains(stream, "\x1b]7000;v=1;history=") {
		t.Fatalf("no history chunk followed the replay:\n%q", stream)
	}

	// End to end: the whole stream, fed to a fresh core, must reconstruct the
	// session with the first row at the top. "A chunk arrived" is not the
	// property under test — "the chunks were prepended" is.
	mirror, err := vtwasm.New(context.Background(), vtwasm.Module, 20, 4, vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new mirror: %v", err)
	}
	defer mirror.Close()
	if err := mirror.Feed([]byte(stream)); err != nil {
		t.Fatalf("feed the replay stream: %v", err)
	}
	rendered, err := mirror.RenderTail(200_000)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	rows := strings.Split(strings.TrimRight(rendered, "\n"), "\n")
	if len(rows) == 0 || !strings.Contains(rows[0], firstRow) {
		t.Fatalf("the replayed history was not prepended; first row = %q", rows[0])
	}
	if !strings.Contains(rows[len(rows)-1], lastRow) {
		t.Fatalf("the live frame did not stay at the bottom; last row = %q", rows[len(rows)-1])
	}
}

// A client that does not ask for history gets exactly today's attach. The
// mobile build renders with an xterm fork that would print the rows.
func TestAClientWithoutHistoryOptInGetsNoChunks(t *testing.T) {
	f := startServeParsed(t, 712, 20, 4)
	defer f.cancel()

	for i := 0; i < 60; i++ {
		writeOutput(t, f, fmt.Sprintf("row %02d\r\n", i))
	}
	waitForParsedOutput(t, f, "row 59")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 20, 4)

	replay := readReplay(t, c)
	if strings.Contains(replay, "history=") {
		t.Fatalf("a client that did not opt in was sent history:\n%q", replay)
	}
	writeOutput(t, f, "live after attach\r\n")
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		typ, payload := c.readFrame(t)
		if typ != MsgTerminalData {
			continue
		}
		if strings.Contains(string(payload), "history=") {
			t.Fatalf("a history chunk reached a client that did not opt in:\n%q", payload)
		}
		if strings.Contains(string(payload), "live after attach") {
			return
		}
	}
	t.Fatal("the live byte that proves nothing else was queued first never arrived")
}

// A fresh session whose mirror holds less than one replayed frame must attach
// exactly as it does today: one frame, no history, nothing else.
func TestAFreshSessionAttachIsUnchanged(t *testing.T) {
	f := startServeParsed(t, 711, 80, 24)
	defer f.cancel()

	writeOutput(t, f, "hello\r\n")
	waitForParsedOutput(t, f, "hello")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 80, 24)

	replay := readReplay(t, c)
	if !strings.Contains(replay, "hello") {
		t.Fatalf("replay = %q, want the current screen", replay)
	}
	if strings.Contains(replay, "history=") {
		t.Fatalf("a fresh session sent a history chunk:\n%q", replay)
	}
}

func waitForParsedOutput(t *testing.T, f *serveFixture, want string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if strings.Contains(string(f.ring.Snapshot()), want) {
			return
		}
		time.Sleep(2 * time.Millisecond)
	}
	// The ring only stores completed lines, so a partial tail never lands;
	// give the pump a beat instead.
	time.Sleep(50 * time.Millisecond)
}

// The wrap-dependent case, which is the one users hit: the child's redraw
// counts rows that only exist because its output WRAPPED at the session's
// width. Replayed as raw bytes into a wider grid the line no longer wraps, the
// cursor-up overshoots, and the frame it meant to overwrite survives above the
// new one — two copies of the same UI, the top one mangled.
func TestAttachReplaySurvivesAWidthChangeUnderWrappedRedraws(t *testing.T) {
	f := startServeParsed(t, 703, 20, 10)
	defer f.cancel()

	// 30 columns of text on a 20-column grid: one logical line, two rows.
	writeOutput(t, f, "STALE_AAAAAAAAAAAAAAAAAAAAAAAA\r\n")
	// The child redraws that line in place, as a TUI footer does.
	writeOutput(t, f, "\x1b[2A\rFRESH_BBBBBBBBBBBBBBBBBBBBBBBB\x1b[J\r\n")
	waitForParsedOutput(t, f, "FRESH")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 100, 30)

	replay := readReplay(t, c)
	if strings.Contains(replay, "STALE") {
		t.Fatalf("the redrawn-over frame survived the width change:\n%q", replay)
	}
	if n := strings.Count(replay, "FRESH"); n != 1 {
		t.Fatalf("want one copy of the live frame, got %d:\n%q", n, replay)
	}
}
