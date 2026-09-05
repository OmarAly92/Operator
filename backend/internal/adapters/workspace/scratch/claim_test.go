package scratch

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func newProbeWorkspace(t *testing.T) (*Workspace, string) {
	t.Helper()
	root := t.TempDir()
	w, err := New(Options{ManagedRoot: root})
	if err != nil {
		t.Fatalf("new: %v", err)
	}
	return w, w.managedRoot
}

func TestIsSessionIDClaimedFalseForUnusedID(t *testing.T) {
	w, _ := newProbeWorkspace(t)
	claimed, err := w.IsSessionIDClaimed(context.Background(), "scratch-5")
	if err != nil {
		t.Fatalf("probe: %v", err)
	}
	if claimed {
		t.Fatal("want free id, got claimed")
	}
}

func TestIsSessionIDClaimedTrueForLeftoverWorkerDir(t *testing.T) {
	w, root := newProbeWorkspace(t)
	dir := filepath.Join(root, "scratch", "workers", "scratch-5")
	if err := os.MkdirAll(filepath.Join(dir, ".claude"), 0o750); err != nil {
		t.Fatal(err)
	}
	claimed, err := w.IsSessionIDClaimed(context.Background(), "scratch-5")
	if err != nil {
		t.Fatalf("probe: %v", err)
	}
	if !claimed {
		t.Fatal("want claimed for a leftover worker dir, got free")
	}
}

func TestIsSessionIDClaimedTrueForLeftoverOrchestratorDir(t *testing.T) {
	w, root := newProbeWorkspace(t)
	dir := filepath.Join(root, "scratch", "orchestrators", "scratch-7")
	if err := os.MkdirAll(filepath.Join(dir, ".codex"), 0o750); err != nil {
		t.Fatal(err)
	}
	claimed, err := w.IsSessionIDClaimed(context.Background(), "scratch-7")
	if err != nil {
		t.Fatalf("probe: %v", err)
	}
	if !claimed {
		t.Fatal("want claimed for a leftover orchestrator dir, got free")
	}
}

func TestIsSessionIDClaimedIgnoresEmptyDir(t *testing.T) {
	w, root := newProbeWorkspace(t)
	if err := os.MkdirAll(filepath.Join(root, "scratch", "workers", "scratch-5"), 0o750); err != nil {
		t.Fatal(err)
	}
	claimed, err := w.IsSessionIDClaimed(context.Background(), "scratch-5")
	if err != nil {
		t.Fatalf("probe: %v", err)
	}
	if claimed {
		t.Fatal("an empty dir does not block Create, so it must not be claimed")
	}
}

// The probe exists to keep Create from ever seeing a dirty path. A free answer
// must therefore mean Create succeeds, and a claimed answer must mean it fails.
func TestClaimProbeAgreesWithCreate(t *testing.T) {
	w, root := newProbeWorkspace(t)
	dir := filepath.Join(root, "scratch", "workers", "scratch-5")
	if err := os.MkdirAll(filepath.Join(dir, ".claude"), 0o750); err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	cfg := ports.WorkspaceConfig{ProjectID: "scratch", SessionID: "scratch-5", Kind: domain.KindWorker}

	claimed, err := w.IsSessionIDClaimed(ctx, cfg.SessionID)
	if err != nil || !claimed {
		t.Fatalf("probe says free (%v, %v) but Create is about to fail", claimed, err)
	}
	if _, err := w.Create(ctx, cfg); err == nil {
		t.Fatal("want Create to refuse the dirty path")
	}

	free := domain.SessionID("scratch-6")
	claimed, err = w.IsSessionIDClaimed(ctx, free)
	if err != nil {
		t.Fatalf("probe: %v", err)
	}
	if claimed {
		t.Fatal("want scratch-6 free")
	}
	cfg.SessionID = free
	if _, err := w.Create(ctx, cfg); err != nil {
		t.Fatalf("probe said free but Create failed: %v", err)
	}
}

func TestIsSessionIDClaimedRejectsTraversal(t *testing.T) {
	w, _ := newProbeWorkspace(t)
	if _, err := w.IsSessionIDClaimed(context.Background(), "../escape"); err == nil {
		t.Fatal("want a rejection for a traversing session id")
	}
}
