package codex

import (
	"strings"
	"testing"
)

func TestReadTurnSummaryStopsAtTheComposer(t *testing.T) {
	summary := "• Created approved.txt.\n────────\n› Improve documentation in @filename\n  gpt-5.6-luna medium · ~/demo"
	got, ok := (&Plugin{}).ReadTurnSummary(summary)
	if !ok || got != "• Created approved.txt." {
		t.Fatalf("summary = %q, %v", got, ok)
	}
}

func TestReadTurnSummaryReadsTheLastMessageOnARealScreen(t *testing.T) {
	summary := "│ directory: /private/tmp/…/scratchpad/signal-codex │\n╰───────────────────────────────────────────────────╯\n\n" +
		"› Run the shell command `touch approved.txt` and then tell me it is done.\n\n" +
		"• Hook failed\n  └ hook exited with code 127\n\n" +
		"• I’ll run the command in the workspace and verify that the file exists.\n\n" +
		"✔ You approved codex to run touch approved.txt this time\n\n• Ran touch approved.txt\n  └ (no output)\n\n" +
		"• Explored\n  └ List approved.txt\n    + Show details\n\n• Done. approved.txt was created.\n\n" +
		"• Hook failed\n  └ hook exited with code 127\n\n  6:19 PM\n" +
		"                                                    Tip: Press ctrl+g to edit your current draft in an external editor.\n\n" +
		"› Ask Codex to do anything\n\n  GPT-6-Sol medium · /private/tmp/…\n  ? for shortcuts                                                                             ⚠ 5 warnings · f2 to view"
	got, ok := (&Plugin{}).ReadTurnSummary(summary)
	if !ok || got != "• Done. approved.txt was created." {
		t.Fatalf("summary = %q, %v", got, ok)
	}
}

func TestReadTurnSummaryReadsNothingFromTheStartupBanner(t *testing.T) {
	summary := "╭───────────────────────────────────────────────────╮\n│ >_ OpenAI Codex (v0.157.1)                        │\n│                                                   │\n" +
		"│ model:     GPT-6-Sol medium   /model to change    │\n│ directory: /private/tmp/…/scratchpad/signal-codex │\n╰───────────────────────────────────────────────────╯\n\n" +
		"                                                  Tip: Use /init to create an AGENTS.md with project-specific guidance.\n\n" +
		"› Ask Codex to do anything\n\n  GPT-6-Sol medium · /private/tmp/…\n  ? for shortcuts"
	if got, ok := (&Plugin{}).ReadTurnSummary(summary); ok || got != "" {
		t.Fatalf("summary = %q, %v", got, ok)
	}
}

func TestReadTurnSummaryMasksALongBearerTokenWrappedOverFifteenLines(t *testing.T) {
	token, wrapped := longWrappedToken()
	summary := "  └ curl -s -H 'Authorization: Bearer\n    " + strings.Join(wrapped, "\n    ") +
		"\n\n› Ask Codex to do anything\n\n  GPT-6-Sol medium · /private/tmp/…"
	got, ok := (&Plugin{}).ReadTurnSummary(summary)
	if !ok {
		t.Fatalf("no summary read")
	}
	assertNoFragmentOf(t, got, token)
	if !strings.HasSuffix(got, "' https://api.example.com/v1/me") {
		t.Fatalf("summary = %q", got)
	}
}

func TestReadTurnSummaryMasksASecretHardWrappedAcrossLines(t *testing.T) {
	key := "sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz0123"
	summary := "• I wired the key\n  " + key[:12] + "\n  " + key[12:] + " into .env and all tests pass.\n\n› Ask Codex to do anything"
	got, ok := (&Plugin{}).ReadTurnSummary(summary)
	if !ok {
		t.Fatalf("no summary read")
	}
	assertNoFragmentOf(t, got, key)
	if !strings.HasPrefix(got, "• I wired the key\n") || !strings.HasSuffix(got, " into .env and all tests pass.") {
		t.Fatalf("summary = %q", got)
	}
}

func TestReadTurnSummaryMasksAWrappedSecretSplitByAnInvisibleRune(t *testing.T) {
	key := "sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz0123"
	summary := "• I wired the key\n  " + key[:12] + string(rune(0x200b)) + "\n  " + key[12:] + " into .env and all tests pass.\n\n› Ask Codex to do anything"
	got, ok := (&Plugin{}).ReadTurnSummary(summary)
	if !ok {
		t.Fatalf("no summary read")
	}
	assertNoFragmentOf(t, got, key)
	if strings.ContainsRune(got, 0x200b) || !strings.HasSuffix(got, " into .env and all tests pass.") {
		t.Fatalf("summary = %q", got)
	}
}
