package codex

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReadQuestionReadsAnApprovalPicker(t *testing.T) {
	pane := "• Running touch approved.txt\nAllow command `touch approved.txt`?\n› 1. Approve once\n  2. Deny\nPress enter to confirm or esc to go back\n"
	got, ok := (&Plugin{}).ReadQuestion(pane)
	if !ok || got.Text != "• Running touch approved.txt · Allow command `touch approved.txt`?" || got.Identity == "" {
		t.Fatalf("ReadQuestion = %+v, %v", got, ok)
	}
}

func TestReadQuestionIgnoresTheComposerTheModelPickerAndWork(t *testing.T) {
	for _, name := range []string{"codex_idle.txt", "codex_model_picker.txt"} {
		raw, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "testdata", "panes", name))
		if err != nil {
			t.Fatalf("read %s: %v", name, err)
		}
		if got, ok := (&Plugin{}).ReadQuestion(string(raw)); ok {
			t.Fatalf("%s read as a question: %+v", name, got)
		}
	}
	working := "Allow command?\n› 1. Approve once\n  2. Deny\n• Working (3s • esc to interrupt)\n"
	if got, ok := (&Plugin{}).ReadQuestion(working); ok {
		t.Fatalf("a working screen read as a question: %+v", got)
	}
}

func TestReadQuestionMasksABearerTokenWrappedOntoTheNextLine(t *testing.T) {
	token := "ghx9Kd8Qm2Lp4Rt7Vw1Zy3Ab5Cd"
	pane := "Would you like to run the following command?\n\nEnvironment: local\nReason: Fetch the current user\n\n" +
		"$ curl -s -H 'Authorization: Bearer\n" + token + "' https://api.example.com/v1/me\n\n" +
		"› 1. Yes, proceed (y)\n  2. Yes, and don't ask again for this command (p)\n  3. No, and tell Codex what to do differently (esc)\n\nPress enter to confirm or esc to cancel\n"
	got, ok := (&Plugin{}).ReadQuestion(pane)
	if !ok {
		t.Fatalf("no question read")
	}
	for i := 0; i+8 <= len(token); i++ {
		if strings.Contains(got.Text, token[i:i+8]) {
			t.Fatalf("text leaks %q of the secret: %q", token[i:i+8], got.Text)
		}
	}
	if !strings.HasPrefix(got.Text, "Reason: Fetch the current user · $ curl -s -H 'Authorization: Bearer") || !strings.Contains(got.Text, "[redacted]' https://api.example.com/v1/me") {
		t.Fatalf("question text = %q", got.Text)
	}
	if !strings.Contains(got.Identity, token) {
		t.Fatalf("identity changed by masking: %q", got.Identity)
	}
}
