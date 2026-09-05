package sessionmanager

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeDialogReader struct {
	present bool
}

func (f fakeDialogReader) ReadDialog(pane string) (ports.Dialog, bool) {
	if !f.present {
		return ports.Dialog{}, false
	}
	selected := 0
	if idx := strings.Index(pane, "SEL:"); idx >= 0 {
		if n, err := strconv.Atoi(pane[idx+len("SEL:"):]); err == nil {
			selected = n
		}
	}
	return ports.Dialog{
		Kind: ports.DialogPermission,
		Menu: ports.Menu{Rows: []string{"1. Yes", "3. No"}, Selected: selected},
	}, true
}

func (f fakeDialogReader) AllowRow(ports.Menu) (int, bool) { return 0, true }
func (f fakeDialogReader) DenyRow(ports.Menu) (int, bool)  { return 1, true }

func (f fakeDialogReader) MenuKeys() ports.MenuKeys {
	return ports.MenuKeys{Up: "up", Down: "down", Select: "enter"}
}

func TestDecideDrivesExactlyOneKeyWhenTheDialogIsOnScreen(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"DIALOG SEL:0", "DIALOG SEL:0", "DIALOG SEL:0", "moved on"}
	m.dialogReader = fakeDialogReader{present: true}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionPermission})

	if err := m.Decide(context.Background(), "s1", "i1", "allow"); err != nil {
		t.Fatalf("Decide: %v", err)
	}
	if len(rt.inputs) != 1 || rt.inputs[0] != "enter" {
		t.Fatalf("expected exactly one Select key, got %q", rt.inputs)
	}
}

func TestDecideWritesNothingWhenTheDialogIsGone(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"idle prompt"}
	m.dialogReader = fakeDialogReader{present: false}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionPermission})

	err := m.Decide(context.Background(), "s1", "i1", "allow")
	if !errors.Is(err, ErrDialogAbsent) {
		t.Fatalf("expected ErrDialogAbsent, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestDecideReportsUnconfirmedWhenTheScreenDoesNotMove(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"DIALOG SEL:0", "DIALOG SEL:0", "DIALOG SEL:0", "DIALOG SEL:0"}
	m.dialogReader = fakeDialogReader{present: true}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionPermission})

	err := m.Decide(context.Background(), "s1", "i1", "allow")
	if !errors.Is(err, ErrUnconfirmed) {
		t.Fatalf("expected ErrUnconfirmed, got %v", err)
	}
	if len(rt.inputs) != 1 {
		t.Fatalf("an unconfirmed decision must not retry, got %d writes", len(rt.inputs))
	}
}

func TestDecideRefusesAStaleInteractionID(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"DIALOG SEL:0"}
	m.dialogReader = fakeDialogReader{present: true}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i2", Kind: domain.InteractionPermission})

	err := m.Decide(context.Background(), "s1", "i1", "allow")
	if !errors.Is(err, ErrDialogAbsent) {
		t.Fatalf("expected ErrDialogAbsent for a stale id, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestDecideRejectsAnUnknownBehavior(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"DIALOG SEL:0"}
	m.dialogReader = fakeDialogReader{present: true}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionPermission})

	if err := m.Decide(context.Background(), "s1", "i1", "maybe"); err == nil {
		t.Fatal("expected an unknown behavior to be rejected")
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestDecideDenyDrivesTheDenyKey(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"DIALOG SEL:0", "DIALOG SEL:0", "DIALOG SEL:1", "DIALOG SEL:1", "moved on"}
	m.dialogReader = fakeDialogReader{present: true}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionPermission})

	if err := m.Decide(context.Background(), "s1", "i1", "deny"); err != nil {
		t.Fatalf("Decide: %v", err)
	}
	if len(rt.inputs) != 2 || rt.inputs[0] != "down" || rt.inputs[1] != "enter" {
		t.Fatalf("expected Down then Select, got %q", rt.inputs)
	}
}
