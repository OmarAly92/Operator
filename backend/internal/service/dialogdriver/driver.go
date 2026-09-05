package dialogdriver

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var (
	// ErrNotOnScreen means the expected dialog was not there when we looked.
	// Nothing was written; the caller reports the dialog as gone.
	ErrNotOnScreen = errors.New("dialogdriver: expected dialog is not on screen")
	// ErrUnconfirmed means the key was written but the screen did not change.
	// The caller must NOT retry: the write may have landed and simply not
	// redrawn, and a second key would answer a second dialog.
	ErrUnconfirmed = errors.New("dialogdriver: screen did not change after the write")
	// ErrStuck means the highlight stopped responding to navigation before it
	// reached the target row.
	ErrStuck = errors.New("dialogdriver: menu highlight stopped moving")
)

// maxMenuSteps bounds navigation so a misread highlight cannot hold the pty
// down on an arrow key. A menu deeper than this is not one we can drive.
const maxMenuSteps = 64

// Screen is the pane the driver reads and writes. The session manager supplies
// one backed by runtime.GetOutput and runtime.SendInput.
type Screen interface {
	Read(ctx context.Context) (string, error)
	Write(ctx context.Context, keys string) error
}

// Driver turns best-effort keystroke injection into something checkable: it
// never writes into a screen it has not just read, and it never reports success
// it has not just observed.
type Driver struct {
	screen Screen
	settle time.Duration
}

// New builds a driver. settle is how long to wait after a write before reading
// back, so a redraw is not mistaken for a screen that did not move; tests pass 0.
func New(screen Screen, settle time.Duration) *Driver {
	return &Driver{screen: screen, settle: settle}
}

// AnswerDialog writes one key into a dialog, but only after confirming the
// dialog is on screen, and reports whether the screen moved afterwards.
func (d *Driver) AnswerDialog(ctx context.Context, present func(pane string) bool, key string) error {
	before, err := d.screen.Read(ctx)
	if err != nil {
		return fmt.Errorf("dialogdriver: read before write: %w", err)
	}
	if !present(before) {
		return ErrNotOnScreen
	}
	if err := d.screen.Write(ctx, key); err != nil {
		return fmt.Errorf("dialogdriver: write: %w", err)
	}
	d.wait(ctx)
	after, err := d.screen.Read(ctx)
	if err != nil {
		return fmt.Errorf("dialogdriver: read after write: %w", err)
	}
	if after == before {
		return ErrUnconfirmed
	}
	return nil
}

// NavigateTo moves a menu's highlight onto target and stops. It does not press
// Select — the caller does that, so a caller can inspect the verified row first.
//
// Each step is verified against a fresh read rather than counted: counting
// presses assumes the menu did not wrap, scroll, or swallow a key, and all
// three happen.
func (d *Driver) NavigateTo(ctx context.Context, read func(pane string) (ports.Menu, bool), keys ports.MenuKeys, target int) error {
	for step := 0; step <= maxMenuSteps; step++ {
		pane, err := d.screen.Read(ctx)
		if err != nil {
			return fmt.Errorf("dialogdriver: read menu: %w", err)
		}
		menu, ok := read(pane)
		if !ok {
			return ErrNotOnScreen
		}
		if target < 0 || target >= len(menu.Rows) {
			return fmt.Errorf("dialogdriver: target row %d out of range for %d rows", target, len(menu.Rows))
		}
		if menu.Selected == target {
			return nil
		}
		key := keys.Down
		if menu.Selected > target {
			key = keys.Up
		}
		if err := d.screen.Write(ctx, key); err != nil {
			return fmt.Errorf("dialogdriver: navigate: %w", err)
		}
		d.wait(ctx)
	}
	return ErrStuck
}

// Press writes a key with no verification. It is only for keys whose effect the
// caller verifies itself on the next read — Select after a verified NavigateTo,
// or Cancel when backing out of a menu we are abandoning anyway.
func (d *Driver) Press(ctx context.Context, key string) error {
	if err := d.screen.Write(ctx, key); err != nil {
		return fmt.Errorf("dialogdriver: press: %w", err)
	}
	d.wait(ctx)
	return nil
}

func (d *Driver) wait(ctx context.Context) {
	if d.settle <= 0 {
		return
	}
	t := time.NewTimer(d.settle)
	defer t.Stop()
	select {
	case <-ctx.Done():
	case <-t.C:
	}
}
