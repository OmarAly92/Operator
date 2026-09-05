package sessionmanager

import (
	"context"
	"fmt"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/service/dialogdriver"
)

const keyEscape = "\x1b"

type CommandResult struct {
	Wrote  bool
	Models []string
}

func (m *Manager) Command(ctx context.Context, id domain.SessionID, cmd domain.SessionCommand, model string) (CommandResult, error) {
	rec, ok, err := m.store.GetSession(ctx, id)
	if err != nil {
		return CommandResult{}, fmt.Errorf("command %s: %w", id, err)
	}
	if !ok {
		return CommandResult{}, ErrNotFound
	}
	if rec.IsTerminated {
		return CommandResult{}, ErrTerminated
	}
	if rec.Activity.State == domain.ActivityExited {
		return CommandResult{}, ErrAgentExited
	}
	if rec.Metadata.RuntimeHandleID == "" {
		return CommandResult{}, ErrIncompleteHandle
	}

	switch cmd {
	case domain.CommandStop:
		return m.commandStop(ctx, rec)
	case domain.CommandCompact:
		return m.commandTyped(ctx, rec, "/compact")
	case domain.CommandModel:
		return m.commandModel(ctx, rec, model)
	default:
		return CommandResult{}, fmt.Errorf("command %s: %w", id, ErrWrongActivityState)
	}
}

func (m *Manager) commandStop(ctx context.Context, rec domain.SessionRecord) (CommandResult, error) {
	if rec.Activity.State != domain.ActivityActive {
		return CommandResult{}, ErrWrongActivityState
	}
	if err := m.runtime.SendInput(ctx, runtimeHandle(rec.Metadata), keyEscape); err != nil {
		return CommandResult{}, fmt.Errorf("command stop %s: %w", rec.ID, err)
	}
	return CommandResult{Wrote: true}, nil
}

func (m *Manager) commandTyped(ctx context.Context, rec domain.SessionRecord, text string) (CommandResult, error) {
	if rec.Activity.State == domain.ActivityBlocked {
		return CommandResult{}, ErrAwaitingDecision
	}
	if rec.Activity.State != domain.ActivityIdle {
		return CommandResult{}, ErrWrongActivityState
	}
	if err := m.requireEmptyComposer(ctx, rec); err != nil {
		return CommandResult{}, err
	}
	if err := m.runtime.SendInput(ctx, runtimeHandle(rec.Metadata), text+"\r"); err != nil {
		return CommandResult{}, fmt.Errorf("command %s %s: %w", text, rec.ID, err)
	}
	return CommandResult{Wrote: true}, nil
}

// commandModel changes the model through the harness's own picker, in ONE call.
// Opening the picker and waiting for a client to choose would park the desktop
// terminal in a menu for as long as the phone takes, so the label is chosen
// before anything is typed and the picker is either driven to it or backed out
// of with Esc. The terminal is never left open.
func (m *Manager) commandModel(ctx context.Context, rec domain.SessionRecord, label string) (CommandResult, error) {
	if rec.Activity.State == domain.ActivityBlocked {
		return CommandResult{}, ErrAwaitingDecision
	}
	if rec.Activity.State != domain.ActivityIdle {
		return CommandResult{}, ErrWrongActivityState
	}
	reader, ok := m.menuReaderFor(rec.Harness)
	if !ok {
		return CommandResult{}, ErrWrongActivityState
	}
	if err := m.requireEmptyComposer(ctx, rec); err != nil {
		return CommandResult{}, err
	}

	handle := runtimeHandle(rec.Metadata)
	driver := m.driverFor(handle)
	if err := driver.Press(ctx, "/model\r"); err != nil {
		return CommandResult{}, fmt.Errorf("command model %s: %w", rec.ID, err)
	}

	pane, err := m.runtime.GetOutput(ctx, handle, commandPaneLines)
	if err != nil {
		return CommandResult{}, fmt.Errorf("command model %s: read picker: %w", rec.ID, err)
	}
	menu, open := reader.ReadMenu(pane)
	if !open {
		m.escape(ctx, driver, rec.ID)
		return CommandResult{}, ErrDialogAbsent
	}
	target := indexOfRow(menu.Rows, label)
	if target < 0 {
		m.escape(ctx, driver, rec.ID)
		return CommandResult{Models: menu.Rows}, ErrModelNotOffered
	}
	if err := driver.NavigateTo(ctx, reader.ReadMenu, reader.MenuKeys(), target); err != nil {
		m.escape(ctx, driver, rec.ID)
		return CommandResult{Models: menu.Rows}, fmt.Errorf("command model %s: %w", rec.ID, err)
	}
	// SessionSelect, never Select: the picker's Enter sets the user's DEFAULT
	// model for every new session, which is not what "change this session's
	// model" asked for (finding 7).
	if err := driver.Press(ctx, reader.MenuKeys().SessionSelect); err != nil {
		return CommandResult{Models: menu.Rows}, fmt.Errorf("command model %s: select: %w", rec.ID, err)
	}
	return CommandResult{Wrote: true, Models: menu.Rows}, nil
}

// requireEmptyComposer refuses an unattended slash-command write while a human
// draft sits unsent in the harness's composer: the write would be appended to
// it and submitted as one garbled prompt. A harness with no detector, or a
// runtime that cannot preserve styling at all, is not gated — the capability is
// opt-in and reports emptiness only from positive evidence, so treating a
// missing capability as "not empty" would make /compact and /model permanently
// unavailable there. A pane read that FAILS is a different thing and is
// surfaced: we could not check, so we do not write.
func (m *Manager) requireEmptyComposer(ctx context.Context, rec domain.SessionRecord) error {
	detector, ok := m.emptyComposerDetectorFor(rec.Harness)
	if !ok {
		return nil
	}
	styled, ok := m.runtime.(ports.StyledTerminalOutputReader)
	if !ok {
		return nil
	}
	output, err := styled.GetStyledOutput(ctx, runtimeHandle(rec.Metadata), sourceComposerProbeLines)
	if err != nil {
		return fmt.Errorf("command %s: read composer: %w", rec.ID, err)
	}
	if !detector.ComposerIsEmpty(output) {
		return ErrComposerNotEmpty
	}
	return nil
}

// escape backs out of a picker we are abandoning. Its failure is logged and
// swallowed: the caller is already returning an error, and reporting the Esc's
// failure instead would hide why the command actually failed.
func (m *Manager) escape(ctx context.Context, driver *dialogdriver.Driver, id domain.SessionID) {
	if err := driver.Press(ctx, keyEscape); err != nil {
		m.logger.Warn("command model: failed to back out of the picker", "sessionID", id, "error", err)
	}
}

// indexOfRow matches a picker row by case-insensitive substring: a harness
// renders "opus" inside a longer descriptive row, and the client's seed label
// is the short name the user picked.
func indexOfRow(rows []string, label string) int {
	want := strings.ToLower(strings.TrimSpace(label))
	if want == "" {
		return -1
	}
	for i, row := range rows {
		if strings.Contains(strings.ToLower(row), want) {
			return i
		}
	}
	return -1
}

// commandPaneLines bounds every pane read a command makes. A picker taller than
// this is not one we can drive; the readers bound themselves the same way.
const commandPaneLines = 40
