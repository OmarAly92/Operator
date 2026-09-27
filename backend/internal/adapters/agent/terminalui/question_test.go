package terminalui

import (
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func TestLastNumberedMenuSkipsNumberedTextAboveTheLiveMenu(t *testing.T) {
	lines := []string{"Plan:", "1. Read the file", "2. Edit it", "Allow command?", "› 1. Yes, proceed", "2. No"}
	menu, start, ok := LastNumberedMenu(lines, "›")
	if !ok || start != 4 || len(menu.Rows) != 2 || menu.Selected != 0 {
		t.Fatalf("menu = %+v start=%d ok=%v", menu, start, ok)
	}
}

func TestQuestionIdentityIgnoresHowTheTextWrapped(t *testing.T) {
	menu := ports.Menu{Rows: []string{"1. Yes", "2. No"}, Selected: 0}
	wide := Question([]string{"Bash command", "rm -rf build dist node_modules", "Do you want to proceed?"}, menu)
	narrow := Question([]string{"Bash command", "rm -rf build dist", "node_modules", "Do you want to proceed?"}, menu)
	if wide.Identity != narrow.Identity {
		t.Fatalf("identities differ:\n%q\n%q", wide.Identity, narrow.Identity)
	}
	if wide.Text != "Bash command · rm -rf build dist node_modules · Do you want to proceed?" {
		t.Fatalf("text = %q", wide.Text)
	}
}

func TestQuestionTextSkipsRuleLines(t *testing.T) {
	got := Question([]string{"Which colour do you prefer?", "────────"}, ports.Menu{Rows: []string{"1. Red", "2. Blue"}})
	if got.Text != "Which colour do you prefer?" {
		t.Fatalf("text = %q", got.Text)
	}
}
