package screen

import (
	"context"
	"io"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeSessions struct {
	mu    sync.Mutex
	rows  map[domain.SessionID]domain.SessionRecord
	lists int
}

func (f *fakeSessions) ListAllSessions(context.Context) ([]domain.SessionRecord, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.lists++
	var out []domain.SessionRecord
	for _, rec := range f.rows {
		out = append(out, rec)
	}
	return out, nil
}

func (f *fakeSessions) GetSession(_ context.Context, id domain.SessionID) (domain.SessionRecord, bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	rec, ok := f.rows[id]
	return rec, ok, nil
}

func (f *fakeSessions) setState(id domain.SessionID, state domain.ActivityState) {
	f.mu.Lock()
	defer f.mu.Unlock()
	rec := f.rows[id]
	rec.Activity.State = state
	rec.UpdatedAt = rec.UpdatedAt.Add(time.Second)
	f.rows[id] = rec
}

type fakeSink struct {
	sessions *fakeSessions
	signals  []ports.ActivitySignal
}

func (f *fakeSink) ApplyActivitySignal(_ context.Context, id domain.SessionID, s ports.ActivitySignal) error {
	f.signals = append(f.signals, s)
	f.sessions.setState(id, s.State)
	return nil
}

type fakePrograms struct {
	fn func(string, ports.TerminalProgramEvent)
}

func (f *fakePrograms) WatchTerminalPrograms(fn func(string, ports.TerminalProgramEvent)) func() {
	f.fn = fn
	return func() { f.fn = nil }
}

type agents map[domain.AgentHarness]ports.Agent

func (a agents) Agent(h domain.AgentHarness) (ports.Agent, bool) {
	agent, ok := a[h]
	return agent, ok
}

func observerFixture(t *testing.T, state domain.ActivityState) (*Observer, *fakeSessions, *fakeSink) {
	t.Helper()
	sessions := &fakeSessions{rows: map[domain.SessionID]domain.SessionRecord{
		"opr-1": {
			ID: "opr-1", Harness: domain.HarnessClaudeCode,
			Activity:  domain.Activity{State: state, LastActivityAt: t0.Add(-time.Minute)},
			UpdatedAt: t0.Add(-time.Minute),
			Metadata:  domain.SessionMetadata{RuntimeHandleID: "handle-1", RuntimeLaunchID: "launch-1"},
		},
	}}
	sink := &fakeSink{sessions: sessions}
	o := New(sessions, sink, &fakePrograms{}, agents{domain.HarnessClaudeCode: claudecode.New()},
		Config{Clock: func() time.Time { return t0 }, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
	return o, sessions, sink
}

func TestObserverRaisesAQuestionForASessionNobodyIsViewing(t *testing.T) {
	o, sessions, sink := observerFixture(t, domain.ActivityActive)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0, Tail: pane(t, "claudecode_permission.txt")})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(ScreenQuestionConfirm))
	if len(sink.signals) != 1 {
		t.Fatalf("signals = %+v, want one", sink.signals)
	}
	got := sink.signals[0]
	if got.Event != ports.EventScreenQuestion || got.ScreenReading != domain.ScreenQuestion || got.State != domain.ActivityBlocked ||
		got.LaunchID != "launch-1" || !got.ExpectedUpdatedAt.Equal(t0.Add(-time.Minute)) || got.ScreenIdentity == "" {
		t.Fatalf("signal = %+v", got)
	}
	if rec, _, _ := sessions.GetSession(context.Background(), "opr-1"); rec.Activity.State != domain.ActivityBlocked {
		t.Fatalf("state = %q", rec.Activity.State)
	}
}

func TestObserverIgnoresTitlesAndUnknownHandles(t *testing.T) {
	o, _, sink := observerFixture(t, domain.ActivityActive)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "x"})
	o.Enqueue("handle-404", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityActive, At: t0})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(time.Minute))
	if len(sink.signals) != 0 {
		t.Fatalf("signals = %+v, want none", sink.signals)
	}
}

func TestObserverSkipsAReadingTheSessionAlreadyHas(t *testing.T) {
	o, _, sink := observerFixture(t, domain.ActivityIdle)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0, Tail: pane(t, "claudecode_idle.txt")})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(time.Minute))
	if len(sink.signals) != 0 {
		t.Fatalf("signals = %+v, want none", sink.signals)
	}
}

func TestObserverTellsTheLifecycleOnceWhichQuestionAHookAlreadyBlockedOn(t *testing.T) {
	o, _, sink := observerFixture(t, domain.ActivityBlocked)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0, Tail: pane(t, "claudecode_permission.txt")})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(ScreenQuestionConfirm))
	for i := 1; i <= 3; i++ {
		o.Step(context.Background(), t0.Add(ScreenQuestionConfirm+time.Duration(i)*reassertEvery))
	}
	if len(sink.signals) != 1 || sink.signals[0].ScreenReading != domain.ScreenQuestion || sink.signals[0].ScreenIdentity == "" || sink.signals[0].ScreenReassert {
		t.Fatalf("signals = %+v, want the new question once, not re-asserted", sink.signals)
	}
}

func TestObserverNeverReassertsAQuestionTheScreenHasMovedOnFrom(t *testing.T) {
	o, sessions, sink := observerFixture(t, domain.ActivityActive)
	ctx := context.Background()
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0, Tail: pane(t, "claudecode_permission.txt")})
	o.Drain(ctx)
	o.Step(ctx, t0.Add(ScreenQuestionConfirm))
	sessions.setState("opr-1", domain.ActivityActive)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityActive, At: t0.Add(ScreenQuestionConfirm + 3*time.Second)})
	o.Drain(ctx)
	o.Step(ctx, t0.Add(ScreenQuestionConfirm+reassertEvery))
	for _, s := range sink.signals[1:] {
		if s.ScreenReading == domain.ScreenQuestion {
			t.Fatalf("an answered question was re-asserted while the screen reads working: %+v", s)
		}
	}
}

func TestObserverStopsReassertingWhenTheScreenNoLongerReadsTheQuestion(t *testing.T) {
	o, sessions, sink := observerFixture(t, domain.ActivityActive)
	ctx := context.Background()
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0, Tail: pane(t, "claudecode_permission.txt")})
	o.Drain(ctx)
	o.Step(ctx, t0.Add(ScreenQuestionConfirm))
	sessions.setState("opr-1", domain.ActivityActive)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0.Add(2 * time.Second), Tail: "✽ Thinking… (3s)\n  esc to interrupt\n"})
	o.Drain(ctx)
	for i := 1; i <= 3; i++ {
		o.Step(ctx, t0.Add(ScreenQuestionConfirm+time.Duration(i)*reassertEvery))
	}
	if len(sink.signals) != 1 {
		t.Fatalf("signals = %+v, want only the first question", sink.signals)
	}
}

func TestObserverForgetsASessionThatEndsBeforeAnyReadingIsConfirmed(t *testing.T) {
	o, sessions, _ := observerFixture(t, domain.ActivityIdle)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityActive, At: t0})
	o.Drain(context.Background())
	if len(o.tracked) != 1 {
		t.Fatalf("tracked = %d, want the session tracked", len(o.tracked))
	}
	sessions.mu.Lock()
	rec := sessions.rows["opr-1"]
	rec.IsTerminated = true
	sessions.rows["opr-1"] = rec
	sessions.mu.Unlock()
	o.Step(context.Background(), t0.Add(time.Second))
	o.Step(context.Background(), t0.Add(time.Second+reassertEvery))
	if len(o.tracked) != 0 {
		t.Fatalf("tracked = %d, want the ended session forgotten", len(o.tracked))
	}
}

func TestObserverForgetsAHandleItsSessionNoLongerOwns(t *testing.T) {
	o, sessions, _ := observerFixture(t, domain.ActivityIdle)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityActive, At: t0})
	o.Drain(context.Background())
	sessions.mu.Lock()
	rec := sessions.rows["opr-1"]
	rec.Metadata.RuntimeHandleID = ""
	sessions.rows["opr-1"] = rec
	sessions.mu.Unlock()
	o.Step(context.Background(), t0.Add(time.Second+reassertEvery))
	if len(o.tracked) != 0 {
		t.Fatalf("tracked = %d, want the released handle forgotten", len(o.tracked))
	}
}

func TestObserverLooksForAnUnknownHandleOnlyOnceInAWhile(t *testing.T) {
	o, sessions, sink := observerFixture(t, domain.ActivityIdle)
	ctx := context.Background()
	for i := 0; i < 5; i++ {
		o.Enqueue("shell-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityActive, At: t0.Add(time.Duration(i) * time.Second)})
		o.Drain(ctx)
		o.Step(ctx, t0.Add(time.Duration(i)*time.Second))
	}
	if sessions.lists != 1 {
		t.Fatalf("listed every session %d times for one unknown handle", sessions.lists)
	}
	o.Step(ctx, t0.Add(untrackedRecheck+time.Second))
	if len(o.untracked) != 0 {
		t.Fatalf("untracked = %v, want expired misses dropped", o.untracked)
	}
	o.Enqueue("shell-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0.Add(untrackedRecheck + time.Second)})
	o.Drain(ctx)
	if sessions.lists != 2 || len(sink.signals) != 0 {
		t.Fatalf("lists = %d signals = %d, want a second look after the recheck and nothing sent", sessions.lists, len(sink.signals))
	}
}

func TestObserverFindsASessionWhoseHandleAppearsAfterAMiss(t *testing.T) {
	o, sessions, sink := observerFixture(t, domain.ActivityActive)
	ctx := context.Background()
	o.Enqueue("opr-2", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityActive, At: t0})
	o.Drain(ctx)
	sessions.mu.Lock()
	sessions.rows["opr-2"] = domain.SessionRecord{
		ID: "opr-2", Harness: domain.HarnessClaudeCode,
		Activity:  domain.Activity{State: domain.ActivityActive},
		UpdatedAt: t0,
		Metadata:  domain.SessionMetadata{RuntimeHandleID: "opr-2", RuntimeLaunchID: "launch-2"},
	}
	sessions.mu.Unlock()
	o.Enqueue("opr-2", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0.Add(time.Second), Tail: pane(t, "claudecode_permission.txt")})
	o.Drain(ctx)
	o.Step(ctx, t0.Add(time.Second+ScreenQuestionConfirm))
	if len(sink.signals) != 1 || sink.signals[0].LaunchID != "launch-2" {
		t.Fatalf("signals = %+v, want the new session's question", sink.signals)
	}
	if sessions.lists != 1 {
		t.Fatalf("lists = %d, want the appearing handle found without another full listing", sessions.lists)
	}
}

func TestObserverReassertsAConfirmedReadingThatAHookOverrode(t *testing.T) {
	o, sessions, sink := observerFixture(t, domain.ActivityActive)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0, Tail: pane(t, "claudecode_permission.txt")})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(ScreenQuestionConfirm))
	sessions.setState("opr-1", domain.ActivityActive)
	o.Step(context.Background(), t0.Add(ScreenQuestionConfirm+2*time.Second))
	if len(sink.signals) != 1 {
		t.Fatalf("re-asserted before the interval: %+v", sink.signals)
	}
	o.Step(context.Background(), t0.Add(ScreenQuestionConfirm+reassertEvery))
	if len(sink.signals) != 2 || sink.signals[1].ScreenIdentity != sink.signals[0].ScreenIdentity {
		t.Fatalf("signals = %+v, want the same question re-asserted once", sink.signals)
	}
	if sink.signals[0].ScreenReassert || !sink.signals[1].ScreenReassert {
		t.Fatalf("signals = %+v, want only the second marked as a re-assert", sink.signals)
	}
}

func TestObserverForgetsATerminatedSession(t *testing.T) {
	o, sessions, sink := observerFixture(t, domain.ActivityActive)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0, Tail: pane(t, "claudecode_permission.txt")})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(ScreenQuestionConfirm))
	sessions.mu.Lock()
	rec := sessions.rows["opr-1"]
	rec.IsTerminated = true
	rec.Activity.State = domain.ActivityExited
	sessions.rows["opr-1"] = rec
	sessions.mu.Unlock()
	o.Step(context.Background(), t0.Add(time.Minute))
	if len(sink.signals) != 1 || len(o.tracked) != 0 {
		t.Fatalf("signals=%d tracked=%d, want 1 and 0", len(sink.signals), len(o.tracked))
	}
}

func TestObserverWatchesQuestionsOnlyForATrackedSessionWhoseAgentReadsThem(t *testing.T) {
	o, sessions, _ := observerFixture(t, domain.ActivityActive)
	if o.WatchesQuestions("opr-1") {
		t.Fatalf("a session with no screen seen yet is watched")
	}
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityActive, At: t0})
	o.Drain(context.Background())
	if !o.WatchesQuestions("opr-1") {
		t.Fatalf("a tracked Claude Code session is not watched")
	}
	if o.WatchesQuestions("opr-404") {
		t.Fatalf("an unknown session is watched")
	}
	sessions.mu.Lock()
	rec := sessions.rows["opr-1"]
	rec.Metadata.RuntimeHandleID = ""
	sessions.rows["opr-1"] = rec
	sessions.mu.Unlock()
	o.Step(context.Background(), t0.Add(time.Second+reassertEvery))
	if o.WatchesQuestions("opr-1") {
		t.Fatalf("a session whose handle was released is still watched")
	}

	sessions.mu.Lock()
	sessions.rows["opr-2"] = domain.SessionRecord{ID: "opr-2", Harness: domain.HarnessAider, Metadata: domain.SessionMetadata{RuntimeHandleID: "handle-2"}}
	sessions.mu.Unlock()
	o.Enqueue("handle-2", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityActive, At: t0})
	o.Drain(context.Background())
	if o.WatchesQuestions("opr-2") {
		t.Fatalf("a session whose agent has no question reader is watched")
	}
}

func TestObserverKeepsWatchingASessionThatMovedToANewHandle(t *testing.T) {
	o, sessions, _ := observerFixture(t, domain.ActivityActive)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityActive, At: t0})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(ScreenActiveConfirm))
	sessions.mu.Lock()
	rec := sessions.rows["opr-1"]
	rec.Metadata.RuntimeHandleID = "handle-2"
	sessions.rows["opr-1"] = rec
	sessions.mu.Unlock()
	o.Enqueue("handle-2", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityActive, At: t0.Add(4 * time.Second)})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(time.Second+reassertEvery))
	if len(o.tracked) != 1 || !o.WatchesQuestions("opr-1") {
		t.Fatalf("tracked = %d, watched = %v; want the new handle still watched", len(o.tracked), o.WatchesQuestions("opr-1"))
	}
}
