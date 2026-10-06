package transcript

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type recordedEvent struct {
	sessionID domain.SessionID
	harness   string
	event     domain.BlockTranscriptEvent
}

// fakeSink is read from the test goroutine while the supervisor writes it in
// Task 9, so it is mutex-guarded from the start and `go test -race` stays clean.
type fakeSink struct {
	mu     sync.Mutex
	events []recordedEvent
	failOn int
	calls  int
}

func (s *fakeSink) RecordTranscript(_ context.Context, id domain.SessionID, harness string, ev domain.BlockTranscriptEvent) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.calls++
	if s.failOn > 0 && s.calls == s.failOn {
		return os.ErrClosed
	}
	s.events = append(s.events, recordedEvent{sessionID: id, harness: harness, event: ev})
	return nil
}

func (s *fakeSink) recorded() []recordedEvent {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]recordedEvent(nil), s.events...)
}

func (s *fakeSink) setFailOn(n int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.failOn = n
}

type fakeOffsets struct {
	path    string
	offset  int64
	found   bool
	writes  int
	lastKey string
}

func (o *fakeOffsets) GetTranscriptOffset(context.Context, string) (string, int64, bool, error) {
	return o.path, o.offset, o.found, nil
}

func (o *fakeOffsets) UpsertTranscriptOffset(_ context.Context, key, path string, offset int64, _ time.Time) error {
	o.writes++
	o.lastKey = key
	o.path, o.offset, o.found = path, offset, true
	return nil
}

func appendLines(t *testing.T, path string, lines ...string) {
	t.Helper()
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer func() { _ = file.Close() }()
	for _, line := range lines {
		if _, err := file.WriteString(line + "\n"); err != nil {
			t.Fatalf("write: %v", err)
		}
	}
}

const (
	assistantLine = `{"type":"assistant","uuid":"u-1","message":{"model":"claude-sonnet-5","content":[{"type":"text","text":"hello"}]}}`
	toolLine      = `{"type":"assistant","uuid":"u-2","message":{"model":"claude-sonnet-5","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"ls"}}]}}`
	resultLine    = `{"type":"user","uuid":"u-3","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"a.txt"}]}}`
)

func newTail(path string) *tail {
	return &tail{sessionID: "s-1", harness: "claude-code", path: path}
}

func TestPumpEmitsCompleteLinesAndAdvancesTheCursor(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine, toolLine)

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	if err := tl.pump(context.Background(), sink, offsets, time.Now); err != nil {
		t.Fatalf("pump: %v", err)
	}
	got := sink.recorded()
	if len(got) != 3 {
		t.Fatalf("emitted %d events: %+v", len(got), got)
	}
	if got[0].event.Kind != domain.BlockEventTurnModel ||
		got[1].event.Kind != domain.BlockEventAssistantText ||
		got[2].event.Kind != domain.BlockEventToolStart {
		t.Fatalf("kinds = %+v", got)
	}
	info, _ := os.Stat(path)
	if tl.offset != info.Size() || offsets.offset != info.Size() {
		t.Fatalf("offset = %d/%d want %d", tl.offset, offsets.offset, info.Size())
	}
}

func TestPumpDoesNotRepeatTheSameModel(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine, toolLine)

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	_ = tl.pump(context.Background(), sink, offsets, time.Now)

	models := 0
	for _, e := range sink.recorded() {
		if e.event.Kind == domain.BlockEventTurnModel {
			models++
		}
	}
	if models != 1 {
		t.Fatalf("emitted %d turn_model events, want 1", models)
	}
}

func TestPumpResumesWithoutRepeating(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine)

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	_ = tl.pump(context.Background(), sink, offsets, time.Now)
	first := len(sink.recorded())

	appendLines(t, path, toolLine, resultLine)
	_ = tl.pump(context.Background(), sink, offsets, time.Now)

	got := sink.recorded()
	if len(got) != first+2 {
		t.Fatalf("second pump emitted %d events, want 2", len(got)-first)
	}
	if got[first].event.Kind != domain.BlockEventToolStart ||
		got[first+1].event.Kind != domain.BlockEventToolResult {
		t.Fatalf("second pump kinds = %+v", got[first:])
	}
}

func TestPumpIgnoresAPartialTrailingRecord(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine)
	file, _ := os.OpenFile(path, os.O_WRONLY|os.O_APPEND, 0o600)
	_, _ = file.WriteString(`{"type":"assistant","uuid":"u-9","mess`)
	_ = file.Close()

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	_ = tl.pump(context.Background(), sink, offsets, time.Now)

	if got := sink.recorded(); len(got) != 2 {
		t.Fatalf("emitted %d events, want the 2 from the one complete line", len(got))
	}
	info, _ := os.Stat(path)
	if tl.offset >= info.Size() {
		t.Fatal("the cursor must stop before the partial record")
	}
}

func TestPumpCountsUnrecognisedRecords(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, `{"type":"future-record-kind"}`, `not json`, assistantLine)

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	if err := tl.pump(context.Background(), sink, offsets, time.Now); err != nil {
		t.Fatalf("pump: %v", err)
	}
	if tl.unknown != 2 {
		t.Fatalf("unknown = %d want 2", tl.unknown)
	}
	if got := sink.recorded(); len(got) != 2 {
		t.Fatalf("an unrecognised record must not stop the pump: %+v", got)
	}
}

func TestPumpRewindsToTheLastCommittedLineOnSinkFailure(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine, toolLine)

	sink := &fakeSink{failOn: 3}
	offsets := &fakeOffsets{}
	tl := newTail(path)
	if err := tl.pump(context.Background(), sink, offsets, time.Now); err == nil {
		t.Fatal("pump must surface a sink failure")
	}
	info, _ := os.Stat(path)
	if tl.offset == 0 || tl.offset >= info.Size() {
		t.Fatalf("offset = %d; want the end of the first line", tl.offset)
	}

	sink.setFailOn(0)
	before := len(sink.recorded())
	if err := tl.pump(context.Background(), sink, offsets, time.Now); err != nil {
		t.Fatalf("retry: %v", err)
	}
	if got := len(sink.recorded()) - before; got != 1 {
		t.Fatalf("retry emitted %d events, want only the failed line's one", got)
	}
}

func TestPumpResetsWhenTheFileShrinks(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine, toolLine)

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	_ = tl.pump(context.Background(), sink, offsets, time.Now)

	if err := os.WriteFile(path, []byte(resultLine+"\n"), 0o600); err != nil {
		t.Fatalf("truncate: %v", err)
	}
	before := len(sink.recorded())
	_ = tl.pump(context.Background(), sink, offsets, time.Now)

	got := sink.recorded()
	if len(got)-before != 1 || got[before].event.Kind != domain.BlockEventToolResult {
		t.Fatalf("after shrink emitted %+v", got[before:])
	}
}

type fakeInterrupts struct{ ids []domain.SessionID }

func (f *fakeInterrupts) ApplyUserInterrupt(_ context.Context, id domain.SessionID) error {
	f.ids = append(f.ids, id)
	return nil
}

const interruptLine = `{"type":"user","uuid":"u-4","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}`

func TestPumpReportsATranscriptThatEndsOnAnInterrupt(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine, interruptLine)

	interrupts := &fakeInterrupts{}
	tl := newTail(path)
	tl.interrupts = interrupts
	if err := tl.pump(context.Background(), &fakeSink{}, &fakeOffsets{}, time.Now); err != nil {
		t.Fatalf("pump: %v", err)
	}
	if len(interrupts.ids) != 1 || interrupts.ids[0] != "s-1" {
		t.Fatalf("interrupts = %v, want [s-1]", interrupts.ids)
	}

	// Nothing new: the same interrupt is not reported twice.
	_ = tl.pump(context.Background(), &fakeSink{}, &fakeOffsets{}, time.Now)
	if len(interrupts.ids) != 1 {
		t.Fatalf("interrupts = %v after an idle pump", interrupts.ids)
	}
}

func TestPumpIgnoresAnInterruptTheUserAlreadyMovedPast(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, interruptLine, `{"type":"user","uuid":"u-5","message":{"content":"carry on"}}`, assistantLine)

	interrupts := &fakeInterrupts{}
	tl := newTail(path)
	tl.interrupts = interrupts
	if err := tl.pump(context.Background(), &fakeSink{}, &fakeOffsets{}, time.Now); err != nil {
		t.Fatalf("pump: %v", err)
	}
	if len(interrupts.ids) != 0 {
		t.Fatalf("interrupts = %v, want none", interrupts.ids)
	}
}

func TestPumpDoesNotReportASubagentInterrupt(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent-a1.jsonl")
	appendLines(t, path, interruptLine)

	interrupts := &fakeInterrupts{}
	tl := newTail(path)
	tl.agentID = "a1"
	tl.interrupts = interrupts
	_ = tl.pump(context.Background(), &fakeSink{}, &fakeOffsets{}, time.Now)
	if len(interrupts.ids) != 0 {
		t.Fatalf("interrupts = %v, want none", interrupts.ids)
	}
}

func TestPumpTiesABackgroundLaunchToItsToolUseAcrossPumps(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, `{"type":"assistant","uuid":"u-1","timestamp":"2026-09-25T00:00:00.000Z","message":{"content":[{"type":"tool_use","id":"toolu_bg","name":"Bash","input":{"command":"sleep 900","description":"Nap","run_in_background":true}}]}}`)

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	if err := tl.pump(context.Background(), sink, offsets, time.Now); err != nil {
		t.Fatalf("pump: %v", err)
	}
	appendLines(t, path, `{"type":"user","uuid":"u-2","timestamp":"2026-09-25T00:00:01.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_bg","content":"Command running in background with ID: b1. Output is being written to: /tmp/t/tasks/b1.output."}]},"toolUseResult":{"backgroundTaskId":"b1"}}`)
	if err := tl.pump(context.Background(), sink, offsets, time.Now); err != nil {
		t.Fatalf("pump: %v", err)
	}
	var detail string
	for _, e := range sink.recorded() {
		if e.event.Kind == domain.BlockEventTaskUpdate {
			detail = e.event.Detail
		}
	}
	want := `{"taskId":"b1","kind":"shell","status":"running","toolUseId":"toolu_bg","description":"Nap","command":"sleep 900","outputFile":"/tmp/t/tasks/b1.output","startedAt":"2026-09-25T00:00:00.000Z"}`
	if detail != want {
		t.Fatalf("detail = %s\nwant %s", detail, want)
	}
}

func TestPumpPrimesLaunchStateBeforeAResumedCursor(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine, `{"type":"assistant","uuid":"u-1","timestamp":"2026-09-25T00:00:00.000Z","message":{"content":[{"type":"tool_use","id":"toolu_bg","name":"Bash","input":{"command":"sleep 900","run_in_background":true}}]}}`)
	info, _ := os.Stat(path)
	appendLines(t, path, `{"type":"user","uuid":"u-2","timestamp":"2026-09-25T00:00:01.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_bg","content":"Command running in background with ID: b1. Output is being written to: /tmp/t/tasks/b1.output."}]},"toolUseResult":{"backgroundTaskId":"b1"}}`)

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	tl.offset = info.Size()
	if err := tl.pump(context.Background(), sink, offsets, time.Now); err != nil {
		t.Fatalf("pump: %v", err)
	}
	got := sink.recorded()
	if len(got) != 2 || got[1].event.Kind != domain.BlockEventTaskUpdate {
		t.Fatalf("events = %+v", got)
	}
	if want := `"command":"sleep 900"`; !strings.Contains(got[1].event.Detail, want) {
		t.Fatalf("detail = %s", got[1].event.Detail)
	}
}
