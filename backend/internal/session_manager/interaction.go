package sessionmanager

import (
	"context"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

// RegisterInteraction records the session's currently pending dialog,
// replacing whatever was there: only one dialog is ever on screen, so keeping
// a stale one would let a client answer a dialog that is no longer there.
func (m *Manager) RegisterInteraction(id domain.SessionID, in domain.PendingInteraction) {
	m.interactionsMu.Lock()
	defer m.interactionsMu.Unlock()
	if m.interactions == nil {
		m.interactions = map[domain.SessionID]domain.PendingInteraction{}
	}
	m.interactions[id] = in
}

// ClearInteractions drops the session's pending dialog, if any, at a turn
// boundary.
func (m *Manager) ClearInteractions(id domain.SessionID) {
	m.interactionsMu.Lock()
	defer m.interactionsMu.Unlock()
	delete(m.interactions, id)
}

// Interaction looks up one pending interaction by id. ok=false covers both an
// unknown session and a stale/answered interaction id.
func (m *Manager) Interaction(id domain.SessionID, interactionID string) (domain.PendingInteraction, bool) {
	m.interactionsMu.Lock()
	defer m.interactionsMu.Unlock()
	in, ok := m.interactions[id]
	if !ok || in.ID != interactionID {
		return domain.PendingInteraction{}, false
	}
	return in, true
}

// Interactions lists the session's pending interactions. An unknown session
// yields an empty list, not an error: reconnect reconciliation should not fail
// just because the session has nothing pending.
func (m *Manager) Interactions(ctx context.Context, id domain.SessionID) ([]domain.PendingInteraction, error) {
	m.interactionsMu.Lock()
	defer m.interactionsMu.Unlock()
	in, ok := m.interactions[id]
	if !ok {
		return nil, nil
	}
	return []domain.PendingInteraction{in}, nil
}
