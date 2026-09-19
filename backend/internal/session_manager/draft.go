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
	rec, err := m.liveSession(ctx, "draft", id)
	if err != nil || rec == nil {
		return "", err
	}
	reader, ok := m.composerReaderFor(rec.Harness)
	if !ok {
		return "", nil
	}
	pane, err := m.idleComposerPane(ctx, "draft", *rec)
	if err != nil || pane == "" {
		return "", err
	}
	draft, ok := reader.ReadComposerDraft(pane)
	if !ok {
		return "", nil
	}
	return draft, nil
}

// Suggestion reads the prompt the harness proposes in its empty composer
// (Claude Code's predicted next prompt) under the same fail-closed rules as
// Draft: a typed draft, a dialog, or any styling ambiguity reads as "".
func (m *Manager) Suggestion(ctx context.Context, id domain.SessionID) (string, error) {
	rec, err := m.liveSession(ctx, "suggestion", id)
	if err != nil || rec == nil {
		return "", err
	}
	reader, ok := m.suggestionReaderFor(rec.Harness)
	if !ok {
		return "", nil
	}
	pane, err := m.idleComposerPane(ctx, "suggestion", *rec)
	if err != nil || pane == "" {
		return "", err
	}
	suggestion, ok := reader.ReadComposerSuggestion(pane)
	if !ok {
		return "", nil
	}
	return suggestion, nil
}

// liveSession returns the record of a session that still has a runtime to
// read, nil when it has none (terminated or never launched), and ErrNotFound
// for an unknown id.
func (m *Manager) liveSession(ctx context.Context, operation string, id domain.SessionID) (*domain.SessionRecord, error) {
	rec, ok, err := m.store.GetSession(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("%s %s: %w", operation, id, err)
	}
	if !ok {
		return nil, ErrNotFound
	}
	if rec.IsTerminated || rec.Metadata.RuntimeHandleID == "" {
		return nil, nil
	}
	return &rec, nil
}

// idleComposerPane returns the styled pane of a live session whose screen
// shows the composer rather than a dialog, or "" when there is nothing safe
// to read. A dialog's own bordered, highlighted rows satisfy the structural
// checks the composer readers use — finding 9's marker-glyph collision, one
// layer above the menu reader it was written for — so a model picker or a
// question menu would otherwise read back as composer text. The check lives
// here rather than inside each plugin so both harnesses and both readers are
// covered by one code path.
func (m *Manager) idleComposerPane(ctx context.Context, operation string, rec domain.SessionRecord) (string, error) {
	styled, ok := m.runtime.(ports.StyledTerminalOutputReader)
	if !ok {
		return "", nil
	}
	pane, err := styled.GetStyledOutput(ctx, runtimeHandle(rec.Metadata), commandPaneLines)
	if err != nil {
		return "", fmt.Errorf("%s %s: %w", operation, rec.ID, err)
	}
	if dialogs, ok := m.dialogReaderFor(rec.Harness); ok {
		if _, onScreen := dialogs.ReadDialog(pane); onScreen {
			return "", nil
		}
	}
	return pane, nil
}
