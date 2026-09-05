package controllers_test

import (
	"net/http"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	sessionmanager "github.com/OmarAly92/operator/backend/internal/session_manager"
)

func TestSessionAnswerSentOnSuccess(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/answer", `{"requestId":"q1","selections":[["second"]]}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	var got controllers.SessionAnswerResponse
	mustJSON(t, body, &got)
	if got.State != "sent" {
		t.Fatalf("state = %q, want sent", got.State)
	}
	if svc.answerCalls != 1 {
		t.Fatalf("service called %d times, want 1", svc.answerCalls)
	}
}

func TestSessionAnswerDialogAbsentIsConflict(t *testing.T) {
	svc := newFakeSessionService()
	svc.answerErr = sessionmanager.ErrDialogAbsent
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/answer", `{"requestId":"q1","selections":[["second"]]}`)
	assertErrorCode(t, body, status, http.StatusConflict, "SESSION_DIALOG_ABSENT")
}

func TestSessionAnswerUnconfirmedIsOK(t *testing.T) {
	svc := newFakeSessionService()
	svc.answerErr = sessionmanager.ErrUnconfirmed
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/answer", `{"requestId":"q1","selections":[["second"]]}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — unconfirmed is not an error; body=%s", status, body)
	}
	var got controllers.SessionAnswerResponse
	mustJSON(t, body, &got)
	if got.State != "unconfirmed" {
		t.Fatalf("state = %q, want unconfirmed", got.State)
	}
}

func TestSessionAnswerRejectsAnInvalidSelection(t *testing.T) {
	svc := newFakeSessionService()
	svc.answerErr = sessionmanager.ErrAnswerInvalid
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/answer", `{"requestId":"q1","selections":[]}`)
	assertErrorCode(t, body, status, http.StatusBadRequest, "SESSION_ANSWER_INVALID")
}

func TestSessionAnswerNotFound(t *testing.T) {
	svc := newFakeSessionService()
	svc.answerErr = sessionmanager.ErrNotFound
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s1/answer", `{"requestId":"q1","selections":[["second"]]}`)
	assertErrorCode(t, body, status, http.StatusNotFound, "SESSION_NOT_FOUND")
}
