package lifecycle

import (
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func intentsOf(sink *fakeNotificationSink, typ domain.NotificationType) []ports.NotificationIntent {
	var out []ports.NotificationIntent
	for _, in := range sink.intents {
		if in.Type == typ {
			out = append(out, in)
		}
	}
	return out
}

func resolutionsOf(sink *fakeNotificationSink, typ domain.NotificationType) []ports.NotificationResolution {
	var out []ports.NotificationResolution
	for _, r := range sink.resolutions {
		if r.Type == typ {
			out = append(out, r)
		}
	}
	return out
}

func alertManager(t *testing.T, state domain.ActivityState) (*Manager, *fakeStore, *fakeNotificationSink, time.Time) {
	t.Helper()
	st := newFakeStore()
	sink := &fakeNotificationSink{}
	m := New(st, nil, WithNotificationSink(sink))
	now := time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC)
	m.clock = func() time.Time { return now }
	st.sessions["mer-1"] = domain.SessionRecord{
		ID: "mer-1", ProjectID: "mer", DisplayName: "split fix",
		Activity:      domain.Activity{State: state, LastActivityAt: now.Add(-time.Minute)},
		FirstSignalAt: now.Add(-time.Hour),
		Metadata:      domain.SessionMetadata{RuntimeHandleID: "mer-1"},
	}
	return m, st, sink, now
}

func TestAlerts_ActiveToIdleEmitsTurnFinishedWithAssistantText(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityActive)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop", LatestAssistantUpdate: "All 42 tests pass."}); err != nil {
		t.Fatal(err)
	}
	got := intentsOf(sink, domain.NotificationTurnFinished)
	if len(got) != 1 || got[0].SessionID != "mer-1" || got[0].SessionDisplayName != "split fix" || got[0].AssistantUpdate != "All 42 tests pass." {
		t.Fatalf("turn_finished intents = %+v", got)
	}
}

func TestAlerts_SecondTurnEmitsAgain(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityActive)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}
	m.clock = func() time.Time { return now.Add(time.Minute) }
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit"}); err != nil {
		t.Fatal(err)
	}
	if got := resolutionsOf(sink, domain.NotificationTurnFinished); len(got) != 1 || got[0].SessionID != "mer-1" {
		t.Fatalf("turn_finished resolutions = %+v", got)
	}
	m.clock = func() time.Time { return now.Add(2 * time.Minute) }
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationTurnFinished); len(got) != 2 {
		t.Fatalf("turn_finished intents = %d, want 2 (session %+v)", len(got), st.sessions["mer-1"])
	}
}

func TestAlerts_NoTurnFinishedFromNonActiveStates(t *testing.T) {
	for _, from := range []domain.ActivityState{domain.ActivityIdle, domain.ActivityWaitingInput, domain.ActivityBlocked} {
		t.Run(string(from), func(t *testing.T) {
			m, _, sink, _ := alertManager(t, from)
			if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle}); err != nil {
				t.Fatal(err)
			}
			if got := intentsOf(sink, domain.NotificationTurnFinished); len(got) != 0 {
				t.Fatalf("turn_finished from %s = %+v, want none", from, got)
			}
		})
	}
}

func TestAlerts_NoTurnFinishedDuringAgentOperation(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityActive)
	m.SetSessionOperationGate(fixedSessionOperationGate(true))
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationTurnFinished); len(got) != 0 {
		t.Fatalf("intents = %+v, want none while an agent operation holds the session", got)
	}
}

func TestAlerts_SessionEndHookEmitsAgentExited(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityIdle)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityExited, Event: "session-end"}); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 1 {
		t.Fatalf("agent_exited intents = %+v, want 1", got)
	}
}

func TestAlerts_SessionEndDuringKillIsSilent(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityIdle)
	m.SetSessionOperationGate(fixedSessionOperationGate(true))
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityExited, Event: "session-end"}); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 0 {
		t.Fatalf("intents = %+v, want none", got)
	}
}

func TestAlerts_ProcessExitedEmitsAgentExitedOnce(t *testing.T) {
	m, _, sink, now := alertManager(t, domain.ActivityActive)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityExited, Event: "process-exited"}); err != nil {
		t.Fatal(err)
	}
	m.clock = func() time.Time { return now.Add(time.Second) }
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityExited, Event: "process-exited"}); err != nil {
		t.Fatal(err)
	}
	got := intentsOf(sink, domain.NotificationAgentExited)
	if len(got) != 1 || got[0].SessionID != "mer-1" || got[0].SessionDisplayName != "split fix" {
		t.Fatalf("agent_exited intents = %+v, want exactly 1", got)
	}
	if got := intentsOf(sink, domain.NotificationTurnFinished); len(got) != 0 {
		t.Fatalf("turn_finished intents = %+v, want none for an exit", got)
	}
}

func TestAlerts_ProcessExitedDuringSessionMutationIsSilent(t *testing.T) {
	m, st, sink, _ := alertManager(t, domain.ActivityActive)
	m.SetSessionOperationGate(fixedSessionOperationGate(true))
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityExited, Event: "process-exited"}); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityExited {
		t.Fatalf("state = %s, want exited (the fact is still recorded)", got)
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 0 {
		t.Fatalf("intents = %+v, want none", got)
	}
}

func TestAlerts_ProcessExitedAfterMarkTerminatedIsSilent(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityActive)
	if err := m.MarkTerminated(ctx, "mer-1"); err != nil {
		t.Fatal(err)
	}
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityExited, Event: "process-exited"}); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 0 {
		t.Fatalf("intents = %+v, want none after termination", got)
	}
}

func TestAlerts_WorkloadDeathEmitsAgentExited(t *testing.T) {
	m, st, sink, _ := alertManager(t, domain.ActivityActive)
	rec := st.sessions["mer-1"]
	rec.Metadata.RuntimeLaunchID = "launch-1"
	st.sessions["mer-1"] = rec
	if err := m.ApplyRuntimeObservation(ctx, "mer-1", ports.RuntimeFacts{Runtime: ports.ProbeAlive, Workload: ports.ProbeDead, LaunchID: "launch-1"}); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 1 {
		t.Fatalf("agent_exited intents = %+v, want 1", got)
	}
}

func TestAlerts_WorkloadDeathDuringKillIsSilent(t *testing.T) {
	m, st, sink, _ := alertManager(t, domain.ActivityActive)
	m.SetSessionOperationGate(fixedSessionOperationGate(true))
	rec := st.sessions["mer-1"]
	rec.Metadata.RuntimeLaunchID = "launch-1"
	st.sessions["mer-1"] = rec
	if err := m.ApplyRuntimeObservation(ctx, "mer-1", ports.RuntimeFacts{Runtime: ports.ProbeAlive, Workload: ports.ProbeDead, LaunchID: "launch-1"}); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityExited {
		t.Fatalf("state = %s, want exited (the fact is still recorded)", got)
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 0 {
		t.Fatalf("intents = %+v, want none", got)
	}
}

func TestAlerts_RuntimeDeathTerminatesWithoutAlert(t *testing.T) {
	m, st, sink, _ := alertManager(t, domain.ActivityActive)
	rec := st.sessions["mer-1"]
	rec.Activity.LastActivityAt = time.Now().Add(-2 * time.Minute)
	st.sessions["mer-1"] = rec
	m.clock = time.Now
	if err := m.ApplyRuntimeObservation(ctx, "mer-1", ports.RuntimeFacts{Runtime: ports.ProbeDead, Workload: ports.ProbeFailed}); err != nil {
		t.Fatal(err)
	}
	if !st.sessions["mer-1"].IsTerminated {
		t.Fatalf("session not terminated: %+v", st.sessions["mer-1"])
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 0 {
		t.Fatalf("intents = %+v, want none for whole-runtime death", got)
	}
}

func TestAlerts_MarkTerminatedResolvesEverySessionAlert(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityExited)
	if err := m.MarkTerminated(ctx, "mer-1"); err != nil {
		t.Fatal(err)
	}
	for _, typ := range []domain.NotificationType{domain.NotificationTurnFinished, domain.NotificationAgentExited} {
		if got := resolutionsOf(sink, typ); len(got) != 1 {
			t.Fatalf("%s resolutions = %+v, want 1", typ, got)
		}
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 0 {
		t.Fatalf("MarkTerminated emitted %+v", got)
	}
}

func TestAlerts_LeavingExitedResolvesAgentExited(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityExited)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit"}); err != nil {
		t.Fatal(err)
	}
	if got := resolutionsOf(sink, domain.NotificationAgentExited); len(got) != 1 {
		t.Fatalf("agent_exited resolutions = %+v, want 1", got)
	}
}
