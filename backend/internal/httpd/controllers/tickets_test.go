package controllers_test

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	ticketsvc "github.com/OmarAly92/operator/backend/internal/service/ticket"
)

type fakeTicketService struct {
	tickets    []domain.Ticket
	file       ticketsvc.File
	created    ticketsvc.CreateInput
	assigned   ticketsvc.AssignInput
	assignName string
	planned    ticketsvc.SpawnInput
	reviewed   ticketsvc.ReviewInput
	reviewName string
	mergeReady string
	merged     string
	done       string
	archived   *bool
	err        error
}

func (f *fakeTicketService) List(context.Context, domain.ProjectID) ([]domain.Ticket, error) {
	return f.tickets, f.err
}
func (f *fakeTicketService) Get(_ context.Context, _ domain.ProjectID, slug string) (domain.Ticket, error) {
	if f.err != nil {
		return domain.Ticket{}, f.err
	}
	for _, t := range f.tickets {
		if t.Slug == slug {
			return t, nil
		}
	}
	return domain.Ticket{}, apierr.NotFound("TICKET_NOT_FOUND", "Unknown ticket")
}
func (f *fakeTicketService) ReadFile(_ context.Context, _ domain.ProjectID, _, _ string) (ticketsvc.File, error) {
	return f.file, f.err
}
func (f *fakeTicketService) WriteFile(_ context.Context, _ domain.ProjectID, _, rel, content string, since time.Time) (ticketsvc.File, error) {
	if f.err != nil {
		return ticketsvc.File{}, f.err
	}
	f.file = ticketsvc.File{Path: rel, Content: content, ModifiedAt: since.Add(time.Second)}
	return f.file, nil
}
func (f *fakeTicketService) Create(_ context.Context, _ domain.ProjectID, in ticketsvc.CreateInput) (ticketsvc.CreateResult, error) {
	f.created = in
	if f.err != nil {
		return ticketsvc.CreateResult{}, f.err
	}
	return ticketsvc.CreateResult{Ticket: domain.Ticket{Slug: "new", Title: in.Title, Status: domain.TicketStatusDraft}, Warnings: []string{"not_on_default_branch"}}, nil
}
func (f *fakeTicketService) Plan(_ context.Context, _ domain.ProjectID, _ string, in ticketsvc.SpawnInput) (domain.Session, error) {
	f.planned = in
	return domain.Session{SessionRecord: domain.SessionRecord{ID: "tk-1"}}, f.err
}
func (f *fakeTicketService) Assign(_ context.Context, _ domain.ProjectID, _, plan string, in ticketsvc.AssignInput) (ticketsvc.AssignResult, error) {
	f.assigned, f.assignName = in, plan
	if f.err != nil {
		return ticketsvc.AssignResult{}, f.err
	}
	if in.DryRun {
		return ticketsvc.AssignResult{Warnings: []string{"plan_order"}}, nil
	}
	return ticketsvc.AssignResult{Warnings: []string{}, Session: &domain.Session{SessionRecord: domain.SessionRecord{ID: "tk-2"}}}, nil
}
func (f *fakeTicketService) MarkDone(_ context.Context, _ domain.ProjectID, _, plan string) (domain.Ticket, error) {
	f.done = plan
	return domain.Ticket{Slug: "editor", Status: domain.TicketStatusDone}, f.err
}
func (f *fakeTicketService) SetArchived(_ context.Context, _ domain.ProjectID, _ string, archived bool) (domain.Ticket, error) {
	f.archived = &archived
	return domain.Ticket{Slug: "editor", Status: domain.TicketStatusArchived}, f.err
}
func (f *fakeTicketService) WatchRoot(context.Context, domain.ProjectID) (string, error) {
	return "", errors.New("not watched in tests")
}
func (f *fakeTicketService) Review(_ context.Context, _ domain.ProjectID, _, plan string, in ticketsvc.ReviewInput) (ticketsvc.ReviewResult, error) {
	f.reviewed, f.reviewName = in, plan
	if f.err != nil {
		return ticketsvc.ReviewResult{}, f.err
	}
	return ticketsvc.ReviewResult{Session: domain.Session{SessionRecord: domain.SessionRecord{ID: "tk-9"}}, Spawned: in.Reviewer == "new"}, nil
}
func (f *fakeTicketService) MergeReady(_ context.Context, _ domain.ProjectID, _, plan, summary string) (domain.Ticket, error) {
	f.mergeReady = summary
	return domain.Ticket{Slug: "editor", Status: domain.TicketStatusAwaitMerge, Plans: []domain.Plan{{File: "plans/" + plan, Status: domain.PlanStatusAwaitMerge, MergeSummary: summary}}}, f.err
}
func (f *fakeTicketService) ApproveMerge(_ context.Context, _ domain.ProjectID, _, plan string) (domain.Ticket, error) {
	f.merged = plan
	return domain.Ticket{Slug: "editor", Status: domain.TicketStatusInProgress}, f.err
}

func newTicketsTestServer(t *testing.T, svc controllers.TicketService) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{Tickets: svc}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestTicketsListGetAndErrors(t *testing.T) {
	svc := &fakeTicketService{tickets: []domain.Ticket{{ProjectID: "p", Slug: "editor", Title: "Editor", Status: domain.TicketStatusReady, Plans: []domain.Plan{{File: "plans/01-core.md", Order: 1, Title: "Core", Status: domain.PlanStatusTodo}}, Files: []string{"ticket.md"}}}}
	srv := newTicketsTestServer(t, svc)
	body, status, _ := doRequest(t, srv, "GET", "/api/v1/projects/p/tickets", "")
	if status != http.StatusOK {
		t.Fatalf("status %d body %s", status, body)
	}
	var list controllers.ListTicketsResponse
	mustJSON(t, body, &list)
	if len(list.Tickets) != 1 || list.Tickets[0].Slug != "editor" || list.Tickets[0].Plans[0].Status != domain.PlanStatusTodo || list.Tickets[0].CreatedAt != nil {
		t.Fatalf("list = %+v", list)
	}
	body, status, _ = doRequest(t, srv, "GET", "/api/v1/projects/p/tickets/nope", "")
	var env struct {
		Code string `json:"code"`
	}
	mustJSON(t, body, &env)
	if status != http.StatusNotFound || env.Code != "TICKET_NOT_FOUND" {
		t.Fatalf("status %d code %q", status, env.Code)
	}
	svc.err = apierr.Invalid("TICKET_UNSUPPORTED_PROJECT", "x", nil)
	_, status, _ = doRequest(t, srv, "GET", "/api/v1/projects/p/tickets", "")
	if status != http.StatusBadRequest {
		t.Fatalf("status %d", status)
	}
}

func TestTicketsFileRoutes(t *testing.T) {
	svc := &fakeTicketService{file: ticketsvc.File{Path: "spec.md", Content: "# S\n", ModifiedAt: time.Unix(1700000000, 0).UTC()}}
	srv := newTicketsTestServer(t, svc)
	body, status, _ := doRequest(t, srv, "GET", "/api/v1/projects/p/tickets/editor/file?path=spec.md", "")
	var f controllers.TicketFileResponse
	mustJSON(t, body, &f)
	if status != http.StatusOK || f.Content != "# S\n" || f.ModifiedAt.Unix() != 1700000000 {
		t.Fatalf("status %d f=%+v", status, f)
	}
	_, status, _ = doRequest(t, srv, "GET", "/api/v1/projects/p/tickets/editor/file", "")
	if status != http.StatusBadRequest {
		t.Fatalf("missing path status %d", status)
	}
	body, status, _ = doRequest(t, srv, "PUT", "/api/v1/projects/p/tickets/editor/file?path=spec.md", `{"content":"v2","ifUnmodifiedSince":"2023-11-14T22:13:20Z"}`)
	mustJSON(t, body, &f)
	if status != http.StatusOK || f.Content != "v2" || f.Path != "spec.md" {
		t.Fatalf("status %d f=%+v", status, f)
	}
	svc.err = apierr.Conflict("TICKET_FILE_STALE", "x", map[string]any{"modifiedAt": "later"})
	_, status, _ = doRequest(t, srv, "PUT", "/api/v1/projects/p/tickets/editor/file?path=spec.md", `{"content":"v3"}`)
	if status != http.StatusConflict {
		t.Fatalf("stale status %d", status)
	}
}

func TestTicketsCreatePlanAssignDoneArchive(t *testing.T) {
	svc := &fakeTicketService{}
	srv := newTicketsTestServer(t, svc)
	body, status, _ := doRequest(t, srv, "POST", "/api/v1/projects/p/tickets", `{"title":"Editor","brief":"b"}`)
	var created controllers.CreateTicketResponse
	mustJSON(t, body, &created)
	if status != http.StatusCreated || created.Ticket.Slug != "new" || svc.created.Brief != "b" || len(created.Warnings) != 1 {
		t.Fatalf("status %d created=%+v", status, created)
	}
	_, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets", `{"brief":"b"}`)
	if status != http.StatusBadRequest {
		t.Fatalf("missing title status %d", status)
	}
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plan", `{"harness":"claude-code","claudeAccountId":"personal","extra":"hi"}`)
	var sv controllers.SessionView
	mustJSON(t, body, &sv)
	if status != http.StatusCreated || sv.ID != "tk-1" || svc.planned.ClaudeAccountID != "personal" || svc.planned.Extra != "hi" {
		t.Fatalf("plan status %d sv=%+v planned=%+v", status, sv, svc.planned)
	}
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/assign?dryRun=1", `{}`)
	var ar controllers.AssignPlanResponse
	mustJSON(t, body, &ar)
	if status != http.StatusOK || ar.Session != nil || len(ar.Warnings) != 1 || !svc.assigned.DryRun || svc.assignName != "01-core.md" {
		t.Fatalf("dry run status %d ar=%+v assigned=%+v", status, ar, svc.assigned)
	}
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/assign", `{"force":true,"harness":"codex"}`)
	mustJSON(t, body, &ar)
	if status != http.StatusCreated || ar.Session == nil || ar.Session.ID != "tk-2" || !svc.assigned.Force || svc.assigned.Harness != domain.HarnessCodex {
		t.Fatalf("assign status %d ar=%+v", status, ar)
	}
	svc.err = apierr.Conflict("TICKET_ASSIGN_BLOCKED", "x", map[string]any{"warnings": []string{"plan_order"}})
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/assign", `{}`)
	var env struct {
		Code    string         `json:"code"`
		Details map[string]any `json:"details"`
	}
	mustJSON(t, body, &env)
	if status != http.StatusConflict || env.Code != "TICKET_ASSIGN_BLOCKED" || env.Details["warnings"] == nil {
		t.Fatalf("blocked status %d env=%+v", status, env)
	}
	svc.err = nil
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/done", "")
	var tr controllers.TicketResponse
	mustJSON(t, body, &tr)
	if status != http.StatusOK || svc.done != "01-core.md" || tr.Ticket.Status != domain.TicketStatusDone {
		t.Fatalf("done status %d tr=%+v", status, tr)
	}
	_, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/archive", "")
	if status != http.StatusOK || svc.archived == nil || !*svc.archived {
		t.Fatalf("archive status %d archived=%v", status, svc.archived)
	}
	_, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/unarchive", "")
	if status != http.StatusOK || *svc.archived {
		t.Fatalf("unarchive status %d archived=%v", status, svc.archived)
	}
}

func TestTicketsReviewMergeReadyMerge(t *testing.T) {
	svc := &fakeTicketService{}
	srv := newTicketsTestServer(t, svc)
	body, status, _ := doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/review", `{"reviewer":"new","model":"sonnet","extra":"strict"}`)
	var rr controllers.ReviewPlanResponse
	mustJSON(t, body, &rr)
	if status != http.StatusOK || rr.Session.ID != "tk-9" || !rr.Spawned || svc.reviewed.Reviewer != "new" || svc.reviewed.Model != "sonnet" || svc.reviewName != "01-core.md" {
		t.Fatalf("review status %d rr=%+v reviewed=%+v", status, rr, svc.reviewed)
	}
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/merge-ready", `{"summary":"gates green"}`)
	var tr controllers.TicketResponse
	mustJSON(t, body, &tr)
	if status != http.StatusOK || svc.mergeReady != "gates green" || tr.Ticket.Status != domain.TicketStatusAwaitMerge || tr.Ticket.Plans[0].MergeSummary != "gates green" {
		t.Fatalf("merge-ready status %d tr=%+v", status, tr)
	}
	_, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/merge", "")
	if status != http.StatusOK || svc.merged != "01-core.md" {
		t.Fatalf("merge status %d merged=%q", status, svc.merged)
	}
	svc.err = apierr.Conflict("TICKET_NOT_MERGE_READY", "x", nil)
	_, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/merge", "")
	if status != http.StatusConflict {
		t.Fatalf("not ready status %d", status)
	}
}

func TestTicketsNotImplementedWithoutService(t *testing.T) {
	srv := newTicketsTestServer(t, nil)
	_, status, _ := doRequest(t, srv, "GET", "/api/v1/projects/p/tickets", "")
	if status != http.StatusNotImplemented {
		t.Fatalf("status %d", status)
	}
}
