package store_test

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
)

func TestLatestPermissionModeSurvivesTheTrim(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)
	insert := func(sessionID string, kind domain.BlockEventKind, text, detail string) {
		t.Helper()
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: sessionID, SourceID: string(kind), Kind: kind, Text: text, Detail: detail, CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert: %v", err)
		}
	}
	insert("s-1", domain.BlockEventPermissionMode, "auto", `{"mode":"auto","version":"2.1.280"}`)
	insert("s-1", domain.BlockEventPermissionMode, "plan", `{"mode":"plan","version":"2.1.280"}`)
	insert("s-2", domain.BlockEventPermissionMode, "default", `{"mode":"default"}`)
	for range 10 {
		insert("s-1", domain.BlockEventToolComplete, "ok", "")
	}
	if _, err := s.TrimBlockEvents(ctx, "s-1", "", 3); err != nil {
		t.Fatalf("trim: %v", err)
	}

	detail, ok, err := s.SelectLatestPermissionMode(ctx, "s-1")
	if err != nil || !ok || !strings.Contains(detail, `"plan"`) {
		t.Fatalf("latest = %q, %v, %v; want the plan detail", detail, ok, err)
	}
	if _, ok, err := s.SelectLatestPermissionMode(ctx, "s-3"); err != nil || ok {
		t.Fatalf("unknown session = %v, %v; want not found", ok, err)
	}
	all, err := s.SelectLatestPermissionModes(ctx)
	if err != nil || !strings.Contains(all["s-1"], `"plan"`) || !strings.Contains(all["s-2"], `"default"`) {
		t.Fatalf("all = %+v, %v", all, err)
	}
	events, err := s.SelectBlockEventsBySession(ctx, "s-1", "", 0, 100)
	if err != nil {
		t.Fatal(err)
	}
	tools := 0
	for _, event := range events {
		if event.Kind == domain.BlockEventToolComplete {
			tools++
		}
	}
	if tools != 3 {
		t.Fatalf("tool events after trim = %d, want 3", tools)
	}
}
