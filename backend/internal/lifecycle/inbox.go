package lifecycle

import (
	"context"
	"fmt"
	"sort"
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

// inboxDispatchTrigger names the event that asked for a nudge. The orchestrator's
// own idle transition is the only trigger that carries no new information, so it
// is the only one subject to the announced-signature check below.
type inboxDispatchTrigger int

const (
	inboxDispatchWorkerIdle inboxDispatchTrigger = iota
	inboxDispatchOrchestratorIdle
	inboxDispatchStartupSweep
)

// dispatchInboxNudge pastes one content-free digest naming how many inbox rows
// are pending for the project's orchestrator. It is idempotent rather than
// exact: repeated calls for the same pending rows may deliver more than one
// digest, but never deliver stale counts and never consume a row — only an
// explicit ack does that. There is no retry, backoff, or timer behind it.
func (m *Manager) dispatchInboxNudge(ctx context.Context, project domain.ProjectID, trigger inboxDispatchTrigger) error {
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
	var (
		count     int
		signature string
	)
	if trigger == inboxDispatchOrchestratorIdle {
		events, err := m.store.ListPendingInboxEvents(ctx, project)
		if err != nil {
			return err
		}
		count = len(events)
		signature = pendingInboxSignature(events)
	} else {
		count, err = m.store.CountPendingInboxEvents(ctx, project)
		if err != nil {
			return err
		}
	}
	if count == 0 {
		return nil
	}
	// The orchestrator's own idle transition is a trigger the nudge itself
	// causes: the paste submits a prompt, the turn ends, and the session crosses
	// back to idle. Re-announcing the same pending set there would loop for as
	// long as the set went unacked. A worker crossing to idle and the startup
	// sweep are exempt: the first is new information, the second is a one-time
	// boot catch-up. This compares content only — it counts no attempts, stores
	// no time, and schedules nothing.
	if trigger == inboxDispatchOrchestratorIdle && m.lastAnnouncedInboxSignature(project) == signature {
		return nil
	}
	msg := fmt.Sprintf("[Operator] %d inbox item(s). Run `opr inbox`.", count)
	outcome, err := m.guard.NudgeCoordination(ctx, orchestratorID, msg, m.steerActive)
	// Sent with a non-nil error means the pane write was attempted and the
	// bytes may already have landed, so the echo must be recorded before the
	// error returns.
	if outcome == sessionguard.Sent {
		m.rememberCoordinationEcho(orchestratorID, msg)
		if trigger == inboxDispatchOrchestratorIdle {
			m.recordAnnouncedInboxSignature(project, signature)
		}
	}
	return err
}

// pendingInboxSignature identifies a pending set by its exact member ids, so a
// set that changed composition without changing size is never mistaken for the
// one already announced.
func pendingInboxSignature(events []domain.OrchestratorInboxEvent) string {
	ids := make([]string, 0, len(events))
	for _, ev := range events {
		ids = append(ids, ev.ID)
	}
	sort.Strings(ids)
	return strings.Join(ids, ",")
}

func (m *Manager) lastAnnouncedInboxSignature(project domain.ProjectID) string {
	m.announcedMu.Lock()
	defer m.announcedMu.Unlock()
	return m.lastAnnounced[project]
}

func (m *Manager) recordAnnouncedInboxSignature(project domain.ProjectID, signature string) {
	m.announcedMu.Lock()
	defer m.announcedMu.Unlock()
	if m.lastAnnounced == nil {
		m.lastAnnounced = map[domain.ProjectID]string{}
	}
	m.lastAnnounced[project] = signature
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

// DispatchPendingInboxEventsOnStartup nudges the live orchestrator of every
// project that has at least one pending inbox row. It runs once at daemon
// boot to cover rows left pending across a restart or written while every
// worker was busy, neither of which produces an activity-signal transition
// for dispatchInboxNudge to fire on.
func (m *Manager) DispatchPendingInboxEventsOnStartup(ctx context.Context) error {
	projects, err := m.store.ListProjectsWithPendingInboxEvents(ctx)
	if err != nil {
		return err
	}
	for _, project := range projects {
		if err := m.dispatchInboxNudge(ctx, project, inboxDispatchStartupSweep); err != nil {
			return err
		}
	}
	return nil
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
