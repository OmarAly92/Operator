package controllers_test

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/ports"
	slashcommandssvc "github.com/OmarAly92/operator/backend/internal/service/slashcommands"
	sessionmanager "github.com/OmarAly92/operator/backend/internal/session_manager"
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
	mu      sync.Mutex
	signals []ports.ActivitySignal
}

func (r *recordingBlockEvents) Record(_ context.Context, _ domain.SessionID, _ string, sig ports.ActivitySignal) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.signals = append(r.signals, sig)
	return nil
}

func (r *recordingBlockEvents) snapshot() []ports.ActivitySignal {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]ports.ActivitySignal(nil), r.signals...)
}

func waitForSignals(t *testing.T, rec *recordingBlockEvents, n int) []ports.ActivitySignal {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for {
		got := rec.snapshot()
		if len(got) >= n || time.Now().After(deadline) {
			return got
		}
		time.Sleep(5 * time.Millisecond)
	}
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
	signals := waitForSignals(t, rec, 2)
	if len(signals) != 2 {
		t.Fatalf("recorded %d signals, want prompt then stop: %+v", len(signals), signals)
	}
	if calls, msg := svc.slashOutputSeen(); calls != 1 || msg != "/context" {
		t.Fatalf("SlashOutput called %d times with %q, want once with /context", calls, msg)
	}
	if signals[0].Event != "user-prompt-submit" || signals[0].LatestUserPrompt != "/context" {
		t.Fatalf("first signal = %+v", signals[0])
	}
	if signals[1].Event != "stop" || signals[1].LatestAssistantUpdate != "```text\n"+svc.slashOutput+"\n```" || signals[1].Harness != "claude-code" {
		t.Fatalf("second signal = %+v", signals[1])
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
	signals := waitForSignals(t, rec, 1)
	time.Sleep(20 * time.Millisecond)
	if signals = rec.snapshot(); len(signals) != 1 || signals[0].Event != "user-prompt-submit" {
		t.Fatalf("signals = %+v, want just the prompt", signals)
	}
}

func TestListModelsReturnsThePickerRows(t *testing.T) {
	svc := newFakeSessionService()
	svc.models = []sessionmanager.ModelOption{
		{Label: "Opus (1M context)", Description: "Opus 5 with 1M context"},
		{Label: "Sonnet", Description: "Sonnet 5 · Efficient for routine tasks", Current: true},
	}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{Sessions: svc}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/opr-1/models", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", status, body)
	}
	want := `{"models":[{"label":"Opus (1M context)","description":"Opus 5 with 1M context","current":false},` +
		`{"label":"Sonnet","description":"Sonnet 5 · Efficient for routine tasks","current":true}]}`
	if strings.TrimSpace(string(body)) != want {
		t.Fatalf("body = %s, want %s", body, want)
	}
}

func TestListModelsMapsCommandErrors(t *testing.T) {
	svc := newFakeSessionService()
	svc.modelsErr = sessionmanager.ErrWrongActivityState
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{Sessions: svc}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/opr-1/models", "")
	if status != http.StatusConflict || !strings.Contains(string(body), "SESSION_COMMAND_UNAVAILABLE") {
		t.Fatalf("status = %d body = %s, want 409 SESSION_COMMAND_UNAVAILABLE", status, body)
	}
}

type fakeModelReader struct {
	models map[domain.SessionID]string
	err    error
}

func (f fakeModelReader) LatestModels(context.Context) (map[domain.SessionID]string, error) {
	return f.models, f.err
}

func TestSessionViewsCarryTheLatestTurnModel(t *testing.T) {
	svc := newFakeSessionService()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{Sessions: svc, SessionModels: fakeModelReader{models: map[domain.SessionID]string{"opr-1": "claude-sonnet-5"}}}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions", "")
	if status != http.StatusOK || !strings.Contains(string(body), `"model":"claude-sonnet-5"`) {
		t.Fatalf("list status = %d body = %s, want the model on opr-1", status, body)
	}
	body, status, _ = doRequest(t, srv, http.MethodGet, "/api/v1/sessions/opr-1", "")
	if status != http.StatusOK || !strings.Contains(string(body), `"model":"claude-sonnet-5"`) {
		t.Fatalf("get status = %d body = %s, want the model", status, body)
	}
}

func TestSessionViewsOmitTheModelWhenTheReadFails(t *testing.T) {
	svc := newFakeSessionService()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{Sessions: svc, SessionModels: fakeModelReader{err: errors.New("db closed")}}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions", "")
	if status != http.StatusOK || strings.Contains(string(body), `"model"`) {
		t.Fatalf("status = %d body = %s, want 200 without a model", status, body)
	}
}
