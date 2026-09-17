package ticket

import (
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func sessWith(status domain.SessionStatus) *domain.Session {
	return &domain.Session{SessionRecord: domain.SessionRecord{ID: "p-1"}, Status: status}
}

func TestPlanStatusTable(t *testing.T) {
	a := domain.PlanAssignmentRecord{SessionID: "p-1"}
	cases := []struct {
		name string
		a    domain.PlanAssignmentRecord
		ok   bool
		sess *domain.Session
		want domain.PlanStatus
	}{
		{"no assignment", domain.PlanAssignmentRecord{}, false, nil, domain.PlanStatusTodo},
		{"done wins", domain.PlanAssignmentRecord{DoneAt: time.Now()}, true, sessWith(domain.StatusWorking), domain.PlanStatusDone},
		{"session missing", a, true, nil, domain.PlanStatusTerminated},
		{"working", a, true, sessWith(domain.StatusWorking), domain.PlanStatusWorking},
		{"needs input", a, true, sessWith(domain.StatusNeedsInput), domain.PlanStatusNeedsYou},
		{"pr open", a, true, sessWith(domain.StatusPROpen), domain.PlanStatusInReview},
		{"draft", a, true, sessWith(domain.StatusDraft), domain.PlanStatusInReview},
		{"ci failed", a, true, sessWith(domain.StatusCIFailed), domain.PlanStatusInReview},
		{"review pending", a, true, sessWith(domain.StatusReviewPending), domain.PlanStatusInReview},
		{"changes requested", a, true, sessWith(domain.StatusChangesRequested), domain.PlanStatusInReview},
		{"approved", a, true, sessWith(domain.StatusApproved), domain.PlanStatusInReview},
		{"mergeable", a, true, sessWith(domain.StatusMergeable), domain.PlanStatusInReview},
		{"merged", a, true, sessWith(domain.StatusMerged), domain.PlanStatusMerged},
		{"merged beats awaiting", domain.PlanAssignmentRecord{SessionID: "p-1", MergeReadyAt: time.Now()}, true, sessWith(domain.StatusMerged), domain.PlanStatusMerged},
		{"awaiting merge", domain.PlanAssignmentRecord{SessionID: "p-1", ReviewRequestedAt: time.Now(), MergeReadyAt: time.Now()}, true, sessWith(domain.StatusPROpen), domain.PlanStatusAwaitMerge},
		{"approved goes back to reviewing", domain.PlanAssignmentRecord{SessionID: "p-1", ReviewRequestedAt: time.Now(), MergeReadyAt: time.Now(), MergeApprovedAt: time.Now()}, true, sessWith(domain.StatusPROpen), domain.PlanStatusReviewing},
		{"reviewing", domain.PlanAssignmentRecord{SessionID: "p-1", ReviewRequestedAt: time.Now()}, true, sessWith(domain.StatusPROpen), domain.PlanStatusReviewing},
		{"reviewing even when implementer terminated", domain.PlanAssignmentRecord{SessionID: "p-1", ReviewRequestedAt: time.Now()}, true, sessWith(domain.StatusTerminated), domain.PlanStatusReviewing},
		{"terminated", a, true, sessWith(domain.StatusTerminated), domain.PlanStatusTerminated},
		{"exited", a, true, sessWith(domain.StatusExited), domain.PlanStatusTerminated},
		{"idle", a, true, sessWith(domain.StatusIdle), domain.PlanStatusIdle},
		{"no signal", a, true, sessWith(domain.StatusNoSignal), domain.PlanStatusIdle},
	}
	for _, tc := range cases {
		if got := planStatus(tc.a, tc.ok, tc.sess); got != tc.want {
			t.Errorf("%s: got %q want %q", tc.name, got, tc.want)
		}
	}
}

func TestCurrentAssignmentsNewestWins(t *testing.T) {
	rows := []domain.PlanAssignmentRecord{
		{ID: 3, PlanFile: "plans/01-a.md", SessionID: "p-3"},
		{ID: 2, PlanFile: "plans/02-b.md", SessionID: "p-2"},
		{ID: 1, PlanFile: "plans/01-a.md", SessionID: "p-1"},
	}
	got := currentAssignments(rows)
	if len(got) != 2 || got["plans/01-a.md"].SessionID != "p-3" || got["plans/02-b.md"].SessionID != "p-2" {
		t.Fatalf("got %+v", got)
	}
}

func TestTicketStatusTable(t *testing.T) {
	plan := func(s domain.PlanStatus) domain.Plan { return domain.Plan{Status: s} }
	cases := []struct {
		name     string
		rec      domain.TicketRecord
		plans    []domain.Plan
		planning *domain.Session
		want     domain.TicketStatus
	}{
		{"archived beats everything", domain.TicketRecord{ArchivedAt: time.Now()}, []domain.Plan{plan(domain.PlanStatusWorking)}, nil, domain.TicketStatusArchived},
		{"draft", domain.TicketRecord{}, nil, nil, domain.TicketStatusDraft},
		{"planning", domain.TicketRecord{PlanningSessionID: "p-1"}, nil, sessWith(domain.StatusWorking), domain.TicketStatusPlanning},
		{"planning session terminated is draft", domain.TicketRecord{PlanningSessionID: "p-1"}, nil, sessWith(domain.StatusTerminated), domain.TicketStatusDraft},
		{"planning session gone is draft", domain.TicketRecord{PlanningSessionID: "p-1"}, nil, nil, domain.TicketStatusDraft},
		{"ready", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusTodo)}, nil, domain.TicketStatusReady},
		{"ready while planning still open", domain.TicketRecord{PlanningSessionID: "p-1"}, []domain.Plan{plan(domain.PlanStatusTodo)}, sessWith(domain.StatusIdle), domain.TicketStatusPlanning},
		{"in progress", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusMerged), plan(domain.PlanStatusWorking)}, nil, domain.TicketStatusInProgress},
		{"in review counts as progress", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusInReview), plan(domain.PlanStatusTodo)}, nil, domain.TicketStatusInProgress},
		{"awaiting merge outranks progress", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusWorking), plan(domain.PlanStatusAwaitMerge)}, nil, domain.TicketStatusAwaitMerge},
		{"reviewing is progress", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusReviewing)}, nil, domain.TicketStatusInProgress},
		{"terminated only is ready", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusTerminated), plan(domain.PlanStatusTodo)}, nil, domain.TicketStatusReady},
		{"done", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusMerged), plan(domain.PlanStatusDone)}, nil, domain.TicketStatusDone},
	}
	for _, tc := range cases {
		if got := ticketStatus(tc.rec, tc.plans, tc.planning); got != tc.want {
			t.Errorf("%s: got %q want %q", tc.name, got, tc.want)
		}
	}
}
