package lifecycle

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeTimer struct {
	after   time.Duration
	fire    func()
	stopped bool
}

type fakeTimers struct {
	mu     sync.Mutex
	timers []*fakeTimer
}

func (f *fakeTimers) afterFunc(d time.Duration, fn func()) func() bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	t := &fakeTimer{after: d, fire: fn}
	f.timers = append(f.timers, t)
	return func() bool {
		f.mu.Lock()
		defer f.mu.Unlock()
		was := !t.stopped
		t.stopped = true
		return was
	}
}

func (f *fakeTimers) only(t *testing.T) *fakeTimer {
	t.Helper()
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.timers) != 1 {
		t.Fatalf("timers = %d, want one", len(f.timers))
	}
	return f.timers[0]
}

type watchesQuestions bool

func (w watchesQuestions) WatchesQuestions(domain.SessionID) bool { return bool(w) }

func heldManager(t *testing.T, watched bool) (*Manager, *fakeStore, *fakeNotificationSink, *fakeTimers, *time.Time, time.Time) {
	t.Helper()
	m, st, sink, now := alertManager(t, domain.ActivityActive)
	clock := movableClock(m, now)
	timers := &fakeTimers{}
	m.afterFunc = timers.afterFunc
	m.SetQuestionWatcher(watchesQuestions(watched))
	return m, st, sink, timers, clock, now
}

var permissionHook = ports.ActivitySignal{Valid: true, State: domain.ActivityBlocked, Event: "permission-request", ToolName: "AskUserQuestion"}

func screenQuestion(identity, text string) ports.ActivitySignal {
	s := screenSignal(domain.ScreenQuestion, identity)
	s.State = domain.ActivityBlocked
	s.ScreenText = text
	return s
}

func TestHeldQuestion_AHookQuestionWaitsForTheScreenAndCarriesItsText(t *testing.T) {
	m, st, sink, timers, clock, now := heldManager(t, true)
	applyAt(t, m, clock, now, permissionHook)
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityBlocked {
		t.Fatalf("state = %q, want the hook applied at once", got)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 0 {
		t.Fatalf("the alert left before the screen question: %+v", got)
	}
	timer := timers.only(t)
	if timer.after != questionTextWait || questionTextWait != 4*time.Second {
		t.Fatalf("wait = %v (constant %v), want 4 s", timer.after, questionTextWait)
	}
	applyAt(t, m, clock, now.Add(1500*time.Millisecond), screenQuestion("Which color? 1. Red 2. Blue", "Which color should the button be?"))
	got := intentsOf(sink, domain.NotificationNeedsInput)
	if len(got) != 1 || got[0].ScreenText != "Which color should the button be?" {
		t.Fatalf("needs_input intents = %+v, want one carrying the question", got)
	}
	if !timer.stopped {
		t.Fatalf("the wait was not cancelled once the question arrived")
	}
	timer.fire()
	applyAt(t, m, clock, now.Add(2*time.Second), screenQuestion("Which color? 1. Red 2. Blue", "Which color should the button be?"))
	applyAt(t, m, clock, now.Add(7*time.Second), reasserted(screenQuestion("Which color? 1. Red 2. Blue", "Which color should the button be?")))
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("one question alerted %d times", len(got))
	}
	if m.alerted["mer-1"].identity != "Which color? 1. Red 2. Blue" {
		t.Fatalf("the question's identity was not remembered: %+v", m.alerted["mer-1"])
	}
}

func TestHeldQuestion_WithoutAScreenQuestionTheAlertLeavesWhenTheWaitEnds(t *testing.T) {
	m, _, sink, timers, clock, now := heldManager(t, true)
	applyAt(t, m, clock, now, permissionHook)
	*clock = now.Add(questionTextWait)
	timers.only(t).fire()
	got := intentsOf(sink, domain.NotificationNeedsInput)
	if len(got) != 1 || got[0].ScreenText != "" || got[0].SessionID != "mer-1" {
		t.Fatalf("needs_input intents = %+v, want the generic alert once the wait ends", got)
	}
	applyAt(t, m, clock, now.Add(3*time.Second), screenQuestion("Which color? 1. Red 2. Blue", "Which color?"))
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("a question read after the wait alerted again: %d", len(got))
	}
	if m.alerted["mer-1"].identity != "Which color? 1. Red 2. Blue" {
		t.Fatalf("the late question's identity was not remembered: %+v", m.alerted["mer-1"])
	}
}

func TestHeldQuestion_AnAnswerBeforeTheWaitEndsDropsTheAlert(t *testing.T) {
	m, st, sink, timers, clock, now := heldManager(t, true)
	applyAt(t, m, clock, now, permissionHook)
	applyAt(t, m, clock, now.Add(time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit"})
	timer := timers.only(t)
	if !timer.stopped {
		t.Fatalf("leaving needs-you did not cancel the wait")
	}
	timer.fire()
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 0 {
		t.Fatalf("an answered question alerted: %+v", got)
	}
	if got := resolutionsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("needs_input resolutions = %+v, want the pause resolved", got)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityActive {
		t.Fatalf("state = %q", got)
	}
}

func TestHeldQuestion_AnExitOutsideTheActivityPathDropsTheAlert(t *testing.T) {
	m, st, sink, timers, clock, now := heldManager(t, true)
	applyAt(t, m, clock, now, permissionHook)
	rec := st.sessions["mer-1"]
	rec.Activity.State = domain.ActivityExited
	st.sessions["mer-1"] = rec
	timers.only(t).fire()
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 0 {
		t.Fatalf("an exited session alerted: %+v", got)
	}
}

func TestHeldQuestion_ARelaunchOrTerminationDropsTheAlert(t *testing.T) {
	for _, end := range []func(*Manager) error{
		func(m *Manager) error { return m.MarkSpawned(ctx, "mer-1", domain.SessionMetadata{}) },
		func(m *Manager) error { return m.MarkTerminated(ctx, "mer-1") },
	} {
		m, _, sink, timers, clock, now := heldManager(t, true)
		applyAt(t, m, clock, now, permissionHook)
		if err := end(m); err != nil {
			t.Fatal(err)
		}
		timer := timers.only(t)
		if !timer.stopped {
			t.Fatalf("the wait survived the session's end")
		}
		timer.fire()
		if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 0 {
			t.Fatalf("an ended session alerted: %+v", got)
		}
	}
}

func TestHeldQuestion_UnwatchedSessionsAndScreenQuestionsAlertAtOnce(t *testing.T) {
	m, _, sink, timers, clock, now := heldManager(t, false)
	applyAt(t, m, clock, now, permissionHook)
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 || len(timers.timers) != 0 {
		t.Fatalf("an unwatched session waited: intents=%+v timers=%d", got, len(timers.timers))
	}

	m, _, sink, timers, clock, now = heldManager(t, true)
	applyAt(t, m, clock, now, screenQuestion("Allow rm? 1. Yes 2. No", "Allow rm?"))
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 || got[0].ScreenText != "Allow rm?" || len(timers.timers) != 0 {
		t.Fatalf("the hookless path changed: intents=%+v timers=%d", got, len(timers.timers))
	}

	m, _, sink, _ = alertManager(t, domain.ActivityActive)
	if err := m.ApplyActivitySignal(ctx, "mer-1", permissionHook); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("with no watcher wired the alert waited: %+v", got)
	}
}

type lockProbeSink struct {
	fakeNotificationSink
	m        *Manager
	underMu  bool
	notified int
}

func (s *lockProbeSink) Notify(c context.Context, intent ports.NotificationIntent) error {
	s.notified++
	if s.m.mu.TryLock() {
		s.m.mu.Unlock()
	} else {
		s.underMu = true
	}
	return s.fakeNotificationSink.Notify(c, intent)
}

func TestHeldQuestion_NeverDispatchesUnderTheLifecycleLock(t *testing.T) {
	for _, release := range []string{"question", "timer"} {
		m, _, _, timers, clock, now := heldManager(t, true)
		probe := &lockProbeSink{m: m}
		m.notifications = probe
		applyAt(t, m, clock, now, permissionHook)
		if release == "question" {
			applyAt(t, m, clock, now.Add(time.Second), screenQuestion("q 1. a 2. b", "q"))
		} else {
			timers.only(t).fire()
		}
		if probe.notified != 1 || probe.underMu {
			t.Fatalf("%s release: notified=%d underLock=%v", release, probe.notified, probe.underMu)
		}
	}
}

func TestHeldQuestion_CloseCancelsTheWait(t *testing.T) {
	m, _, sink, timers, clock, now := heldManager(t, true)
	applyAt(t, m, clock, now, permissionHook)
	m.Close()
	timer := timers.only(t)
	if !timer.stopped {
		t.Fatalf("Close left the wait running")
	}
	timer.fire()
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 0 {
		t.Fatalf("an alert left after Close: %+v", got)
	}
	applyAt(t, m, clock, now.Add(time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit"})
	applyAt(t, m, clock, now.Add(2*time.Second), permissionHook)
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 || len(timers.timers) != 1 {
		t.Fatalf("after Close: intents=%+v timers=%d, want an immediate alert and no new wait", got, len(timers.timers))
	}
}

func TestHeldQuestion_TheDefaultTimerReleasesTheAlert(t *testing.T) {
	m, _, _, now := alertManager(t, domain.ActivityActive)
	movableClock(m, now)
	done := make(chan struct{})
	probe := &releaseProbe{done: done}
	m.notifications = probe
	m.SetQuestionWatcher(watchesQuestions(true))
	if err := m.ApplyActivitySignal(ctx, "mer-1", permissionHook); err != nil {
		t.Fatal(err)
	}
	select {
	case <-done:
	case <-time.After(questionTextWait + 5*time.Second):
		t.Fatalf("the real timer never released the alert")
	}
	if len(probe.intents) != 1 || probe.intents[0].Type != domain.NotificationNeedsInput {
		t.Fatalf("intents = %+v", probe.intents)
	}
}

type releaseProbe struct {
	fakeNotificationSink
	done chan struct{}
}

func (r *releaseProbe) Notify(c context.Context, intent ports.NotificationIntent) error {
	err := r.fakeNotificationSink.Notify(c, intent)
	close(r.done)
	return err
}
