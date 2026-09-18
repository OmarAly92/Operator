package controllers

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	ticketsvc "github.com/OmarAly92/operator/backend/internal/service/ticket"
	"github.com/OmarAly92/operator/backend/internal/workspacewatch"
)

type TicketService interface {
	List(ctx context.Context, project domain.ProjectID) ([]domain.Ticket, error)
	Get(ctx context.Context, project domain.ProjectID, slug string) (domain.Ticket, error)
	ReadFile(ctx context.Context, project domain.ProjectID, slug, rel string) (ticketsvc.File, error)
	WriteFile(ctx context.Context, project domain.ProjectID, slug, rel, content string, ifUnmodifiedSince time.Time) (ticketsvc.File, error)
	Create(ctx context.Context, project domain.ProjectID, in ticketsvc.CreateInput) (ticketsvc.CreateResult, error)
	Plan(ctx context.Context, project domain.ProjectID, slug string, in ticketsvc.SpawnInput) (domain.Session, error)
	Assign(ctx context.Context, project domain.ProjectID, slug, plan string, in ticketsvc.AssignInput) (ticketsvc.AssignResult, error)
	MarkDone(ctx context.Context, project domain.ProjectID, slug, plan string) (domain.Ticket, error)
	SetArchived(ctx context.Context, project domain.ProjectID, slug string, archived bool) (domain.Ticket, error)
	WatchRoot(ctx context.Context, project domain.ProjectID) (string, error)
	Review(ctx context.Context, project domain.ProjectID, slug, plan string, in ticketsvc.ReviewInput) (ticketsvc.ReviewResult, error)
	MergeReady(ctx context.Context, project domain.ProjectID, slug, plan, summary string) (domain.Ticket, error)
	ApproveMerge(ctx context.Context, project domain.ProjectID, slug, plan string) (domain.Ticket, error)
}

type TicketsController struct {
	Svc TicketService
}

func (c *TicketsController) Register(r chi.Router) {
	r.Get("/projects/{id}/tickets", c.list)
	r.Post("/projects/{id}/tickets", c.create)
	r.Get("/projects/{id}/tickets/events", c.events)
	r.Get("/projects/{id}/tickets/{slug}", c.get)
	r.Get("/projects/{id}/tickets/{slug}/file", c.readFile)
	r.Put("/projects/{id}/tickets/{slug}/file", c.writeFile)
	r.Post("/projects/{id}/tickets/{slug}/plan", c.plan)
	r.Post("/projects/{id}/tickets/{slug}/archive", c.archive)
	r.Post("/projects/{id}/tickets/{slug}/unarchive", c.unarchive)
	r.Post("/projects/{id}/tickets/{slug}/plans/{plan}/assign", c.assign)
	r.Post("/projects/{id}/tickets/{slug}/plans/{plan}/done", c.done)
	r.Post("/projects/{id}/tickets/{slug}/plans/{plan}/review", c.review)
	r.Post("/projects/{id}/tickets/{slug}/plans/{plan}/merge-ready", c.mergeReady)
	r.Post("/projects/{id}/tickets/{slug}/plans/{plan}/merge", c.merge)
}

func ticketSlug(r *http.Request) string { return strings.TrimSpace(chi.URLParam(r, "slug")) }
func ticketPlan(r *http.Request) string { return strings.TrimSpace(chi.URLParam(r, "plan")) }

func planView(p domain.Plan) PlanView {
	return PlanView{File: p.File, Order: p.Order, Title: p.Title, Status: p.Status, SessionID: p.SessionID, ReviewerSessionID: p.ReviewerID, MergeSummary: p.MergeSummary, KickoffFile: p.KickoffFile, Unordered: p.Unordered, Warning: p.Warning}
}

func ticketView(t domain.Ticket) TicketView {
	v := TicketView{
		ProjectID: t.ProjectID, Slug: t.Slug, Title: t.Title, Brief: t.Brief, Status: t.Status,
		PlanningSessionID: t.PlanningSessionID, Warning: t.Warning,
		Plans: make([]PlanView, 0, len(t.Plans)), Files: t.Files,
	}
	if v.Files == nil {
		v.Files = []string{}
	}
	for _, p := range t.Plans {
		v.Plans = append(v.Plans, planView(p))
	}
	if !t.CreatedAt.IsZero() {
		at := t.CreatedAt
		v.CreatedAt = &at
	}
	if !t.ArchivedAt.IsZero() {
		at := t.ArchivedAt
		v.ArchivedAt = &at
	}
	return v
}

func ticketFileView(f ticketsvc.File) TicketFileResponse {
	return TicketFileResponse{Path: f.Path, Content: f.Content, ModifiedAt: f.ModifiedAt}
}

func (c *TicketsController) list(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/projects/{id}/tickets")
		return
	}
	tickets, err := c.Svc.List(r.Context(), projectID(r))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	views := make([]TicketView, 0, len(tickets))
	for _, t := range tickets {
		views = append(views, ticketView(t))
	}
	envelope.WriteJSON(w, http.StatusOK, ListTicketsResponse{Tickets: views})
}

func (c *TicketsController) get(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/projects/{id}/tickets/{slug}")
		return
	}
	t, err := c.Svc.Get(r.Context(), projectID(r), ticketSlug(r))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, TicketResponse{Ticket: ticketView(t)})
}

func (c *TicketsController) create(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets")
		return
	}
	var req CreateTicketRequest
	if err := decodeJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	if strings.TrimSpace(req.Title) == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "TICKET_TITLE_REQUIRED", "title is required", nil)
		return
	}
	res, err := c.Svc.Create(r.Context(), projectID(r), ticketsvc.CreateInput{Title: req.Title, Brief: req.Brief})
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	warnings := res.Warnings
	if warnings == nil {
		warnings = []string{}
	}
	envelope.WriteJSON(w, http.StatusCreated, CreateTicketResponse{Ticket: ticketView(res.Ticket), Warnings: warnings})
}

func (c *TicketsController) readFile(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/projects/{id}/tickets/{slug}/file")
		return
	}
	rel := strings.TrimSpace(r.URL.Query().Get("path"))
	if rel == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "TICKET_PATH_REQUIRED", "path query parameter is required", nil)
		return
	}
	f, err := c.Svc.ReadFile(r.Context(), projectID(r), ticketSlug(r), rel)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ticketFileView(f))
}

func (c *TicketsController) writeFile(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "PUT", "/api/v1/projects/{id}/tickets/{slug}/file")
		return
	}
	rel := strings.TrimSpace(r.URL.Query().Get("path"))
	if rel == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "TICKET_PATH_REQUIRED", "path query parameter is required", nil)
		return
	}
	var req SaveTicketFileRequest
	if err := decodeJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	var since time.Time
	if req.IfUnmodifiedSince != nil {
		since = *req.IfUnmodifiedSince
	}
	f, err := c.Svc.WriteFile(r.Context(), projectID(r), ticketSlug(r), rel, req.Content, since)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ticketFileView(f))
}

func (c *TicketsController) plan(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets/{slug}/plan")
		return
	}
	var req PlanTicketRequest
	if err := decodeOptionalJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	sess, err := c.Svc.Plan(r.Context(), projectID(r), ticketSlug(r), ticketsvc.SpawnInput{Harness: req.Harness, Model: req.Model, ClaudeAccountID: req.ClaudeAccountID, Extra: req.Extra})
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusCreated, sessionView(sess))
}

func (c *TicketsController) assign(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/assign")
		return
	}
	var req AssignPlanRequest
	if err := decodeOptionalJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	dry := r.URL.Query().Get("dryRun")
	in := ticketsvc.AssignInput{
		SpawnInput: ticketsvc.SpawnInput{Harness: req.Harness, Model: req.Model, ClaudeAccountID: req.ClaudeAccountID, Extra: req.Extra},
		Force:      req.Force,
		DryRun:     dry == "1" || dry == "true",
	}
	res, err := c.Svc.Assign(r.Context(), projectID(r), ticketSlug(r), ticketPlan(r), in)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	out := AssignPlanResponse{Warnings: res.Warnings}
	if out.Warnings == nil {
		out.Warnings = []string{}
	}
	status := http.StatusOK
	if res.Session != nil {
		v := sessionView(*res.Session)
		out.Session = &v
		status = http.StatusCreated
	}
	envelope.WriteJSON(w, status, out)
}

func (c *TicketsController) done(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/done")
		return
	}
	t, err := c.Svc.MarkDone(r.Context(), projectID(r), ticketSlug(r), ticketPlan(r))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, TicketResponse{Ticket: ticketView(t)})
}

func (c *TicketsController) review(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/review")
		return
	}
	var req ReviewPlanRequest
	if err := decodeOptionalJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	res, err := c.Svc.Review(r.Context(), projectID(r), ticketSlug(r), ticketPlan(r), ticketsvc.ReviewInput{
		SpawnInput: ticketsvc.SpawnInput{Harness: req.Harness, Model: req.Model, ClaudeAccountID: req.ClaudeAccountID, Extra: req.Extra},
		Reviewer:   req.Reviewer,
	})
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ReviewPlanResponse{Session: sessionView(res.Session), Spawned: res.Spawned})
}

func (c *TicketsController) mergeReady(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/merge-ready")
		return
	}
	var req MergeReadyRequest
	if err := decodeOptionalJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	t, err := c.Svc.MergeReady(r.Context(), projectID(r), ticketSlug(r), ticketPlan(r), req.Summary)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, TicketResponse{Ticket: ticketView(t)})
}

func (c *TicketsController) merge(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/merge")
		return
	}
	t, err := c.Svc.ApproveMerge(r.Context(), projectID(r), ticketSlug(r), ticketPlan(r))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, TicketResponse{Ticket: ticketView(t)})
}

func (c *TicketsController) archive(w http.ResponseWriter, r *http.Request) {
	c.setArchived(w, r, true, "/api/v1/projects/{id}/tickets/{slug}/archive")
}

func (c *TicketsController) unarchive(w http.ResponseWriter, r *http.Request) {
	c.setArchived(w, r, false, "/api/v1/projects/{id}/tickets/{slug}/unarchive")
}

func (c *TicketsController) setArchived(w http.ResponseWriter, r *http.Request, archived bool, specPath string) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", specPath)
		return
	}
	t, err := c.Svc.SetArchived(r.Context(), projectID(r), ticketSlug(r), archived)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, TicketResponse{Ticket: ticketView(t)})
}

func (c *TicketsController) events(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/projects/{id}/tickets/events")
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "SSE_UNSUPPORTED", "Streaming is not supported by this server", nil)
		return
	}
	root, err := c.Svc.WatchRoot(r.Context(), projectID(r))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	changes, err := workspacewatch.Watch(r.Context(), root)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	h := w.Header()
	h.Set("Content-Type", "text/event-stream; charset=utf-8")
	h.Set("Cache-Control", "no-cache")
	h.Set("Connection", "keep-alive")
	h.Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()
	keepAlive := time.NewTicker(15 * time.Second)
	defer keepAlive.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case _, ok := <-changes:
			if !ok {
				return
			}
			if _, err := fmt.Fprint(w, "event: tickets_changed\ndata: {}\n\n"); err != nil {
				return
			}
			flusher.Flush()
		case <-keepAlive.C:
			if _, err := fmt.Fprint(w, ": keepalive\n\n"); err != nil {
				return
			}
			flusher.Flush()
		}
	}
}
