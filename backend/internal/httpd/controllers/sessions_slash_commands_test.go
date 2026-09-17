package controllers_test

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
)

func newSendWithBlocksServer(t *testing.T, svc *fakeSessionService, rec *fakeBlockEventRecorder) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{Sessions: svc, BlockEvents: rec}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestSendBuiltinSlashCommandRecordsPromptBlock(t *testing.T) {
	svc := newFakeSessionService()
	s := svc.sessions["opr-1"]
	s.Harness = "claude-code"
	svc.sessions["opr-1"] = s
	rec := &fakeBlockEventRecorder{}
	srv := newSendWithBlocksServer(t, svc, rec)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/send", `{"message":"/compact"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if rec.calls != 1 {
		t.Fatalf("Record calls = %d, want 1", rec.calls)
	}
	if rec.gotID != domain.SessionID("opr-1") || rec.gotHarness != "claude-code" {
		t.Fatalf("recorded for %s/%s, want opr-1/claude-code", rec.gotID, rec.gotHarness)
	}
	if rec.gotSignal.Event != "user-prompt-submit" || rec.gotSignal.LatestUserPrompt != "/compact" {
		t.Fatalf("signal = %+v, want user-prompt-submit carrying /compact", rec.gotSignal)
	}
}

func TestSendPlainMessageRecordsNoBlock(t *testing.T) {
	svc := newFakeSessionService()
	rec := &fakeBlockEventRecorder{}
	srv := newSendWithBlocksServer(t, svc, rec)

	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/send", `{"message":"hello"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if rec.calls != 0 {
		t.Fatalf("Record calls = %d, want 0 (the hook records ordinary prompts)", rec.calls)
	}
}

func TestSendBuiltinOnOtherHarnessRecordsNoBlock(t *testing.T) {
	svc := newFakeSessionService()
	s := svc.sessions["opr-1"]
	s.Harness = "codex"
	svc.sessions["opr-1"] = s
	rec := &fakeBlockEventRecorder{}
	srv := newSendWithBlocksServer(t, svc, rec)

	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/send", `{"message":"/compact"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if rec.calls != 0 {
		t.Fatalf("Record calls = %d, want 0 for a non-claude harness", rec.calls)
	}
}
