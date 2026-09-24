package httpd

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

type harnessLookup map[domain.SessionID]domain.AgentHarness

func (h harnessLookup) Get(_ context.Context, id domain.SessionID) (domain.Session, error) {
	harness, ok := h[id]
	if !ok {
		return domain.Session{}, errors.New("not found")
	}
	var s domain.Session
	s.Harness = harness
	return s, nil
}

func postMCPToolCalled(t *testing.T, r http.Handler, body string) int {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1/internal/telemetry/mcp-tool-called", strings.NewReader(body))
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec.Code
}

func TestMCPToolCallRollupCountsCallsAndDistinctSessionsPerDay(t *testing.T) {
	rollup := newMCPToolCallRollup(t.TempDir())
	day1 := time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC)
	report := mcpToolCallKey{Harness: "claude-code", Tool: "session_report", Outcome: "ok", State: "needs_you"}
	board := mcpToolCallKey{Harness: "codex", Tool: "board_get", Outcome: "ok"}

	for _, session := range []string{"opr-1", "opr-1", "opr-2"} {
		if flushed := rollup.record(day1, report, session); flushed != nil {
			t.Fatalf("flushed mid-day: %#v", flushed)
		}
	}
	rollup.record(day1.Add(time.Hour), board, "opr-3")
	if flushed := rollup.flushBefore(day1.Add(2 * time.Hour)); flushed != nil {
		t.Fatalf("flushed the current day: %#v", flushed)
	}

	flushed := rollup.record(day1.Add(24*time.Hour), board, "opr-3")
	if len(flushed) != 1 || flushed[0].Day != "2026-09-23" || len(flushed[0].Counts) != 2 {
		t.Fatalf("flushed = %#v, want day 1's two counts", flushed)
	}
	got := flushed[0].Counts
	if got[0].mcpToolCallKey != report || got[0].Calls != 3 || len(got[0].Sessions) != 2 {
		t.Fatalf("report count = %#v, want 3 calls from 2 sessions", got[0])
	}
	if got[1].mcpToolCallKey != board || got[1].Calls != 1 {
		t.Fatalf("board count = %#v", got[1])
	}
}

func TestMCPToolCallRollupSurvivesRestartAndFlushesAtStart(t *testing.T) {
	dir := t.TempDir()
	day1 := time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC)
	newMCPToolCallRollup(dir).record(day1, mcpToolCallKey{Harness: "codex", Tool: "session_get", Outcome: "ok"}, "opr-1")

	restarted := newMCPToolCallRollup(dir)
	if flushed := restarted.flushBefore(day1.Add(time.Hour)); flushed != nil {
		t.Fatalf("flushed the current day after restart: %#v", flushed)
	}
	restarted.record(day1.Add(time.Hour), mcpToolCallKey{Harness: "codex", Tool: "session_get", Outcome: "ok"}, "opr-1")

	flushed := newMCPToolCallRollup(dir).flushBefore(day1.Add(24 * time.Hour))
	if len(flushed) != 1 || flushed[0].Counts[0].Calls != 2 {
		t.Fatalf("flushed = %#v, want both calls kept across restarts", flushed)
	}
	if again := newMCPToolCallRollup(dir).flushBefore(day1.Add(24 * time.Hour)); again != nil {
		t.Fatalf("a flushed day was emitted twice: %#v", again)
	}
}

func TestMCPToolCalledRouteValidatesAndNeverExportsTheSession(t *testing.T) {
	sink := &captureSink{}
	dir := t.TempDir()
	r := chi.NewRouter()
	mountMCPTelemetry(r, config.Config{DataDir: dir}, sink, harnessLookup{"opr-1": "claude-code"})

	for _, body := range []string{
		`{"sessionId":"opr-1","tool":"session_report","outcome":"ok","state":"needs_you"}`,
		`{"sessionId":"opr-9","tool":"board_get","outcome":"error","state":"needs_you"}`,
	} {
		if code := postMCPToolCalled(t, r, body); code != http.StatusAccepted {
			t.Fatalf("%s: status = %d, want 202", body, code)
		}
	}
	for _, body := range []string{
		`{"tool":"shell_exec","outcome":"ok"}`,
		`{"tool":"board_get","outcome":"maybe"}`,
		`{"tool":"board_get","outcome":"ok","reason":"secret"}`,
	} {
		if code := postMCPToolCalled(t, r, body); code != http.StatusBadRequest {
			t.Fatalf("%s: status = %d, want 400", body, code)
		}
	}
	if len(sink.events) != 0 {
		t.Fatalf("events = %#v, want none before the day closes", sink.events)
	}

	// The next daemon start closes the recorded day.
	rollup := newMCPToolCallRollup(dir)
	flushed := rollup.flushBefore(time.Now().Add(48 * time.Hour))
	emitMCPToolCallRollup(context.Background(), sink, "", flushed)
	if len(sink.events) != 2 {
		t.Fatalf("events = %#v, want one per harness, tool, outcome and state", sink.events)
	}
	report, board := sink.events[0].Payload, sink.events[1].Payload
	if sink.events[1].Name != mcpToolCallsEvent || board["tool"] != "board_get" || board["harness"] != "unknown" || board["outcome"] != "error" {
		t.Fatalf("board event = %#v", sink.events[1])
	}
	if _, ok := board["state"]; ok {
		t.Fatalf("a state was kept on a non-report tool: %#v", board)
	}
	if report["tool"] != "session_report" || report["harness"] != "claude-code" || report["state"] != "needs_you" ||
		report["calls"] != 1 || report["sessions"] != 1 {
		t.Fatalf("report event = %#v", report)
	}
	for _, ev := range sink.events {
		for _, v := range ev.Payload {
			if s, ok := v.(string); ok && strings.HasPrefix(s, "opr-") {
				t.Fatalf("session id exported: %#v", ev.Payload)
			}
		}
	}
}

func TestMCPToolCalledRouteRequiresLoopback(t *testing.T) {
	sink := &captureSink{}
	r := chi.NewRouter()
	mountMCPTelemetry(r, config.Config{DataDir: t.TempDir()}, sink, nil)

	req := httptest.NewRequest(http.MethodPost, "http://evil.example/internal/telemetry/mcp-tool-called", strings.NewReader(`{"tool":"board_get","outcome":"ok"}`))
	req.Host = "evil.example"
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", rec.Code)
	}
}
