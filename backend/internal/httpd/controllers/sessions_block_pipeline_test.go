package controllers_test

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/sqlitetest"
)

// TestBlockPipelineEndToEnd drives a real store through the real router: hook
// POST, normalization, redaction, persistence, and the blocks GET. Every other
// block test stubs at least one seam, and a seam is exactly where the harness
// defect that made every event "unknown" survived a green suite.
func TestBlockPipelineEndToEnd(t *testing.T) {
	store := sqlitetest.MustOpen(t)
	svc := blockeventsvc.NewService(store, nil, 500)

	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{
		Activity:     noopActivityRecorder{},
		UsageHooks:   noopUsageHookRecorder{},
		BlockEvents:  svc,
		BlockHistory: svc,
	}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)

	post := func(body string) {
		t.Helper()
		_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s-e2e/activity", body)
		if status != http.StatusOK {
			t.Fatalf("activity status = %d", status)
		}
	}

	post(`{"state":"active","event":"user-prompt-submit","harness":"grok","latestUserPrompt":"run it","hookVersion":"1"}`)
	post(`{"state":"active","event":"post-tool-use-failure","harness":"claude-code","toolName":"Bash","toolUseId":"tu-1","toolInput":"{\"command\":\"goose up\"}","latestAssistantUpdate":"token=ghp_abcdefghijklmnopqrstuvwxyz123456","hookVersion":"1"}`)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-e2e/blocks", "")
	if status != http.StatusOK {
		t.Fatalf("blocks status = %d: %s", status, body)
	}
	var got controllers.ListSessionBlockEventsResponse
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(got.Blocks) != 2 {
		t.Fatalf("blocks = %d, want 2", len(got.Blocks))
	}
	if got.Blocks[0].Kind != "prompt_submit" {
		t.Errorf("grok prompt kind = %q, want prompt_submit", got.Blocks[0].Kind)
	}
	if got.Blocks[1].Kind != "tool_complete" || got.Blocks[1].ErrorType == "" {
		t.Errorf("failed tool = kind %q errorType %q, want tool_complete + non-empty", got.Blocks[1].Kind, got.Blocks[1].ErrorType)
	}
	if got.Blocks[1].ToolInput == "" {
		t.Error("toolInput was lost end to end")
	}
	if got.Blocks[1].HookVersion != "1" {
		t.Errorf("hookVersion = %q, want 1", got.Blocks[1].HookVersion)
	}
	if len(got.Blocks[1].RedactedSpans) == 0 {
		t.Error("a github token crossed the wire unredacted / unmarked")
	}
}
