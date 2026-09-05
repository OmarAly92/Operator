package usage

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type usageSummaryStoreStub struct {
	projectID  domain.ProjectID
	rows       []domain.CompactSessionUsage
	session    domain.SessionRecord
	found      bool
	incomplete bool
	models     []domain.UsageModelAggregate
	context    domain.SessionContext
	hasContext bool
	rollup     []domain.UsageRollupBucket
	calls      [6]int
}

func (s *usageSummaryStoreStub) ListCompactSessionUsage(_ context.Context, id domain.ProjectID) ([]domain.CompactSessionUsage, error) {
	s.projectID, s.calls[0] = id, s.calls[0]+1
	return s.rows, nil
}
func (s *usageSummaryStoreStub) GetSession(context.Context, domain.SessionID) (domain.SessionRecord, bool, error) {
	s.calls[1]++
	return s.session, s.found, nil
}
func (s *usageSummaryStoreStub) ListUsageModelAggregates(context.Context, domain.SessionID) ([]domain.UsageModelAggregate, error) {
	s.calls[2]++
	return s.models, nil
}
func (s *usageSummaryStoreStub) GetUsageSessionIncomplete(context.Context, domain.SessionID) (bool, error) {
	s.calls[3]++
	return s.incomplete, nil
}
func (s *usageSummaryStoreStub) GetSessionContext(context.Context, domain.SessionID) (domain.SessionContext, bool, error) {
	s.calls[4]++
	return s.context, s.hasContext, nil
}
func (s *usageSummaryStoreStub) UsageRollup(context.Context, time.Time, time.Time, string) ([]domain.UsageRollupBucket, error) {
	s.calls[5]++
	return s.rollup, nil
}

func TestSummaryReaderListCompactUsesOneBatchRead(t *testing.T) {
	store := &usageSummaryStoreStub{rows: []domain.CompactSessionUsage{
		{SessionID: "empty"},
		{SessionID: "used", TotalTokens: 120},
		{SessionID: "incomplete", TotalTokens: 60, Incomplete: true},
	}}
	got, err := NewSummaryReader(store).ListCompact(context.Background(), "reverb")
	mustNoError(t, err)
	if store.calls[0] != 1 || store.projectID != "reverb" || len(got) != 3 {
		t.Fatalf("read=%d project=%q items=%+v", store.calls[0], store.projectID, got)
	}
	if got[1].TotalTokens != 120 || got[1].Incomplete || !got[2].Incomplete {
		t.Fatalf("compact summaries = %+v", got)
	}
}

func TestSummaryReaderGetAggregatesModelsAndIntegrity(t *testing.T) {
	reasoning := int64(40)
	store := &usageSummaryStoreStub{
		found:      true,
		incomplete: true,
		session:    domain.SessionRecord{ID: "reverb-12", Harness: domain.HarnessCodex},
		models: []domain.UsageModelAggregate{
			{
				Harness: domain.HarnessCodex, ModelID: "gpt-5.6",
				Tokens:              domain.UsageTokenMetrics{InputTokens: 1000, UncachedInputTokens: 600, CacheReadTokens: 400, OutputTokens: 200, ReasoningTokens: &reasoning},
				ReasoningEventCount: 2,
			},
			{
				Harness: domain.HarnessClaudeCode, ModelID: "claude-sonnet",
				Tokens: domain.UsageTokenMetrics{InputTokens: 100, UncachedInputTokens: 80, CacheReadTokens: 20, OutputTokens: 25},
			},
		},
	}

	got, err := NewSummaryReader(store).Get(context.Background(), "reverb-12")
	mustNoError(t, err)
	if !got.Incomplete {
		t.Fatal("integrity failure did not mark usage incomplete")
	}
	if got.Totals.InputTokens == nil || *got.Totals.InputTokens != 1100 ||
		got.Totals.OutputTokens == nil || *got.Totals.OutputTokens != 225 ||
		got.Totals.ReasoningTokens == nil || *got.Totals.ReasoningTokens != 40 {
		t.Fatalf("totals = %+v", got.Totals)
	}
	if len(got.Harnesses) != 2 || got.Harnesses[0].Models[0].ModelID != "gpt-5.6" {
		t.Fatalf("harnesses = %+v", got.Harnesses)
	}
	if store.calls != [6]int{0, 1, 1, 1, 1, 0} {
		t.Fatalf("store calls = %v", store.calls)
	}
}

func TestGetIncludesContextWhenObserved(t *testing.T) {
	reader := NewSummaryReader(&usageSummaryStoreStub{
		found:      true,
		context:    domain.SessionContext{Harness: "claude-code", Used: 64880},
		hasContext: true,
	})
	got, err := reader.Get(context.Background(), "scratch-1")
	mustNoError(t, err)
	if got.Context == nil {
		t.Fatal("context = nil, want the observed context")
	}
	if got.Context.Used != 64880 {
		t.Fatalf("used = %d, want 64880", got.Context.Used)
	}
}

func TestGetOmitsContextWhenNeverObserved(t *testing.T) {
	reader := NewSummaryReader(&usageSummaryStoreStub{found: true})
	got, err := reader.Get(context.Background(), "scratch-1")
	mustNoError(t, err)
	if got.Context != nil {
		t.Fatal("context must stay nil so the client renders nothing rather than zero")
	}
}

func TestRollupRejectsUnknownBucket(t *testing.T) {
	reader := NewSummaryReader(&usageSummaryStoreStub{})
	if _, err := reader.Rollup(context.Background(), time.Now().Add(-time.Hour), time.Now(), "fortnight"); err == nil {
		t.Fatal("want an error for an unsupported bucket")
	}
}

func TestSummaryReaderGetReturnsUnavailableMetricsWithoutEvents(t *testing.T) {
	store := &usageSummaryStoreStub{found: true, session: domain.SessionRecord{ID: "empty"}}
	got, err := NewSummaryReader(store).Get(context.Background(), "empty")
	mustNoError(t, err)
	if got.Totals.InputTokens != nil || got.Totals.OutputTokens != nil || len(got.Harnesses) != 0 {
		t.Fatalf("empty usage = %+v", got)
	}
}
