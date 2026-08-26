package blockevent

import (
	"context"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeStore struct {
	inserted []Record
	trimmed  []string
	nextSeq  int64
}

func (f *fakeStore) InsertBlockEvent(_ context.Context, rec Record) (int64, error) {
	f.nextSeq++
	rec.Seq = f.nextSeq
	f.inserted = append(f.inserted, rec)
	return rec.Seq, nil
}

func (f *fakeStore) SelectBlockEventsBySession(context.Context, string, int64, int) ([]Record, error) {
	return f.inserted, nil
}

func (f *fakeStore) TrimBlockEvents(_ context.Context, sessionID string, _ int) (int64, error) {
	f.trimmed = append(f.trimmed, sessionID)
	return 0, nil
}

type fakePublisher struct{ published []Record }

func (f *fakePublisher) PublishBlockEvent(_ string, rec Record) {
	f.published = append(f.published, rec)
}

func TestRecordNormalizesAndPublishes(t *testing.T) {
	store, pub := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, pub, 500)

	err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{
		Event:     "post-tool-use",
		ToolName:  "Bash",
		ToolUseID: "tu-1",
	})
	if err != nil {
		t.Fatalf("Record: %v", err)
	}
	if len(store.inserted) != 1 {
		t.Fatalf("inserted %d, want 1", len(store.inserted))
	}
	got := store.inserted[0]
	if got.Kind != domain.BlockEventToolComplete {
		t.Fatalf("Kind = %q, want tool_complete", got.Kind)
	}
	if got.SourceID != "tu-1" {
		t.Fatalf("SourceID = %q, want the hook's tool use id", got.SourceID)
	}
	if len(pub.published) != 1 || pub.published[0].Seq != 1 {
		t.Fatalf("published = %+v, want one record carrying its assigned seq", pub.published)
	}
}

func TestRecordKeepsUnknownEventsWithTheirRawName(t *testing.T) {
	store, pub := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, pub, 500)

	if err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{
		Event: "brand-new-hook",
	}); err != nil {
		t.Fatalf("Record: %v", err)
	}
	got := store.inserted[0]
	if got.Kind != domain.BlockEventUnknown {
		t.Fatalf("Kind = %q, want unknown", got.Kind)
	}
	if got.RawEvent != "brand-new-hook" {
		t.Fatalf("RawEvent = %q, want the raw name preserved", got.RawEvent)
	}
}

func TestRecordRedactsBeforeStoringOrPublishing(t *testing.T) {
	store, pub := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, pub, 500)

	if err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{
		Event:            "user-prompt-submit",
		LatestUserPrompt: "deploy with AKIAIOSFODNN7EXAMPLE now",
	}); err != nil {
		t.Fatalf("Record: %v", err)
	}
	if strings.Contains(store.inserted[0].Text, "AKIAIOSFODNN7EXAMPLE") {
		t.Fatal("secret reached the store")
	}
	if strings.Contains(pub.published[0].Text, "AKIAIOSFODNN7EXAMPLE") {
		t.Fatal("secret reached a client")
	}
	if len(store.inserted[0].RedactedSpans) == 0 {
		t.Fatal("redaction was not reported to the UI")
	}
}

func TestRecordIgnoresSignalsWithNoEvent(t *testing.T) {
	store, pub := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, pub, 500)

	if err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{}); err != nil {
		t.Fatalf("Record: %v", err)
	}
	if len(store.inserted) != 0 || len(pub.published) != 0 {
		t.Fatal("an eventless signal produced a block event")
	}
}
