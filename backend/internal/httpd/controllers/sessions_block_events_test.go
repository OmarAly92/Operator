package controllers_test

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/service/usage"
)

type fakeBlockEventRecorder struct {
	gotID      domain.SessionID
	gotHarness string
	gotSignal  ports.ActivitySignal
	calls      int
	err        error
}

func (f *fakeBlockEventRecorder) Record(_ context.Context, id domain.SessionID, harness string, sig ports.ActivitySignal) error {
	f.calls++
	f.gotID = id
	f.gotHarness = harness
	f.gotSignal = sig
	return f.err
}

func newBlockEventsTestServer(t *testing.T, rec *fakeBlockEventRecorder) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{
		Activity:  noopActivityRecorder{},
		UsageHooks: noopUsageHookRecorder{},
	}
	if rec != nil {
		deps.BlockEvents = rec
	}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

type noopActivityRecorder struct{}

func (noopActivityRecorder) ApplyActivitySignal(context.Context, domain.SessionID, ports.ActivitySignal) error {
	return nil
}

type noopUsageHookRecorder struct{}

func (noopUsageHookRecorder) RecordHook(context.Context, domain.SessionID, usage.HookSignal) error {
	return nil
}

func TestSessionsAPI_ActivityRecordsBlockEvent(t *testing.T) {
	rec := &fakeBlockEventRecorder{}
	srv := newBlockEventsTestServer(t, rec)

	body, status, _ := doRequest(t, srv, "POST", "/api/v1/sessions/opr-1/activity", `{
		"state":"active",
		"event":"post-tool-use",
		"toolName":"Bash",
		"toolUseId":"tu-1",
		"usage":{"harness":"claude-code"}
	}`)
	if status != http.StatusOK {
		t.Fatalf("activity = %d, want 200; body=%s", status, body)
	}
	if rec.calls != 1 {
		t.Fatalf("block recorder calls = %d, want 1", rec.calls)
	}
	if rec.gotID != "opr-1" {
		t.Fatalf("session id = %q, want opr-1", rec.gotID)
	}
	if rec.gotHarness != "claude-code" {
		t.Fatalf("harness = %q, want claude-code", rec.gotHarness)
	}
	if rec.gotSignal.ToolUseID != "tu-1" {
		t.Fatalf("ToolUseID = %q, want tu-1", rec.gotSignal.ToolUseID)
	}
}

func TestSessionsAPI_ActivitySkipsBlockEventWithoutAnEventName(t *testing.T) {
	rec := &fakeBlockEventRecorder{}
	srv := newBlockEventsTestServer(t, rec)

	_, status, _ := doRequest(t, srv, "POST", "/api/v1/sessions/opr-1/activity", `{"state":"active"}`)
	if status != http.StatusOK {
		t.Fatalf("activity = %d, want 200", status)
	}
	if rec.calls != 0 {
		t.Fatalf("block recorder calls = %d, want 0 for an eventless signal", rec.calls)
	}
}

func TestSessionsAPI_ActivitySurvivesBlockRecorderFailure(t *testing.T) {
	rec := &fakeBlockEventRecorder{err: context.DeadlineExceeded}
	srv := newBlockEventsTestServer(t, rec)

	body, status, _ := doRequest(t, srv, "POST", "/api/v1/sessions/opr-1/activity", `{"state":"active","event":"stop"}`)
	if status != http.StatusOK {
		t.Fatalf("activity = %d, want 200 despite a failing block recorder; body=%s", status, body)
	}
}

func TestSessionsAPI_ActivityWorksWithNoBlockRecorder(t *testing.T) {
	srv := newBlockEventsTestServer(t, nil)

	_, status, _ := doRequest(t, srv, "POST", "/api/v1/sessions/opr-1/activity", `{"state":"active","event":"stop"}`)
	if status != http.StatusOK {
		t.Fatalf("activity = %d, want 200 with a nil recorder", status)
	}
}
