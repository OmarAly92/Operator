package controllers_test

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/ports"
	slashcommandssvc "github.com/OmarAly92/operator/backend/internal/service/slashcommands"
	"github.com/OmarAly92/operator/backend/internal/slashcommands"
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

type fakeSlashCommandLister struct {
	commands []slashcommands.Command
	err      error
	gotID    domain.SessionID
}

func (f *fakeSlashCommandLister) List(_ context.Context, id domain.SessionID) ([]slashcommands.Command, error) {
	f.gotID = id
	return f.commands, f.err
}

func TestListSlashCommands(t *testing.T) {
	lister := &fakeSlashCommandLister{commands: []slashcommands.Command{
		{Name: "compact", Description: "Clear conversation history but keep a summary in context", Source: "builtin"},
		{Name: "model", Description: "Set the AI model for Claude Code", Source: "builtin", Interactive: true},
		{Name: "sc:analyze", Description: "Comprehensive code analysis", Source: "user"},
	}}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{Sessions: newFakeSessionService(), SlashCommands: lister}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/opr-1/slash-commands", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if lister.gotID != "opr-1" {
		t.Fatalf("listed %q, want opr-1", lister.gotID)
	}
	want := `{"commands":[` +
		`{"name":"compact","description":"Clear conversation history but keep a summary in context","source":"builtin","interactive":false},` +
		`{"name":"model","description":"Set the AI model for Claude Code","source":"builtin","interactive":true},` +
		`{"name":"sc:analyze","description":"Comprehensive code analysis","source":"user","interactive":false}]}`
	if strings.TrimSpace(string(body)) != want {
		t.Fatalf("body:\n got %s\nwant %s", body, want)
	}
}

func TestListSlashCommandsUnknownSession(t *testing.T) {
	lister := &fakeSlashCommandLister{err: slashcommandssvc.ErrSessionNotFound}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{Sessions: newFakeSessionService(), SlashCommands: lister}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/ghost/slash-commands", "")
	assertErrorCode(t, body, status, http.StatusNotFound, "SESSION_NOT_FOUND")
}

func TestListSlashCommandsNotWired(t *testing.T) {
	srv := newSessionTestServer(t, newFakeSessionService())
	_, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/opr-1/slash-commands", "")
	if status != http.StatusNotImplemented {
		t.Fatalf("status = %d, want 501 when the lister is nil", status)
	}
}

type recordingBlockEvents struct {
	signals []ports.ActivitySignal
}

func (r *recordingBlockEvents) Record(_ context.Context, _ domain.SessionID, _ string, sig ports.ActivitySignal) error {
	r.signals = append(r.signals, sig)
	return nil
}

func TestSendBuiltinRecordsThePaneOutputAsTheReply(t *testing.T) {
	svc := newFakeSessionService()
	s := svc.sessions["opr-1"]
	s.Harness = "claude-code"
	svc.sessions["opr-1"] = s
	svc.slashOutput = "Context Usage\n⛁ ⛁ ⛁   Sonnet 5"
	rec := &recordingBlockEvents{}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{Sessions: svc, BlockEvents: rec}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)

	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/send", `{"message":"/context"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if svc.slashOutputCalls != 1 || svc.slashOutputMessage != "/context" {
		t.Fatalf("SlashOutput called %d times with %q, want once with /context", svc.slashOutputCalls, svc.slashOutputMessage)
	}
	if len(rec.signals) != 2 {
		t.Fatalf("recorded %d signals, want prompt then stop: %+v", len(rec.signals), rec.signals)
	}
	if rec.signals[0].Event != "user-prompt-submit" || rec.signals[0].LatestUserPrompt != "/context" {
		t.Fatalf("first signal = %+v", rec.signals[0])
	}
	if rec.signals[1].Event != "stop" || rec.signals[1].LatestAssistantUpdate != svc.slashOutput || rec.signals[1].Harness != "claude-code" {
		t.Fatalf("second signal = %+v", rec.signals[1])
	}
}

func TestSendBuiltinWithNoPaneOutputRecordsOnlyThePrompt(t *testing.T) {
	svc := newFakeSessionService()
	s := svc.sessions["opr-1"]
	s.Harness = "claude-code"
	svc.sessions["opr-1"] = s
	rec := &recordingBlockEvents{}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{Sessions: svc, BlockEvents: rec}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)

	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/send", `{"message":"/compact"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if len(rec.signals) != 1 || rec.signals[0].Event != "user-prompt-submit" {
		t.Fatalf("signals = %+v, want just the prompt", rec.signals)
	}
}
