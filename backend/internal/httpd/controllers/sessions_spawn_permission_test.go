package controllers_test

import (
	"net/http"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestSpawnForwardsThePermissionMode(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions", `{"projectId":"opr","permissionMode":"bypass-permissions"}`)
	if status != http.StatusCreated {
		t.Fatalf("status = %d, want 201; body=%s", status, body)
	}
	if got := svc.lastSpawnConfig.AgentConfig.Permissions; got != domain.PermissionModeBypassPermissions {
		t.Fatalf("spawn permissions = %q, want bypass-permissions", got)
	}
}

func TestSpawnWithoutAPermissionModeLeavesTheProjectDefault(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions", `{"projectId":"opr"}`)
	if status != http.StatusCreated {
		t.Fatalf("status = %d, want 201; body=%s", status, body)
	}
	if got := svc.lastSpawnConfig.AgentConfig.Permissions; got != "" {
		t.Fatalf("spawn permissions = %q, want empty", got)
	}
}

func TestSpawnRejectsAnUnknownPermissionMode(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions", `{"projectId":"opr","permissionMode":"yolo"}`)
	assertErrorCode(t, body, status, http.StatusBadRequest, "INVALID_PERMISSION_MODE")
}
