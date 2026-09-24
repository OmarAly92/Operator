package ptyhost

import (
	"context"
	"os"
	"testing"

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
