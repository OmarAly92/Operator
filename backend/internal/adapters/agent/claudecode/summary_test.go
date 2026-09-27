package claudecode

import "testing"

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
