package sessionmanager

import (
	"context"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// Draft reads the harness's unsent composer draft. It never writes. A harness
// with no composer reader, a runtime that cannot preserve styling, or any
// styling ambiguity all report an empty draft rather than an error: the
// caller mirrors the result into another client's composer, so it fails
// closed instead of guessing.
func (m *Manager) Draft(ctx context.Context, id domain.SessionID) (string, error) {
	rec, ok, err := m.store.GetSession(ctx, id)
	if err != nil {
		return "", fmt.Errorf("draft %s: %w", id, err)
	}
	if !ok {
		return "", ErrNotFound
	}
	if rec.IsTerminated || rec.Metadata.RuntimeHandleID == "" {
		return "", nil
	}
	reader, ok := m.composerReaderFor(rec.Harness)
	if !ok {
		return "", nil
	}
	styled, ok := m.runtime.(ports.StyledTerminalOutputReader)
	if !ok {
		return "", nil
	}
	pane, err := styled.GetStyledOutput(ctx, runtimeHandle(rec.Metadata), commandPaneLines)
	if err != nil {
		return "", fmt.Errorf("draft %s: %w", id, err)
	}
	draft, ok := reader.ReadComposerDraft(pane)
	if !ok {
		return "", nil
	}
	return draft, nil
}
