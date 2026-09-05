package controllers_test

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
)

type fakeUsageSummaryService struct {
	projectID    domain.ProjectID
	sessionID    domain.SessionID
	items        []domain.CompactSessionUsage
	detail       domain.SessionUsageSummary
	rollup       []domain.UsageRollupBucket
	rollupFrom   time.Time
	rollupTo     time.Time
	rollupBucket string
	err          error
}

func (f *fakeUsageSummaryService) ListCompact(_ context.Context, projectID domain.ProjectID) ([]domain.CompactSessionUsage, error) {
	f.projectID = projectID
	return f.items, f.err
}

func (f *fakeUsageSummaryService) Get(_ context.Context, sessionID domain.SessionID) (domain.SessionUsageSummary, error) {
	f.sessionID = sessionID
	return f.detail, f.err
}

func (f *fakeUsageSummaryService) Rollup(_ context.Context, from, to time.Time, bucket string) ([]domain.UsageRollupBucket, error) {
	f.rollupFrom = from
	f.rollupTo = to
	f.rollupBucket = bucket
	return f.rollup, f.err
}

func newUsageTestServer(t *testing.T, svc *fakeUsageSummaryService) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{UsageSummary: svc}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestUsageAPIListsCompactProjectUsage(t *testing.T) {
	svc := &fakeUsageSummaryService{items: []domain.CompactSessionUsage{{
		SessionID: "reverb-12", TotalTokens: 12400, Incomplete: true,
	}}}
	srv := newUsageTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/usage/sessions?projectId=reverb", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if svc.projectID != "reverb" {
		t.Fatalf("project id = %q, want reverb", svc.projectID)
	}
	var got struct {
		Sessions []struct {
			SessionID   string `json:"sessionId"`
			TotalTokens int64  `json:"totalTokens"`
			Incomplete  bool   `json:"incomplete"`
		} `json:"sessions"`
	}
	mustJSON(t, body, &got)
	if len(got.Sessions) != 1 || got.Sessions[0].SessionID != "reverb-12" ||
		got.Sessions[0].TotalTokens != 12400 || !got.Sessions[0].Incomplete {
		t.Fatalf("response = %+v", got)
	}
}

func TestUsageAPIShowsDetailedSessionTokenTelemetryWithoutCost(t *testing.T) {
	input := int64(1000)
	output := int64(200)
	cacheRead := int64(400)
	svc := &fakeUsageSummaryService{detail: domain.SessionUsageSummary{
		SessionID: "reverb-12", Incomplete: true,
		Totals: domain.UsageMetricTotals{
			InputTokens: &input, CacheReadTokens: &cacheRead, OutputTokens: &output,
		},
		Harnesses: []domain.HarnessUsageSummary{{
			Harness: domain.HarnessCodex,
			Models:  []domain.ModelUsageSummary{{ModelID: "gpt-5.6"}},
		}},
	}}
	srv := newUsageTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/usage/sessions/reverb-12", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if svc.sessionID != "reverb-12" {
		t.Fatalf("session id = %q", svc.sessionID)
	}
	for _, forbidden := range []string{`"cost"`, `"valueNanos"`, `"pricingVersion"`} {
		if strings.Contains(string(body), forbidden) {
			t.Fatalf("detailed usage exposed %s: %s", forbidden, body)
		}
	}
	var got struct {
		SessionID  string `json:"sessionId"`
		Incomplete bool   `json:"incomplete"`
		Totals     struct {
			InputTokens int64 `json:"inputTokens"`
		} `json:"totals"`
		Harnesses []struct {
			Models []struct {
				ModelID string `json:"modelId"`
			} `json:"models"`
		} `json:"harnesses"`
	}
	mustJSON(t, body, &got)
	if got.SessionID != "reverb-12" || !got.Incomplete || got.Totals.InputTokens != 1000 ||
		len(got.Harnesses) != 1 || len(got.Harnesses[0].Models) != 1 ||
		got.Harnesses[0].Models[0].ModelID != "gpt-5.6" {
		t.Fatalf("response = %+v", got)
	}
}

func TestGetSessionUsageIncludesContext(t *testing.T) {
	observedAt := time.Date(2026, time.September, 5, 12, 30, 0, 0, time.UTC)
	svc := &fakeUsageSummaryService{detail: domain.SessionUsageSummary{
		SessionID: "scratch-1",
		Context: &domain.SessionContext{
			Harness: "claude-code", ModelID: "claude-sonnet-5", Used: 64880, Window: 0, ObservedAt: observedAt,
		},
	}}
	srv := newUsageTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/usage/sessions/scratch-1", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	var got struct {
		Context *struct {
			Harness    string    `json:"harness"`
			ModelID    string    `json:"modelId"`
			Used       int64     `json:"used"`
			Window     int64     `json:"window"`
			ObservedAt time.Time `json:"observedAt"`
		} `json:"context"`
	}
	mustJSON(t, body, &got)
	if got.Context == nil || got.Context.Harness != "claude-code" || got.Context.ModelID != "claude-sonnet-5" ||
		got.Context.Used != 64880 || got.Context.ObservedAt != observedAt {
		t.Fatalf("context = %+v", got.Context)
	}
	if got.Context.Window != 0 {
		t.Fatalf("window = %d, want 0 for Claude", got.Context.Window)
	}
}

func TestRollupDefaultsToFourteenDays(t *testing.T) {
	input := int64(123)
	svc := &fakeUsageSummaryService{rollup: []domain.UsageRollupBucket{{
		Start:  time.Date(2026, time.September, 1, 0, 0, 0, 0, time.UTC),
		Totals: domain.UsageMetricTotals{InputTokens: &input},
	}}}
	srv := newUsageTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/usage/rollup?bucket=day", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if svc.rollupBucket != "day" || svc.rollupTo.Sub(svc.rollupFrom) != 14*24*time.Hour {
		t.Fatalf("rollup request = bucket %q, range %s", svc.rollupBucket, svc.rollupTo.Sub(svc.rollupFrom))
	}
	var got struct {
		Bucket  string `json:"bucket"`
		Buckets []struct {
			Start  string `json:"start"`
			Totals struct {
				InputTokens int64 `json:"inputTokens"`
			} `json:"totals"`
		} `json:"buckets"`
	}
	mustJSON(t, body, &got)
	if got.Bucket != "day" || len(got.Buckets) != 1 || got.Buckets[0].Start != "2026-09-01" ||
		got.Buckets[0].Totals.InputTokens != 123 {
		t.Fatalf("response = %+v", got)
	}
}

func TestRollupAcceptsWeekAtMaximumRange(t *testing.T) {
	svc := &fakeUsageSummaryService{}
	srv := newUsageTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/usage/rollup?bucket=week&days=90", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if svc.rollupBucket != "week" || svc.rollupTo.Sub(svc.rollupFrom) != 90*24*time.Hour {
		t.Fatalf("rollup request = bucket %q, range %s", svc.rollupBucket, svc.rollupTo.Sub(svc.rollupFrom))
	}
}

func TestRollupRejectsBadBucket(t *testing.T) {
	srv := newUsageTestServer(t, &fakeUsageSummaryService{})
	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/usage/rollup?bucket=fortnight", "")
	assertErrorCode(t, body, status, http.StatusBadRequest, "INVALID_BUCKET")
}

func TestRollupRejectsInvalidRange(t *testing.T) {
	tests := []struct {
		name string
		days string
	}{
		{name: "empty", days: ""},
		{name: "zero", days: "0"},
		{name: "negative", days: "-1"},
		{name: "non-numeric", days: "not-a-number"},
		{name: "above maximum", days: "500"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			srv := newUsageTestServer(t, &fakeUsageSummaryService{})
			body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/usage/rollup?bucket=day&days="+test.days, "")
			assertErrorCode(t, body, status, http.StatusBadRequest, "INVALID_RANGE")
		})
	}
}
