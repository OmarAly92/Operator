package daemon

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/ptyregistry"
	scratchws "github.com/OmarAly92/operator/backend/internal/adapters/workspace/scratch"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
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
	store.SetSessionIDInUse(sessionIDClaimProbe(testLoggerDiscard(), ptyhost.New(ptyhost.Options{})))

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

// The workspace root outlives the database that allocates session numbers. A
// reset or freshly migrated database restarts MAX(num)+1 at 1 while the scratch
// directories from the previous database are still on disk, and Create then
// refuses every one of them as dirty — a spawn that fails identically forever
// because the failed seed row is rolled back and frees the number again. This
// drives the real store through the real scratch adapter: an occupied number
// must be skipped.
func TestSessionIDAllocationSkipsNumbersHeldByAScratchWorkspace(t *testing.T) {
	ctx := context.Background()
	const project = "scratch"

	root := t.TempDir()
	ws, err := scratchws.New(scratchws.Options{ManagedRoot: root})
	if err != nil {
		t.Fatalf("scratch workspace: %v", err)
	}
	// Leftovers from a previous database: numbers 1 and 2 are still on disk.
	for _, leftover := range []string{project + "-1", project + "-2"} {
		dir := filepath.Join(root, project, "workers", leftover)
		if err := os.MkdirAll(filepath.Join(dir, ".claude"), 0o750); err != nil {
			t.Fatalf("seed leftover %s: %v", leftover, err)
		}
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
	store.SetSessionIDInUse(sessionIDClaimProbe(testLoggerDiscard(), ws))

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
	if rec.ID != domain.SessionID(project+"-3") {
		t.Fatalf("ID = %q, want %s-3 — 1 and 2 still have directories on disk", rec.ID, project)
	}

	// The allocated id must actually be usable, which is the whole point.
	if _, err := ws.Create(ctx, ports.WorkspaceConfig{
		ProjectID: domain.ProjectID(project),
		SessionID: rec.ID,
		Kind:      domain.KindWorker,
	}); err != nil {
		t.Fatalf("workspace Create for the allocated id failed: %v", err)
	}
}
