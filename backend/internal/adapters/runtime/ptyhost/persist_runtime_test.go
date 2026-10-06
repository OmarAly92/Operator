package ptyhost

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func seedHistoryFile(t *testing.T, sessionID string) string {
	t.Helper()
	path, err := historyPath(sessionID)
	if err != nil {
		t.Fatalf("historyPath: %v", err)
	}
	if err := writeHistoryFile(path, []byte(historyMagic+"from an earlier host\r\n")); err != nil {
		t.Fatalf("write history: %v", err)
	}
	return path
}

func TestCreateDropsAStaleHistoryForAFreshSession(t *testing.T) {
	isolateRegistry(t)
	path := seedHistoryFile(t, "sess-fresh")
	hosts := map[string]*inProcHost{}
	rt := New(Options{Spawner: fakeSpawnerFor(t, hosts, livePID())})
	if _, err := rt.Create(context.Background(), ports.RuntimeConfig{
		SessionID:     domain.SessionID("sess-fresh"),
		WorkspacePath: t.TempDir(),
		Argv:          []string{"sh"},
	}); err != nil {
		t.Fatalf("Create: %v", err)
	}
	defer hosts["sess-fresh"].cleanup(t)
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("a fresh session kept another host's history (stat err = %v)", err)
	}
}

func TestCreateKeepsTheHistoryOfARestoredSession(t *testing.T) {
	isolateRegistry(t)
	path := seedHistoryFile(t, "sess-restored")
	hosts := map[string]*inProcHost{}
	rt := New(Options{Spawner: fakeSpawnerFor(t, hosts, livePID())})
	if _, err := rt.Create(context.Background(), ports.RuntimeConfig{
		SessionID:      domain.SessionID("sess-restored"),
		WorkspacePath:  t.TempDir(),
		Argv:           []string{"sh"},
		RestoreHistory: true,
	}); err != nil {
		t.Fatalf("Create: %v", err)
	}
	defer hosts["sess-restored"].cleanup(t)
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("a restored session lost its history before its host could read it: %v", err)
	}
}

func TestPruneStaleHistoryKeepsAnInFlightSessionNotYetRegistered(t *testing.T) {
	isolateRegistry(t)
	rt := New(Options{})
	rt.mu.Lock()
	rt.sessions["in-flight"] = nil
	rt.mu.Unlock()
	path, err := historyPath("in-flight")
	if err != nil {
		t.Fatalf("historyPath: %v", err)
	}
	if err := writeHistoryFile(path, []byte(historyMagic+"old\r\n")); err != nil {
		t.Fatalf("write history: %v", err)
	}
	old := time.Now().Add(-historyRetention - time.Hour)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Fatalf("chtimes: %v", err)
	}

	rt.pruneStaleHistory(time.Now(), "other-session")

	if _, err := os.Stat(path); err != nil {
		t.Fatalf("a concurrently relaunching session's history was pruned before it could be registered: %v", err)
	}
}

func TestARelaunchedHostSeededThroughPrepareHistoryReplaysOldRowsBeforeNewOutput(t *testing.T) {
	isolateRegistry(t)
	const sessionID = "sess-prepared"
	wantPath, err := historyPath(sessionID)
	if err != nil {
		t.Fatalf("historyPath: %v", err)
	}
	if err := writeHistoryFile(wantPath, []byte(historyMagic+"old 0000\r\nold 0001\r\n")); err != nil {
		t.Fatalf("write history: %v", err)
	}

	parser := newMirror(t, 20, 4)
	gotPath := prepareHistory(sessionID, parser)
	if gotPath != wantPath {
		t.Fatalf("prepareHistory path = %q, want %q", gotPath, wantPath)
	}

	f := startServeWithHistory(t, 4211, 20, 4, parser, filepath.Join(t.TempDir(), "unused.vt"), 0, 0)
	writeOutput(t, f, "new child\r\n")
	waitForParsedOutput(t, f, "new child")

	c := newTestClient(t, f.addr)
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
		t.Fatalf("replay through the real RunHost seeding path does not start with the seeded row; first row = %q", rows[0])
	}
	joined := strings.Join(rows, "\n")
	oldest := strings.Index(joined, "old 0001")
	newest := strings.Index(joined, "new child")
	if oldest < 0 || newest < 0 || oldest > newest {
		t.Fatalf("want the prepareHistory-seeded rows above the new child's output; rows:\n%s", joined)
	}
}
