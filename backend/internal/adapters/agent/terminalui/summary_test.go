package terminalui

import "testing"

func TestTurnSummaryKeepsTheLastLinesWithoutRules(t *testing.T) {
	lines := []string{"one", "", "────", "two", "╭──╮", "three", "four"}
	if got := TurnSummary(lines, 3); got != "two\nthree\nfour" {
		t.Fatalf("summary = %q", got)
	}
}
