package controllers_test

import (
	"net/http"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	sessionmanager "github.com/OmarAly92/operator/backend/internal/session_manager"
)

func TestSessionDecisionSentOnSuccess(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/decision", `{"requestId":"i1","behavior":"allow"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	var got controllers.SessionDecisionResponse
	mustJSON(t, body, &got)
	if got.State != "sent" {
		t.Fatalf("state = %q, want sent", got.State)
	}
	if svc.decideCalls != 1 {
		t.Fatalf("service called %d times, want 1", svc.decideCalls)
	}
}

func TestSessionDecisionDialogAbsentIsConflict(t *testing.T) {
	svc := newFakeSessionService()
	svc.decideErr = sessionmanager.ErrDialogAbsent
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/decision", `{"requestId":"i1","behavior":"allow"}`)
	assertErrorCode(t, body, status, http.StatusConflict, "SESSION_DIALOG_ABSENT")
}

func TestSessionDecisionUnconfirmedIsOK(t *testing.T) {
	svc := newFakeSessionService()
	svc.decideErr = sessionmanager.ErrUnconfirmed
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/decision", `{"requestId":"i1","behavior":"allow"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — unconfirmed is not an error; body=%s", status, body)
	}
	var got controllers.SessionDecisionResponse
	mustJSON(t, body, &got)
	if got.State != "unconfirmed" {
		t.Fatalf("state = %q, want unconfirmed", got.State)
	}
}

func TestSessionDecisionRejectsUnknownBehavior(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/decision", `{"requestId":"i1","behavior":"maybe"}`)
	assertErrorCode(t, body, status, http.StatusBadRequest, "SESSION_DECISION_INVALID")
	if svc.decideCalls != 0 {
		t.Fatal("an unknown behavior must not reach the service")
	}
}

func TestSessionDecisionNotFound(t *testing.T) {
	svc := newFakeSessionService()
	svc.decideErr = sessionmanager.ErrNotFound
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/decision", `{"requestId":"i1","behavior":"allow"}`)
	assertErrorCode(t, body, status, http.StatusNotFound, "SESSION_NOT_FOUND")
}

func TestSendRemainsRefusedWhileAnApprovalIsPending(t *testing.T) {
	svc := newFakeSessionService()
	svc.sendErr = sessionmanager.ErrAwaitingDecision
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/send", `{"message":"hi"}`)
	if status != http.StatusConflict {
		t.Fatalf("status = %d, want 409 — decision is the ONLY write admitted while blocked; body=%s", status, body)
	}
}
