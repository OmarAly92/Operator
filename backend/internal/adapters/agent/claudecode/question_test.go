package claudecode

import (
	"strconv"
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

const wrappedToken = "ghx9Kd8Qm2Lp4Rt7Vw1Zy3Ab5Cd"

func assertNoTokenFragment(t *testing.T, text, token string) {
	t.Helper()
	for i := 0; i+8 <= len(token); i++ {
		if strings.Contains(text, token[i:i+8]) {
			t.Fatalf("text leaks %q of the secret: %q", token[i:i+8], text)
		}
	}
}

func TestReadQuestionMasksABearerTokenWrappedOntoTheNextLine(t *testing.T) {
	dialog := func(command ...string) string {
		return "────────────────────────────────────────\n Bash command\n\n   " + strings.Join(command, "\n   ") +
			"\n   Fetch the current user\n\n Do you want to proceed?\n ❯ 1. Yes\n   2. Yes, and don't ask again for curl commands\n   3. No\n\n Esc to cancel · Tab to amend\n"
	}
	for _, pane := range []string{
		dialog("curl -s -H 'Authorization: Bearer", wrappedToken+"' https://api.example.com/v1/me"),
		dialog("curl -s -H 'Authorization: Bearer "+wrappedToken[:10], wrappedToken[10:]+"' https://api.example.com/v1/me"),
	} {
		question, ok := (&Plugin{}).ReadQuestion(pane)
		if !ok {
			t.Fatalf("no question read from %q", pane)
		}
		assertNoTokenFragment(t, question.Text, wrappedToken)
		if !strings.Contains(question.Text, "https://api.example.com/v1/me · Fetch the current user · Do you want to proceed?") || !strings.Contains(question.Text, "[redacted]") {
			t.Fatalf("question text = %q", question.Text)
		}
		if !strings.Contains(question.Identity, wrappedToken[10:]) {
			t.Fatalf("identity changed by masking: %q", question.Identity)
		}
	}
}

func longWrappedToken() (string, []string) {
	var b strings.Builder
	for i := 0; b.Len() < 900; i++ {
		b.WriteString("eyJ" + strconv.Itoa(i*7919) + "aZ" + strconv.Itoa(i) + "q_")
	}
	token := b.String()[:900]
	text := token + "' https://api.example.com/v1/me"
	var lines []string
	for len(text) > 60 {
		lines = append(lines, text[:60])
		text = text[60:]
	}
	return token, append(lines, text)
}

func TestReadQuestionMasksALongBearerTokenWrappedOverFifteenLines(t *testing.T) {
	token, wrapped := longWrappedToken()
	pane := "────────────────────────────────────────\n Bash command\n\n   curl -s -H 'Authorization: Bearer\n   " + strings.Join(wrapped, "\n   ") +
		"\n\n Do you want to proceed?\n ❯ 1. Yes\n   2. Yes, and don't ask again for curl commands\n   3. No\n\n Esc to cancel · Tab to amend\n"
	question, ok := (&Plugin{}).ReadQuestion(pane)
	if !ok {
		t.Fatalf("no question read")
	}
	assertNoTokenFragment(t, question.Text, token)
	if !strings.HasSuffix(question.Text, "' https://api.example.com/v1/me · Do you want to proceed?") || !strings.Contains(question.Identity, token[880:]) {
		t.Fatalf("question = %+v", question)
	}
}
