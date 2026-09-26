package controllers_test

import (
	"errors"
	"fmt"
	"net/http"
	"slices"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	sessionmanager "github.com/OmarAly92/operator/backend/internal/session_manager"
)

func TestSessionCommandPermissionModeReportsTheConfirmedMode(t *testing.T) {
	svc := newFakeSessionService()
	svc.permissionModeResult = sessionmanager.PermissionModeResult{Mode: domain.PermissionModePlan}
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/command", `{"command":"permission-mode","mode":"plan"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d body = %s", status, body)
	}
	var got controllers.SessionCommandResponse
	mustJSON(t, body, &got)
	if got.State != "sent" || got.PermissionMode != "plan" || got.Restarted {
		t.Fatalf("response = %+v", got)
	}
	if !slices.Equal(svc.permissionModeTargets, []domain.PermissionMode{domain.PermissionModePlan}) || svc.commandCalls != 0 {
		t.Fatalf("targets = %v commandCalls = %d", svc.permissionModeTargets, svc.commandCalls)
	}
}

func TestSessionCommandPermissionModeReportsARestart(t *testing.T) {
	svc := newFakeSessionService()
	svc.permissionModeResult = sessionmanager.PermissionModeResult{Mode: domain.PermissionModeAuto, Restarted: true}
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/command", `{"command":"permission-mode","mode":"auto"}`)
	var got controllers.SessionCommandResponse
	mustJSON(t, body, &got)
	if status != http.StatusOK || got.PermissionMode != "auto" || !got.Restarted {
		t.Fatalf("status = %d response = %+v", status, got)
	}
}

func TestSessionCommandPermissionModeRequiresAMode(t *testing.T) {
	for _, payload := range []string{
		`{"command":"permission-mode"}`,
		`{"command":"permission-mode","mode":"  "}`,
	} {
		svc := newFakeSessionService()
		srv := newSessionTestServer(t, svc)
		body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/command", payload)
		assertErrorCode(t, body, status, http.StatusBadRequest, "SESSION_COMMAND_MODE_REQUIRED")
		if len(svc.permissionModeTargets) != 0 {
			t.Fatalf("payload %s reached the service", payload)
		}
	}
}

func TestSessionCommandPermissionModeRejectsAnInvalidModeLikeSpawn(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)
	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/command", `{"command":"permission-mode","mode":"yolo"}`)
	assertErrorCode(t, body, status, http.StatusBadRequest, "INVALID_PERMISSION_MODE")
	var got errorBody
	mustJSON(t, body, &got)
	if got.Error != "bad_request" {
		t.Fatalf("error = %q, want bad_request like spawn", got.Error)
	}
	if len(svc.permissionModeTargets) != 0 {
		t.Fatal("an invalid mode reached the service")
	}
}

func TestSessionCommandPermissionModeErrorCodes(t *testing.T) {
	tests := []struct {
		name   string
		err    error
		status int
		code   string
	}{
		{"unsupported", sessionmanager.ErrPermissionModeUnsupported, http.StatusConflict, "PERMISSION_MODE_UNSUPPORTED"},
		{"unreadable observation", fmt.Errorf("permission mode opr-1: %w: %w", sessionmanager.ErrPermissionModeUnsupported, errors.New("db closed")), http.StatusConflict, "PERMISSION_MODE_UNSUPPORTED"},
		{"unconfirmed", sessionmanager.ErrPermissionModeUnconfirmed, http.StatusConflict, "PERMISSION_MODE_UNCONFIRMED"},
		{"busy", sessionmanager.ErrSessionBusy, http.StatusConflict, "SESSION_BUSY"},
		{"awaiting", sessionmanager.ErrAwaitingDecision, http.StatusConflict, "SESSION_AWAITING_DECISION"},
		{"unavailable", sessionmanager.ErrWrongActivityState, http.StatusConflict, "SESSION_COMMAND_UNAVAILABLE"},
		{"exited", sessionmanager.ErrAgentExited, http.StatusConflict, "SESSION_NOT_RUNNING"},
		{"not found", sessionmanager.ErrNotFound, http.StatusNotFound, "SESSION_NOT_FOUND"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc := newFakeSessionService()
			svc.permissionModeErr = tt.err
			srv := newSessionTestServer(t, svc)
			body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/command", `{"command":"permission-mode","mode":"auto"}`)
			assertErrorCode(t, body, status, tt.status, tt.code)
		})
	}
}
