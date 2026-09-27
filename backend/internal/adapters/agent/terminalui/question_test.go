package terminalui

import (
	"strings"
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

func TestQuestionTextStartsBelowTheDialogsTopRule(t *testing.T) {
	got := Question([]string{"❯ Ask me something", "────────", "Do you prefer tabs or spaces?"}, ports.Menu{Rows: []string{"1. Tabs", "2. Spaces"}})
	if got.Text != "Do you prefer tabs or spaces?" || got.Identity != "❯ Ask me something ──────── Do you prefer tabs or spaces? 1. Tabs 2. Spaces" {
		t.Fatalf("question = %+v", got)
	}
}

func TestQuestionAtMasksATokenWhoseKeywordIsAboveTheContext(t *testing.T) {
	lines := []string{"curl -H 'Authorization: Bearer", "abcdefghijklmnop1234' https://x.test", "", "", "", "", "Run it?", "1. Yes", "2. No"}
	got := QuestionAt(lines, 7, ports.Menu{Rows: []string{"1. Yes", "2. No"}})
	if got.Text != "[redacted]' https://x.test · Run it?" {
		t.Fatalf("text = %q", got.Text)
	}
	if got.Identity != "abcdefghijklmnop1234' https://x.test Run it? 1. Yes 2. No" {
		t.Fatalf("identity = %q", got.Identity)
	}
}

func TestQuestionAtMasksAWrappedTokenSplitByAnInvisibleRune(t *testing.T) {
	key := "sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz0123"
	lines := []string{"export OPENAI_KEY=" + key[:12] + string(rune(0x2062)), key[12:] + " now", "Run it?", "1. Yes", "2. No"}
	got := QuestionAt(lines, 3, ports.Menu{Rows: []string{"1. Yes", "2. No"}})
	for i := 0; i+8 <= len(key); i++ {
		if strings.Contains(got.Text, key[i:i+8]) {
			t.Fatalf("text leaks %q of the secret: %q", key[i:i+8], got.Text)
		}
	}
	if strings.ContainsRune(got.Text, 0x2062) || !strings.HasSuffix(got.Text, " now · Run it?") {
		t.Fatalf("text = %q", got.Text)
	}
	if got.Identity != strings.Join(strings.Fields(strings.Join(append(lines[:3:3], "1. Yes", "2. No"), " ")), " ") {
		t.Fatalf("identity = %q, want it built from the raw screen", got.Identity)
	}
}
