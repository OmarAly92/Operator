package controllers_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	shelltermsvc "github.com/OmarAly92/operator/backend/internal/service/shellterm"
)

type fakeShellTerminalService struct {
	gotOpenInput   shelltermsvc.OpenShellTerminalInput
	gotCloseID     string
	gotRenameID    string
	gotRenameTitle string
	opened         shelltermsvc.ShellTerminal
	renamed        shelltermsvc.ShellTerminal
	listed         []shelltermsvc.ShellTerminal
	err            error
}

func (f *fakeShellTerminalService) OpenShellTerminal(_ context.Context, in shelltermsvc.OpenShellTerminalInput) (shelltermsvc.ShellTerminal, error) {
	f.gotOpenInput = in
	return f.opened, f.err
}

func (f *fakeShellTerminalService) ListShellTerminalsForCurrentAppRun(context.Context) ([]shelltermsvc.ShellTerminal, error) {
	return f.listed, f.err
}

func (f *fakeShellTerminalService) RenameShellTerminal(_ context.Context, handleID, title string) (shelltermsvc.ShellTerminal, error) {
	f.gotRenameID = handleID
	f.gotRenameTitle = title
	return f.renamed, f.err
}

func (f *fakeShellTerminalService) CloseShellTerminal(_ context.Context, handleID string) error {
	f.gotCloseID = handleID
	return f.err
}

func newShellTerminalTestServer(t *testing.T, svc controllers.ShellTerminalService) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{ShellTerminals: svc}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func newShellTerminalBlocksTestServer(t *testing.T, svc controllers.ShellTerminalService, blocks controllers.ShellTerminalBlockHistory) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{ShellTerminals: svc, ShellTerminalBlocks: blocks}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

type fakeShellTerminalBlockHistory struct {
	gotTerminalID string
	gotLimit      int
	blocks        []domain.Block
	err           error
}

func (f *fakeShellTerminalBlockHistory) History(_ context.Context, terminalID string, limit int) ([]domain.Block, error) {
	f.gotTerminalID = terminalID
	f.gotLimit = limit
	return f.blocks, f.err
}

func intPtr(v int) *int { return &v }

func sampleTerminalBlocks() []domain.Block {
	older := domain.Block{
		TerminalID:     "shellterm-abc123",
		SourceID:       "src-1",
		SessionID:      "portfolio-3",
		Command:        "echo hi",
		Cwd:            "/repos/portfolio",
		GitBranch:      "main",
		ExitCode:       intPtr(0),
		RawOutput:      []byte("hi\n"),
		StartedAt:      time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC),
		FinishedAt:     time.Date(2026, 7, 20, 12, 0, 1, 0, time.UTC),
		CreatedAt:      time.Date(2026, 7, 20, 12, 0, 1, 0, time.UTC),
		ShellKind:      "zsh",
		ShellVersion:   "5.9",
		TruncatedLines: 0,
		TruncatedBytes: 0,
		CaptureEpoch:   "epoch-1",
		StartOffset:    0,
		EndOffset:      3,
	}
	newer := domain.Block{
		TerminalID:     "shellterm-abc123",
		SourceID:       "src-2",
		Command:        "false",
		Cwd:            "/repos/portfolio",
		GitBranch:      "main",
		ExitCode:       nil,
		RawOutput:      []byte{0xff, 0xfe, 0x00, 0x01, 0x80},
		StartedAt:      time.Date(2026, 7, 20, 12, 1, 0, 0, time.UTC),
		FinishedAt:     time.Date(2026, 7, 20, 12, 1, 2, 0, time.UTC),
		CreatedAt:      time.Date(2026, 7, 20, 12, 1, 2, 0, time.UTC),
		ShellKind:      "zsh",
		ShellVersion:   "5.9",
		TruncatedLines: 4,
		TruncatedBytes: 128,
		CaptureEpoch:   "epoch-1",
		StartOffset:    3,
		EndOffset:      9,
	}
	return []domain.Block{older, newer}
}

func TestShellTerminalsAPI_BlocksReturnsHistoryOldestToNewest(t *testing.T) {
	svc := &fakeShellTerminalService{listed: []shelltermsvc.ShellTerminal{sampleShellTerminal()}}
	hist := &fakeShellTerminalBlockHistory{blocks: sampleTerminalBlocks()}
	srv := newShellTerminalBlocksTestServer(t, svc, hist)

	body, status, hdr := doRequest(t, srv, "GET", "/api/v1/shell-terminals/shellterm-abc123/blocks", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	assertJSON(t, hdr)

	var got []struct {
		TerminalID     string `json:"terminalId"`
		SourceID       string `json:"sourceId"`
		SessionID      string `json:"sessionId"`
		Command        string `json:"command"`
		Cwd            string `json:"cwd"`
		GitBranch      string `json:"gitBranch"`
		ExitCode       *int   `json:"exitCode"`
		RawOutput      string `json:"rawOutput"`
		ShellKind      string `json:"shellKind"`
		ShellVersion   string `json:"shellVersion"`
		TruncatedLines int    `json:"truncatedLines"`
		TruncatedBytes int    `json:"truncatedBytes"`
		CaptureEpoch   string `json:"captureEpoch"`
		StartOffset    int64  `json:"startOffset"`
		EndOffset      int64  `json:"endOffset"`
		StartedAt      string `json:"startedAt"`
		FinishedAt     string `json:"finishedAt"`
		CreatedAt      string `json:"createdAt"`
	}
	mustJSON(t, body, &got)
	if len(got) != 2 {
		t.Fatalf("blocks = %d, want 2", len(got))
	}
	if got[0].SourceID != "src-1" || got[1].SourceID != "src-2" {
		t.Fatalf("order = [%s %s], want oldest→newest [src-1 src-2]", got[0].SourceID, got[1].SourceID)
	}
	if hist.gotTerminalID != "shellterm-abc123" {
		t.Errorf("history keyed by %q, want the runtime handle", hist.gotTerminalID)
	}
	if hist.gotLimit != 100 {
		t.Errorf("default limit = %d, want 100", hist.gotLimit)
	}

	if got[0].ExitCode == nil || *got[0].ExitCode != 0 {
		t.Errorf("older exitCode = %v, want 0", got[0].ExitCode)
	}
	if !bytes.Contains(body, []byte(`"exitCode":null`)) {
		t.Errorf("nullable exitCode did not serialize as null; body=%s", body)
	}
	if got[1].ExitCode != nil {
		t.Errorf("newer exitCode = %v, want null", *got[1].ExitCode)
	}

	rawDecoded, err := base64.StdEncoding.DecodeString(got[1].RawOutput)
	if err != nil {
		t.Fatalf("rawOutput is not valid base64: %v", err)
	}
	if !bytes.Equal(rawDecoded, []byte{0xff, 0xfe, 0x00, 0x01, 0x80}) {
		t.Errorf("rawOutput round-trip = %x, want fffe000180", rawDecoded)
	}

	if got[1].TruncatedLines != 4 || got[1].TruncatedBytes != 128 {
		t.Errorf("truncation counters = (%d, %d), want (4, 128)", got[1].TruncatedLines, got[1].TruncatedBytes)
	}
	if got[1].CaptureEpoch != "epoch-1" || got[1].StartOffset != 3 || got[1].EndOffset != 9 {
		t.Errorf("cursor fields = (%s, %d, %d)", got[1].CaptureEpoch, got[1].StartOffset, got[1].EndOffset)
	}
	if got[1].ShellKind != "zsh" || got[1].ShellVersion != "5.9" {
		t.Errorf("shell kind/version = (%s, %s)", got[1].ShellKind, got[1].ShellVersion)
	}
	if got[0].StartedAt == "" || got[0].FinishedAt == "" || got[0].CreatedAt == "" {
		t.Errorf("timestamps missing: %+v", got[0])
	}
	if got[0].SessionID != "portfolio-3" || got[1].SessionID != "" {
		t.Errorf("sessionId handling = (%q, %q)", got[0].SessionID, got[1].SessionID)
	}
}

func TestShellTerminalsAPI_BlocksUnknownHandleReturnsNotFoundEnvelope(t *testing.T) {
	svc := &fakeShellTerminalService{listed: []shelltermsvc.ShellTerminal{sampleShellTerminal()}}
	hist := &fakeShellTerminalBlockHistory{blocks: sampleTerminalBlocks()}
	srv := newShellTerminalBlocksTestServer(t, svc, hist)

	body, status, hdr := doRequest(t, srv, "GET", "/api/v1/shell-terminals/shellterm-ghost/blocks", "")
	if status != http.StatusNotFound {
		t.Fatalf("status = %d, want 404; body=%s", status, body)
	}
	assertJSON(t, hdr)
	var env struct {
		Error     string `json:"error"`
		Code      string `json:"code"`
		Message   string `json:"message"`
		RequestID string `json:"requestId"`
	}
	mustJSON(t, body, &env)
	if env.Error != "not_found" || env.Code != "SHELL_TERMINAL_NOT_FOUND" {
		t.Errorf("envelope = %+v", env)
	}
	if env.RequestID == "" {
		t.Errorf("missing request id in error envelope: %s", body)
	}
	if hist.gotTerminalID != "" {
		t.Errorf("history was queried for an unknown handle: %q", hist.gotTerminalID)
	}
}

func TestShellTerminalsAPI_BlocksRejectsInvalidLimit(t *testing.T) {
	for _, raw := range []string{"abc", "-1", "0", "501"} {
		svc := &fakeShellTerminalService{listed: []shelltermsvc.ShellTerminal{sampleShellTerminal()}}
		hist := &fakeShellTerminalBlockHistory{blocks: sampleTerminalBlocks()}
		srv := newShellTerminalBlocksTestServer(t, svc, hist)

		body, status, hdr := doRequest(t, srv, "GET", "/api/v1/shell-terminals/shellterm-abc123/blocks?limit="+raw, "")
		if status != http.StatusBadRequest {
			t.Fatalf("limit=%s status = %d, want 400; body=%s", raw, status, body)
		}
		assertJSON(t, hdr)
		var env struct {
			Error     string `json:"error"`
			RequestID string `json:"requestId"`
		}
		mustJSON(t, body, &env)
		if env.Error != "bad_request" || env.RequestID == "" {
			t.Errorf("limit=%s envelope = %+v", raw, env)
		}
	}
}

func TestShellTerminalsAPI_BlocksHonorsExplicitLimit(t *testing.T) {
	svc := &fakeShellTerminalService{listed: []shelltermsvc.ShellTerminal{sampleShellTerminal()}}
	hist := &fakeShellTerminalBlockHistory{blocks: sampleTerminalBlocks()}
	srv := newShellTerminalBlocksTestServer(t, svc, hist)

	body, status, _ := doRequest(t, srv, "GET", "/api/v1/shell-terminals/shellterm-abc123/blocks?limit=25", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if hist.gotLimit != 25 {
		t.Errorf("limit passed through = %d, want 25", hist.gotLimit)
	}
}

func TestShellTerminalsAPI_BlocksReachableThroughSameMiddlewareChain(t *testing.T) {
	svc := &fakeShellTerminalService{listed: []shelltermsvc.ShellTerminal{sampleShellTerminal()}}
	hist := &fakeShellTerminalBlockHistory{blocks: nil}
	srv := newShellTerminalBlocksTestServer(t, svc, hist)

	if _, status, _ := doRequest(t, srv, "GET", "/api/v1/shell-terminals", ""); status != http.StatusOK {
		t.Fatalf("sibling list route status = %d, want 200", status)
	}
	body, status, hdr := doRequest(t, srv, "GET", "/api/v1/shell-terminals/shellterm-abc123/blocks", "")
	if status != http.StatusOK {
		t.Fatalf("blocks route status = %d, want 200; body=%s", status, body)
	}
	assertJSON(t, hdr)
	var got []json.RawMessage
	mustJSON(t, body, &got)
	if len(got) != 0 {
		t.Fatalf("empty history should be [], got %s", body)
	}
}

func TestShellTerminalsAPI_BlocksNotImplementedWithoutHistoryService(t *testing.T) {
	svc := &fakeShellTerminalService{listed: []shelltermsvc.ShellTerminal{sampleShellTerminal()}}
	srv := newShellTerminalBlocksTestServer(t, svc, nil)

	body, status, _ := doRequest(t, srv, "GET", "/api/v1/shell-terminals/shellterm-abc123/blocks", "")
	if status != http.StatusNotImplemented {
		t.Fatalf("status = %d, want 501; body=%s", status, body)
	}
}

func sampleShellTerminal() shelltermsvc.ShellTerminal {
	return shelltermsvc.ShellTerminal{
		HandleID:   "shellterm-abc123",
		ProjectID:  "portfolio",
		WorkingDir: "/repos/portfolio",
		Title:      "portfolio",
		CreatedAt:  time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC),
	}
}

func TestShellTerminalsAPI_OpenReturnsHandleForMuxAttach(t *testing.T) {
	svc := &fakeShellTerminalService{opened: sampleShellTerminal()}
	srv := newShellTerminalTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "POST", "/api/v1/shell-terminals", `{"projectId":"portfolio"}`)
	if status != http.StatusCreated {
		t.Fatalf("status = %d, want 201; body=%s", status, body)
	}
	if svc.gotOpenInput.ProjectID != "portfolio" {
		t.Errorf("project id = %q, want portfolio", svc.gotOpenInput.ProjectID)
	}
	var resp struct {
		ShellTerminal struct {
			HandleID   string `json:"handleId"`
			WorkingDir string `json:"workingDir"`
			Title      string `json:"title"`
		} `json:"shellTerminal"`
	}
	mustJSON(t, body, &resp)
	if resp.ShellTerminal.HandleID != "shellterm-abc123" {
		t.Errorf("handle id = %q, want the runtime handle the mux attaches to", resp.ShellTerminal.HandleID)
	}
	if resp.ShellTerminal.Title != "portfolio" {
		t.Errorf("title = %q", resp.ShellTerminal.Title)
	}
}

// The bug this guards: a shell opened from a session view must reach the
// service with the session id intact, not just the project id, since only the
// session id can resolve to the session's own worktree.
func TestShellTerminalsAPI_OpenPassesSessionScopeThrough(t *testing.T) {
	svc := &fakeShellTerminalService{opened: sampleShellTerminal()}
	srv := newShellTerminalTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "POST", "/api/v1/shell-terminals", `{"projectId":"portfolio","sessionId":"portfolio-3"}`)
	if status != http.StatusCreated {
		t.Fatalf("status = %d, want 201; body=%s", status, body)
	}
	if svc.gotOpenInput.ProjectID != "portfolio" {
		t.Errorf("project id = %q, want portfolio", svc.gotOpenInput.ProjectID)
	}
	if svc.gotOpenInput.SessionID != "portfolio-3" {
		t.Errorf("session id = %q, want portfolio-3", svc.gotOpenInput.SessionID)
	}
}

// The topbar action fires with no project selected and sends no body; that must
// open a shell rather than 400.
func TestShellTerminalsAPI_OpenAcceptsEmptyBody(t *testing.T) {
	svc := &fakeShellTerminalService{opened: sampleShellTerminal()}
	srv := newShellTerminalTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "POST", "/api/v1/shell-terminals", "")
	if status != http.StatusCreated {
		t.Fatalf("status = %d, want 201; body=%s", status, body)
	}
	if svc.gotOpenInput.ProjectID != "" {
		t.Errorf("project id = %q, want empty", svc.gotOpenInput.ProjectID)
	}
}

func TestShellTerminalsAPI_OpenRejectsMalformedBody(t *testing.T) {
	srv := newShellTerminalTestServer(t, &fakeShellTerminalService{opened: sampleShellTerminal()})

	body, status, _ := doRequest(t, srv, "POST", "/api/v1/shell-terminals", "{not json")
	if status != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", status, body)
	}
}

func TestShellTerminalsAPI_List(t *testing.T) {
	svc := &fakeShellTerminalService{listed: []shelltermsvc.ShellTerminal{sampleShellTerminal()}}
	srv := newShellTerminalTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "GET", "/api/v1/shell-terminals", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	var resp struct {
		ShellTerminals []struct {
			HandleID string `json:"handleId"`
		} `json:"shellTerminals"`
	}
	mustJSON(t, body, &resp)
	if len(resp.ShellTerminals) != 1 || resp.ShellTerminals[0].HandleID != "shellterm-abc123" {
		t.Fatalf("terminals = %+v", resp.ShellTerminals)
	}
}

func TestShellTerminalsAPI_ResponseCarriesDurableBlocksCapability(t *testing.T) {
	captured := sampleShellTerminal()
	captured.DurableBlocks = true
	uncaptured := sampleShellTerminal()
	uncaptured.HandleID = "shellterm-nocapture"
	uncaptured.DurableBlocks = false

	svc := &fakeShellTerminalService{
		opened: captured,
		listed: []shelltermsvc.ShellTerminal{captured, uncaptured},
	}
	srv := newShellTerminalTestServer(t, svc)

	openBody, openStatus, _ := doRequest(t, srv, "POST", "/api/v1/shell-terminals", `{"projectId":"portfolio"}`)
	if openStatus != http.StatusCreated {
		t.Fatalf("open status = %d, want 201; body=%s", openStatus, openBody)
	}
	var openResp struct {
		ShellTerminal struct {
			DurableBlocks bool `json:"durableBlocks"`
		} `json:"shellTerminal"`
	}
	mustJSON(t, openBody, &openResp)
	if !openResp.ShellTerminal.DurableBlocks {
		t.Errorf("open durableBlocks = false, want true when the runtime is capturing")
	}

	listBody, listStatus, _ := doRequest(t, srv, "GET", "/api/v1/shell-terminals", "")
	if listStatus != http.StatusOK {
		t.Fatalf("list status = %d, want 200; body=%s", listStatus, listBody)
	}
	var listResp struct {
		ShellTerminals []struct {
			HandleID      string `json:"handleId"`
			DurableBlocks bool   `json:"durableBlocks"`
		} `json:"shellTerminals"`
	}
	mustJSON(t, listBody, &listResp)
	got := map[string]bool{}
	for _, term := range listResp.ShellTerminals {
		got[term.HandleID] = term.DurableBlocks
	}
	if !got["shellterm-abc123"] {
		t.Errorf("list: captured handle reported durableBlocks=false")
	}
	if got["shellterm-nocapture"] {
		t.Errorf("list: uncaptured handle reported durableBlocks=true")
	}
}

func TestShellTerminalsAPI_CloseReturnsNoContent(t *testing.T) {
	svc := &fakeShellTerminalService{}
	srv := newShellTerminalTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "DELETE", "/api/v1/shell-terminals/shellterm-abc123", "")
	if status != http.StatusNoContent {
		t.Fatalf("status = %d, want 204; body=%s", status, body)
	}
	if svc.gotCloseID != "shellterm-abc123" {
		t.Errorf("closed handle = %q", svc.gotCloseID)
	}
}

func TestShellTerminalsAPI_CloseUnknownHandleReturnsNotFoundEnvelope(t *testing.T) {
	svc := &fakeShellTerminalService{err: apierr.NotFound("SHELL_TERMINAL_NOT_FOUND", "No such shell terminal")}
	srv := newShellTerminalTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "DELETE", "/api/v1/shell-terminals/shellterm-ghost", "")
	if status != http.StatusNotFound {
		t.Fatalf("status = %d, want 404; body=%s", status, body)
	}
}

func TestShellTerminalsAPI_RenameReturnsUpdatedTerminal(t *testing.T) {
	renamed := sampleShellTerminal()
	renamed.Title = "deploy"
	svc := &fakeShellTerminalService{renamed: renamed}
	srv := newShellTerminalTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "PATCH", "/api/v1/shell-terminals/shellterm-abc123", `{"title":"deploy"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if svc.gotRenameID != "shellterm-abc123" || svc.gotRenameTitle != "deploy" {
		t.Errorf("rename args = (%q, %q)", svc.gotRenameID, svc.gotRenameTitle)
	}
	var resp struct {
		ShellTerminal struct {
			Title string `json:"title"`
		} `json:"shellTerminal"`
	}
	mustJSON(t, body, &resp)
	if resp.ShellTerminal.Title != "deploy" {
		t.Errorf("response title = %q, want deploy", resp.ShellTerminal.Title)
	}
}

func TestShellTerminalsAPI_RenameRejectsMalformedBody(t *testing.T) {
	srv := newShellTerminalTestServer(t, &fakeShellTerminalService{})

	body, status, _ := doRequest(t, srv, "PATCH", "/api/v1/shell-terminals/shellterm-abc123", "{not json")
	if status != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", status, body)
	}
}

// A daemon built without the service must answer the locked 501 envelope, not
// panic on a nil interface.
func TestShellTerminalsAPI_NotImplementedWithoutService(t *testing.T) {
	srv := newShellTerminalTestServer(t, nil)

	for _, tc := range []struct{ method, path string }{
		{"GET", "/api/v1/shell-terminals"},
		{"POST", "/api/v1/shell-terminals"},
		{"PATCH", "/api/v1/shell-terminals/shellterm-abc123"},
		{"DELETE", "/api/v1/shell-terminals/shellterm-abc123"},
	} {
		body, status, _ := doRequest(t, srv, tc.method, tc.path, "")
		if status != http.StatusNotImplemented {
			t.Errorf("%s %s status = %d, want 501; body=%s", tc.method, tc.path, status, body)
		}
	}
}
