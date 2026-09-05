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
		"clipped menu":      "❯ 1. Yes\n" + strings.Repeat("wrapped description\n", 12) + "2. No\nEsc to cancel · Tab to amend",
	} {
		t.Run(name, func(t *testing.T) {
			if dlg, ok := (&Plugin{}).ReadDialog(pane); ok {
				t.Fatalf("unexpected dialog: %+v", dlg)
			}
		})
	}
}
