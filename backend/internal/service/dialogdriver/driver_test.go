package dialogdriver

import (
	"context"
	"errors"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type scriptedScreen struct {
	panes  []string
	at     int
	writes []string
}

func (s *scriptedScreen) Read(context.Context) (string, error) {
	if s.at >= len(s.panes) {
		return s.panes[len(s.panes)-1], nil
	}
	pane := s.panes[s.at]
	s.at++
	return pane, nil
}

func (s *scriptedScreen) Write(_ context.Context, keys string) error {
	s.writes = append(s.writes, keys)
	return nil
}

func TestAnswerDialogWritesOnceWhenThePromptIsPresentAndTheScreenMoves(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"DIALOG", "done"}}
	d := New(screen, 0)

	err := d.AnswerDialog(context.Background(), func(p string) bool { return p == "DIALOG" }, "y")
	if err != nil {
		t.Fatalf("AnswerDialog: %v", err)
	}
	if len(screen.writes) != 1 || screen.writes[0] != "y" {
		t.Fatalf("expected exactly one write of y, got %q", screen.writes)
	}
}

func TestAnswerDialogRefusesAndWritesNothingWhenAbsent(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"idle prompt"}}
	d := New(screen, 0)

	err := d.AnswerDialog(context.Background(), func(p string) bool { return p == "DIALOG" }, "y")
	if !errors.Is(err, ErrNotOnScreen) {
		t.Fatalf("expected ErrNotOnScreen, got %v", err)
	}
	if len(screen.writes) != 0 {
		t.Fatalf("a refused answer must write nothing, got %q", screen.writes)
	}
}

func TestAnswerDialogReportsUnconfirmedWhenTheScreenDoesNotMove(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"DIALOG", "DIALOG"}}
	d := New(screen, 0)

	err := d.AnswerDialog(context.Background(), func(p string) bool { return p == "DIALOG" }, "y")
	if !errors.Is(err, ErrUnconfirmed) {
		t.Fatalf("expected ErrUnconfirmed, got %v", err)
	}
	if len(screen.writes) != 1 {
		t.Fatalf("an unconfirmed answer must not retry, got %d writes", len(screen.writes))
	}
}

func TestNavigateToWalksToTheVerifiedRow(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"row0", "row1", "row2"}}
	read := func(p string) (ports.Menu, bool) {
		switch p {
		case "row0":
			return ports.Menu{Rows: []string{"a", "b", "c"}, Selected: 0}, true
		case "row1":
			return ports.Menu{Rows: []string{"a", "b", "c"}, Selected: 1}, true
		case "row2":
			return ports.Menu{Rows: []string{"a", "b", "c"}, Selected: 2}, true
		}
		return ports.Menu{}, false
	}
	keys := ports.MenuKeys{Up: "\x1b[A", Down: "\x1b[B", Select: "\r", Cancel: "\x1b"}
	d := New(screen, 0)

	if err := d.NavigateTo(context.Background(), read, keys, 2); err != nil {
		t.Fatalf("NavigateTo: %v", err)
	}
	for _, w := range screen.writes {
		if w != keys.Down {
			t.Fatalf("expected only Down presses, got %q", screen.writes)
		}
	}
	if len(screen.writes) != 2 {
		t.Fatalf("expected 2 Down presses, got %d", len(screen.writes))
	}
}

func TestNavigateToGivesUpWhenTheHighlightStopsMoving(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"stuck"}}
	read := func(string) (ports.Menu, bool) {
		return ports.Menu{Rows: []string{"a", "b", "c"}, Selected: 0}, true
	}
	keys := ports.MenuKeys{Up: "\x1b[A", Down: "\x1b[B", Select: "\r", Cancel: "\x1b"}
	d := New(screen, 0)

	err := d.NavigateTo(context.Background(), read, keys, 2)
	if !errors.Is(err, ErrStuck) {
		t.Fatalf("expected ErrStuck, got %v", err)
	}
	if len(screen.writes) > maxMenuSteps+1 {
		t.Fatalf("the driver must bound its presses, got %d", len(screen.writes))
	}
}

func TestNavigateToIsANoOpWhenAlreadyOnTheTargetRow(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"row1"}}
	read := func(string) (ports.Menu, bool) {
		return ports.Menu{Rows: []string{"a", "b", "c"}, Selected: 1}, true
	}
	d := New(screen, 0)

	if err := d.NavigateTo(context.Background(), read, ports.MenuKeys{Down: "\x1b[B", Up: "\x1b[A"}, 1); err != nil {
		t.Fatalf("NavigateTo: %v", err)
	}
	if len(screen.writes) != 0 {
		t.Fatalf("expected no presses, got %q", screen.writes)
	}
}

func TestNavigateToRefusesWhenTheMenuIsGone(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"idle"}}
	read := func(string) (ports.Menu, bool) { return ports.Menu{}, false }
	d := New(screen, 0)

	err := d.NavigateTo(context.Background(), read, ports.MenuKeys{Down: "\x1b[B"}, 1)
	if !errors.Is(err, ErrNotOnScreen) {
		t.Fatalf("expected ErrNotOnScreen, got %v", err)
	}
	if len(screen.writes) != 0 {
		t.Fatalf("expected no presses, got %q", screen.writes)
	}
}
