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

func (f fakeDialogReader) ReadMenu(pane string) (ports.Menu, bool) {
	dlg, ok := f.ReadDialog(pane)
	return dlg.Menu, ok
}

func (f fakeDialogReader) MenuKeys() ports.MenuKeys {
	return ports.MenuKeys{Up: "up", Down: "down", Select: "enter"}
}

// fakeQuestionReader is a question dialog whose rows are keyed by the pane's
// name, so a test can make consecutive reads return a DIFFERENT question's
// rows — the multi-question case Answer must resolve group-by-group.
type fakeQuestionReader struct {
	rows   map[string][]string
	kind   ports.DialogKind
	multi  string
	noMenu bool
}

func (f fakeQuestionReader) ReadDialog(pane string) (ports.Dialog, bool) {
	if f.noMenu {
		return ports.Dialog{}, false
	}
	name, rest, ok := strings.Cut(pane, ":")
	if !ok {
		return ports.Dialog{}, false
	}
	selected, err := strconv.Atoi(rest)
	if err != nil {
		return ports.Dialog{}, false
	}
	rows, ok := f.rows[name]
	if !ok {
		return ports.Dialog{}, false
	}
	kind := f.kind
	if kind == "" {
		kind = ports.DialogQuestion
	}
	return ports.Dialog{Kind: kind, Menu: ports.Menu{Rows: rows, Selected: selected}}, true
}

func (f fakeQuestionReader) ReadMenu(pane string) (ports.Menu, bool) {
	dlg, ok := f.ReadDialog(pane)
	return dlg.Menu, ok
}

func (f fakeQuestionReader) AllowRow(ports.Menu) (int, bool) { return 0, false }
func (f fakeQuestionReader) DenyRow(ports.Menu) (int, bool)  { return 0, false }

func (f fakeQuestionReader) MenuKeys() ports.MenuKeys {
	return ports.MenuKeys{Up: "\x1b[A", Down: "\x1b[B", Select: "\r", Cancel: "\x1b", SessionSelect: "s", Multi: f.multi}
}

func questionRows(rows ...string) map[string][]string {
	return map[string][]string{"MENU": rows}
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

func TestAnswerNavigatesToTheVerifiedRowBeforeEnter(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"MENU:0", "MENU:0", "MENU:1", "moved on"}
	m.dialogReader = fakeQuestionReader{rows: questionRows("first", "second")}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", [][]string{{"second"}}); err != nil {
		t.Fatalf("Answer: %v", err)
	}
	last := rt.inputs[len(rt.inputs)-1]
	if last != "\r" {
		t.Fatalf("expected Enter last, got %q", rt.inputs)
	}
	if len(rt.inputs) < 2 {
		t.Fatalf("expected navigation before Enter, got %q", rt.inputs)
	}
}

func TestAnswerWritesNothingWhenTheMenuIsGone(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"idle"}
	m.dialogReader = fakeQuestionReader{noMenu: true}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	err := m.Answer(context.Background(), "s1", "q1", [][]string{{"first"}})
	if !errors.Is(err, ErrDialogAbsent) {
		t.Fatalf("expected ErrDialogAbsent, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestAnswerRejectsALabelThatIsNotOnScreen(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"MENU:0"}
	m.dialogReader = fakeQuestionReader{rows: questionRows("first", "second")}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", [][]string{{"nonexistent option"}}); err == nil {
		t.Fatal("expected a label with no matching row to be rejected")
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestAnswerRejectsAnEmptySelection(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"MENU:0"}
	m.dialogReader = fakeQuestionReader{rows: questionRows("first", "second")}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", nil); err == nil {
		t.Fatal("expected an empty selection to be rejected")
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestAnswerTogglesEveryRowOfAMultiSelectBeforeEnter(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"MENU:0", "MENU:0", "MENU:0", "MENU:1", "MENU:2"}
	m.dialogReader = fakeQuestionReader{rows: questionRows("a", "b", "c"), multi: " "}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", [][]string{{"a", "c"}}); err != nil {
		t.Fatalf("Answer: %v", err)
	}
	spaces := 0
	for _, in := range rt.inputs {
		if in == " " {
			spaces++
		}
	}
	if spaces != 2 {
		t.Fatalf("expected one toggle per selected row, got %d in %q", spaces, rt.inputs)
	}
}

func TestAnswerRefusesATerminatedSession(t *testing.T) {
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:           "s1",
		Harness:      domain.HarnessClaudeCode,
		Activity:     domain.Activity{State: domain.ActivityBlocked},
		Metadata:     domain.SessionMetadata{RuntimeHandleID: "h1"},
		IsTerminated: true,
	}
	rt.panes = []string{"MENU:0"}
	m.dialogReader = fakeQuestionReader{rows: questionRows("first", "second")}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", [][]string{{"first"}}); !errors.Is(err, ErrTerminated) {
		t.Fatalf("expected ErrTerminated, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

// TestAnswerRefusesADialogThatIsNotAQuestion mirrors Decide's kind check: all
// three dialogs render the same numbered menu (finding 6), so without it a
// question answer would drive keys into a permission prompt or a model picker.
func TestAnswerRefusesADialogThatIsNotAQuestion(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"MENU:0"}
	m.dialogReader = fakeQuestionReader{rows: questionRows("first", "second"), kind: ports.DialogModel}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	err := m.Answer(context.Background(), "s1", "q1", [][]string{{"first"}})
	if !errors.Is(err, ErrDialogAbsent) {
		t.Fatalf("expected ErrDialogAbsent for a model picker, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

// TestAnswerResolvesEachGroupAgainstItsOwnMenu pins the multi-question fix:
// submitting question 1 moves the dialog on, so question 2's labels must be
// resolved against the rows now on screen. Resolving both against the first
// read answered question 2 with question 1's rows.
func TestAnswerResolvesEachGroupAgainstItsOwnMenu(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	// Q1 is on screen for the first group's read and its navigation; after its
	// Enter the pane shows Q2, whose rows share no label with Q1.
	rt.panes = []string{"Q1:0", "Q1:0", "Q1:1", "Q2:0", "Q2:0", "Q2:1"}
	m.dialogReader = fakeQuestionReader{rows: map[string][]string{
		"Q1": {"red", "green"},
		"Q2": {"north", "south"},
	}}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", [][]string{{"green"}, {"south"}}); err != nil {
		t.Fatalf("Answer: %v", err)
	}
	enters := 0
	for _, in := range rt.inputs {
		if in == "\r" {
			enters++
		}
	}
	if enters != 2 {
		t.Fatalf("expected one Enter per question group, got %d in %q", enters, rt.inputs)
	}
}

// A label that only exists on the FIRST question must be rejected when it is
// offered for the second: the stale-read bug would have accepted it.
func TestAnswerRejectsASecondGroupLabelThatIsNotOnTheSecondQuestion(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"Q1:0", "Q1:0", "Q1:1", "Q2:0"}
	m.dialogReader = fakeQuestionReader{rows: map[string][]string{
		"Q1": {"red", "green"},
		"Q2": {"north", "south"},
	}}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	err := m.Answer(context.Background(), "s1", "q1", [][]string{{"green"}, {"red"}})
	if !errors.Is(err, ErrAnswerInvalid) {
		t.Fatalf("expected ErrAnswerInvalid for a stale label, got %v", err)
	}
}

func TestDecideRefusesAnExitedAgent(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityExited)
	rt.panes = []string{"DIALOG SEL:0"}
	m.dialogReader = fakeDialogReader{present: true}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionPermission})

	if err := m.Decide(context.Background(), "s1", "i1", "allow"); !errors.Is(err, ErrAgentExited) {
		t.Fatalf("expected ErrAgentExited, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestAnswerRefusesAnExitedAgent(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityExited)
	rt.panes = []string{"MENU:0"}
	m.dialogReader = fakeQuestionReader{rows: questionRows("first", "second")}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", [][]string{{"first"}}); !errors.Is(err, ErrAgentExited) {
		t.Fatalf("expected ErrAgentExited, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestDecideAndAnswerRefuseAnIncompleteHandle(t *testing.T) {
	for _, name := range []string{"decide", "answer"} {
		m, st, rt, _ := newManager()
		st.sessions["s1"] = domain.SessionRecord{
			ID:       "s1",
			Harness:  domain.HarnessClaudeCode,
			Activity: domain.Activity{State: domain.ActivityBlocked},
		}
		m.dialogReader = fakeQuestionReader{rows: questionRows("first")}
		m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionPermission})

		var err error
		if name == "decide" {
			err = m.Decide(context.Background(), "s1", "i1", "allow")
		} else {
			m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionQuestion})
			err = m.Answer(context.Background(), "s1", "i1", [][]string{{"first"}})
		}
		if !errors.Is(err, ErrIncompleteHandle) {
			t.Fatalf("%s: expected ErrIncompleteHandle, got %v", name, err)
		}
		if len(rt.inputs) != 0 {
			t.Fatalf("%s: expected no writes, got %q", name, rt.inputs)
		}
	}
}
