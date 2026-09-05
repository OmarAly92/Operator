package sessionmanager

import (
	"context"
	"errors"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/service/dialogdriver"
)

// ErrUnconfirmed means the key was written but the screen did not move. The
// caller must present this to the user as "unconfirmed", never as failure:
// the write may well have landed. Nothing is retried.
var ErrUnconfirmed = errors.New("session: action was written but not confirmed on screen")

// ErrAnswerInvalid means the selection is empty or names an option that is not
// on the menu currently on screen. Nothing is written.
var ErrAnswerInvalid = errors.New("session: answer selection is invalid")

// Decide answers a pending permission dialog by driving one key into it.
//
// Because the phone answers the DIALOG rather than the hook, there is no
// deadline: Claude Code's dialog waits indefinitely, so a request is still
// answerable an hour later. The interaction id is checked first so that two
// clients racing one dialog cannot have the loser answer the NEXT dialog.
func (m *Manager) Decide(ctx context.Context, id domain.SessionID, interactionID, behavior string) error {
	rec, ok, err := m.store.GetSession(ctx, id)
	if err != nil {
		return fmt.Errorf("decide %s: %w", id, err)
	}
	if !ok {
		return ErrNotFound
	}
	if rec.IsTerminated {
		return ErrTerminated
	}
	if rec.Activity.State == domain.ActivityExited {
		return ErrAgentExited
	}
	if rec.Metadata.RuntimeHandleID == "" {
		return ErrIncompleteHandle
	}
	pending, ok := m.Interaction(id, interactionID)
	if !ok || pending.Kind != domain.InteractionPermission {
		return ErrDialogAbsent
	}
	reader, ok := m.dialogReaderFor(rec.Harness)
	if !ok {
		return ErrDialogAbsent
	}
	if behavior != "allow" && behavior != "deny" {
		return fmt.Errorf("decide %s: unknown behavior %q", id, behavior)
	}

	handle := runtimeHandle(rec.Metadata)
	driver := m.driverFor(handle)

	// The permission prompt is a numbered menu whose options vary by tool
	// (finding 6), so the row is found by meaning and then navigated to —
	// there is no fixed answer key.
	pane, err := m.runtime.GetOutput(ctx, handle, commandPaneLines)
	if err != nil {
		return fmt.Errorf("decide %s: read dialog: %w", id, err)
	}
	dlg, on := reader.ReadDialog(pane)
	if !on || dlg.Kind != ports.DialogPermission {
		return ErrDialogAbsent
	}
	row, found := reader.AllowRow(dlg.Menu)
	if behavior == "deny" {
		row, found = reader.DenyRow(dlg.Menu)
	}
	if !found {
		return ErrDialogAbsent
	}
	keys := reader.MenuKeys()
	readMenu := func(pane string) (ports.Menu, bool) {
		d, on := reader.ReadDialog(pane)
		return d.Menu, on
	}
	if err := driver.NavigateTo(ctx, readMenu, keys, row); err != nil {
		return m.answerFailure(id, err)
	}
	present := func(pane string) bool {
		d, on := reader.ReadDialog(pane)
		return on && d.Kind == ports.DialogPermission
	}
	switch err := driver.AnswerDialog(ctx, present, keys.Select); {
	case err == nil:
		m.ClearInteractions(id)
		return nil
	case errors.Is(err, dialogdriver.ErrNotOnScreen):
		m.ClearInteractions(id)
		return ErrDialogAbsent
	case errors.Is(err, dialogdriver.ErrUnconfirmed):
		return ErrUnconfirmed
	default:
		return fmt.Errorf("decide %s: %w", id, err)
	}
}

// Answer drives a question's menu. Selections is one group of option LABELS
// per question in the dialog; a single-element group is a single-select,
// several are a multi-select whose rows are toggled before Enter.
//
// Labels, never indices: the harness inserts synthetic rows ("Type
// something.", "Chat about this") the transcript never listed, so a position
// carried from the client lands on the wrong row (finding 8).
//
// Every hop is verified against a fresh read by the driver rather than counted:
// counting presses assumes the menu did not wrap, scroll or swallow a key.
func (m *Manager) Answer(ctx context.Context, id domain.SessionID, interactionID string, selections [][]string) error {
	if len(selections) == 0 {
		return fmt.Errorf("answer %s: no selections: %w", id, ErrAnswerInvalid)
	}
	rec, ok, err := m.store.GetSession(ctx, id)
	if err != nil {
		return fmt.Errorf("answer %s: %w", id, err)
	}
	if !ok {
		return ErrNotFound
	}
	if rec.IsTerminated {
		return ErrTerminated
	}
	if rec.Activity.State == domain.ActivityExited {
		return ErrAgentExited
	}
	if rec.Metadata.RuntimeHandleID == "" {
		return ErrIncompleteHandle
	}
	pending, ok := m.Interaction(id, interactionID)
	if !ok || pending.Kind != domain.InteractionQuestion {
		return ErrDialogAbsent
	}
	reader, ok := m.dialogReaderFor(rec.Harness)
	if !ok {
		return ErrDialogAbsent
	}

	handle := runtimeHandle(rec.Metadata)
	driver := m.driverFor(handle)
	keys := reader.MenuKeys()
	readMenu := func(pane string) (ports.Menu, bool) {
		d, on := reader.ReadDialog(pane)
		if !on || d.Kind != ports.DialogQuestion {
			return ports.Menu{}, false
		}
		return d.Menu, true
	}
	// Reading the dialog rather than the bare menu is what tells a question
	// apart from a permission prompt or a model picker, which render the same
	// numbered menu (finding 6). Decide makes the mirror-image check.
	readQuestion := func() (ports.Menu, error) {
		pane, err := m.runtime.GetOutput(ctx, handle, commandPaneLines)
		if err != nil {
			return ports.Menu{}, fmt.Errorf("answer %s: read menu: %w", id, err)
		}
		menu, on := readMenu(pane)
		if !on {
			return ports.Menu{}, ErrDialogAbsent
		}
		return menu, nil
	}

	menu, err := readQuestion()
	if err != nil {
		return err
	}
	for i, group := range selections {
		// Each group answers a DIFFERENT question, and submitting the previous
		// one moves the dialog on, so every group after the first is resolved
		// against the rows now on screen. Resolving all of them against the
		// first read would silently answer question 2 with question 1's rows.
		if i > 0 {
			if menu, err = readQuestion(); err != nil {
				return err
			}
		}
		rows, err := resolveRows(id, menu, group)
		if err != nil {
			return err
		}
		for j, row := range rows {
			if err := driver.NavigateTo(ctx, readMenu, keys, row); err != nil {
				return m.answerFailure(id, err)
			}
			// Multi-select toggles each row and submits once at the end; a
			// single-select submits on the row itself.
			if len(rows) > 1 && keys.Multi != "" && j < len(rows) {
				if err := driver.Press(ctx, keys.Multi); err != nil {
					return m.answerFailure(id, err)
				}
			}
		}
		if err := driver.Press(ctx, keys.Select); err != nil {
			return m.answerFailure(id, err)
		}
	}
	m.ClearInteractions(id)
	return nil
}

// resolveRows maps one question group's option labels onto the rows currently
// on screen. It resolves every label before the caller writes anything: a
// half-answered question is worse than a refused one, and a label with no
// matching row means the menu is not the one the client was looking at.
func resolveRows(id domain.SessionID, menu ports.Menu, group []string) ([]int, error) {
	if len(group) == 0 {
		return nil, fmt.Errorf("answer %s: empty selection group: %w", id, ErrAnswerInvalid)
	}
	rows := make([]int, 0, len(group))
	for _, label := range group {
		row := indexOfRow(menu.Rows, label)
		if row < 0 {
			return nil, fmt.Errorf("answer %s: option %q is not on screen: %w", id, label, ErrAnswerInvalid)
		}
		rows = append(rows, row)
	}
	return rows, nil
}

func (m *Manager) answerFailure(id domain.SessionID, err error) error {
	if errors.Is(err, dialogdriver.ErrNotOnScreen) {
		m.ClearInteractions(id)
		return ErrDialogAbsent
	}
	if errors.Is(err, dialogdriver.ErrUnconfirmed) {
		return ErrUnconfirmed
	}
	return fmt.Errorf("answer %s: %w", id, err)
}
