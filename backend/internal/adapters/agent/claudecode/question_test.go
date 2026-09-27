package claudecode

import (
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

const claudeWorkingPane = "✽ Flambéing… (13s · still thinking with high effort)\n" +
	"────────────────────────────────────────\n❯ \n────────────────────────────────────────\n" +
	"  ⏵⏵ auto mode on (shift+tab to cycle) · esc to interrupt · ← for agents\n"

func TestReadQuestionReadsPermissionAndQuestionDialogs(t *testing.T) {
	p := &Plugin{}
	permission, ok := p.ReadQuestion(readPane(t, "claudecode_permission.txt"))
	if !ok || !strings.Contains(permission.Text, "Do you want to create fixture-probe.txt?") || permission.Identity == "" {
		t.Fatalf("permission = %+v, %v", permission, ok)
	}
	question, ok := p.ReadQuestion(readPane(t, "claudecode_question.txt"))
	if !ok || !strings.Contains(question.Text, "Which colour do you prefer?") {
		t.Fatalf("question = %+v, %v", question, ok)
	}
	for _, name := range []string{"claudecode_model_picker.txt", "claudecode_idle.txt"} {
		if got, ok := p.ReadQuestion(readPane(t, name)); ok {
			t.Fatalf("%s read as a question: %+v", name, got)
		}
	}
}

func TestDetectTerminalActivityReadsTheComposer(t *testing.T) {
	p := &Plugin{}
	if state, ok := p.DetectTerminalActivity(readPane(t, "claudecode_idle.txt")); !ok || state != domain.ActivityIdle {
		t.Fatalf("idle pane = (%q, %v), want idle", state, ok)
	}
	if state, ok := p.DetectTerminalActivity(claudeWorkingPane); ok {
		t.Fatalf("working pane = (%q, %v), want no reading", state, ok)
	}
	for _, name := range []string{"claudecode_permission.txt", "claudecode_question.txt"} {
		if state, ok := p.DetectTerminalActivity(readPane(t, name)); ok {
			t.Fatalf("%s = (%q, %v), want no reading while a dialog is open", name, state, ok)
		}
	}
}

func TestReadQuestionNeverReadsThePromptAboveTheDialog(t *testing.T) {
	pane := " ▐▛███▛█   Claude Code v2.1.280\n" +
		"❯ Use the AskUserQuestion tool to ask me whether I prefer tabs or spaces, then reply with only my answer.\n" +
		"────────────────────────────────────────\n ☐ Indentation \nDo you prefer tabs or spaces?\n" +
		"❯ 1. Tabs\n     Indent with tab characters\n  2. Spaces\n     Indent with space characters\n  3. Type something.\n" +
		"────────────────────────────────────────\n  4. Chat about this\nEnter to select · ↑/↓ to navigate · Esc to cancel\n"
	question, ok := (&Plugin{}).ReadQuestion(pane)
	if !ok || question.Text != "☐ Indentation · Do you prefer tabs or spaces?" {
		t.Fatalf("question = %+v, %v", question, ok)
	}
}
