package lifecycle

import (
	"context"
	"fmt"
	"strings"
	"sync"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/sessionguard"
)

// resolveLiveOrchestrator returns the project's non-terminated orchestrator, if
// one exists. A project without a live orchestrator simply has nobody to nudge:
// the pending rows stay pending until one exists again.
func (m *Manager) resolveLiveOrchestrator(ctx context.Context, project domain.ProjectID) (domain.SessionID, bool, error) {
	recs, err := m.store.ListSessions(ctx, project)
	if err != nil {
		return "", false, fmt.Errorf("list sessions for %s: %w", project, err)
	}
	for _, rec := range recs {
		if rec.Kind == domain.KindOrchestrator && !rec.IsTerminated {
			return rec.ID, true, nil
		}
	}
	return "", false, nil
}

func (m *Manager) dispatchLockFor(project domain.ProjectID) *sync.Mutex {
	m.dispatchLocksMu.Lock()
	defer m.dispatchLocksMu.Unlock()
	if m.dispatchLocks == nil {
		m.dispatchLocks = map[domain.ProjectID]*sync.Mutex{}
	}
	lock, ok := m.dispatchLocks[project]
	if !ok {
		lock = &sync.Mutex{}
		m.dispatchLocks[project] = lock
	}
	return lock
}

// dispatchInboxNudge pastes one content-free digest naming how many inbox rows
// are pending for the project's orchestrator. It is idempotent rather than
// exact: repeated calls for the same pending rows may deliver more than one
// digest, but never deliver stale counts and never consume a row — only an
// explicit ack does that. There is no retry, backoff, or timer behind it.
func (m *Manager) dispatchInboxNudge(ctx context.Context, project domain.ProjectID) error {
	if m.guard == nil {
		return nil
	}
	lock := m.dispatchLockFor(project)
	lock.Lock()
	defer lock.Unlock()

	orchestratorID, found, err := m.resolveLiveOrchestrator(ctx, project)
	if err != nil {
		return err
	}
	if !found {
		return nil
	}
	rec, ok, err := m.store.GetSession(ctx, orchestratorID)
	if err != nil {
		return err
	}
	// A zero FirstSignalAt means no hook from this orchestrator's current
	// process has ever arrived, so its pane cannot be proven writable yet.
	if !ok || rec.FirstSignalAt.IsZero() {
		return nil
	}
	count, err := m.store.CountPendingInboxEvents(ctx, project)
	if err != nil {
		return err
	}
	if count == 0 {
		return nil
	}
	msg := fmt.Sprintf("[Operator] %d inbox item(s). Run `opr inbox`.", count)
	outcome, err := m.guard.NudgeCoordination(ctx, orchestratorID, msg, m.steerActive)
	// Sent with a non-nil error means the pane write was attempted and the
	// bytes may already have landed, so the echo must be recorded before the
	// error returns.
	if outcome == sessionguard.Sent {
		m.rememberCoordinationEcho(orchestratorID, msg)
	}
	return err
}

// rememberCoordinationEcho records the exact text this daemon just wrote into a
// session's pane. Harnesses whose prompt hook fires on any submitted input echo
// that text straight back as the session's own latestUserPrompt; the record
// lets the ingest path recognize and drop it. Several coordination writes can
// be in flight for one session before any of them is echoed back, so each
// session holds a set: a later write must never displace an earlier unechoed
// one. The set is bounded by the number of coordination producers, and each
// entry is removed when its echo arrives.
func (m *Manager) rememberCoordinationEcho(id domain.SessionID, msg string) {
	trimmed := strings.TrimSpace(msg)
	if trimmed == "" {
		return
	}
	m.echoMu.Lock()
	if m.pendingEcho == nil {
		m.pendingEcho = map[domain.SessionID]map[string]struct{}{}
	}
	if m.pendingEcho[id] == nil {
		m.pendingEcho[id] = map[string]struct{}{}
	}
	m.pendingEcho[id][trimmed] = struct{}{}
	m.echoMu.Unlock()
}

// consumeCoordinationEcho reports whether prompt is one of the daemon's own
// outstanding writes into id, consuming just that entry so a genuine later
// repeat of the same text is kept and the session's other outstanding writes
// stay recognizable.
func (m *Manager) consumeCoordinationEcho(id domain.SessionID, prompt string) bool {
	m.echoMu.Lock()
	defer m.echoMu.Unlock()
	pending, ok := m.pendingEcho[id]
	if !ok {
		return false
	}
	if _, found := pending[prompt]; !found {
		return false
	}
	delete(pending, prompt)
	if len(pending) == 0 {
		delete(m.pendingEcho, id)
	}
	return true
}

// ListPendingInboxEvents returns the project's unacknowledged inbox rows.
func (m *Manager) ListPendingInboxEvents(ctx context.Context, project domain.ProjectID) ([]domain.OrchestratorInboxEvent, error) {
	return m.store.ListPendingInboxEvents(ctx, project)
}

// AckInboxEvents marks the named pending rows acknowledged and reports how many
// transitioned.
func (m *Manager) AckInboxEvents(ctx context.Context, project domain.ProjectID, ids []string) (int, error) {
	return m.store.AckInboxEvents(ctx, project, ids)
}
