package screen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/codex"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func pane(t *testing.T, name string) string {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "testdata", "panes", name))
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	return string(raw)
}

func activity(state ports.TerminalActivity, tail, cursor string) ports.TerminalProgramEvent {
	return ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: state, Tail: tail, CursorLine: cursor}
}

func TestClassify(t *testing.T) {
	claude := claudecode.New()
	for _, tc := range []struct {
		name    string
		agent   any
		event   ports.TerminalProgramEvent
		reading domain.ScreenReading
		confirm time.Duration
		text    string
	}{
		{"output is working", claude, activity(ports.TerminalActivityActive, "", ""), domain.ScreenWorking, ScreenActiveConfirm, ""},
		{"a Claude Code permission dialog", claude, activity(ports.TerminalActivityIdle, pane(t, "claudecode_permission.txt"), ""), domain.ScreenQuestion, ScreenQuestionConfirm, "Do you want to create fixture-probe.txt?"},
		{"a Claude Code idle composer", claude, activity(ports.TerminalActivityIdle, pane(t, "claudecode_idle.txt"), ""), domain.ScreenSettled, ScreenSettleConfirm, ""},
		{"Claude Code ignores a y/n typed into its composer", claude, activity(ports.TerminalActivityPrompting, pane(t, "claudecode_idle.txt"), "❯ ok? (y/n) "), domain.ScreenSettled, ScreenSettleConfirm, ""},
		{"a Codex approval picker", codex.New(), activity(ports.TerminalActivityIdle, "Allow command?\n› 1. Approve once\n  2. Deny\n", ""), domain.ScreenQuestion, ScreenQuestionConfirm, "Allow command?"},
		{"a Codex idle composer", codex.New(), activity(ports.TerminalActivityIdle, pane(t, "codex_idle.txt"), ""), domain.ScreenSettled, ScreenSettleConfirm, ""},
		{"no adapter: a prompt at the cursor", nil, activity(ports.TerminalActivityPrompting, "Overwrite build.log? (y/n) ", "Overwrite build.log? (y/n) "), domain.ScreenQuestion, ScreenQuestionConfirm, "Overwrite build.log? (y/n)"},
		{"no adapter: quiet is settled only after a minute", nil, activity(ports.TerminalActivityIdle, "compiling", ""), domain.ScreenSettled, ScreenQuietSettle, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := Classify(tc.agent, tc.event)
			if got.Reading != tc.reading || got.Confirm != tc.confirm || !strings.Contains(got.Text, tc.text) {
				t.Fatalf("Classify = %+v, want %s after %v with text %q", got, tc.reading, tc.confirm, tc.text)
			}
		})
	}
	if got := Classify(claude, activity(ports.TerminalActivityIdle, "✽ Thinking… (3s)\n  esc to interrupt\n", "")); got.Reading != "" {
		t.Fatalf("a working Claude Code screen read as %+v", got)
	}
	if got := Classify(claude, ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "x"}); got.Reading != "" {
		t.Fatalf("a title read as %+v", got)
	}
}
