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
	// A dialog's own bordered, highlighted rows satisfy the very structural
	// checks the composer-draft readers use — finding 9's marker-glyph
	// collision, one layer above the menu reader it was written for. A model
	// picker or a question menu on screen therefore reads back as a "draft",
	// and mirroring it into another client's composer would put text there the
	// user never wrote. The check lives here rather than inside each plugin so
	// both harnesses are covered by one code path.
	if dialogs, ok := m.dialogReaderFor(rec.Harness); ok {
		if _, onScreen := dialogs.ReadDialog(pane); onScreen {
			return "", nil
		}
	}
	draft, ok := reader.ReadComposerDraft(pane)
	if !ok {
		return "", nil
	}
	return draft, nil
}
