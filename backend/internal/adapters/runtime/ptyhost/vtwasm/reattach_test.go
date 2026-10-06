package vtwasm

import (
	"strings"
	"testing"
)

const (
	promptStartMark = "\x1b]133;A\x1b\\"
	outputStartMark = "\x1b]133;C\x1b\\"
)

func runningCommand(id, cmd string) string {
	return zshPrompt(id) + cmd + "\r\n" +
		"\x1b]7000;v=1;id=" + id + ";cmd=" + cmd + "\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07"
}

func TestReplayReopensTheCommandRunningAtAttach(t *testing.T) {
	p := newTestParser(t, 80, 24)
	if err := p.FeedAt([]byte(zshCommand("t-1", "true", "done\r\n")), 1000); err != nil {
		t.Fatalf("feed: %v", err)
	}
	if err := p.FeedAt([]byte(runningCommand("t-2", "sleep 9")+"partial\r\n"), 5000); err != nil {
		t.Fatalf("feed: %v", err)
	}

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	tail := withoutSettledRows(t, out)
	prompt := strings.Index(tail, promptStartMark)
	command := strings.Index(tail, "tmp % sleep 9")
	meta := strings.Index(tail, "\x1b]7000;v=1;cmd=sleep 9;start_ms=5000\x1b\\"+outputStartMark)
	output := strings.Index(tail, "partial")
	if prompt < 0 || command < prompt || meta < command || output < meta {
		t.Fatalf("want the prompt mark, the command row, cmd+start_ms+C, then the output:\n%q", tail)
	}
	if strings.Contains(tail[:prompt], "done") {
		t.Fatalf("the finished command leaked out of the settled rows:\n%q", tail)
	}
}

func TestReplayOfAFullScreenProgramCarriesItsCommandUnderTheAlternateScreen(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, zshCommand("t-1", "true", "done\r\n")+
		runningCommand("t-2", "vim big.txt")+
		"\x1b[?1049h\x1b[H\x1b[2Jfile text")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	enter := strings.Index(out, "\x1b[?1049h")
	command := strings.Index(out, "tmp % vim big.txt")
	start := strings.Index(out, outputStartMark)
	if enter < 0 || command < 0 || start < command || enter < start {
		t.Fatalf("want the primary rows and the command's marks before the alternate screen:\n%q", out)
	}
	if !strings.Contains(out[enter:], "file text") {
		t.Fatalf("the alternate screen is missing:\n%q", out)
	}
	if strings.Count(out, settledBegin) != 1 || strings.Index(out, settledEnd) > command {
		t.Fatalf("the finished command must stay inside the settled rows:\n%q", out)
	}
}

func TestReplayAfterClearKeepsTheFinishedCommandsAndTheLineEditor(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, zshCommand("t-1", "echo one", "one\r\n")+
		zshCommand("t-2", "clear", "\x1b[3J\x1b[H\x1b[2J")+
		zshPrompt("t-3"))

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if !strings.HasSuffix(out, readyMark) {
		t.Fatalf("a replay after clear must still end with ready:\n%q", out)
	}
	begin, end := strings.Index(out, settledBegin), strings.Index(out, settledEnd)
	if begin < 0 || end < begin {
		t.Fatalf("want a settled pair:\n%q", out)
	}
	settled := stripSGR(out[begin:end])
	if !strings.Contains(settled, "one\r\n") || !strings.Contains(settled, "tmp % clear\r\n") {
		t.Fatalf("the rows before clear must replay as settled rows:\n%q", out)
	}
	if strings.Count(out, inputReadyMark) != 1 {
		t.Fatalf("want the line editor handed back once:\n%q", out)
	}
}
