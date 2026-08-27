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

	got, err := s.SelectBlockEventsBySession(ctx, "s-1", 0, 100)
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	if len(got) != 5 {
		t.Fatalf("len = %d, want 5", len(got))
	}
	if got[0].Seq >= got[1].Seq {
		t.Fatalf("sequence not ascending: %d then %d", got[0].Seq, got[1].Seq)
	}

	afterFirst, err := s.SelectBlockEventsBySession(ctx, "s-1", got[0].Seq, 100)
	if err != nil {
		t.Fatalf("select after: %v", err)
	}
	if len(afterFirst) != 4 {
		t.Fatalf("resume len = %d, want 4", len(afterFirst))
	}

	if _, err := s.TrimBlockEvents(ctx, "s-1", 2); err != nil {
		t.Fatalf("trim: %v", err)
	}
	kept, err := s.SelectBlockEventsBySession(ctx, "s-1", 0, 100)
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
	if _, err := s.TrimBlockEvents(ctx, "s-1", 1); err != nil {
		t.Fatalf("trim: %v", err)
	}
	other, err := s.SelectBlockEventsBySession(ctx, "s-2", 0, 100)
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

	got, err := s.SelectBlockEventsBySession(ctx, "s-1", 0, 100)
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

	all, err := s.SelectBlockEventsBySession(ctx, "s-1", 0, 100)
	if err != nil {
		t.Fatalf("select all: %v", err)
	}
	if len(all) != 6 {
		t.Fatalf("rows = %d, want 6", len(all))
	}

	older, err := s.SelectBlockEventsBeforeSeq(ctx, "s-1", all[4].Seq, 2)
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

	older, err := s.SelectBlockEventsBeforeSeq(ctx, "s-1", seq, 10)
	if err != nil {
		t.Fatalf("select before: %v", err)
	}
	if len(older) != 0 {
		t.Fatalf("rows = %d, want 0 at the start of the log", len(older))
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

	all, err := s.SelectBlockEventsBySession(ctx, "s-1", 0, 100)
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	older, err := s.SelectBlockEventsBeforeSeq(ctx, "s-1", all[1].Seq, 10)
	if err != nil {
		t.Fatalf("select before: %v", err)
	}
	for _, rec := range older {
		if rec.SessionID != "s-1" {
			t.Fatalf("row from %q leaked into s-1's page", rec.SessionID)
		}
	}
}
