package sessionmanager

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

const paneAfterContext = "" +
	"❯ /help \n" +
	"  ⎿  Help dialog dismissed\n" +
	"\n" +
	"❯ /context \n" +
	"  ⎿  Context Usage\n" +
	"     ⛁ ⛁ ⛁ ⛁ ⛶   Sonnet 5\n" +
	"     ⛶ ⛶ ⛶ ⛶ ⛶   87.9k/1m tokens (9%)\n" +
	"     Skills · /skills\n" +
	"     ├ sc:analyze: ~40 tokens\n" +
	"     └ init: ~20 tokens\n" +
	"────────────────────────────────────────────────────────────────────\n" +
	"❯ \n" +
	"────────────────────────────────────────────────────────────────────\n" +
	"  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents\n" +
	"                                                       87856 tokens\n"

const paneAfterCompactTwice = "" +
	"❯ /compact\n" +
	"  ⎿  Compacted\n" +
	"❯ /compact\n" +
	"  ⎿  Not enough messages to compact.\n" +
	"────────────────────────────────────────────────────────────────────\n" +
	"❯ \n" +
	"────────────────────────────────────────────────────────────────────\n"

const paneWhileCompacting = "" +
	"❯ /compact\n" +
	"✻ Compacting conversation… (3s)\n" +
	"────────────────────────────────────────────────────────────────────\n" +
	"❯ \n"

func TestExtractSlashOutputLiftsTheBlockAfterTheLastEcho(t *testing.T) {
	got := extractSlashOutput(paneAfterContext, "/context")
	want := "Context Usage\n" +
		"⛁ ⛁ ⛁ ⛁ ⛶   Sonnet 5\n" +
		"⛶ ⛶ ⛶ ⛶ ⛶   87.9k/1m tokens (9%)\n" +
		"Skills · /skills\n" +
		"├ sc:analyze: ~40 tokens\n" +
		"└ init: ~20 tokens"
	if got != want {
		t.Fatalf("extract:\n got %q\nwant %q", got, want)
	}
}

func TestExtractSlashOutputUsesTheLastEchoAndTrailingWhitespaceIsIgnored(t *testing.T) {
	if got := extractSlashOutput(paneAfterCompactTwice, "/compact"); got != "Not enough messages to compact." {
		t.Fatalf("got %q", got)
	}
	if got := extractSlashOutput(paneAfterCompactTwice, "/compact  "); got != "Not enough messages to compact." {
		t.Fatalf("message with trailing spaces: got %q", got)
	}
}

func TestExtractSlashOutputIsEmptyWhenTheEchoIsAbsent(t *testing.T) {
	if got := extractSlashOutput(paneAfterContext, "/clear"); got != "" {
		t.Fatalf("got %q, want empty", got)
	}
	if got := extractSlashOutput("", "/context"); got != "" {
		t.Fatalf("empty pane: got %q", got)
	}
}

func newSlashOutputTestManager(t *testing.T, panes ...string) (*Manager, *fakeRuntime, *fakeStore) {
	t.Helper()
	st := newFakeStore()
	st.sessions["s1"] = domain.SessionRecord{ID: "s1", Harness: "claude-code",
		Metadata: domain.SessionMetadata{RuntimeHandleID: "s1"}}
	rt := &fakeRuntime{panes: panes}
	m := newSendTestManager(t, fakeAgent{}, &fakeMessenger{}, st)
	m.runtime = rt
	m.slashOutput = slashOutputConfig{pollInterval: time.Millisecond, budget: 20 * time.Millisecond}
	return m, rt, st
}

func TestSlashOutputReturnsOnceTwoReadsAgree(t *testing.T) {
	m, rt, _ := newSlashOutputTestManager(t, paneAfterContext, paneAfterContext)

	got, err := m.SlashOutput(context.Background(), "s1", "/context")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(got, "Context Usage") {
		t.Fatalf("got %q", got)
	}
	if rt.outputCalls != 2 {
		t.Fatalf("pane reads = %d, want 2 (stable after the second)", rt.outputCalls)
	}
}

func TestSlashOutputGivesUpOnAChangingSpinner(t *testing.T) {
	m, _, _ := newSlashOutputTestManager(t,
		strings.ReplaceAll(paneWhileCompacting, "(3s)", "(1s)"),
		strings.ReplaceAll(paneWhileCompacting, "(3s)", "(2s)"),
		paneWhileCompacting,
		strings.ReplaceAll(paneWhileCompacting, "(3s)", "(4s)"),
	)

	got, err := m.SlashOutput(context.Background(), "s1", "/compact")
	if err != nil {
		t.Fatal(err)
	}
	if got != "" {
		t.Fatalf("got %q, want empty (never stable within the budget)", got)
	}
}

func TestSlashOutputIsEmptyForNonBuiltinsAndSessionsWithoutARuntime(t *testing.T) {
	m, rt, st := newSlashOutputTestManager(t, paneAfterContext)

	if got, err := m.SlashOutput(context.Background(), "s1", "/sc:analyze"); err != nil || got != "" {
		t.Fatalf("custom command: got %q, %v", got, err)
	}
	if rt.outputCalls != 0 {
		t.Fatalf("a custom command must not read the pane; reads = %d", rt.outputCalls)
	}
	st.sessions["s1"] = domain.SessionRecord{ID: "s1", Harness: "claude-code"}
	if got, err := m.SlashOutput(context.Background(), "s1", "/context"); err != nil || got != "" {
		t.Fatalf("no runtime handle: got %q, %v", got, err)
	}
	if _, err := m.SlashOutput(context.Background(), "ghost", "/context"); err != ErrNotFound {
		t.Fatalf("unknown session err = %v, want ErrNotFound", err)
	}
}

func TestSlashOutputReadsDeepEnoughForALongBlock(t *testing.T) {
	m, rt, _ := newSlashOutputTestManager(t, paneAfterContext, paneAfterContext)

	if _, err := m.SlashOutput(context.Background(), "s1", "/context"); err != nil {
		t.Fatal(err)
	}
	if rt.outputLines != slashOutputPaneLines || slashOutputPaneLines < 200 {
		t.Fatalf("pane read depth = %d, want slashOutputPaneLines (>= 200): /context alone renders over 100 lines on a real session and the echo scrolls out of a 40-line read", rt.outputLines)
	}
}
