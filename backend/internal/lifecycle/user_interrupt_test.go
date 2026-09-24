package lifecycle

import (
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestUserInterrupt_EndsAnActiveTurnWithoutATurnFinishedAlert(t *testing.T) {
	m, st, sink, _ := alertManager(t, domain.ActivityActive)
	if err := m.ApplyUserInterrupt(ctx, "mer-1"); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityIdle {
		t.Fatalf("state = %q, want idle", got)
	}
	if got := intentsOf(sink, domain.NotificationTurnFinished); len(got) != 0 {
		t.Fatalf("the user stopped the turn themselves; turn_finished intents = %+v", got)
	}
}

func TestUserInterrupt_ClearsABlockedDialog(t *testing.T) {
	for _, state := range []domain.ActivityState{domain.ActivityBlocked, domain.ActivityWaitingInput} {
		m, st, _, _ := alertManager(t, state)
		if err := m.ApplyUserInterrupt(ctx, "mer-1"); err != nil {
			t.Fatal(err)
		}
		if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityIdle {
			t.Fatalf("%s: state = %q, want idle", state, got)
		}
	}
}

func TestUserInterrupt_LeavesIdleAndExitedSessionsAlone(t *testing.T) {
	for _, state := range []domain.ActivityState{domain.ActivityIdle, domain.ActivityExited} {
		m, st, _, _ := alertManager(t, state)
		before := st.sessions["mer-1"]
		if err := m.ApplyUserInterrupt(ctx, "mer-1"); err != nil {
			t.Fatal(err)
		}
		if got := st.sessions["mer-1"]; got.Activity != before.Activity || !got.UpdatedAt.Equal(before.UpdatedAt) {
			t.Fatalf("%s: session changed to %+v", state, got.Activity)
		}
	}
}

func TestUserInterrupt_IgnoresAnUnknownSession(t *testing.T) {
	m, _, _, _ := alertManager(t, domain.ActivityActive)
	if err := m.ApplyUserInterrupt(ctx, "mer-404"); err != nil {
		t.Fatal(err)
	}
}
