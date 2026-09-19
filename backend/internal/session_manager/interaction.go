package sessionmanager

import (
	"context"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
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
	in, ok := m.interactions[id]
	m.interactionsMu.Unlock()
	if !ok {
		return nil, nil
	}
	if in.Kind == domain.InteractionPermission {
		in.Options = m.permissionOptions(ctx, id)
	}
	return []domain.PendingInteraction{in}, nil
}

func (m *Manager) permissionOptions(ctx context.Context, id domain.SessionID) []string {
	rec, ok, err := m.store.GetSession(ctx, id)
	if err != nil || !ok || rec.Metadata.RuntimeHandleID == "" {
		return nil
	}
	reader, ok := m.dialogReaderFor(rec.Harness)
	if !ok {
		return nil
	}
	pane, err := m.runtime.GetOutput(ctx, runtimeHandle(rec.Metadata), commandPaneLines)
	if err != nil {
		return nil
	}
	dlg, on := reader.ReadDialog(pane)
	if !on || dlg.Kind != ports.DialogPermission {
		return nil
	}
	options := make([]string, 0, len(dlg.Menu.Rows))
	for _, option := range parseModelOptions(dlg.Menu) {
		options = append(options, option.Label)
	}
	return options
}
