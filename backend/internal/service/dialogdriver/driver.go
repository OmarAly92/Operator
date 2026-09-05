package dialogdriver

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var (
	ErrNotOnScreen = errors.New("dialogdriver: expected dialog is not on screen")
	ErrUnconfirmed = errors.New("dialogdriver: screen did not change after the write")
	ErrStuck       = errors.New("dialogdriver: menu highlight stopped moving")
)

const maxMenuSteps = 64

type Screen interface {
	Read(ctx context.Context) (string, error)
	Write(ctx context.Context, keys string) error
}

type Driver struct {
	screen Screen
	settle time.Duration
}

func New(screen Screen, settle time.Duration) *Driver {
	return &Driver{screen: screen, settle: settle}
}

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
