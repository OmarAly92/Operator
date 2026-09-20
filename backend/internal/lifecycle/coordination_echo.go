package lifecycle

import (
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

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
