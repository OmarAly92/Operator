package controllers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeInboxStore struct {
	events []domain.OrchestratorInboxEvent
	acked  []string
}

func (f *fakeInboxStore) ListPendingInboxEvents(_ context.Context, project domain.ProjectID) ([]domain.OrchestratorInboxEvent, error) {
	var out []domain.OrchestratorInboxEvent
	for _, ev := range f.events {
		if ev.ProjectID == project {
			out = append(out, ev)
		}
	}
	return out, nil
}

func (f *fakeInboxStore) AckInboxEvents(_ context.Context, _ domain.ProjectID, ids []string) (int, error) {
	f.acked = append(f.acked, ids...)
	return len(ids), nil
}

type fakeInboxSessions struct {
	sessions map[domain.SessionID]domain.Session
}

func (f *fakeInboxSessions) Get(_ context.Context, id domain.SessionID) (domain.Session, error) {
	sess, ok := f.sessions[id]
	if !ok {
		return domain.Session{}, ports.ErrSessionNotFound
	}
	return sess, nil
}

func TestInboxListResolvesEachEventAgainstTheLiveSessionRecord(t *testing.T) {
	worker := domain.Session{}
	worker.ID = "opr-1"
	worker.Metadata.LatestUserPrompt = "search for new iphone 18"
	worker.Metadata.LatestAssistantUpdate = "Here is what I found."

	c := &InboxController{
		Events:   &fakeInboxStore{events: []domain.OrchestratorInboxEvent{{ID: "evt-1", ProjectID: "proj-1", WorkerID: "opr-1", Kind: domain.InboxEventWorkerIdle}}},
		Sessions: &fakeInboxSessions{sessions: map[domain.SessionID]domain.Session{"opr-1": worker}},
	}
	r := chi.NewRouter()
	c.Register(r)

	req := httptest.NewRequest(http.MethodGet, "/projects/proj-1/inbox", nil)
	rr := httptest.NewRecorder()
	r.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rr.Code, rr.Body.String())
	}
	var res InboxResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &res); err != nil {
		t.Fatal(err)
	}
	if len(res.Entries) != 1 || res.Entries[0].Worker.LatestUserPrompt != "search for new iphone 18" {
		t.Fatalf("entries = %+v", res.Entries)
	}
}

func TestInboxListKeepsEntriesWhoseWorkerSessionCannotBeResolved(t *testing.T) {
	worker := domain.Session{}
	worker.ID = "opr-1"

	c := &InboxController{
		Events: &fakeInboxStore{events: []domain.OrchestratorInboxEvent{
			{ID: "evt-1", ProjectID: "proj-1", WorkerID: "opr-1", Kind: domain.InboxEventWorkerIdle},
			{ID: "evt-2", ProjectID: "proj-1", WorkerID: "opr-gone", Kind: domain.InboxEventWorkerIdle},
		}},
		Sessions: &fakeInboxSessions{sessions: map[domain.SessionID]domain.Session{"opr-1": worker}},
	}
	r := chi.NewRouter()
	c.Register(r)

	req := httptest.NewRequest(http.MethodGet, "/projects/proj-1/inbox", nil)
	rr := httptest.NewRecorder()
	r.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rr.Code, rr.Body.String())
	}
	var res InboxResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &res); err != nil {
		t.Fatal(err)
	}
	if len(res.Entries) != 2 {
		t.Fatalf("entries = %+v, want both rows: an unresolvable worker must not make its row un-ackable", res.Entries)
	}
	degraded := res.Entries[1]
	if degraded.ID != "evt-2" || degraded.Kind != string(domain.InboxEventWorkerIdle) {
		t.Fatalf("degraded entry = %+v, want its id and kind intact so it can be acked", degraded)
	}
	if degraded.Worker.ID != "" {
		t.Fatalf("degraded entry worker = %+v, want the zero value", degraded.Worker)
	}
}

func TestInboxAckIsANoopForUnknownIds(t *testing.T) {
	store := &fakeInboxStore{}
	c := &InboxController{Events: store, Sessions: &fakeInboxSessions{sessions: map[domain.SessionID]domain.Session{}}}
	r := chi.NewRouter()
	c.Register(r)

	body := strings.NewReader(`{"ids":["unknown-1"]}`)
	req := httptest.NewRequest(http.MethodPost, "/projects/proj-1/inbox/ack", body)
	rr := httptest.NewRecorder()
	r.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rr.Code, rr.Body.String())
	}
}
