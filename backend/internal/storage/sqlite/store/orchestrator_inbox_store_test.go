package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestUpdateSessionFromActivitySignalAndEnqueueInboxEvent_AtomicAndCoalesced(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	proj := domain.ProjectID("proj-1")
	seedProject(t, s, string(proj))
	rec, err := s.CreateSession(ctx, sampleRecord(string(proj)))
	if err != nil {
		t.Fatal(err)
	}

	rec.Activity = domain.Activity{State: domain.ActivityIdle, LastActivityAt: time.Now().UTC()}
	rec.UpdatedAt = time.Now().UTC()
	event := domain.OrchestratorInboxEvent{
		ID: "evt-1", ProjectID: proj, WorkerID: rec.ID,
		Kind: domain.InboxEventWorkerIdle, OccurredAt: rec.Activity.LastActivityAt,
	}
	applied, err := s.UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx, rec, event)
	if err != nil || !applied {
		t.Fatalf("applied=%v err=%v", applied, err)
	}

	count, err := s.CountPendingInboxEvents(ctx, proj)
	if err != nil || count != 1 {
		t.Fatalf("count=%d err=%v, want 1", count, err)
	}

	event2 := event
	event2.ID = "evt-2"
	applied, err = s.UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx, rec, event2)
	if err != nil || !applied {
		t.Fatalf("second call: applied=%v err=%v", applied, err)
	}
	count, err = s.CountPendingInboxEvents(ctx, proj)
	if err != nil || count != 1 {
		t.Fatalf("count after duplicate=%d err=%v, want 1 (coalesced)", count, err)
	}
}

func TestUpdateSessionFromActivitySignalAndEnqueueInboxEvent_NoRowWhenActivityWriteMisses(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	proj := domain.ProjectID("proj-1")
	seedProject(t, s, string(proj))
	rec, err := s.CreateSession(ctx, sampleRecord(string(proj)))
	if err != nil {
		t.Fatal(err)
	}

	stale := rec
	stale.Metadata.RuntimeLaunchID = "stale-launch"
	event := domain.OrchestratorInboxEvent{
		ID: "evt-1", ProjectID: proj, WorkerID: rec.ID,
		Kind: domain.InboxEventWorkerIdle, OccurredAt: time.Now().UTC(),
	}
	applied, err := s.UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx, stale, event)
	if err != nil {
		t.Fatal(err)
	}
	if applied {
		t.Fatal("expected applied=false when the activity write's WHERE clause misses")
	}
	count, err := s.CountPendingInboxEvents(ctx, proj)
	if err != nil || count != 0 {
		t.Fatalf("count=%d err=%v, want 0: the insert must not survive a rolled-back transaction", count, err)
	}
}

func TestAckInboxEvents_UnknownAndAlreadyAckedAreNoops(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	proj := domain.ProjectID("proj-1")
	seedProject(t, s, string(proj))
	rec, err := s.CreateSession(ctx, sampleRecord(string(proj)))
	if err != nil {
		t.Fatal(err)
	}
	rec.Activity = domain.Activity{State: domain.ActivityIdle, LastActivityAt: time.Now().UTC()}
	event := domain.OrchestratorInboxEvent{ID: "evt-1", ProjectID: proj, WorkerID: rec.ID, Kind: domain.InboxEventWorkerIdle, OccurredAt: time.Now().UTC()}
	if _, err := s.UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx, rec, event); err != nil {
		t.Fatal(err)
	}

	n, err := s.AckInboxEvents(ctx, proj, []string{"evt-1", "unknown-id"})
	if err != nil || n != 1 {
		t.Fatalf("n=%d err=%v, want 1", n, err)
	}

	n, err = s.AckInboxEvents(ctx, proj, []string{"evt-1"})
	if err != nil || n != 0 {
		t.Fatalf("re-ack n=%d err=%v, want 0 (no-op, not an error)", n, err)
	}

	pending, err := s.ListPendingInboxEvents(ctx, proj)
	if err != nil || len(pending) != 0 {
		t.Fatalf("pending=%v err=%v, want none", pending, err)
	}
}

func TestListProjectsWithPendingInboxEvents(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	projA := domain.ProjectID("proj-a")
	projB := domain.ProjectID("proj-b")
	seedProject(t, s, string(projA))
	seedProject(t, s, string(projB))
	recA, err := s.CreateSession(ctx, sampleRecord(string(projA)))
	if err != nil {
		t.Fatal(err)
	}
	recB, err := s.CreateSession(ctx, sampleRecord(string(projB)))
	if err != nil {
		t.Fatal(err)
	}

	eventA := domain.OrchestratorInboxEvent{ID: "evt-a", ProjectID: projA, WorkerID: recA.ID, Kind: domain.InboxEventWorkerIdle, OccurredAt: time.Now().UTC()}
	if _, err := s.UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx, recA, eventA); err != nil {
		t.Fatal(err)
	}
	eventB := domain.OrchestratorInboxEvent{ID: "evt-b", ProjectID: projB, WorkerID: recB.ID, Kind: domain.InboxEventWorkerIdle, OccurredAt: time.Now().UTC()}
	if _, err := s.UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx, recB, eventB); err != nil {
		t.Fatal(err)
	}

	projects, err := s.ListProjectsWithPendingInboxEvents(ctx)
	if err != nil || len(projects) != 2 {
		t.Fatalf("projects=%v err=%v, want 2", projects, err)
	}

	if _, err := s.AckInboxEvents(ctx, projA, []string{"evt-a"}); err != nil {
		t.Fatal(err)
	}
	projects, err = s.ListProjectsWithPendingInboxEvents(ctx)
	if err != nil || len(projects) != 1 || projects[0] != projB {
		t.Fatalf("projects after ack=%v err=%v, want [%s]", projects, err, projB)
	}
}
