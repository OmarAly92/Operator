package lifecycle

import (
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func screenSignal(reading domain.ScreenReading, identity string) ports.ActivitySignal {
	return ports.ActivitySignal{Valid: true, Event: ports.ScreenEvent(reading), ScreenReading: reading, ScreenIdentity: identity, ScreenText: identity}
}

func movableClock(m *Manager, start time.Time) *time.Time {
	current := start
	m.clock = func() time.Time { return current }
	return &current
}

func TestScreen_QuestionWithoutHooksBlocksAndAlertsOnce(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityActive)
	movableClock(m, now)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenQuestion, "Allow rm? 1. Yes 2. No")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityBlocked {
		t.Fatalf("state = %q, want blocked", got)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("needs_input intents = %+v, want one", got)
	}
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenQuestion, "Allow rm? 1. Yes 2. No")); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("a repeated reading alerted again: %+v", got)
	}
}

func TestScreen_FreshHookBlocksDemotionUntilStale(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityIdle)
	clock := movableClock(m, now)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "pre-tool-use", ToolName: "Bash", ToolUseID: "t1"}); err != nil {
		t.Fatal(err)
	}
	*clock = now.Add(10 * time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenSettled, "")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityActive {
		t.Fatalf("a fresh hook was overridden: state = %q", got)
	}
	*clock = now.Add(domain.HookFreshWindow + time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenSettled, "")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityIdle {
		t.Fatalf("a stale hook was not corrected: state = %q", got)
	}
	if got := intentsOf(sink, domain.NotificationTurnFinished); len(got) != 1 {
		t.Fatalf("turn_finished intents = %+v, want one for the corrected turn", got)
	}
}

func TestScreen_LateHookAfterScreenQuestionAlertsOnce(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityActive)
	clock := movableClock(m, now)
	question := screenSignal(domain.ScreenQuestion, "Bash echo first Do you want to proceed? 1. Yes 2. No")
	if err := m.ApplyActivitySignal(ctx, "mer-1", question); err != nil {
		t.Fatal(err)
	}
	*clock = now.Add(time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityBlocked, Event: "permission-request", ToolName: "Bash"}); err != nil {
		t.Fatal(err)
	}
	*clock = now.Add(2 * time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit"}); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityActive {
		t.Fatalf("a fresh hook lost: state = %q", got)
	}
	*clock = now.Add(2*time.Second + domain.HookFreshWindow)
	if err := m.ApplyActivitySignal(ctx, "mer-1", question); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityBlocked {
		t.Fatalf("the re-asserted question did not apply: state = %q", got)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("one question alerted %d times: %+v", len(got), got)
	}
}

func TestScreen_ADifferentQuestionAlertsAgain(t *testing.T) {
	m, _, sink, now := alertManager(t, domain.ActivityActive)
	clock := movableClock(m, now)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenQuestion, "first")); err != nil {
		t.Fatal(err)
	}
	*clock = now.Add(5 * time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenWorking, "")); err != nil {
		t.Fatal(err)
	}
	*clock = now.Add(9 * time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenQuestion, "second")); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 2 {
		t.Fatalf("two questions gave %d alerts", len(got))
	}
	if got := resolutionsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("the first question was not resolved: %+v", got)
	}
}

func TestScreen_SignalsNeverSetFirstSignalAt(t *testing.T) {
	m, st, _, now := alertManager(t, domain.ActivityIdle)
	movableClock(m, now)
	rec := st.sessions["mer-1"]
	rec.FirstSignalAt = time.Time{}
	st.sessions["mer-1"] = rec
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenWorking, "")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"]; got.Activity.State != domain.ActivityActive || !got.FirstSignalAt.IsZero() {
		t.Fatalf("session = %+v, want active with no first signal", got)
	}
}

func TestScreen_SameStateScreenSignalIsANoOp(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityBlocked)
	movableClock(m, now)
	before := st.sessions["mer-1"]
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenQuestion, "q")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"]; !got.UpdatedAt.Equal(before.UpdatedAt) || len(sink.intents) != 0 {
		t.Fatalf("a same-state reading wrote %+v and intents %+v", got, sink.intents)
	}
}

func TestScreen_SettledClearsAStaleBlockedDialog(t *testing.T) {
	m, st, _, now := alertManager(t, domain.ActivityBlocked)
	movableClock(m, now)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenSettled, "")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityIdle {
		t.Fatalf("state = %q, want idle", got)
	}
}

func TestScreen_NeverResurrectsAnExitedAgent(t *testing.T) {
	m, st, _, now := alertManager(t, domain.ActivityExited)
	movableClock(m, now)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenWorking, "")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityExited {
		t.Fatalf("state = %q, want exited", got)
	}
}

func applyAt(t *testing.T, m *Manager, clock *time.Time, at time.Time, s ports.ActivitySignal) {
	t.Helper()
	*clock = at
	if err := m.ApplyActivitySignal(ctx, "mer-1", s); err != nil {
		t.Fatal(err)
	}
}

func reasserted(s ports.ActivitySignal) ports.ActivitySignal {
	s.ScreenReassert = true
	return s
}

const editQuestion = "Do you want to make this edit? 1. Yes 2. No"

func TestScreen_AReassertedQuestionNeverOverridesTheAnswerAFreshHookReported(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityIdle)
	clock := movableClock(m, now)
	applyAt(t, m, clock, now, ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit"})
	applyAt(t, m, clock, now.Add(time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "pre-tool-use", ToolName: "Edit", ToolUseID: "t1"})
	applyAt(t, m, clock, now.Add(2*time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityBlocked, Event: "permission-request", ToolName: "Edit"})
	applyAt(t, m, clock, now.Add(20*time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "post-tool-use", ToolName: "Edit", ToolUseID: "t1"})
	applyAt(t, m, clock, now.Add(21*time.Second), reasserted(screenSignal(domain.ScreenQuestion, editQuestion)))
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityActive {
		t.Fatalf("a re-asserted question overrode a fresh answer: state = %q", got)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("needs_input intents = %d, want the hook's one", len(got))
	}
}

func TestScreen_AQuestionAHookAlreadyBlockedOnIsRememberedAndNeverAlertsTwice(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityIdle)
	clock := movableClock(m, now)
	applyAt(t, m, clock, now, ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "pre-tool-use", ToolName: "Edit", ToolUseID: "t1"})
	applyAt(t, m, clock, now.Add(time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityBlocked, Event: "permission-request", ToolName: "Edit"})
	applyAt(t, m, clock, now.Add(2*time.Second), screenSignal(domain.ScreenQuestion, editQuestion))
	applyAt(t, m, clock, now.Add(20*time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "post-tool-use", ToolName: "Edit", ToolUseID: "t1"})
	applyAt(t, m, clock, now.Add(21*time.Second), screenSignal(domain.ScreenQuestion, editQuestion))
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityBlocked {
		t.Fatalf("state = %q, want the question on screen to block", got)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("one question alerted %d times", len(got))
	}
}

func TestScreen_SuppressedHooksNeverKeepAScreenQuestionOnTheCard(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityIdle)
	clock := movableClock(m, now)
	applyAt(t, m, clock, now, ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "pre-tool-use", ToolName: "Edit", ToolUseID: "t1"})
	applyAt(t, m, clock, now.Add(2*time.Second), screenSignal(domain.ScreenQuestion, editQuestion))
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityBlocked {
		t.Fatalf("state = %q, want the lost permission hook filled by the screen", got)
	}
	applyAt(t, m, clock, now.Add(5*time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "post-tool-use", ToolName: "Edit", ToolUseID: "t1"})
	applyAt(t, m, clock, now.Add(6*time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "pre-tool-use", ToolName: "Bash", ToolUseID: "t2"})
	applyAt(t, m, clock, now.Add(9*time.Second), screenSignal(domain.ScreenWorking, ""))
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityActive {
		t.Fatalf("an answered question stuck on the card: state = %q", got)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("needs_input intents = %d, want one", len(got))
	}
}

func TestScreen_AnAnsweredHookQuestionNeverComesBackOrSticks(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityIdle)
	clock := movableClock(m, now)
	applyAt(t, m, clock, now, ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit"})
	applyAt(t, m, clock, now.Add(time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "pre-tool-use", ToolName: "Edit", ToolUseID: "t1"})
	applyAt(t, m, clock, now.Add(2*time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityBlocked, Event: "permission-request", ToolName: "Edit"})
	applyAt(t, m, clock, now.Add(3*time.Second), screenSignal(domain.ScreenQuestion, editQuestion))
	applyAt(t, m, clock, now.Add(20*time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "post-tool-use", ToolName: "Edit", ToolUseID: "t1"})
	applyAt(t, m, clock, now.Add(21*time.Second), reasserted(screenSignal(domain.ScreenQuestion, editQuestion)))
	applyAt(t, m, clock, now.Add(23*time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "pre-tool-use", ToolName: "Bash", ToolUseID: "t2"})
	applyAt(t, m, clock, now.Add(24*time.Second), screenSignal(domain.ScreenWorking, ""))
	applyAt(t, m, clock, now.Add(40*time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "post-tool-use", ToolName: "Bash", ToolUseID: "t2"})
	applyAt(t, m, clock, now.Add(41*time.Second), screenSignal(domain.ScreenWorking, ""))
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityActive {
		t.Fatalf("working agent stuck at %q", got)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("needs_input intents = %d, want one", len(got))
	}
}

func TestScreen_NeverClearsAWaitingInputAHookReported(t *testing.T) {
	m, st, _, now := alertManager(t, domain.ActivityActive)
	clock := movableClock(m, now)
	applyAt(t, m, clock, now, ports.ActivitySignal{Valid: true, State: domain.ActivityWaitingInput, Event: "notification"})
	for _, reading := range []domain.ScreenReading{domain.ScreenSettled, domain.ScreenWorking} {
		applyAt(t, m, clock, now.Add(domain.HookFreshWindow+time.Minute), screenSignal(reading, ""))
		applyAt(t, m, clock, now.Add(domain.HookFreshWindow+time.Minute), reasserted(screenSignal(reading, "")))
		if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityWaitingInput {
			t.Fatalf("screen %s cleared the hook's waiting_input: state = %q", reading, got)
		}
	}
	applyAt(t, m, clock, now.Add(2*time.Minute), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit"})
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityActive {
		t.Fatalf("a newer hook did not move on: state = %q", got)
	}
}

func TestScreen_AWaitingInputTheScreenSetCanBeClearedByTheScreen(t *testing.T) {
	m, st, _, now := alertManager(t, domain.ActivityActive)
	clock := movableClock(m, now)
	applyAt(t, m, clock, now, screenSignal(domain.ScreenWaiting, ""))
	applyAt(t, m, clock, now.Add(5*time.Second), screenSignal(domain.ScreenWorking, ""))
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityActive {
		t.Fatalf("state = %q, want the screen's own waiting cleared", got)
	}
}

func TestScreen_ForgetsHookAndQuestionMemoryWhenTheSessionEndsOrRelaunches(t *testing.T) {
	m, _, _, now := alertManager(t, domain.ActivityActive)
	clock := movableClock(m, now)
	applyAt(t, m, clock, now, ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "pre-tool-use", ToolName: "Bash", ToolUseID: "t1"})
	applyAt(t, m, clock, now.Add(time.Second), screenSignal(domain.ScreenQuestion, "q"))
	if err := m.MarkSpawned(ctx, "mer-1", domain.SessionMetadata{}); err != nil {
		t.Fatal(err)
	}
	if len(m.hookAt) != 0 || len(m.alerted) != 0 || len(m.screenAt) != 0 {
		t.Fatalf("a relaunch kept hook=%v alerted=%v screen=%v", m.hookAt, m.alerted, m.screenAt)
	}
	applyAt(t, m, clock, now.Add(2*time.Second), ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "pre-tool-use", ToolName: "Bash", ToolUseID: "t2"})
	applyAt(t, m, clock, now.Add(3*time.Second), screenSignal(domain.ScreenQuestion, "q"))
	if err := m.MarkTerminated(ctx, "mer-1"); err != nil {
		t.Fatal(err)
	}
	if len(m.hookAt) != 0 || len(m.alerted) != 0 || len(m.screenAt) != 0 {
		t.Fatalf("a terminated session kept hook=%v alerted=%v screen=%v", m.hookAt, m.alerted, m.screenAt)
	}
}

func TestScreen_IntentsCarryTheScreenText(t *testing.T) {
	m, _, sink, now := alertManager(t, domain.ActivityActive)
	clock := movableClock(m, now)
	question := screenSignal(domain.ScreenQuestion, "q")
	question.ScreenText = "Allow command `rm -rf build`?"
	if err := m.ApplyActivitySignal(ctx, "mer-1", question); err != nil {
		t.Fatal(err)
	}
	*clock = now.Add(5 * time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenWorking, "")); err != nil {
		t.Fatal(err)
	}
	settledSignal := screenSignal(domain.ScreenSettled, "")
	settledSignal.ScreenText = "Removed build/."
	*clock = now.Add(10 * time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", settledSignal); err != nil {
		t.Fatal(err)
	}
	needs := intentsOf(sink, domain.NotificationNeedsInput)
	done := intentsOf(sink, domain.NotificationTurnFinished)
	if len(needs) != 1 || needs[0].ScreenText != "Allow command `rm -rf build`?" || len(done) != 1 || done[0].ScreenText != "Removed build/." {
		t.Fatalf("needs=%+v done=%+v", needs, done)
	}
}
