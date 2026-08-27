package controllers_test

import (
	"context"
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
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/redact"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
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
		Activity:   noopActivityRecorder{},
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

func TestActivityPassesTheReportedHarnessToBlockEvents(t *testing.T) {
	rec := &fakeBlockEventRecorder{}
	srv := newBlockEventsTestServer(t, rec)

	body := `{"state":"active","event":"user-prompt-submit","harness":"grok","latestUserPrompt":"go"}`
	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s-1/activity", body)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if rec.gotHarness != "grok" {
		t.Fatalf("harness = %q, want grok — without it every block kind is unknown", rec.gotHarness)
	}
}

func TestActivityFallsBackToTheUsageHarness(t *testing.T) {
	rec := &fakeBlockEventRecorder{}
	srv := newBlockEventsTestServer(t, rec)

	body := `{"state":"active","event":"stop","usage":{"harness":"claude-code","transcriptPath":"/tmp/t.jsonl"}}`
	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s-1/activity", body)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if rec.gotHarness != "claude-code" {
		t.Fatalf("harness = %q, want claude-code — an opr older than this task sends it only here", rec.gotHarness)
	}
}

func TestActivityPrefersTheExplicitHarnessOverUsage(t *testing.T) {
	rec := &fakeBlockEventRecorder{}
	srv := newBlockEventsTestServer(t, rec)

	body := `{"state":"active","event":"stop","harness":"grok","usage":{"harness":"claude-code","transcriptPath":"/tmp/t.jsonl"}}`
	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s-1/activity", body)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if rec.gotHarness != "grok" {
		t.Fatalf("harness = %q, want grok — the explicit field is authoritative", rec.gotHarness)
	}
}

func TestActivityCarriesTheToolInputAndHookVersion(t *testing.T) {
	rec := &fakeBlockEventRecorder{}
	srv := newBlockEventsTestServer(t, rec)

	body := `{"state":"active","event":"post-tool-use","harness":"claude-code","toolName":"Bash","toolInput":"{\"command\":\"ls\"}","hookVersion":"1"}`
	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s-1/activity", body)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if rec.gotSignal.ToolInput == "" || rec.gotSignal.HookVersion != "1" {
		t.Fatalf("signal = %+v, want the tool input and hook version carried through", rec.gotSignal)
	}
}

func TestSessionsAPI_ActivityWorksWithNoBlockRecorder(t *testing.T) {
	srv := newBlockEventsTestServer(t, nil)

	_, status, _ := doRequest(t, srv, "POST", "/api/v1/sessions/opr-1/activity", `{"state":"active","event":"stop"}`)
	if status != http.StatusOK {
		t.Fatalf("activity = %d, want 200 with a nil recorder", status)
	}
}

type fakeBlockEventHistory struct {
	recs       []blockeventsvc.Record
	err        error
	gotSession domain.SessionID
	gotAfter   int64
	gotLimit   int
}

func (f *fakeBlockEventHistory) History(_ context.Context, id domain.SessionID, afterSeq int64, limit int) ([]blockeventsvc.Record, error) {
	f.gotSession = id
	f.gotAfter = afterSeq
	f.gotLimit = limit
	return f.recs, f.err
}

func newBlockHistoryTestServer(t *testing.T, hist *fakeBlockEventHistory) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{
		Activity:   noopActivityRecorder{},
		UsageHooks: noopUsageHookRecorder{},
	}
	if hist != nil {
		deps.BlockHistory = hist
	}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestListBlockEventsReturnsPersistedLog(t *testing.T) {
	created := time.Date(2026, 8, 27, 10, 0, 0, 0, time.UTC)
	hist := &fakeBlockEventHistory{recs: []blockeventsvc.Record{{
		Seq:            7,
		SessionID:      "s-1",
		SourceID:       "tu-1",
		Kind:           domain.BlockEventToolComplete,
		Harness:        "claude-code",
		ToolName:       "Bash",
		ToolUseID:      "tu-1",
		Text:           "token=[redacted]",
		RedactedSpans:  []redact.Span{{Start: 6, End: 16}},
		TruncatedLines: 3,
		CreatedAt:      created,
	}}}
	srv := newBlockHistoryTestServer(t, hist)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks?afterSeq=4&limit=50", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", status, body)
	}
	var got controllers.ListSessionBlockEventsResponse
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(got.Blocks) != 1 {
		t.Fatalf("blocks = %d, want 1", len(got.Blocks))
	}
	b := got.Blocks[0]
	if b.Seq != 7 || b.Kind != string(domain.BlockEventToolComplete) || b.ToolUseID != "tu-1" {
		t.Errorf("view = %+v, want seq 7 / tool_complete / tu-1", b)
	}
	if b.TruncatedLines != 3 {
		t.Errorf("truncatedLines = %d, want 3 — the drop count must survive the view", b.TruncatedLines)
	}
	if len(b.RedactedSpans) != 1 || b.RedactedSpans[0].Start != 6 || b.RedactedSpans[0].End != 16 {
		t.Errorf("redactedSpans = %+v, want [{6 16}]", b.RedactedSpans)
	}
	if hist.gotSession != "s-1" || hist.gotAfter != 4 || hist.gotLimit != 50 {
		t.Errorf("history args = (%q, %d, %d), want (s-1, 4, 50)", hist.gotSession, hist.gotAfter, hist.gotLimit)
	}
}

func TestListBlockEventsDefaultsCursorAndLimit(t *testing.T) {
	hist := &fakeBlockEventHistory{}
	srv := newBlockHistoryTestServer(t, hist)

	_, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if hist.gotAfter != 0 || hist.gotLimit != 0 {
		t.Errorf("defaults = (%d, %d), want (0, 0) so the service picks its own bound", hist.gotAfter, hist.gotLimit)
	}
}

func TestListBlockEventsRejectsBadQuery(t *testing.T) {
	srv := newBlockHistoryTestServer(t, &fakeBlockEventHistory{})

	for _, q := range []string{"?afterSeq=abc", "?limit=abc", "?afterSeq=-1", "?limit=0", "?limit=100000"} {
		_, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks"+q, "")
		if status != http.StatusBadRequest {
			t.Errorf("%s: status = %d, want 400", q, status)
		}
	}
}

func TestListBlockEventsWithoutServiceIsNotImplemented(t *testing.T) {
	srv := newBlockHistoryTestServer(t, nil)

	_, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks", "")
	if status != http.StatusNotImplemented {
		t.Errorf("status = %d, want 501", status)
	}
}

func TestListBlockEventsSurfacesServiceFailure(t *testing.T) {
	srv := newBlockHistoryTestServer(t, &fakeBlockEventHistory{err: context.DeadlineExceeded})

	_, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks", "")
	if status < 500 {
		t.Errorf("status = %d, want a 5xx", status)
	}
}
