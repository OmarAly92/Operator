package controllers_test

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
)

// SetAgentReport stores the report verbatim; validation belongs to the session
// service and is tested there.
func (f *fakeSessionService) SetAgentReport(_ context.Context, id domain.SessionID, state domain.AgentReportState, reason string) (domain.Session, error) {
	s, ok := f.sessions[id]
	if !ok {
		return domain.Session{}, apierr.NotFound("SESSION_NOT_FOUND", "Unknown session")
	}
	if state == "" {
		s.AgentReport = nil
	} else {
		s.AgentReport = &domain.AgentReport{State: state, Reason: reason, At: time.Now().UTC()}
	}
	f.sessions[id] = s
	return s, nil
}

func TestAgentReportRouteSetsAndClearsTheReport(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "PUT", "/api/v1/sessions/opr-1/agent-report", `{"state":"needs_you","reason":"Which database should I use?"}`)
	if status != http.StatusOK {
		t.Fatalf("set = %d, want 200; body=%s", status, body)
	}
	var set struct {
		Session struct {
			AgentReport *struct {
				State  string `json:"state"`
				Reason string `json:"reason"`
			} `json:"agentReport"`
		} `json:"session"`
	}
	mustJSON(t, body, &set)
	if set.Session.AgentReport == nil || set.Session.AgentReport.State != "needs_you" || set.Session.AgentReport.Reason != "Which database should I use?" {
		t.Fatalf("set response = %s", body)
	}

	body, status, _ = doRequest(t, srv, "DELETE", "/api/v1/sessions/opr-1/agent-report", "")
	if status != http.StatusOK {
		t.Fatalf("clear = %d, want 200; body=%s", status, body)
	}
	if svc.sessions["opr-1"].AgentReport != nil {
		t.Fatalf("report not cleared: %+v", svc.sessions["opr-1"].AgentReport)
	}
	var cleared map[string]map[string]any
	mustJSON(t, body, &cleared)
	if _, present := cleared["session"]["agentReport"]; present {
		t.Fatalf("cleared session still serializes agentReport: %s", body)
	}
}

func TestAgentReportRouteRejectsBadInput(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	for _, tc := range []struct {
		name, path, body string
		want             int
	}{
		{"invalid json", "/api/v1/sessions/opr-1/agent-report", `{`, http.StatusBadRequest},
		{"missing state", "/api/v1/sessions/opr-1/agent-report", `{"reason":"x"}`, http.StatusBadRequest},
		{"unknown session", "/api/v1/sessions/ghost/agent-report", `{"state":"needs_you","reason":"x"}`, http.StatusNotFound},
	} {
		t.Run(tc.name, func(t *testing.T) {
			body, status, _ := doRequest(t, srv, "PUT", tc.path, tc.body)
			if status != tc.want {
				t.Fatalf("status = %d, want %d; body=%s", status, tc.want, body)
			}
		})
	}
}
