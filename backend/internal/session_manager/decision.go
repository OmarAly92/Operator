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
		return m.answerFailure(ctx, id, driver, err)
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

func (m *Manager) answerFailure(ctx context.Context, id domain.SessionID, driver *dialogdriver.Driver, err error) error {
	if errors.Is(err, dialogdriver.ErrNotOnScreen) {
		m.ClearInteractions(id)
		return ErrDialogAbsent
	}
	if errors.Is(err, dialogdriver.ErrUnconfirmed) {
		return ErrUnconfirmed
	}
	return fmt.Errorf("answer %s: %w", id, err)
}
