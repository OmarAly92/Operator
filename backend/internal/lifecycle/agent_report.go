package lifecycle

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// agentReportStore is the persistence surface for agent reports. It is optional
// on the store (focused reducer fakes need not implement it); production SQLite
// does. The report columns are never written by UpdateSession.
type agentReportStore interface {
	SetSessionAgentReport(ctx context.Context, id domain.SessionID, report domain.AgentReport, updatedAt time.Time) (bool, error)
	ClearSessionAgentReport(ctx context.Context, id domain.SessionID, updatedAt time.Time) (bool, error)
}

// SetAgentReport records (or, with a nil report, clears) what the agent
// reported about its own card through the Operator MCP server.
//
// A needs_you report alerts the user only once it takes effect: a report written
// mid-turn waits for the turn to end (ApplyActivitySignal raises it on the
// active→idle transition instead of turn_finished), while a report written by an
// agent that is already idle alerts now.
func (m *Manager) SetAgentReport(ctx context.Context, id domain.SessionID, report *domain.AgentReport) error {
	store, ok := m.store.(agentReportStore)
	if !ok {
		return errors.New("lifecycle: store does not persist agent reports")
	}
	m.mu.Lock()
	rec, found, err := m.store.GetSession(ctx, id)
	if err != nil {
		m.mu.Unlock()
		return err
	}
	if !found {
		m.mu.Unlock()
		return fmt.Errorf("%w: %s", ports.ErrSessionNotFound, id)
	}
	if rec.IsTerminated {
		m.mu.Unlock()
		return fmt.Errorf("%w: %s", ports.ErrSessionTerminated, id)
	}
	now := m.clock()
	if report == nil {
		cleared, err := store.ClearSessionAgentReport(ctx, id, now)
		m.mu.Unlock()
		if err != nil {
			return err
		}
		if cleared && rec.AgentReport.NeedsYou() {
			m.resolveNotifications(ctx, agentReportResolutions(rec, now)...)
		}
		return nil
	}
	if report.At.IsZero() {
		report.At = now
	}
	if _, err := store.SetSessionAgentReport(ctx, id, *report, now); err != nil {
		m.mu.Unlock()
		return err
	}
	var intent *ports.NotificationIntent
	var resolutions []ports.NotificationResolution
	switch {
	case report.State == domain.AgentReportNeedsYou && !rec.AgentReport.NeedsYou() &&
		rec.Activity.State == domain.ActivityIdle:
		next := rec
		next.AgentReport = report
		intent = m.agentReportIntent(next)
	case report.State != domain.AgentReportNeedsYou && rec.AgentReport.NeedsYou():
		resolutions = agentReportResolutions(rec, now)
	}
	m.mu.Unlock()
	m.emitNotification(ctx, intent)
	m.resolveNotifications(ctx, resolutions...)
	return nil
}

// agentReportIntent is the Needs you alert for a needs_you report, carrying the
// agent's own reason as the body.
func (m *Manager) agentReportIntent(rec domain.SessionRecord) *ports.NotificationIntent {
	intent := m.sessionIntent(domain.NotificationNeedsInput, rec)
	intent.AgentReportReason = rec.AgentReport.Reason
	if intent.CreatedAt.IsZero() || rec.AgentReport.At.After(intent.CreatedAt) {
		intent.CreatedAt = rec.AgentReport.At
	}
	return intent
}

// agentReportResolutions closes the Needs you alert a needs_you report raised,
// unless the session is independently waiting on the user (a permission prompt
// or waiting_input), whose alert must stay open.
func agentReportResolutions(rec domain.SessionRecord, now time.Time) []ports.NotificationResolution {
	if rec.Activity.State.NeedsInput() {
		return nil
	}
	return []ports.NotificationResolution{{
		Type:       domain.NotificationNeedsInput,
		SessionID:  rec.ID,
		ResolvedAt: now,
	}}
}

// clearsAgentReport reports whether an activity signal starts a new user turn,
// which is what ends an agent report: the user answered (or Operator pasted a
// nudge, which is also a user turn). A harness whose hooks tag the prompt
// submission clears on exactly that event; for untagged signals, a transition
// from idle or waiting_input into active is the only way a new turn starts. A
// permission dialog resolving mid-turn (blocked→active) never clears.
func clearsAgentReport(prev domain.ActivityState, s ports.ActivitySignal) bool {
	if !s.Valid || s.State != domain.ActivityActive {
		return false
	}
	if s.Event == "user-prompt-submit" {
		return true
	}
	return s.Event == "" && (prev == domain.ActivityIdle || prev == domain.ActivityWaitingInput)
}
