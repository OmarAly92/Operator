package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestBoardCDCProjectChanges(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	project := domain.ProjectRecord{ID: "board", Path: "/tmp/board", RegisteredAt: time.Now().UTC()}
	if err := s.UpsertProject(ctx, project); err != nil {
		t.Fatal(err)
	}
	project.DisplayName = "Renamed"
	if err := s.UpsertProject(ctx, project); err != nil {
		t.Fatal(err)
	}
	if err := s.UpsertProject(ctx, project); err != nil {
		t.Fatal(err)
	}
	if ok, err := s.ArchiveProject(ctx, project.ID, time.Now().UTC()); err != nil || !ok {
		t.Fatalf("archive: %v, %v", ok, err)
	}
	events, err := s.EventsAfter(ctx, 0, 100)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"project_created", "project_updated", "project_updated"}
	if len(events) != len(want) {
		t.Fatalf("events = %+v, want create, rename and archive only", events)
	}
	for i, event := range events {
		if string(event.Type) != want[i] || event.ProjectID != project.ID || event.SessionID != "" {
			t.Fatalf("event %d = %+v", i, event)
		}
	}
}

func TestBoardCDCDeletedSeedSurvivesSessionRemoval(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "board")
	now := time.Now().UTC()
	session, err := s.CreateSession(ctx, domain.SessionRecord{
		ProjectID: "board", Kind: domain.KindWorker, Harness: domain.HarnessClaudeCode,
		Activity:  domain.Activity{State: domain.ActivityIdle, LastActivityAt: now},
		Metadata:  domain.SessionMetadata{WorkspaceMode: domain.WorkspaceModeWorktree},
		CreatedAt: now, UpdatedAt: now,
	})
	if err != nil {
		t.Fatal(err)
	}
	head, err := s.LatestSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if ok, err := s.DeleteSession(ctx, session.ID); err != nil || !ok {
		t.Fatalf("delete: %v, %v", ok, err)
	}
	events, err := s.EventsAfter(ctx, head, 100)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || string(events[0].Type) != "session_deleted" || events[0].ProjectID != "board" || events[0].SessionID != "" {
		t.Fatalf("deletion event = %+v", events)
	}
}
