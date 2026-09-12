package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestCreateSessionSkipsIDsClaimedOutsideTheStore(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "scratch")

	claimed := map[domain.SessionID]bool{"scratch-1": true, "scratch-2": true}
	s.SetSessionIDInUse(func(_ context.Context, id domain.SessionID) bool {
		return claimed[id]
	})

	rec, err := s.CreateSession(ctx, sampleRecord("scratch"))
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	if rec.ID != "scratch-3" {
		t.Fatalf("ID = %q, want scratch-3 (scratch-1 and scratch-2 are claimed elsewhere)", rec.ID)
	}
}

func TestCreateSessionAfterSkippingKeepsNumberingMonotonic(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "scratch")

	claimed := map[domain.SessionID]bool{"scratch-1": true}
	s.SetSessionIDInUse(func(_ context.Context, id domain.SessionID) bool {
		return claimed[id]
	})

	first, err := s.CreateSession(ctx, sampleRecord("scratch"))
	if err != nil {
		t.Fatalf("create first session: %v", err)
	}
	second, err := s.CreateSession(ctx, sampleRecord("scratch"))
	if err != nil {
		t.Fatalf("create second session: %v", err)
	}
	if first.ID != "scratch-2" || second.ID != "scratch-3" {
		t.Fatalf("IDs = %q, %q; want scratch-2, scratch-3", first.ID, second.ID)
	}
}

func TestCreateSessionWithoutProbeUsesNextNum(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "scratch")

	rec, err := s.CreateSession(ctx, sampleRecord("scratch"))
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	if rec.ID != "scratch-1" {
		t.Fatalf("ID = %q, want scratch-1", rec.ID)
	}
}

func TestCreateSession_PersistsSpawnedBy(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "proj-1")

	rec := sampleRecord("proj-1")
	rec.SpawnedBy = "proj-1-1"
	created, err := s.CreateSession(ctx, rec)
	if err != nil {
		t.Fatal(err)
	}
	if created.SpawnedBy != "proj-1-1" {
		t.Fatalf("created.SpawnedBy = %q, want proj-1-1", created.SpawnedBy)
	}

	got, ok, err := s.GetSession(ctx, created.ID)
	if err != nil || !ok {
		t.Fatalf("GetSession: ok=%v err=%v", ok, err)
	}
	if got.SpawnedBy != "proj-1-1" {
		t.Fatalf("GetSession(...).SpawnedBy = %q, want proj-1-1 (round-trip through storage)", got.SpawnedBy)
	}
}

func TestCreateSession_EmptySpawnedByForHumanSpawn(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "proj-1")

	created, err := s.CreateSession(ctx, sampleRecord("proj-1"))
	if err != nil {
		t.Fatal(err)
	}
	if created.SpawnedBy != "" {
		t.Fatalf("SpawnedBy = %q, want empty for a human spawn", created.SpawnedBy)
	}
}

func TestCreateSessionStopsSkippingAfterBoundedAttempts(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "scratch")

	var probes int
	s.SetSessionIDInUse(func(_ context.Context, _ domain.SessionID) bool {
		probes++
		return true
	})

	if _, err := s.CreateSession(ctx, sampleRecord("scratch")); err == nil {
		t.Fatal("create session succeeded, want an error when every candidate ID is claimed")
	}
	if probes > 128 {
		t.Fatalf("probed %d candidates, want a bounded search", probes)
	}
}

func TestMarkSessionPreviewOpenedAdvancesOnlyToCurrentRevision(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "mer")
	rec, err := s.CreateSession(ctx, sampleRecord("mer"))
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	for _, target := range []string{"http://localhost:5173", "http://localhost:5173/?v=2"} {
		if _, err := s.SetSessionPreviewURL(ctx, rec.ID, target, time.Now().UTC()); err != nil {
			t.Fatalf("set preview url %q: %v", target, err)
		}
	}
	stored, ok, err := s.GetSession(ctx, rec.ID)
	if err != nil || !ok {
		t.Fatalf("get session: ok=%v err=%v", ok, err)
	}
	if stored.Metadata.PreviewRevision != 2 || stored.Metadata.PreviewOpenedRevision != 0 {
		t.Fatalf("seed state revision=%d opened=%d, want revision=2 opened=0",
			stored.Metadata.PreviewRevision, stored.Metadata.PreviewOpenedRevision)
	}

	for _, revision := range []int64{1, 3} {
		applied, err := s.MarkSessionPreviewOpened(ctx, rec.ID, revision, time.Now().UTC())
		if err != nil {
			t.Fatalf("mark preview opened %d: %v", revision, err)
		}
		if applied {
			t.Fatalf("stale/future acknowledgement of revision %d matched a row, want zero rows", revision)
		}
	}

	applied, err := s.MarkSessionPreviewOpened(ctx, rec.ID, 2, time.Now().UTC())
	if err != nil {
		t.Fatalf("mark preview opened current revision: %v", err)
	}
	if !applied {
		t.Fatal("acknowledgement of the current revision matched zero rows, want one row updated")
	}

	repeatApplied, err := s.MarkSessionPreviewOpened(ctx, rec.ID, 2, time.Now().UTC())
	if err != nil {
		t.Fatalf("repeat mark preview opened: %v", err)
	}
	if repeatApplied {
		t.Fatal("idempotent repeat matched a row, want zero rows")
	}

	final, ok, err := s.GetSession(ctx, rec.ID)
	if err != nil || !ok {
		t.Fatalf("final get session: ok=%v err=%v", ok, err)
	}
	if final.Metadata.PreviewOpenedRevision != 2 {
		t.Fatalf("persisted preview_opened_revision = %d, want 2", final.Metadata.PreviewOpenedRevision)
	}
	if final.Metadata.PreviewRevision != 2 {
		t.Fatalf("preview_revision changed to %d, want untouched 2", final.Metadata.PreviewRevision)
	}
}

// budgetTestRecord builds a minimally valid session row for the budget-query
// tests below: CreateSession enforces a workspace_mode CHECK constraint that
// the brief's illustrative literals omit, so every fixture here sets it.
func budgetTestRecord(proj domain.ProjectID, kind domain.SessionKind, spawnedBy domain.SessionID, at time.Time) domain.SessionRecord {
	return domain.SessionRecord{
		ProjectID: proj,
		Kind:      kind,
		SpawnedBy: spawnedBy,
		Metadata:  domain.SessionMetadata{WorkspaceMode: domain.WorkspaceModeWorktree},
		CreatedAt: at,
		UpdatedAt: at,
	}
}

func TestCountLiveSessionsByProjectAndKind_CountsOnlyLiveMatchingKind(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "proj-1")
	const proj domain.ProjectID = "proj-1"
	now := time.Now().UTC()

	live, err := s.CreateSession(ctx, budgetTestRecord(proj, domain.KindWorker, "", now))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateSession(ctx, budgetTestRecord(proj, domain.KindOrchestrator, "", now)); err != nil {
		t.Fatal(err)
	}
	terminated, err := s.CreateSession(ctx, budgetTestRecord(proj, domain.KindWorker, "", now))
	if err != nil {
		t.Fatal(err)
	}
	terminated.IsTerminated = true
	if err := s.UpdateSession(ctx, terminated); err != nil {
		t.Fatal(err)
	}

	n, err := s.CountLiveSessionsByProjectAndKind(ctx, proj, domain.KindWorker)
	if err != nil || n != 1 {
		t.Fatalf("n=%d err=%v, want 1 (only %s is live and a worker)", n, err, live.ID)
	}
}

func TestCountSessionsSpawnedBySince_CountsOnlyMatchingSpawnerWithinWindow(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "proj-1")
	const proj domain.ProjectID = "proj-1"
	now := time.Now().UTC()

	inWindow, err := s.CreateSession(ctx, budgetTestRecord(proj, domain.KindWorker, "orch-1", now))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateSession(ctx, budgetTestRecord(proj, domain.KindWorker, "orch-1", now.Add(-2*time.Hour))); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateSession(ctx, budgetTestRecord(proj, domain.KindWorker, "", now)); err != nil {
		t.Fatal(err)
	}

	n, err := s.CountSessionsSpawnedBySince(ctx, proj, "orch-1", now.Add(-time.Hour))
	if err != nil || n != 1 {
		t.Fatalf("n=%d err=%v, want 1 (%s only)", n, err, inWindow.ID)
	}
}

func TestOldestSessionSpawnedBySince_ReturnsOldestInWindow(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "proj-1")
	const proj domain.ProjectID = "proj-1"
	now := time.Now().UTC()
	older := now.Add(-30 * time.Minute)

	if _, err := s.CreateSession(ctx, budgetTestRecord(proj, domain.KindWorker, "orch-1", older)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateSession(ctx, budgetTestRecord(proj, domain.KindWorker, "orch-1", now)); err != nil {
		t.Fatal(err)
	}

	got, ok, err := s.OldestSessionSpawnedBySince(ctx, proj, "orch-1", now.Add(-time.Hour))
	if err != nil || !ok {
		t.Fatalf("ok=%v err=%v", ok, err)
	}
	if !got.Equal(older) {
		t.Fatalf("got=%v, want the older row's created_at=%v", got, older)
	}
}

func TestOldestSessionSpawnedBySince_NoneInWindow(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "proj-1")
	const proj domain.ProjectID = "proj-1"

	_, ok, err := s.OldestSessionSpawnedBySince(ctx, proj, "orch-1", time.Now().UTC().Add(-time.Hour))
	if err != nil || ok {
		t.Fatalf("ok=%v err=%v, want false/nil with nothing spawned", ok, err)
	}
}
