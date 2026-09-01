package daemon

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/ptyregistry"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/sqlitetest"
)

// A pty-host outlives the daemon that spawned it, so a database allocating
// session ids from 1 — a fresh install, a reset data dir, a second instance —
// can hand out an id a live host still holds. This drives the real store
// through the real registry-backed probe: an occupied id must be skipped, not
// handed out.
func TestSessionIDAllocationSkipsIDsHeldByALivePtyHost(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("USERPROFILE", home)

	ctx := context.Background()
	const project = "oprclaim"
	occupied := project + "-1"

	// The test process is its own live host: registering our PID means the
	// registry's dead-PID pruning keeps the entry for the whole run.
	if err := ptyregistry.Register(ptyregistry.Entry{
		SessionID:    occupied,
		PtyHostPID:   os.Getpid(),
		PipePath:     "127.0.0.1:0",
		RegisteredAt: time.Now().UTC().Format(time.RFC3339),
	}); err != nil {
		t.Fatalf("occupy session id %s: %v", occupied, err)
	}

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
	store.SetSessionIDInUse(sessionIDClaimProbe(ptyhost.New(ptyhost.Options{}), testLoggerDiscard()))

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
		t.Fatalf("ID = %q, but a live pty-host already holds that id", rec.ID)
	}
	if rec.ID != domain.SessionID(project+"-2") {
		t.Fatalf("ID = %q, want %s-2", rec.ID, project)
	}
}
