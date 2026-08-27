package blockevent

import (
	"context"
	"strings"
	"sync"
	"testing"
	"unicode/utf8"

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

type concurrentStore struct {
	mu sync.Mutex
	n  int64
}

func (s *concurrentStore) InsertBlockEvent(context.Context, Record) (int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.n++
	return s.n, nil
}

func (s *concurrentStore) SelectBlockEventsBySession(context.Context, string, int64, int) ([]Record, error) {
	return nil, nil
}

func (s *concurrentStore) TrimBlockEvents(context.Context, string, int) (int64, error) {
	return 0, nil
}

func TestRecordIsSafeUnderConcurrentCalls(t *testing.T) {
	svc := NewService(&concurrentStore{}, nil, 500)
	var wg sync.WaitGroup
	for range 50 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{
				Event: "stop",
			}); err != nil {
				t.Errorf("Record: %v", err)
			}
		}()
	}
	wg.Wait()
}

func TestRecordTruncatesOnARuneBoundary(t *testing.T) {
	store := &fakeStore{}
	svc := NewService(store, nil, 500)

	// One ASCII byte shifts every following two-byte rune off the even
	// boundary, so the cap lands in the middle of one.
	text := "a" + strings.Repeat("é", maxTextBytes)
	if err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{
		Event:                 "stop",
		LatestAssistantUpdate: text,
	}); err != nil {
		t.Fatalf("Record: %v", err)
	}
	got := store.inserted[0].Text
	if !utf8.ValidString(got) {
		t.Fatalf("truncated text is not valid UTF-8; trailing bytes % x", got[len(got)-3:])
	}
	if store.inserted[0].TruncatedLines == 0 {
		t.Fatal("truncation was not recorded")
	}
}

func TestRecordRedactsTheToolInput(t *testing.T) {
	store := &fakeStore{}
	svc := NewService(store, nil, 500)

	if err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{
		Event:       "post-tool-use",
		ToolName:    "Bash",
		ToolInput:   `{"command":"curl -H 'Authorization: Bearer abcdefghijklmnopqrstuvwxyz'"}`,
		HookVersion: "1",
	}); err != nil {
		t.Fatalf("record: %v", err)
	}

	rec := store.inserted[0]
	if strings.Contains(rec.ToolInput, "abcdefghijklmnopqrstuvwxyz") {
		t.Fatal("a bearer token reached the store inside the tool input")
	}
	if !strings.Contains(rec.ToolInput, "[redacted]") {
		t.Errorf("toolInput = %q, want a visible mask", rec.ToolInput)
	}
	if rec.HookVersion != "1" {
		t.Errorf("hookVersion = %q, want 1", rec.HookVersion)
	}
}

func TestRecordUsesTheReportedHarness(t *testing.T) {
	store := &fakeStore{}
	svc := NewService(store, nil, 500)

	if err := svc.Record(context.Background(), "s-1", "grok", ports.ActivitySignal{
		Event: "user-prompt-submit",
	}); err != nil {
		t.Fatalf("record: %v", err)
	}

	if got := store.inserted[0].Kind; got != domain.BlockEventPromptSubmit {
		t.Fatalf("kind = %q, want prompt_submit — grok has a mapper and must not fall through to unknown", got)
	}
}
