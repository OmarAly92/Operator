package codex

import (
	"os"
	"path/filepath"
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
