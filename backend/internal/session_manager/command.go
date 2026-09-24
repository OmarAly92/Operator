package sessionmanager

import (
	"context"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/service/dialogdriver"
)

const keyEscape = "\x1b"

type CommandResult struct {
	Wrote  bool
	Models []string
}

type ModelOption struct {
	Label       string
	Description string
	Current     bool
}

func (m *Manager) Command(ctx context.Context, id domain.SessionID, cmd domain.SessionCommand, model string) (CommandResult, error) {
	rec, err := m.commandRecord(ctx, id)
	if err != nil {
		return CommandResult{}, err
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

func (m *Manager) commandRecord(ctx context.Context, id domain.SessionID) (domain.SessionRecord, error) {
	rec, ok, err := m.store.GetSession(ctx, id)
	if err != nil {
		return domain.SessionRecord{}, fmt.Errorf("command %s: %w", id, err)
	}
	if !ok {
		return domain.SessionRecord{}, ErrNotFound
	}
	if rec.IsTerminated {
		return domain.SessionRecord{}, ErrTerminated
	}
	if rec.Activity.State == domain.ActivityExited {
		return domain.SessionRecord{}, ErrAgentExited
	}
	if rec.Metadata.RuntimeHandleID == "" {
		return domain.SessionRecord{}, ErrIncompleteHandle
	}
	return rec, nil
}

// Models opens the harness's model picker just long enough to read it, then
// backs out with Esc. It is the only way to learn which models this Claude
// Code build offers and which one the session is on: the picker marks the
// current row with ✔ and neither fact is written anywhere else.
func (m *Manager) Models(ctx context.Context, id domain.SessionID) ([]ModelOption, error) {
	rec, err := m.commandRecord(ctx, id)
	if err != nil {
		return nil, err
	}
	if rec.Activity.State == domain.ActivityBlocked {
		return nil, ErrAwaitingDecision
	}
	if rec.Activity.State != domain.ActivityIdle {
		return nil, ErrWrongActivityState
	}
	reader, ok := m.menuReaderFor(rec.Harness)
	if !ok {
		return nil, ErrWrongActivityState
	}
	if err := m.requireEmptyComposer(ctx, rec); err != nil {
		return nil, err
	}
	handle := runtimeHandle(rec.Metadata)
	driver := m.driverFor(handle)
	if err := driver.Press(ctx, "/model\r"); err != nil {
		return nil, fmt.Errorf("models %s: %w", rec.ID, err)
	}
	menu, open, err := m.awaitMenu(ctx, reader, handle)
	m.escape(ctx, driver, rec.ID)
	if err != nil {
		return nil, fmt.Errorf("models %s: read picker: %w", rec.ID, err)
	}
	if !open {
		return nil, ErrDialogAbsent
	}
	return parseModelOptions(menu), nil
}

// awaitMenu re-reads the pane until the picker has rendered. One read after a
// fixed settle was enough on a quiet machine and not on a busy one; a menu
// that has not appeared within the budget is reported absent.
func (m *Manager) awaitMenu(ctx context.Context, reader ports.TerminalMenuReader, handle ports.RuntimeHandle) (ports.Menu, bool, error) {
	deadline := time.Now().Add(menuAppearBudget)
	for {
		pane, err := m.runtime.GetOutput(ctx, handle, commandPaneLines)
		if err != nil {
			return ports.Menu{}, false, err
		}
		if menu, open := reader.ReadMenu(pane); open {
			return menu, true, nil
		}
		if time.Now().After(deadline) {
			return ports.Menu{}, false, nil
		}
		if err := sleepContext(ctx, menuAppearPoll); err != nil {
			return ports.Menu{}, false, err
		}
	}
}

const (
	menuAppearBudget = 2 * time.Second
	menuAppearPoll   = 100 * time.Millisecond
)

var (
	menuRowNumber  = regexp.MustCompile(`^\d+\.\s+`)
	menuRowColumns = regexp.MustCompile(`\s{2,}`)
)

func parseModelOptions(menu ports.Menu) []ModelOption {
	options := make([]ModelOption, 0, len(menu.Rows))
	marked := false
	for _, row := range menu.Rows {
		row = menuRowNumber.ReplaceAllString(strings.TrimSpace(row), "")
		label, description, _ := strings.Cut(row, "  ")
		description = strings.TrimSpace(menuRowColumns.ReplaceAllString(description, " "))
		current := strings.Contains(label, "✔")
		label = strings.TrimSpace(strings.ReplaceAll(label, "✔", ""))
		marked = marked || current
		options = append(options, ModelOption{Label: label, Description: description, Current: current})
	}
	if !marked && menu.Selected >= 0 && menu.Selected < len(options) {
		options[menu.Selected].Current = true
	}
	return options
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

	menu, open, err := m.awaitMenu(ctx, reader, handle)
	if err != nil {
		return CommandResult{}, fmt.Errorf("command model %s: read picker: %w", rec.ID, err)
	}
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
	for i, option := range parseModelOptions(ports.Menu{Rows: rows, Selected: -1}) {
		if strings.EqualFold(option.Label, want) {
			return i
		}
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
