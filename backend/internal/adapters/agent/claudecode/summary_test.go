package claudecode

import (
	"strings"
	"testing"
)

func TestReadTurnSummaryStopsAtTheComposerAndDropsTheTurnFooter(t *testing.T) {
	summary := "⏺ Updated greet.py to print a farewell.\n  git diff --stat:\n   greet.py | 7 ++++++-\n✻ Baked for 11s · done 6:13 PM\n────────\n❯\n────────\n  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents"
	got, ok := (&Plugin{}).ReadTurnSummary(summary)
	if !ok || got != "Updated greet.py to print a farewell.\ngit diff --stat:\ngreet.py | 7 ++++++-" {
		t.Fatalf("summary = %q, %v", got, ok)
	}
}

func TestReadTurnSummaryReadsTheLastReplyOnARealScreen(t *testing.T) {
	summary := " ▐▛███▛█   Claude Code v2.1.280\n▝▜██████▀  Opus 5.5 (1M context) · Claude Max\n  ▝▝ ▝▝    /…/scratchpad/signal-claude\n\n" +
		"❯ Run these as two separate Bash tool calls, one after the other: touch first-call.txt and then\n  touch second-call.txt. Do not combine them.\n\n" +
		"⏺ Bash(touch first-call.txt)\n  ⎿  Done\n\n⏺ Bash(touch second-call.txt)\n  ⎿  Done\n\n" +
		"⏺ I ran two separate Bash calls, one after the other: touch first-call.txt, then touch\n  second-call.txt. Both finished without errors.\n\n" +
		"✻ Brewed for 6s · done 6:34 PM\n\n────────\n❯\n────────\n  ⏸ manual mode on · ? for shortcuts · ← 1 agent                                      42896 tokens\n                                                                                ◐ medium · /effort"
	got, ok := (&Plugin{}).ReadTurnSummary(summary)
	if !ok || got != "I ran two separate Bash calls, one after the other: touch first-call.txt, then touch\nsecond-call.txt. Both finished without errors." {
		t.Fatalf("summary = %q, %v", got, ok)
	}
}

func TestReadTurnSummaryNeverReadsTheBannerOrThePromptAsAReply(t *testing.T) {
	summary := " ▐▛███▛█   Claude Code v2.1.280\n▝▜██████▀  Opus 5.5 (1M context) · Claude Max\n\n❯ Say hi\n\n────────\n❯\n────────\n  ⏸ manual mode on"
	if got, ok := (&Plugin{}).ReadTurnSummary(summary); ok || got != "" {
		t.Fatalf("summary = %q, %v", got, ok)
	}
}

func TestReadTurnSummaryKeepsTheStartOfALongReply(t *testing.T) {
	summary := "⏺ one\n  two\n  three\n  four\n  five\n  six\n  seven\n\n────────\n❯\n────────"
	if got, _ := (&Plugin{}).ReadTurnSummary(summary); got != "one\ntwo\nthree\nfour\nfive\nsix" {
		t.Fatalf("summary = %q", got)
	}
}

func TestReadTurnSummaryReadsNothingWhenTheComposerHasNoRuleAbove(t *testing.T) {
	summary := "⏺ Done: 42 tests pass.\n\n❯\n────────\n  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents"
	if got, ok := (&Plugin{}).ReadTurnSummary(summary); ok || got != "" {
		t.Fatalf("summary = %q, %v", got, ok)
	}
}

func TestReadTurnSummaryMasksSecretsHardWrappedAcrossLines(t *testing.T) {
	password := "Xk9mP2qR7vT4wZ1n"
	key := "sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz0123"
	summary := "⏺ I set the database password=\n  " + password + " and wired the key\n  " + key[:12] + "\n  " + key[12:] + " into .env.\n  All tests pass.\n\n" +
		"✻ Baked for 11s · done 6:13 PM\n────────\n❯\n────────\n  ⏵⏵ auto mode on (shift+tab to cycle)"
	got, ok := (&Plugin{}).ReadTurnSummary(summary)
	if !ok {
		t.Fatalf("no summary read")
	}
	assertNoTokenFragment(t, got, password)
	assertNoTokenFragment(t, got, key)
	for _, want := range []string{"I set the database password=", "and wired the key", "into .env.", "All tests pass.", "[redacted]"} {
		if !strings.Contains(got, want) {
			t.Fatalf("summary = %q, missing %q", got, want)
		}
	}
}

func TestReadTurnSummaryMasksALongBearerTokenWrappedOverFifteenLines(t *testing.T) {
	token, wrapped := longWrappedToken()
	summary := "  ⎿  curl -s -H 'Authorization: Bearer\n     " + strings.Join(wrapped, "\n     ") +
		"\n\n✻ Baked for 3s · done 6:13 PM\n────────\n❯\n────────\n  ⏵⏵ auto mode on (shift+tab to cycle)"
	got, ok := (&Plugin{}).ReadTurnSummary(summary)
	if !ok {
		t.Fatalf("no summary read")
	}
	assertNoTokenFragment(t, got, token)
	if !strings.HasSuffix(got, "' https://api.example.com/v1/me") {
		t.Fatalf("summary = %q", got)
	}
}

func TestReadTurnSummaryMasksAWrappedSecretSplitByAnInvisibleRune(t *testing.T) {
	key := "sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz0123"
	summary := "⏺ I wired the key\n  " + key[:12] + string(rune(0x00ad)) + "\n  " + key[12:] + " into .env.\n\n" +
		"✻ Baked for 11s · done 6:13 PM\n────────\n❯\n────────\n  ⏵⏵ auto mode on (shift+tab to cycle)"
	got, ok := (&Plugin{}).ReadTurnSummary(summary)
	if !ok {
		t.Fatalf("no summary read")
	}
	assertNoTokenFragment(t, got, key)
	if strings.ContainsRune(got, 0x00ad) || !strings.Contains(got, "into .env.") {
		t.Fatalf("summary = %q", got)
	}
}
