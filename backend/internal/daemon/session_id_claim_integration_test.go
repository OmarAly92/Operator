package daemon

import (
	"context"
	"os/exec"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/tmux"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/sqlitetest"
)

// A tmux server outlives the daemon that populated it, so a database allocating
// session ids from 1 — a fresh install, a reset data dir, a second instance —
// used to hand out a name tmux still held and the spawn died at launch with
// "duplicate session". This drives the real store through the real tmux probe:
// an occupied name must be skipped, not handed out.
func TestSessionIDAllocationSkipsNamesHeldByTheRealTmuxServer(t *testing.T) {
	tmuxBin, err := exec.LookPath("tmux")
	if err != nil {
		t.Skip("tmux unavailable")
	}

	ctx := context.Background()
	const project = "oprclaim"
	occupied := project + "-1"

	if out, err := exec.Command(tmuxBin, "new-session", "-d", "-s", occupied).CombinedOutput(); err != nil {
		t.Fatalf("occupy tmux session %s: %v: %s", occupied, err, out)
	}
	t.Cleanup(func() {
		_ = exec.Command(tmuxBin, "kill-session", "-t", "="+occupied).Run()
	})

	store := sqlitetest.MustOpen(t)
	if err := store.UpsertProject(ctx, domain.ProjectRecord{
		ID:           project,
		DisplayName:  project,
		Path:         t.TempDir(),
		Kind:         domain.ProjectKindScratch,
		RegisteredAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("seed project: %v", err)
	}
	store.SetSessionIDInUse(sessionIDClaimProbe(tmux.New(tmux.Options{}), testLoggerDiscard()))

	rec, err := store.CreateSession(ctx, domain.SessionRecord{
		ProjectID: project,
		Kind:      domain.KindWorker,
		Harness:   domain.HarnessClaudeCode,
		CreatedAt: time.Now().UTC(),
		UpdatedAt: time.Now().UTC(),
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	if rec.ID == domain.SessionID(occupied) {
		t.Fatalf("ID = %q, but tmux already holds that session name", rec.ID)
	}
	if rec.ID != domain.SessionID(project+"-2") {
		t.Fatalf("ID = %q, want %s-2", rec.ID, project)
	}
}
