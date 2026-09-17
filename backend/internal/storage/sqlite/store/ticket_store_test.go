package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestTicketsInsertGetPlanningSessionArchive(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "tk")
	now := time.Now().UTC().Truncate(time.Second)
	if err := s.InsertTicket(ctx, domain.TicketRecord{ProjectID: "tk", Slug: "editor", CreatedAt: now}); err != nil {
		t.Fatal(err)
	}
	if err := s.InsertTicket(ctx, domain.TicketRecord{ProjectID: "tk", Slug: "auth", CreatedAt: now.Add(time.Second)}); err != nil {
		t.Fatal(err)
	}
	list, err := s.ListTickets(ctx, "tk")
	if err != nil || len(list) != 2 || list[0].Slug != "editor" || list[1].Slug != "auth" {
		t.Fatalf("list = %+v err = %v", list, err)
	}
	sess, err := s.CreateSession(ctx, domain.SessionRecord{
		ProjectID: "tk", Kind: domain.KindWorker, Harness: domain.HarnessClaudeCode,
		Activity:  domain.Activity{State: domain.ActivityIdle, LastActivityAt: now},
		Metadata:  domain.SessionMetadata{WorkspaceMode: domain.WorkspaceModeInPlace},
		CreatedAt: now, UpdatedAt: now,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.SetTicketPlanningSession(ctx, "tk", "editor", sess.ID); err != nil {
		t.Fatal(err)
	}
	got, ok, err := s.GetTicket(ctx, "tk", "editor")
	if err != nil || !ok || got.PlanningSessionID != sess.ID || !got.ArchivedAt.IsZero() {
		t.Fatalf("get = %+v ok=%v err=%v", got, ok, err)
	}
	ref, ok, err := s.SessionTicketRef(ctx, sess.ID)
	if err != nil || !ok || ref.Slug != "editor" || ref.Role != domain.TicketRolePlanning || ref.PlanFile != "" {
		t.Fatalf("ref = %+v ok=%v err=%v", ref, ok, err)
	}
	if err := s.SetTicketPlanningSession(ctx, "tk", "editor", ""); err != nil {
		t.Fatal(err)
	}
	if _, ok, _ := s.SessionTicketRef(ctx, sess.ID); ok {
		t.Fatal("cleared planning session still resolves a ref")
	}
	if err := s.SetTicketArchivedAt(ctx, "tk", "editor", now); err != nil {
		t.Fatal(err)
	}
	got, _, _ = s.GetTicket(ctx, "tk", "editor")
	if !got.ArchivedAt.Equal(now) {
		t.Fatalf("archived_at = %v want %v", got.ArchivedAt, now)
	}
	if err := s.SetTicketArchivedAt(ctx, "tk", "editor", time.Time{}); err != nil {
		t.Fatal(err)
	}
	got, _, _ = s.GetTicket(ctx, "tk", "editor")
	if !got.ArchivedAt.IsZero() {
		t.Fatalf("archived_at not cleared: %v", got.ArchivedAt)
	}
	if _, ok, err := s.GetTicket(ctx, "tk", "missing"); ok || err != nil {
		t.Fatalf("missing ticket ok=%v err=%v", ok, err)
	}
	if err := s.SetTicketPlanningSession(ctx, "tk", "missing", sess.ID); err == nil {
		t.Fatal("update of missing ticket should fail")
	}
}

func TestPlanAssignmentsNewestFirstAndRef(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "tk")
	now := time.Now().UTC().Truncate(time.Second)
	if err := s.InsertTicket(ctx, domain.TicketRecord{ProjectID: "tk", Slug: "editor", CreatedAt: now}); err != nil {
		t.Fatal(err)
	}
	mk := func() domain.SessionID {
		sess, err := s.CreateSession(ctx, domain.SessionRecord{
			ProjectID: "tk", Kind: domain.KindWorker, Harness: domain.HarnessClaudeCode,
			Activity:  domain.Activity{State: domain.ActivityIdle, LastActivityAt: now},
			Metadata:  domain.SessionMetadata{WorkspaceMode: domain.WorkspaceModeWorktree},
			CreatedAt: now, UpdatedAt: now,
		})
		if err != nil {
			t.Fatal(err)
		}
		return sess.ID
	}
	first, second := mk(), mk()
	if err := s.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: "tk", Slug: "editor", PlanFile: "plans/01-core.md", SessionID: first, AssignedAt: now}); err != nil {
		t.Fatal(err)
	}
	if err := s.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: "tk", Slug: "editor", PlanFile: "plans/01-core.md", SessionID: second, AssignedAt: now.Add(time.Second)}); err != nil {
		t.Fatal(err)
	}
	if err := s.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: "tk", Slug: "editor", PlanFile: "plans/02-ui.md", AssignedAt: now, DoneAt: now}); err != nil {
		t.Fatal(err)
	}
	rows, err := s.ListPlanAssignments(ctx, "tk", "editor")
	if err != nil || len(rows) != 3 {
		t.Fatalf("rows = %+v err = %v", rows, err)
	}
	if rows[0].PlanFile != "plans/02-ui.md" || rows[0].SessionID != "" || rows[0].DoneAt.IsZero() {
		t.Fatalf("newest row wrong: %+v", rows[0])
	}
	if rows[1].SessionID != second || rows[2].SessionID != first || rows[1].ID <= rows[2].ID {
		t.Fatalf("order wrong: %+v", rows)
	}
	ref, ok, err := s.SessionTicketRef(ctx, second)
	if err != nil || !ok || ref.Slug != "editor" || ref.PlanFile != "plans/01-core.md" || ref.Role != domain.TicketRoleImplementing {
		t.Fatalf("ref = %+v ok=%v err=%v", ref, ok, err)
	}
	if _, ok, _ := s.SessionTicketRef(ctx, "nope"); ok {
		t.Fatal("unknown session resolved a ref")
	}
	id := rows[1].ID
	reviewer := mk()
	if err := s.MarkPlanReviewRequested(ctx, id, reviewer, now); err != nil {
		t.Fatal(err)
	}
	if ref, ok, err := s.SessionTicketRef(ctx, reviewer); err != nil || !ok || ref.Role != domain.TicketRoleReviewing || ref.PlanFile != "plans/01-core.md" {
		t.Fatalf("reviewer ref = %+v ok=%v err=%v", ref, ok, err)
	}
	if err := s.MarkPlanMergeReady(ctx, id, now.Add(time.Second), "gates green, verified in app"); err != nil {
		t.Fatal(err)
	}
	if err := s.MarkPlanMergeApproved(ctx, id, now.Add(2*time.Second)); err != nil {
		t.Fatal(err)
	}
	got, ok, err := s.GetPlanAssignment(ctx, id)
	if err != nil || !ok || got.ReviewerSessionID != reviewer || !got.ReviewRequestedAt.Equal(now) || !got.MergeReadyAt.Equal(now.Add(time.Second)) || got.MergeSummary != "gates green, verified in app" || !got.MergeApprovedAt.Equal(now.Add(2*time.Second)) {
		t.Fatalf("assignment = %+v ok=%v err=%v", got, ok, err)
	}
	if err := s.MarkPlanMergeReady(ctx, 9999, now, "x"); err == nil {
		t.Fatal("unknown assignment must fail")
	}
}

func TestTicketsEmitTicketUpdatedCDC(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "tk")
	head, err := s.LatestSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC()
	if err := s.InsertTicket(ctx, domain.TicketRecord{ProjectID: "tk", Slug: "editor", CreatedAt: now}); err != nil {
		t.Fatal(err)
	}
	if err := s.SetTicketArchivedAt(ctx, "tk", "editor", now); err != nil {
		t.Fatal(err)
	}
	if err := s.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: "tk", Slug: "editor", PlanFile: "plans/01-core.md", AssignedAt: now, DoneAt: now}); err != nil {
		t.Fatal(err)
	}
	events, err := s.EventsAfter(ctx, head, 100)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.MarkPlanMergeReady(ctx, 1, now, "ready"); err != nil {
		t.Fatal(err)
	}
	if len(events) != 3 {
		t.Fatalf("events = %+v, want three ticket_updated", events)
	}
	events, err = s.EventsAfter(ctx, head, 100)
	if err != nil || len(events) != 4 || string(events[3].Type) != "ticket_updated" {
		t.Fatalf("after merge-ready events = %+v err=%v", events, err)
	}
	for _, e := range events {
		if string(e.Type) != "ticket_updated" || e.ProjectID != "tk" || e.SessionID != "" {
			t.Fatalf("event = %+v", e)
		}
	}
}
