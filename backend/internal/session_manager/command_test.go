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
	multi  string
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
		Multi:         f.multi,
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

// fakeEmptyComposerDetector reports emptiness from the pane text so a test can
// put a human draft on screen.
type fakeEmptyComposerDetector struct{ empty bool }

func (f fakeEmptyComposerDetector) ComposerIsEmpty(string) bool { return f.empty }

// TestCommandCompactRefusesANonEmptyComposer and its /model sibling pin the
// guard on this plan's two NEW unattended writes: typing a slash command into a
// pty that holds a human's unsent draft submits "<their draft>/compact" as one
// garbled prompt.
func TestCommandCompactRefusesANonEmptyComposer(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)
	rt.styledOutput = "❯ half a thought the user has not sent"
	m.emptyComposerDetector = fakeEmptyComposerDetector{empty: false}

	_, err := m.Command(context.Background(), "s1", domain.CommandCompact, "")
	if !errors.Is(err, ErrComposerNotEmpty) {
		t.Fatalf("expected ErrComposerNotEmpty, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestCommandCompactWritesWhenTheComposerIsEmpty(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)
	rt.styledOutput = "❯"
	m.emptyComposerDetector = fakeEmptyComposerDetector{empty: true}

	res, err := m.Command(context.Background(), "s1", domain.CommandCompact, "")
	if err != nil {
		t.Fatalf("Command: %v", err)
	}
	if !res.Wrote || len(rt.inputs) != 1 || rt.inputs[0] != "/compact\r" {
		t.Fatalf("expected one /compact write, got %+v %q", res, rt.inputs)
	}
}

func TestCommandModelRefusesANonEmptyComposer(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)
	rt.styledOutput = "❯ half a thought the user has not sent"
	rt.panes = []string{"MENU:0"}
	m.menuReader = fakeMenuReader{rows: []string{"sonnet", "opus"}}
	m.emptyComposerDetector = fakeEmptyComposerDetector{empty: false}

	_, err := m.Command(context.Background(), "s1", domain.CommandModel, "opus")
	if !errors.Is(err, ErrComposerNotEmpty) {
		t.Fatalf("expected ErrComposerNotEmpty, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

// A harness with no detector stays usable: the capability is opt-in and only
// reports emptiness from positive evidence.
func TestCommandCompactIsNotGatedWhenTheHarnessHasNoDetector(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)

	if _, err := m.Command(context.Background(), "s1", domain.CommandCompact, ""); err != nil {
		t.Fatalf("Command: %v", err)
	}
	if len(rt.inputs) != 1 {
		t.Fatalf("expected the write to proceed, got %q", rt.inputs)
	}
}

func TestModelsReadsThePickerAndBacksOut(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)
	rt.panes = []string{"MENU:3"}
	m.menuReader = fakeMenuReader{rows: []string{
		"1. Default (recommended)  Opus 5 with 1M context · Best for everyday, complex tasks",
		"2. Opus (1M context)      Opus 5 with 1M context · Best for everyday, complex tasks",
		"3. Fable                  Fable 5.1 · Most capable for your hardest and longest-running tasks",
		"4. Sonnet ✔               Sonnet 5 · Efficient for routine tasks",
		"5. Haiku                  Haiku 4.5 · Fastest for quick answers",
	}}

	options, err := m.Models(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Models: %v", err)
	}
	want := []ModelOption{
		{Label: "Default (recommended)", Description: "Opus 5 with 1M context · Best for everyday, complex tasks"},
		{Label: "Opus (1M context)", Description: "Opus 5 with 1M context · Best for everyday, complex tasks"},
		{Label: "Fable", Description: "Fable 5.1 · Most capable for your hardest and longest-running tasks"},
		{Label: "Sonnet", Description: "Sonnet 5 · Efficient for routine tasks", Current: true},
		{Label: "Haiku", Description: "Haiku 4.5 · Fastest for quick answers"},
	}
	if !slices.Equal(options, want) {
		t.Fatalf("Models = %+v, want %+v", options, want)
	}
	if got := rt.inputs; len(got) != 2 || got[0] != "/model\r" || got[1] != "\x1b" {
		t.Fatalf("inputs = %q, want /model then Esc", got)
	}
}

func TestModelsFallsBackToTheCursorRowWhenNothingIsTicked(t *testing.T) {
	options := parseModelOptions(ports.Menu{Rows: []string{"1. sonnet", "2. opus"}, Selected: 1})
	if !options[1].Current || options[0].Current {
		t.Fatalf("options = %+v, want the cursor row marked current", options)
	}
}

func TestModelsRefusedWhileActive(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityActive)
	if _, err := m.Models(context.Background(), "s1"); !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("expected ErrWrongActivityState, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("a refused read must write nothing, got %q", rt.inputs)
	}
}

func TestIndexOfRowPrefersAnExactLabelOverASubstring(t *testing.T) {
	rows := []string{
		"1. Default (recommended)  Opus 5 with 1M context",
		"2. Opus (1M context)      Opus 5 with 1M context",
		"3. Sonnet ✔               Sonnet 5",
	}
	if got := indexOfRow(rows, "Opus (1M context)"); got != 1 {
		t.Fatalf("indexOfRow(Opus (1M context)) = %d, want 1", got)
	}
	if got := indexOfRow(rows, "sonnet"); got != 2 {
		t.Fatalf("indexOfRow(sonnet) = %d, want 2", got)
	}
}
