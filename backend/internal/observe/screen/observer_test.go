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
	mu   sync.Mutex
	rows map[domain.SessionID]domain.SessionRecord
}

func (f *fakeSessions) ListAllSessions(context.Context) ([]domain.SessionRecord, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
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
	o, _, sink := observerFixture(t, domain.ActivityBlocked)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0, Tail: pane(t, "claudecode_permission.txt")})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(time.Minute))
	if len(sink.signals) != 0 {
		t.Fatalf("signals = %+v, want none", sink.signals)
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
