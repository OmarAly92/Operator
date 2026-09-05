package sessionmanager

import (
	"context"
	"errors"
	"slices"
	"strconv"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeMenuReader struct {
	rows   []string
	noMenu bool
}

func (f fakeMenuReader) ReadMenu(pane string) (ports.Menu, bool) {
	if f.noMenu {
		return ports.Menu{}, false
	}
	idx := strings.Index(pane, "MENU:")
	if idx < 0 {
		return ports.Menu{}, false
	}
	n, err := strconv.Atoi(pane[idx+len("MENU:"):])
	if err != nil {
		return ports.Menu{}, false
	}
	return ports.Menu{Rows: f.rows, Selected: n}, true
}

func (f fakeMenuReader) MenuKeys() ports.MenuKeys {
	return ports.MenuKeys{
		Up:            "\x1b[A",
		Down:          "\x1b[B",
		Select:        "\r",
		Cancel:        "\x1b",
		SessionSelect: "s",
	}
}

func TestCommandStopWritesEscapeWhileActive(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityActive)

	res, err := m.Command(context.Background(), "s1", domain.CommandStop, "")
	if err != nil {
		t.Fatalf("Command: %v", err)
	}
	if !res.Wrote {
		t.Fatal("expected Wrote=true")
	}
	if len(rt.inputs) != 1 || rt.inputs[0] != "\x1b" {
		t.Fatalf("expected exactly one Esc write, got %q", rt.inputs)
	}
}

func TestCommandStopRefusedWhileIdleAndWritesNothing(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)

	_, err := m.Command(context.Background(), "s1", domain.CommandStop, "")
	if !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("expected ErrWrongActivityState, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("a refused command must write nothing, got %q", rt.inputs)
	}
}

func TestCommandCompactTypesTheSlashCommandWhileIdle(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)

	if _, err := m.Command(context.Background(), "s1", domain.CommandCompact, ""); err != nil {
		t.Fatalf("Command: %v", err)
	}
	if len(rt.inputs) != 1 || rt.inputs[0] != "/compact\r" {
		t.Fatalf("expected one /compact write, got %q", rt.inputs)
	}
}

func TestCommandCompactRefusedWhileActive(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityActive)

	_, err := m.Command(context.Background(), "s1", domain.CommandCompact, "")
	if !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("expected ErrWrongActivityState, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("a refused command must write nothing, got %q", rt.inputs)
	}
}

func TestCommandCompactRefusedWhileBlocked(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)

	_, err := m.Command(context.Background(), "s1", domain.CommandCompact, "")
	if !errors.Is(err, ErrAwaitingDecision) {
		t.Fatalf("expected ErrAwaitingDecision, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("a refused command must write nothing, got %q", rt.inputs)
	}
}

func TestCommandRejectsUnknownVerb(t *testing.T) {
	if _, ok := domain.ParseSessionCommand("rm -rf"); ok {
		t.Fatal("expected an unknown verb to be rejected")
	}
	for _, verb := range []string{"stop", "compact", "model"} {
		if _, ok := domain.ParseSessionCommand(verb); !ok {
			t.Fatalf("expected %q to parse", verb)
		}
	}
}

func TestCommandModelDrivesThePickerToTheMatchingRow(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)
	rt.panes = []string{
		"MENU:0", // after /model is typed
		"MENU:0", // NavigateTo's first read
		"MENU:1", // after one Down
	}
	m.menuReader = fakeMenuReader{rows: []string{"sonnet", "opus"}}

	res, err := m.Command(context.Background(), "s1", domain.CommandModel, "opus")
	if err != nil {
		t.Fatalf("Command: %v", err)
	}
	if got, want := res.Models, []string{"sonnet", "opus"}; !slices.Equal(got, want) {
		t.Fatalf("Models = %v, want %v", got, want)
	}
	if rt.inputs[0] != "/model\r" {
		t.Fatalf("expected /model to be typed first, got %q", rt.inputs)
	}
	if last := rt.inputs[len(rt.inputs)-1]; last != "s" {
		t.Fatalf("expected the session-scoped select key %q last, got %q", "s", rt.inputs)
	}
	for _, in := range rt.inputs {
		if in == "\r" && in != rt.inputs[0] {
			t.Fatal("Enter in the model picker sets the user's global default; only /model's own submit may use it")
		}
	}
}

func TestCommandModelBacksOutWhenTheLabelIsNotOffered(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)
	rt.panes = []string{"MENU:0"}
	m.menuReader = fakeMenuReader{rows: []string{"sonnet", "opus"}}

	_, err := m.Command(context.Background(), "s1", domain.CommandModel, "gpt-5")
	if !errors.Is(err, ErrModelNotOffered) {
		t.Fatalf("expected ErrModelNotOffered, got %v", err)
	}
	if last := rt.inputs[len(rt.inputs)-1]; last != "\x1b" {
		t.Fatalf("expected Esc to back out of the picker, got %q", rt.inputs)
	}
	for _, in := range rt.inputs {
		if in == "\r" {
			t.Fatal("a failed model command must never press Enter")
		}
	}
}

func TestCommandModelBacksOutWhenNoMenuAppears(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)
	rt.panes = []string{"idle prompt"}
	m.menuReader = fakeMenuReader{noMenu: true}

	_, err := m.Command(context.Background(), "s1", domain.CommandModel, "opus")
	if !errors.Is(err, ErrDialogAbsent) {
		t.Fatalf("expected ErrDialogAbsent, got %v", err)
	}
	if last := rt.inputs[len(rt.inputs)-1]; last != "\x1b" {
		t.Fatalf("expected Esc to back out, got %q", rt.inputs)
	}
}

func TestCommandModelRefusedWhileActive(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityActive)

	_, err := m.Command(context.Background(), "s1", domain.CommandModel, "opus")
	if !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("expected ErrWrongActivityState, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("a refused command must write nothing, got %q", rt.inputs)
	}
}

func newCommandTestManager(t *testing.T, state domain.ActivityState) (*Manager, *fakeRuntime) {
	t.Helper()
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessClaudeCode,
		Activity: domain.Activity{State: state},
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	return m, rt
}
