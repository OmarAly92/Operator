package controllers

import (
	"context"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
)

// InboxEventStore is the controller-facing inbox contract.
type InboxEventStore interface {
	ListPendingInboxEvents(ctx context.Context, project domain.ProjectID) ([]domain.OrchestratorInboxEvent, error)
	AckInboxEvents(ctx context.Context, project domain.ProjectID, ids []string) (int, error)
}

// InboxSessionReader resolves an inbox event's worker against the live
// session record.
type InboxSessionReader interface {
	Get(ctx context.Context, id domain.SessionID) (domain.Session, error)
}

// InboxController owns the /projects/{id}/inbox routes.
type InboxController struct {
	Events   InboxEventStore
	Sessions InboxSessionReader
}

// Register mounts the inbox routes on the supplied router.
func (c *InboxController) Register(r chi.Router) {
	r.Get("/projects/{id}/inbox", c.list)
	r.Post("/projects/{id}/inbox/ack", c.ack)
}

func (c *InboxController) list(w http.ResponseWriter, r *http.Request) {
	if c.Events == nil || c.Sessions == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/projects/{id}/inbox")
		return
	}
	events, err := c.Events.ListPendingInboxEvents(r.Context(), projectID(r))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	entries := make([]InboxEntryView, 0, len(events))
	for _, ev := range events {
		sess, err := c.Sessions.Get(r.Context(), ev.WorkerID)
		if err != nil {
			continue
		}
		entries = append(entries, InboxEntryView{
			ID:         ev.ID,
			Kind:       string(ev.Kind),
			OccurredAt: ev.OccurredAt,
			Worker:     sessionView(sess),
		})
	}
	envelope.WriteJSON(w, http.StatusOK, InboxResponse{Entries: entries})
}

func (c *InboxController) ack(w http.ResponseWriter, r *http.Request) {
	if c.Events == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/inbox/ack")
		return
	}
	var req AckInboxEventsRequest
	if err := decodeJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	acked, err := c.Events.AckInboxEvents(r.Context(), projectID(r), req.IDs)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, AckInboxEventsResponse{Acked: acked})
}
