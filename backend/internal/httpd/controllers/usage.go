package controllers

import (
	"context"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
)

// UsageSummaryService is the controller-facing compact usage read contract.
type UsageSummaryService interface {
	ListCompact(context.Context, domain.ProjectID) ([]domain.CompactSessionUsage, error)
	Get(context.Context, domain.SessionID) (domain.SessionUsageSummary, error)
	Rollup(context.Context, time.Time, time.Time, string) ([]domain.UsageRollupBucket, error)
}

// UsageController owns compact dashboard usage routes.
type UsageController struct {
	Svc UsageSummaryService
}

// Register mounts usage routes on the supplied router.
func (c *UsageController) Register(r chi.Router) {
	r.Get("/usage/sessions", c.listSessions)
	r.Get("/usage/sessions/{sessionId}", c.getSession)
	r.Get("/usage/rollup", c.rollup)
}

func (c *UsageController) listSessions(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/usage/sessions")
		return
	}
	items, err := c.Svc.ListCompact(r.Context(), domain.ProjectID(r.URL.Query().Get("projectId")))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	out := make([]CompactSessionUsageResponse, 0, len(items))
	for _, item := range items {
		out = append(out, CompactSessionUsageResponse{
			SessionID: item.SessionID, TotalTokens: item.TotalTokens, Incomplete: item.Incomplete,
		})
	}
	envelope.WriteJSON(w, http.StatusOK, ListCompactSessionUsageResponse{Sessions: out})
}

func (c *UsageController) getSession(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/usage/sessions/{sessionId}")
		return
	}
	summary, err := c.Svc.Get(r.Context(), domain.SessionID(chi.URLParam(r, "sessionId")))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, sessionUsageResponse(summary))
}

func (c *UsageController) rollup(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/usage/rollup")
		return
	}
	bucket, days, ok := usageRollupParams(w, r)
	if !ok {
		return
	}
	to := time.Now().UTC()
	buckets, err := c.Svc.Rollup(r.Context(), to.Add(-time.Duration(days)*24*time.Hour), to, bucket)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, usageRollupResponse(bucket, buckets))
}

func usageRollupParams(w http.ResponseWriter, r *http.Request) (string, int, bool) {
	bucket := r.URL.Query().Get("bucket")
	if bucket != "day" && bucket != "week" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_BUCKET", "Bucket must be day or week", nil)
		return "", 0, false
	}
	days := 14
	if r.URL.Query().Has("days") {
		raw := r.URL.Query().Get("days")
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 90 {
			envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_RANGE", "Days must be an integer between 1 and 90", nil)
			return "", 0, false
		}
		days = parsed
	}
	return bucket, days, true
}

func sessionUsageResponse(summary domain.SessionUsageSummary) SessionUsageResponse {
	harnesses := make([]UsageHarnessResponse, 0, len(summary.Harnesses))
	for _, harness := range summary.Harnesses {
		models := make([]UsageModelResponse, 0, len(harness.Models))
		for _, model := range harness.Models {
			models = append(models, UsageModelResponse{
				ModelID: model.ModelID, Totals: usageTotalsResponse(model.Totals),
			})
		}
		harnesses = append(harnesses, UsageHarnessResponse{
			Harness: string(harness.Harness), Totals: usageTotalsResponse(harness.Totals), Models: models,
		})
	}
	return SessionUsageResponse{
		SessionID: summary.SessionID, Incomplete: summary.Incomplete,
		Context: sessionContextResponse(summary.Context),
		Totals:  usageTotalsResponse(summary.Totals), Harnesses: harnesses,
	}
}

func sessionContextResponse(sessionContext *domain.SessionContext) *SessionContextResponse {
	if sessionContext == nil {
		return nil
	}
	return &SessionContextResponse{
		Harness: sessionContext.Harness, ModelID: sessionContext.ModelID,
		Used: sessionContext.Used, Window: sessionContext.Window, ObservedAt: sessionContext.ObservedAt,
	}
}

func usageRollupResponse(bucket string, buckets []domain.UsageRollupBucket) UsageRollupResponse {
	responses := make([]UsageRollupBucketResponse, 0, len(buckets))
	for _, rollupBucket := range buckets {
		responses = append(responses, UsageRollupBucketResponse{
			Start: rollupBucket.Start.UTC().Format(time.DateOnly), Totals: usageTotalsResponse(rollupBucket.Totals),
		})
	}
	return UsageRollupResponse{Bucket: bucket, Buckets: responses}
}

func usageTotalsResponse(totals domain.UsageMetricTotals) UsageTotalsResponse {
	return UsageTotalsResponse{
		InputTokens: totals.InputTokens, UncachedInputTokens: totals.UncachedInputTokens,
		CacheReadTokens: totals.CacheReadTokens, CacheWriteTokens: totals.CacheWriteTokens,
		OutputTokens: totals.OutputTokens, ReasoningTokens: totals.ReasoningTokens,
	}
}
