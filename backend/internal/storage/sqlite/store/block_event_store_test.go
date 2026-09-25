package store_test

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
)

func TestBlockEventRoundTripAndTrim(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)

	for i := range 5 {
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: "s-1",
			SourceID:  "tool-" + string(rune('a'+i)),
			Kind:      domain.BlockEventToolComplete,
			ToolName:  "Bash",
			Text:      "ok",
			CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert %d: %v", i, err)
		}
	}

	got, err := s.SelectBlockEventsBySession(ctx, "s-1", "", 0, 100)
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	if len(got) != 5 {
		t.Fatalf("len = %d, want 5", len(got))
	}
	if got[0].Seq >= got[1].Seq {
		t.Fatalf("sequence not ascending: %d then %d", got[0].Seq, got[1].Seq)
	}

	afterFirst, err := s.SelectBlockEventsBySession(ctx, "s-1", "", got[0].Seq, 100)
	if err != nil {
		t.Fatalf("select after: %v", err)
	}
	if len(afterFirst) != 4 {
		t.Fatalf("resume len = %d, want 4", len(afterFirst))
	}

	if _, err := s.TrimBlockEvents(ctx, "s-1", "", 2); err != nil {
		t.Fatalf("trim: %v", err)
	}
	kept, err := s.SelectBlockEventsBySession(ctx, "s-1", "", 0, 100)
	if err != nil {
		t.Fatalf("select after trim: %v", err)
	}
	if len(kept) != 2 {
		t.Fatalf("kept = %d, want 2", len(kept))
	}
}

func TestBlockEventTrimIsPerSession(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)
	for _, id := range []string{"s-1", "s-1", "s-1", "s-2"} {
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: id, Kind: domain.BlockEventStop, CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert: %v", err)
		}
	}
	if _, err := s.TrimBlockEvents(ctx, "s-1", "", 1); err != nil {
		t.Fatalf("trim: %v", err)
	}
	other, err := s.SelectBlockEventsBySession(ctx, "s-2", "", 0, 100)
	if err != nil {
		t.Fatalf("select s-2: %v", err)
	}
	if len(other) != 1 {
		t.Fatalf("s-2 lost rows to s-1's trim: %d", len(other))
	}
}

func TestBlockEventStoreRoundTripsToolInputAndHookVersion(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)

	if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
		SessionID:   "s-1",
		Kind:        domain.BlockEventToolComplete,
		Harness:     "claude-code",
		ToolName:    "Bash",
		ToolInput:   `{"command":"ls"}`,
		HookVersion: "1",
		CreatedAt:   time.Now().UTC(),
	}); err != nil {
		t.Fatalf("insert: %v", err)
	}

	got, err := s.SelectBlockEventsBySession(ctx, "s-1", "", 0, 100)
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("rows = %d, want 1", len(got))
	}
	if got[0].ToolInput != `{"command":"ls"}` || got[0].HookVersion != "1" {
		t.Errorf("row = %+v, want the tool input and hook version to survive the round trip", got[0])
	}
}

func TestSelectBlockEventsBeforeSeqReadsBackwardsInForwardOrder(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)

	for i := 0; i < 6; i++ {
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: "s-1",
			Kind:      domain.BlockEventStop,
			Text:      fmt.Sprintf("line %d", i),
			CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert %d: %v", i, err)
		}
	}

	all, err := s.SelectBlockEventsBySession(ctx, "s-1", "", 0, 100)
	if err != nil {
		t.Fatalf("select all: %v", err)
	}
	if len(all) != 6 {
		t.Fatalf("rows = %d, want 6", len(all))
	}

	older, err := s.SelectBlockEventsBeforeSeq(ctx, "s-1", "", all[4].Seq, 2)
	if err != nil {
		t.Fatalf("select before: %v", err)
	}
	if len(older) != 2 {
		t.Fatalf("rows = %d, want 2", len(older))
	}
	if older[0].Seq != all[2].Seq || older[1].Seq != all[3].Seq {
		t.Errorf("seqs = %d,%d, want %d,%d — the page must be the two immediately older, ascending",
			older[0].Seq, older[1].Seq, all[2].Seq, all[3].Seq)
	}
}

func TestSelectBlockEventsBeforeSeqAtTheStartIsEmpty(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)

	seq, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
		SessionID: "s-1",
		Kind:      domain.BlockEventStop,
		CreatedAt: time.Now().UTC(),
	})
	if err != nil {
		t.Fatalf("insert: %v", err)
	}

	older, err := s.SelectBlockEventsBeforeSeq(ctx, "s-1", "", seq, 10)
	if err != nil {
		t.Fatalf("select before: %v", err)
	}
	if len(older) != 0 {
		t.Fatalf("rows = %d, want 0 at the start of the log", len(older))
	}
}

func TestBlockEventStoreRoundTripsSource(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)
	if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
		SessionID: "s-1",
		Kind:      domain.BlockEventAssistantText,
		Source:    domain.BlockEventSourceTranscript,
		Text:      "done",
		CreatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("insert: %v", err)
	}
	recs, err := s.SelectBlockEventsBySession(ctx, "s-1", "", 0, 10)
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	if len(recs) != 1 || recs[0].Source != domain.BlockEventSourceTranscript {
		t.Fatalf("source = %+v", recs)
	}
}

func TestBlockEventStoreScopesRowsByAgent(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	base := blockeventsvc.Record{SessionID: "s1", Kind: domain.BlockEventAssistantText, CreatedAt: time.Now().UTC()}
	if _, err := s.InsertBlockEvent(ctx, base); err != nil {
		t.Fatal(err)
	}
	agent := base
	agent.AgentID = "a1"
	agent.Detail = `{"agentId":"a1"}`
	if _, err := s.InsertBlockEvent(ctx, agent); err != nil {
		t.Fatal(err)
	}
	main, err := s.SelectBlockEventsBySession(ctx, "s1", "", 0, 10)
	if err != nil || len(main) != 1 || main[0].AgentID != "" {
		t.Fatalf("main rows = %+v, %v; want exactly the unscoped row", main, err)
	}
	scoped, err := s.SelectBlockEventsBySession(ctx, "s1", "a1", 0, 10)
	if err != nil || len(scoped) != 1 || scoped[0].AgentID != "a1" || scoped[0].Detail != `{"agentId":"a1"}` {
		t.Fatalf("agent rows = %+v, %v; want the a1 row with its detail", scoped, err)
	}
	before, err := s.SelectBlockEventsBeforeSeq(ctx, "s1", "a1", scoped[0].Seq+1, 10)
	if err != nil || len(before) != 1 || before[0].AgentID != "a1" {
		t.Fatalf("before rows = %+v, %v", before, err)
	}
}

func TestSelectBlockEventsBeforeSeqIsScopedToOneSession(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)

	for _, id := range []string{"s-1", "s-2", "s-1"} {
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: id,
			Kind:      domain.BlockEventStop,
			CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert %s: %v", id, err)
		}
	}

	all, err := s.SelectBlockEventsBySession(ctx, "s-1", "", 0, 100)
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	older, err := s.SelectBlockEventsBeforeSeq(ctx, "s-1", "", all[1].Seq, 10)
	if err != nil {
		t.Fatalf("select before: %v", err)
	}
	for _, rec := range older {
		if rec.SessionID != "s-1" {
			t.Fatalf("row from %q leaked into s-1's page", rec.SessionID)
		}
	}
}

func TestSelectLatestTurnModelsIgnoresSubagentRows(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)

	if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
		SessionID: "s1",
		Kind:      domain.BlockEventTurnModel,
		Text:      "claude-opus-4",
		CreatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("insert main turn_model: %v", err)
	}
	if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
		SessionID: "s1",
		AgentID:   "a1",
		Kind:      domain.BlockEventTurnModel,
		Text:      "claude-haiku-4",
		CreatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("insert subagent turn_model: %v", err)
	}

	models, err := s.SelectLatestTurnModels(ctx)
	if err != nil {
		t.Fatalf("select latest turn models: %v", err)
	}
	if got := models["s1"]; got != "claude-opus-4" {
		t.Fatalf("models[s1] = %q, want the main session's model, not the subagent's", got)
	}
}

func TestBlockEventTrimIsScopedPerAgent(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)

	for range 3 {
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: "s1",
			Kind:      domain.BlockEventStop,
			CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert main: %v", err)
		}
	}
	for range 2 {
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: "s1",
			AgentID:   "a1",
			Kind:      domain.BlockEventStop,
			CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert agent: %v", err)
		}
	}

	if _, err := s.TrimBlockEvents(ctx, "s1", "", 2); err != nil {
		t.Fatalf("trim main: %v", err)
	}

	main, err := s.SelectBlockEventsBySession(ctx, "s1", "", 0, 100)
	if err != nil {
		t.Fatalf("select main: %v", err)
	}
	if len(main) != 2 {
		t.Fatalf("main rows = %d, want 2 (oldest evicted)", len(main))
	}

	agent, err := s.SelectBlockEventsBySession(ctx, "s1", "a1", 0, 100)
	if err != nil {
		t.Fatalf("select agent: %v", err)
	}
	if len(agent) != 2 {
		t.Fatalf("agent a1 rows = %d, want 2 untouched by the main scope's trim", len(agent))
	}
}

func TestTaskUpdatesSurviveTheBlockTrimOnTheirOwnBudget(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	insert := func(kind domain.BlockEventKind, agentID, source string) {
		t.Helper()
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: "s1",
			AgentID:   agentID,
			SourceID:  source,
			Kind:      kind,
			CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert: %v", err)
		}
	}
	insert(domain.BlockEventTaskUpdate, "", "t1")
	insert(domain.BlockEventTaskUpdate, "", "t2")
	for range 4 {
		insert(domain.BlockEventStop, "", "")
	}
	insert(domain.BlockEventTaskUpdate, "", "t3")
	insert(domain.BlockEventTaskUpdate, "a1", "t4")

	if _, err := s.TrimBlockEvents(ctx, "s1", "", 2); err != nil {
		t.Fatalf("trim: %v", err)
	}
	tasks, err := s.SelectTaskUpdates(ctx, "s1")
	if err != nil {
		t.Fatalf("select task updates: %v", err)
	}
	if len(tasks) != 3 || tasks[0].SourceID != "t2" || tasks[1].SourceID != "t3" || tasks[2].SourceID != "t4" || tasks[2].AgentID != "a1" {
		t.Fatalf("task updates = %+v, want t2,t3 then the subagent's t4", tasks)
	}
	all, err := s.SelectBlockEventsBySession(ctx, "s1", "", 0, 100)
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	stops := 0
	for _, rec := range all {
		if rec.Kind == domain.BlockEventStop {
			stops++
		}
	}
	if stops != 2 || len(all) != 4 {
		t.Fatalf("rows after trim = %+v", all)
	}
}
