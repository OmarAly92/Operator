package codex

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

func TestReadDialogRecognisesTheRealModelPicker(t *testing.T) {
	for _, fixture := range []string{"codex_model_picker.txt", "codex_model_picker_row2.txt"} {
		t.Run(fixture, func(t *testing.T) {
			pane := readPane(t, fixture)
			for _, capture := range []string{pane, "\x1b[32m" + strings.ReplaceAll(pane, "\n", "\x1b[0m\r\n\x1b[32m") + "\x1b[0m"} {
				dlg, ok := (&Plugin{}).ReadDialog(capture)
				if !ok || dlg.Kind != ports.DialogModel || dlg.Title != "Select Model and Effort" || len(dlg.Menu.Rows) != 5 {
					t.Fatalf("ReadDialog = %+v, %v; want model picker with five rows", dlg, ok)
				}
				if !strings.HasSuffix(dlg.Menu.Rows[4], "simpler coding tasks.") {
					t.Fatalf("missing last-row continuation: %q", dlg.Menu.Rows[4])
				}
			}
		})
	}
}

func TestReadDialogRejectsIdleStaleAndMalformedPanes(t *testing.T) {
	model := readPane(t, "codex_model_picker.txt")
	for name, pane := range map[string]string{
		"empty":             "",
		"blank":             "\n\n\n",
		"garbage":           "some unrelated output\nmore output",
		"idle":              readPane(t, "codex_idle.txt"),
		"stale":             model + strings.Repeat("new output\n", 12),
		"new prompt":        model + "\n› new input\n",
		"no footer":         strings.ReplaceAll(model, "Press enter to confirm or esc to go back", ""),
		"no title":          strings.ReplaceAll(model, "Select Model and Effort", ""),
		"missing row":       strings.ReplaceAll(model, "4. gpt-5.5", "6. gpt-5.5"),
		"missing highlight": strings.ReplaceAll(model, "› 3.", "3."),
		"two highlights":    strings.ReplaceAll(model, "4. gpt-5.5", "› 4. gpt-5.5"),
	} {
		t.Run(name, func(t *testing.T) {
			if dlg, ok := (&Plugin{}).ReadDialog(pane); ok {
				t.Fatalf("unexpected dialog: %+v", dlg)
			}
		})
	}
}

func TestReadDialogDoesNotGuessUncapturedPermissions(t *testing.T) {
	for _, pane := range []string{
		readPane(t, "claudecode_permission.txt"),
		"› 1. Approve once\n2. Deny\nPress enter to confirm or esc to go back\n",
	} {
		if dlg, ok := (&Plugin{}).ReadDialog(pane); ok {
			t.Fatalf("unexpected dialog: %+v", dlg)
		}
	}
}

func TestPermissionRowsFailClosedWithoutACapturedPermission(t *testing.T) {
	p := &Plugin{}
	menu := ports.Menu{Rows: []string{"1. Yes", "2. Approve once", "3. No", "4. Deny"}}
	if row, ok := p.AllowRow(menu); ok {
		t.Fatalf("unexpected allow row: %d", row)
	}
	if row, ok := p.DenyRow(menu); ok {
		t.Fatalf("unexpected deny row: %d", row)
	}
}

func TestReadMenuFindsRowsAndTheHighlight(t *testing.T) {
	p := &Plugin{}
	menu, ok := p.ReadMenu(readPane(t, "codex_model_picker.txt"))
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

func TestReadMenuTracksADifferentHighlight(t *testing.T) {
	p := &Plugin{}
	first, _ := p.ReadMenu(readPane(t, "codex_model_picker.txt"))
	second, ok := p.ReadMenu(readPane(t, "codex_model_picker_row2.txt"))
	if !ok {
		t.Fatal("expected the second picker pane to be recognised")
	}
	if first.Selected == second.Selected {
		t.Fatal("the two fixtures must differ in which row is highlighted, or the reader is not reading the highlight")
	}
}

func TestReadMenuRejectsAnIdlePane(t *testing.T) {
	p := &Plugin{}
	if _, ok := p.ReadMenu(readPane(t, "codex_idle.txt")); ok {
		t.Fatal("an idle pane must not be read as a menu")
	}
}

func TestMenuKeysAreNonEmpty(t *testing.T) {
	keys := (&Plugin{}).MenuKeys()
	want := ports.MenuKeys{Up: "\x1b[A", Down: "\x1b[B", Select: "\r", Cancel: "\x1b", SessionSelect: "\r"}
	if keys != want {
		t.Fatalf("MenuKeys = %+v, want %+v", keys, want)
	}
}
