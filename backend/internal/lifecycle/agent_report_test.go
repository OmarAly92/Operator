package lifecycle

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// reportStore adds the agent-report columns to the reducer fake, written only
// through their own methods like the SQLite store.
type reportStore struct {
	*fakeStore
	clears int
}

func (s *reportStore) SetSessionAgentReport(_ context.Context, id domain.SessionID, report domain.AgentReport, _ time.Time) (bool, error) {
	rec, ok := s.sessions[id]
	if !ok {
		return false, nil
	}
	rec.AgentReport = &report
	s.sessions[id] = rec
	return true, nil
}

func (s *reportStore) ClearSessionAgentReport(_ context.Context, id domain.SessionID, _ time.Time) (bool, error) {
	rec, ok := s.sessions[id]
	if !ok || rec.AgentReport == nil {
		return false, nil
	}
	rec.AgentReport = nil
	s.sessions[id] = rec
	s.clears++
	return true, nil
}

var reportNow = time.Date(2026, 9, 24, 12, 0, 0, 0, time.UTC)

func reportManager(t *testing.T, activity domain.ActivityState) (*Manager, *reportStore, *fakeNotificationSink) {
	t.Helper()
	st := &reportStore{fakeStore: newFakeStore()}
	sink := &fakeNotificationSink{}
	m := New(st, nil, WithNotificationSink(sink))
	m.clock = func() time.Time { return reportNow }
	st.sessions["mer-1"] = domain.SessionRecord{
		ID: "mer-1", ProjectID: "mer", DisplayName: "db-choice",
		Activity:      domain.Activity{State: activity, LastActivityAt: reportNow.Add(-time.Minute)},
		FirstSignalAt: reportNow.Add(-time.Hour),
	}
	return m, st, sink
}

func needsYou(reason string) *domain.AgentReport {
	return &domain.AgentReport{State: domain.AgentReportNeedsYou, Reason: reason}
}

func TestAgentReportMidTurnAlertsWhenTheTurnEnds(t *testing.T) {
	m, st, sink := reportManager(t, domain.ActivityActive)

	if err := m.SetAgentReport(ctx, "mer-1", needsYou("Postgres or SQLite?")); err != nil {
		t.Fatal(err)
	}
	if len(sink.intents) != 0 {
		t.Fatalf("a mid-turn report alerted before the agent stopped: %+v", sink.intents)
	}
	if st.sessions["mer-1"].AgentReport.At != reportNow {
		t.Fatalf("report not stamped: %+v", st.sessions["mer-1"].AgentReport)
	}

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}
	if len(sink.intents) != 1 {
		t.Fatalf("intents = %+v, want exactly one alert for the stop", sink.intents)
	}
	got := sink.intents[0]
	if got.Type != domain.NotificationNeedsInput || got.AgentReportReason != "Postgres or SQLite?" {
		t.Fatalf("stop alert = %+v, want a needs_input alert carrying the reason (not turn_finished)", got)
	}
}

func TestAgentReportWhileIdleAlertsNow(t *testing.T) {
	m, _, sink := reportManager(t, domain.ActivityIdle)

	if err := m.SetAgentReport(ctx, "mer-1", needsYou("Need an API key")); err != nil {
		t.Fatal(err)
	}
	if len(sink.intents) != 1 || sink.intents[0].Type != domain.NotificationNeedsInput {
		t.Fatalf("intents = %+v, want one needs_input alert", sink.intents)
	}
	// Repeating the same state does not re-alert.
	if err := m.SetAgentReport(ctx, "mer-1", needsYou("Still need the key")); err != nil {
		t.Fatal(err)
	}
	if len(sink.intents) != 1 {
		t.Fatalf("a repeated needs_you report re-alerted: %+v", sink.intents)
	}
}

func TestAgentReportIsClearedByTheNextUserTurn(t *testing.T) {
	m, st, sink := reportManager(t, domain.ActivityIdle)
	if err := m.SetAgentReport(ctx, "mer-1", needsYou("Which branch?")); err != nil {
		t.Fatal(err)
	}

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit"}); err != nil {
		t.Fatal(err)
	}
	if st.sessions["mer-1"].AgentReport != nil {
		t.Fatalf("user prompt did not clear the report: %+v", st.sessions["mer-1"].AgentReport)
	}
	resolved := false
	for _, r := range sink.resolutions {
		resolved = resolved || r.Type == domain.NotificationNeedsInput
	}
	if !resolved {
		t.Fatalf("clearing a needs_you report must resolve its alert: %+v", sink.resolutions)
	}
}

func TestAgentReportSurvivesAPermissionPromptMidTurn(t *testing.T) {
	m, st, _ := reportManager(t, domain.ActivityActive)
	if err := m.SetAgentReport(ctx, "mer-1", needsYou("Which branch?")); err != nil {
		t.Fatal(err)
	}
	for _, s := range []ports.ActivitySignal{
		{Valid: true, State: domain.ActivityBlocked, Event: "permission-request"},
		{Valid: true, State: domain.ActivityActive, Event: "post-tool-use"},
	} {
		if err := m.ApplyActivitySignal(ctx, "mer-1", s); err != nil {
			t.Fatal(err)
		}
	}
	if st.sessions["mer-1"].AgentReport == nil || st.clears != 0 {
		t.Fatal("a permission prompt resolving mid-turn wiped the report")
	}
}

func TestAgentReportUntaggedSignalClearsOnlyOnANewTurn(t *testing.T) {
	m, st, _ := reportManager(t, domain.ActivityBlocked)
	if err := m.SetAgentReport(ctx, "mer-1", needsYou("x")); err != nil {
		t.Fatal(err)
	}
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityActive}); err != nil {
		t.Fatal(err)
	}
	if st.sessions["mer-1"].AgentReport == nil {
		t.Fatal("blocked→active (untagged) is not a new turn and must keep the report")
	}
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle}); err != nil {
		t.Fatal(err)
	}
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityActive}); err != nil {
		t.Fatal(err)
	}
	if st.sessions["mer-1"].AgentReport != nil {
		t.Fatal("idle→active (untagged) starts a new turn and must clear the report")
	}
}

func TestAgentReportClearAndDowngradeResolveTheAlert(t *testing.T) {
	m, _, sink := reportManager(t, domain.ActivityIdle)
	if err := m.SetAgentReport(ctx, "mer-1", needsYou("x")); err != nil {
		t.Fatal(err)
	}
	if err := m.SetAgentReport(ctx, "mer-1", &domain.AgentReport{State: domain.AgentReportReadyForReview}); err != nil {
		t.Fatal(err)
	}
	if len(sink.resolutions) != 1 || sink.resolutions[0].Type != domain.NotificationNeedsInput {
		t.Fatalf("needs_you→ready_for_review resolutions = %+v", sink.resolutions)
	}
	if err := m.SetAgentReport(ctx, "mer-1", nil); err != nil {
		t.Fatal(err)
	}
	if len(sink.resolutions) != 1 {
		t.Fatalf("clearing a ready_for_review report resolved an alert: %+v", sink.resolutions)
	}
}

func TestAgentReportRejectsUnknownAndTerminatedSessions(t *testing.T) {
	m, st, _ := reportManager(t, domain.ActivityIdle)
	if err := m.SetAgentReport(ctx, "ghost", needsYou("x")); !errors.Is(err, ports.ErrSessionNotFound) {
		t.Fatalf("unknown session err = %v", err)
	}
	rec := st.sessions["mer-1"]
	rec.IsTerminated = true
	st.sessions["mer-1"] = rec
	if err := m.SetAgentReport(ctx, "mer-1", needsYou("x")); !errors.Is(err, ports.ErrSessionTerminated) {
		t.Fatalf("terminated session err = %v", err)
	}
}
