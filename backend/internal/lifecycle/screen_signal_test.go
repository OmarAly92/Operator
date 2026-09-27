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
