package controllers_test

import (
	"net/http"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	sessionmanager "github.com/OmarAly92/operator/backend/internal/session_manager"
)

func TestSessionCommandSentOnSuccess(t *testing.T) {
	svc := newFakeSessionService()
	svc.commandResult = sessionmanager.CommandResult{Wrote: true}
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/command", `{"command":"stop"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	var got controllers.SessionCommandResponse
	mustJSON(t, body, &got)
	if got.State != "sent" {
		t.Fatalf("state = %q, want sent", got.State)
	}
	if svc.commandCalls != 1 {
		t.Fatalf("service called %d times, want 1", svc.commandCalls)
	}
}

func TestSessionCommandRejectsUnknownVerb(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/command", `{"command":"reboot"}`)
	assertErrorCode(t, body, status, http.StatusBadRequest, "SESSION_COMMAND_UNKNOWN")
	if svc.commandCalls != 0 {
		t.Fatal("an unknown verb must not reach the service")
	}
}

func TestSessionCommandWrongStateIsConflict(t *testing.T) {
	svc := newFakeSessionService()
	svc.commandErr = sessionmanager.ErrWrongActivityState
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/command", `{"command":"stop"}`)
	assertErrorCode(t, body, status, http.StatusConflict, "SESSION_COMMAND_UNAVAILABLE")
}

func TestSessionCommandBlockedIsAwaitingDecision(t *testing.T) {
	svc := newFakeSessionService()
	svc.commandErr = sessionmanager.ErrAwaitingDecision
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/command", `{"command":"compact"}`)
	assertErrorCode(t, body, status, http.StatusConflict, "SESSION_AWAITING_DECISION")
}

func TestSessionCommandModelRequiresALabel(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/command", `{"command":"model"}`)
	assertErrorCode(t, body, status, http.StatusBadRequest, "SESSION_COMMAND_MODEL_REQUIRED")
	if svc.commandCalls != 0 {
		t.Fatal("a model command with no label must not reach the service")
	}
}

func TestSessionCommandModelNotOfferedIncludesOfferedModels(t *testing.T) {
	svc := newFakeSessionService()
	svc.commandErr = sessionmanager.ErrModelNotOffered
	svc.commandResult = sessionmanager.CommandResult{Models: []string{"sonnet", "haiku"}}
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/command", `{"command":"model","model":"opus"}`)
	assertErrorCode(t, body, status, http.StatusConflict, "SESSION_MODEL_NOT_OFFERED")

	var got errorBody
	mustJSON(t, body, &got)
	models, ok := got.Details["models"].([]any)
	if !ok {
		t.Fatalf("details.models missing or wrong type: %#v", got.Details)
	}
	want := []string{"sonnet", "haiku"}
	if len(models) != len(want) {
		t.Fatalf("models = %v, want %v", models, want)
	}
	for i, m := range models {
		if m != want[i] {
			t.Fatalf("models = %v, want %v", models, want)
		}
	}
}

func TestSessionCommandReportsANonEmptyComposerAsAConflict(t *testing.T) {
	svc := newFakeSessionService()
	svc.commandErr = sessionmanager.ErrComposerNotEmpty
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/command", `{"command":"compact"}`)
	assertErrorCode(t, body, status, http.StatusConflict, "SESSION_COMPOSER_NOT_EMPTY")
}
