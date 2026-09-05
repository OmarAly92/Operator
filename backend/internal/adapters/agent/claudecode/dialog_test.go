package claudecode

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func readPane(t *testing.T, name string) string {
	t.Helper()
	pane, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "testdata", "panes", name))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	return string(pane)
}

func readStyledPane(t *testing.T, name string) string {
	t.Helper()
	return readPane(t, name)
}

func TestReadDialogRecognisesTheRealPermissionDialog(t *testing.T) {
	p := &Plugin{}
	dlg, ok := p.ReadDialog(readPane(t, "claudecode_permission.txt"))
	if !ok || dlg.Kind != ports.DialogPermission {
		t.Fatalf("ReadDialog = %+v, %v; want permission", dlg, ok)
	}
	if dlg.Title != "Do you want to create fixture-probe.txt?" || len(dlg.Menu.Rows) != 3 {
		t.Fatalf("unexpected dialog: %+v", dlg)
	}
	if dlg.Menu.Rows[1] != "2. Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session (shift+tab)" {
		t.Fatalf("wrapped row = %q", dlg.Menu.Rows[1])
	}
	if row, ok := p.AllowRow(dlg.Menu); !ok || row != 0 {
		t.Fatalf("AllowRow = %d, %v; want 0, true", row, ok)
	}
	if row, ok := p.DenyRow(dlg.Menu); !ok || row != 2 {
		t.Fatalf("DenyRow = %d, %v; want 2, true", row, ok)
	}
}

func TestPermissionRowsMatchOnlyUnambiguousPlainAnswers(t *testing.T) {
	p := &Plugin{}
	for _, tt := range []struct {
		name  string
		rows  []string
		allow int
		deny  int
	}{
		{"reordered", []string{"1. No", "2. Yes"}, 1, 0},
		{"compound", []string{"2. Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session (shift+tab)", "3. No"}, -1, 1},
		{"unknown", []string{"1. Yesterday", "2. Nobody"}, -1, -1},
		{"ambiguous", []string{"1. Yes", "2. Yes", "3. No", "4. No"}, -1, -1},
		{"empty", nil, -1, -1},
	} {
		t.Run(tt.name, func(t *testing.T) {
			menu := ports.Menu{Rows: tt.rows}
			if row, ok := p.AllowRow(menu); ok != (tt.allow >= 0) || ok && row != tt.allow {
				t.Fatalf("AllowRow = %d, %v; want %d", row, ok, tt.allow)
			}
			if row, ok := p.DenyRow(menu); ok != (tt.deny >= 0) || ok && row != tt.deny {
				t.Fatalf("DenyRow = %d, %v; want %d", row, ok, tt.deny)
			}
		})
	}
}

func TestReadDialogTellsTheThreeKindsApartByTheirFooter(t *testing.T) {
	for _, tt := range []struct {
		fixture string
		kind    ports.DialogKind
		rows    int
	}{
		{"claudecode_permission.txt", ports.DialogPermission, 3},
		{"claudecode_model_picker.txt", ports.DialogModel, 5},
		{"claudecode_model_picker_row2.txt", ports.DialogModel, 5},
		{"claudecode_question.txt", ports.DialogQuestion, 5},
	} {
		t.Run(tt.fixture, func(t *testing.T) {
			pane := readPane(t, tt.fixture)
			for _, capture := range []string{pane, "\x1b[32m" + strings.ReplaceAll(pane, "\n", "\x1b[0m\r\n\x1b[32m") + "\x1b[0m"} {
				dlg, ok := (&Plugin{}).ReadDialog(capture)
				if !ok || dlg.Kind != tt.kind || len(dlg.Menu.Rows) != tt.rows {
					t.Fatalf("ReadDialog = %+v, %v; want %s with %d rows", dlg, ok, tt.kind, tt.rows)
				}
			}
		})
	}
}

func TestReadDialogRejectsIdleStaleAndMalformedPanes(t *testing.T) {
	permission := readPane(t, "claudecode_permission.txt")
	for name, pane := range map[string]string{
		"empty":             "",
		"blank":             "\n\n\n",
		"garbage":           "some unrelated output\nmore output",
		"idle":              readPane(t, "claudecode_idle.txt"),
		"stale":             permission + strings.Repeat("new output\n", 12),
		"new prompt":        permission + "\n❯\u00a0new input\n",
		"no footer":         strings.ReplaceAll(permission, "Esc to cancel · Tab to amend", ""),
		"no menu":           "Do you want to create a file?\nEsc to cancel · Tab to amend",
		"missing row":       strings.ReplaceAll(permission, "3. No", "4. No"),
		"missing first row": strings.ReplaceAll(permission, "❯ 1. Yes", ""),
		"missing highlight": strings.ReplaceAll(permission, "❯ 1. Yes", "1. Yes"),
		"two highlights":    strings.ReplaceAll(permission, "3. No", "❯ 3. No"),
		"clipped menu":      "❯ 1. Yes\n" + strings.Repeat("wrapped description\n", 40) + "2. No\nEsc to cancel · Tab to amend",
	} {
		t.Run(name, func(t *testing.T) {
			if dlg, ok := (&Plugin{}).ReadDialog(pane); ok {
				t.Fatalf("unexpected dialog: %+v", dlg)
			}
		})
	}
}

func TestReadDialogSurvivesAnExtraMenuRow(t *testing.T) {
	pane := readPane(t, "claudecode_model_picker.txt")
	extra := strings.Replace(pane, "    5. Haiku                  Haiku 4.5 · Fastest for quick answers",
		"    5. Zephyr                 Zephyr · Another model.\n    6. Haiku                  Haiku 4.5 · Fastest for quick answers", 1)
	if _, ok := (&Plugin{}).ReadDialog(extra); !ok {
		t.Error("one extra menu row breaks model reading entirely")
	}
}

func TestReadMenuFindsRowsAndTheHighlight(t *testing.T) {
	p := &Plugin{}
	menu, ok := p.ReadMenu(readPane(t, "claudecode_model_picker.txt"))
	if !ok {
		t.Fatal("expected the model picker to be recognised")
	}
	if len(menu.Rows) < 2 {
		t.Fatalf("expected several rows, got %v", menu.Rows)
	}
	if menu.Selected < 0 || menu.Selected >= len(menu.Rows) {
		t.Fatalf("Selected = %d, out of range for %d rows", menu.Selected, len(menu.Rows))
	}
}

func TestReadMenuReadsQuestionOptions(t *testing.T) {
	menu, ok := (&Plugin{}).ReadMenu(readPane(t, "claudecode_question.txt"))
	if !ok || len(menu.Rows) != 5 {
		t.Fatalf("ReadMenu = %+v, %v; want five question options", menu, ok)
	}
}

func TestReadMenuTracksADifferentHighlight(t *testing.T) {
	p := &Plugin{}
	first, _ := p.ReadMenu(readPane(t, "claudecode_model_picker.txt"))
	second, ok := p.ReadMenu(readPane(t, "claudecode_model_picker_row2.txt"))
	if !ok {
		t.Fatal("expected the second picker pane to be recognised")
	}
	if first.Selected == second.Selected {
		t.Fatal("the two fixtures must differ in which row is highlighted, or the reader is not reading the highlight")
	}
}

func TestReadMenuRejectsAnIdlePane(t *testing.T) {
	p := &Plugin{}
	if _, ok := p.ReadMenu(readPane(t, "claudecode_idle.txt")); ok {
		t.Fatal("an idle pane must not be read as a menu")
	}
}

func TestReadComposerDraftReturnsAHumanAuthoredDraft(t *testing.T) {
	p := &Plugin{}
	draft, ok := p.ReadComposerDraft(readStyledPane(t, "claudecode_idle_styled.txt"))
	if !ok {
		t.Fatal("expected the composer draft to be read")
	}
	if draft != "run the sample task" {
		t.Fatalf("draft = %q", draft)
	}
}

func TestReadComposerDraftRejectsDimPlaceholderText(t *testing.T) {
	// A placeholder mirrored into the phone's composer would have the user
	// send text they never wrote.
	p := &Plugin{}
	if draft, ok := p.ReadComposerDraft(readStyledPane(t, "claudecode_placeholder_styled.txt")); ok {
		t.Fatalf("placeholder text must not read as a draft, got %q", draft)
	}
}

func TestReadComposerDraftFailsClosedOnUnstyledInput(t *testing.T) {
	// Plain output carries no dim/normal distinction. Answering from it would
	// be a guess.
	p := &Plugin{}
	if _, ok := p.ReadComposerDraft(readPane(t, "claudecode_idle.txt")); ok {
		t.Fatal("an unstyled pane must fail closed, not guess")
	}
}

func TestMenuKeysAreNonEmpty(t *testing.T) {
	keys := (&Plugin{}).MenuKeys()
	want := ports.MenuKeys{Up: "\x1b[A", Down: "\x1b[B", Select: "\r", Cancel: "\x1b", Multi: " ", SessionSelect: "s"}
	if keys != want {
		t.Fatalf("MenuKeys = %+v, want %+v", keys, want)
	}
}
