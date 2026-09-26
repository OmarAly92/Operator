package vtwasm

import (
	"strings"
	"testing"
)

const (
	inputReadyMark    = "\x1b]7000;v=1;input-ready=1"
	inputReleasedMark = "\x1b]7000;v=1;input-released=1"
)

func lineEditorStateAfter(t *testing.T, replay string) LineEditorState {
	t.Helper()
	fresh := newTestParser(t, 80, 24)
	feed(t, fresh, replay)
	state, err := fresh.LineEditorState()
	if err != nil {
		t.Fatalf("line editor state: %v", err)
	}
	return state
}

func TestReplayAtAnOwnedPromptHandsTheLineEditorToTheAttachingCore(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, zshCommand("t-1", "echo one", "one\r\n")+zshPrompt("t-2"))
	if state, err := p.LineEditorState(); err != nil || state != LineEditorOwned {
		t.Fatalf("mirror state = %v, %v; want owned", state, err)
	}

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if strings.Count(out, inputReadyMark) != 1 || strings.Contains(out, inputReleasedMark) {
		t.Fatalf("want one input-ready and no input-released in the replay:\n%q", out)
	}
	if strings.Index(out, inputReadyMark) < strings.Index(out, settledEnd) {
		t.Fatalf("input-ready must follow the settled rows:\n%q", out)
	}
	if strings.Contains(out, "typeahead") {
		t.Fatalf("a replay never carries a typeahead report:\n%q", out)
	}
	if got := lineEditorStateAfter(t, out); got != LineEditorOwned {
		t.Fatalf("attaching core state = %v, want owned", got)
	}
	if got := lineEditorStateAfter(t, withoutSettledRows(t, out)); got != LineEditorOwned {
		t.Fatalf("attaching core state after the settled filter = %v, want owned", got)
	}
}

func TestReplayWhileACommandRunsReleasesTheLineEditor(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, zshCommand("t-1", "true", "done\r\n")+
		zshPrompt("t-2")+"sleep 9\r\n"+
		"\x1b]7000;v=1;id=t-2;cmd=sleep 9\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07partial")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if strings.Contains(out, inputReadyMark) {
		t.Fatalf("a running command's replay must not hand over the line editor:\n%q", out)
	}
	if got := lineEditorStateAfter(t, out); got != LineEditorReleased {
		t.Fatalf("attaching core state = %v, want released", got)
	}
}

func TestReplayWithoutShellIntegrationLeavesTheLineEditorUnknown(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "\x1b[1mClaude Code\x1b[0m\r\n> ")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if strings.Contains(out, "input-") {
		t.Fatalf("an agent replay must carry no line editor marks:\n%q", out)
	}
	if got := lineEditorStateAfter(t, out); got != LineEditorUnknown {
		t.Fatalf("attaching core state = %v, want unknown", got)
	}
}
