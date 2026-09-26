package controllers_test

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
)

type fakePermissionModes struct {
	modes  map[domain.SessionID]domain.PermissionModeObservation
	err    error
	allErr error
}

func (f fakePermissionModes) LatestPermissionModes(context.Context) (map[domain.SessionID]domain.PermissionModeObservation, error) {
	if f.allErr != nil {
		return nil, f.allErr
	}
	return f.modes, f.err
}

func (f fakePermissionModes) LatestPermissionMode(_ context.Context, id domain.SessionID) (domain.PermissionModeObservation, bool, error) {
	observation, ok := f.modes[id]
	return observation, ok, f.err
}

type fakePermissionModeGate struct{ version string }

func (f fakePermissionModeGate) PermissionModeSupport(harness domain.AgentHarness, version string) bool {
	return harness == domain.HarnessClaudeCode && version == f.version
}

func (fakePermissionModeGate) PermissionModeReadable(harness domain.AgentHarness) bool {
	return harness == domain.HarnessClaudeCode
}

func permissionModeServer(t *testing.T, modes fakePermissionModes) *httptest.Server {
	t.Helper()
	return permissionModeServerFor(t, domain.HarnessClaudeCode, modes)
}

func permissionModeServerFor(t *testing.T, harness domain.AgentHarness, modes fakePermissionModes) *httptest.Server {
	t.Helper()
	svc := newFakeSessionService()
	s := svc.sessions["opr-1"]
	s.Harness = harness
	s.LaunchPermissionMode = domain.PermissionModeBypassPermissions
	svc.sessions["opr-1"] = s
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{Sessions: svc, SessionPermissionModes: modes, PermissionModeGate: fakePermissionModeGate{version: "2.1.280"}}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestSessionViewsReportTheObservedPermissionMode(t *testing.T) {
	srv := permissionModeServer(t, fakePermissionModes{modes: map[domain.SessionID]domain.PermissionModeObservation{
		"opr-1": {Mode: domain.PermissionModePlan, Version: "2.1.280"},
	}})

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/opr-1", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d body = %s", status, body)
	}
	var got controllers.SessionResponse
	mustJSON(t, body, &got)
	if got.Session.PermissionMode != "plan" || !got.Session.Capabilities.PermissionMode {
		t.Fatalf("session = %+v", got.Session)
	}
	if strings.Contains(string(body), "permissionModeCycle") {
		t.Fatalf("the session view still carries a predicted Shift+Tab cycle: %s", body)
	}
}

func TestSessionViewsOmitAModeTheTranscriptReportedAsUnknown(t *testing.T) {
	srv := permissionModeServer(t, fakePermissionModes{modes: map[domain.SessionID]domain.PermissionModeObservation{
		"opr-1": {Version: "2.1.280"},
	}})

	for _, path := range []string{"/api/v1/sessions/opr-1", "/api/v1/sessions"} {
		body, status, _ := doRequest(t, srv, http.MethodGet, path, "")
		if status != http.StatusOK {
			t.Fatalf("%s status = %d body = %s", path, status, body)
		}
		if strings.Contains(string(body), `"permissionMode":"`) || !strings.Contains(string(body), `"permissionMode":true`) {
			t.Fatalf("%s body = %s; want no mode, still changeable", path, body)
		}
	}
}

func TestSessionViewsFallBackToTheLaunchModeBeforeTheTranscriptReports(t *testing.T) {
	srv := permissionModeServer(t, fakePermissionModes{})

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d body = %s", status, body)
	}
	var got controllers.ListSessionsResponse
	mustJSON(t, body, &got)
	if len(got.Sessions) != 1 || got.Sessions[0].PermissionMode != "bypass-permissions" || got.Sessions[0].Capabilities.PermissionMode {
		t.Fatalf("sessions = %+v; want the launch mode and no capability before a version is known", got.Sessions)
	}
}

func TestSessionViewsKeepTheLaunchModeWhenTheReadFails(t *testing.T) {
	srv := permissionModeServer(t, fakePermissionModes{err: errors.New("db closed")})

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions", "")
	if status != http.StatusOK || !strings.Contains(string(body), `"permissionMode":"bypass-permissions"`) {
		t.Fatalf("status = %d body = %s", status, body)
	}
}

func TestSessionGetReadsOnlyThatSessionsPermissionMode(t *testing.T) {
	srv := permissionModeServer(t, fakePermissionModes{
		modes:  map[domain.SessionID]domain.PermissionModeObservation{"opr-1": {Mode: domain.PermissionModePlan, Version: "2.1.280"}},
		allErr: errors.New("the get endpoint must not read every session"),
	})

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/opr-1", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d body = %s", status, body)
	}
	var got controllers.SessionResponse
	mustJSON(t, body, &got)
	if got.Session.PermissionMode != "plan" || !got.Session.Capabilities.PermissionMode {
		t.Fatalf("session = %+v", got.Session)
	}
}

func TestSessionViewsLeaveThePermissionModeEmptyForAHarnessWithoutAReader(t *testing.T) {
	srv := permissionModeServerFor(t, domain.HarnessCodex, fakePermissionModes{})

	for _, path := range []string{"/api/v1/sessions", "/api/v1/sessions/opr-1"} {
		body, status, _ := doRequest(t, srv, http.MethodGet, path, "")
		if status != http.StatusOK {
			t.Fatalf("%s status = %d body = %s", path, status, body)
		}
		if strings.Contains(string(body), `"permissionMode":"`) || strings.Contains(string(body), `"permissionMode":true`) {
			t.Fatalf("%s body = %s; want no permission mode and no capability", path, body)
		}
	}
}
