package vtwasm

import (
	"strings"
	"testing"
)

const (
	settledBegin = "\x1b]7000;v=1;settled=begin\x1b\\"
	settledEnd   = "\x1b]7000;v=1;settled=end\x1b\\"
)

func zshPrompt(id string) string {
	return "\x1b]7000;v=1;id=" + id + ";cwd=%2Ftmp;branch=\x1b\\" +
		"\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m" + strings.Repeat(" ", 79) + "\r \r" +
		"\x1b]133;A\x07tmp % \x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07"
}

func zshCommand(id, cmd, output string) string {
	return zshPrompt(id) + cmd + "\r\n" +
		"\x1b]7000;v=1;id=" + id + ";cmd=" + cmd + "\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07" +
		output +
		"\x1b]7000;v=1;id=" + id + ";exit=0\x1b\\\x1b]133;D;0\x07"
}

func withoutSettledRows(t *testing.T, out string) string {
	t.Helper()
	begin := strings.Index(out, settledBegin)
	end := strings.Index(out, settledEnd)
	if begin < 0 || end < begin {
		t.Fatalf("want a settled=begin before a settled=end, got:\n%q", out)
	}
	return out[:begin] + out[end+len(settledEnd):]
}

func TestReplayBracketsTheRowsOfFinishedCommands(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, zshCommand("t-1", "cat", "one two\r\none two\r\n")+
		zshCommand("t-2", "printf P8-END", "P8-END\r\n")+
		zshPrompt("t-3"))

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if strings.Count(out, settledBegin) != 1 || strings.Count(out, settledEnd) != 1 {
		t.Fatalf("want exactly one settled pair, got:\n%q", out)
	}
	settled := out[strings.Index(out, settledBegin):strings.Index(out, settledEnd)]
	if got := stripSGR(settled); !strings.Contains(got, "tmp % cat\r\none two\r\none two\r\ntmp % printf P8-END\r\nP8-END\r\n") {
		t.Fatalf("settled rows are not every finished command's rows:\n%q", got)
	}
	tail := stripSGR(stripOSC(withoutSettledRows(t, out)))
	if strings.Contains(tail, "one two") || strings.Contains(tail, "P8-END") {
		t.Fatalf("the rows outside the settled pair still carry finished output:\n%q", tail)
	}
	if !strings.Contains(tail, "tmp %") {
		t.Fatalf("the live prompt must stay outside the settled pair:\n%q", tail)
	}
}

func TestReplayKeepsARunningCommandOutsideTheSettledRows(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, zshCommand("t-1", "true", "done\r\n")+
		zshPrompt("t-2")+"sleep 9\r\n"+
		"\x1b]7000;v=1;id=t-2;cmd=sleep 9\x1b\\\x1b]133;C\x07partial")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	tail := stripSGR(stripOSC(withoutSettledRows(t, out)))
	if strings.Contains(tail, "done") {
		t.Fatalf("the finished command leaked out of the settled rows:\n%q", tail)
	}
	if !strings.Contains(tail, "tmp % sleep 9\r\npartial") {
		t.Fatalf("the running command must replay in full outside the settled rows:\n%q", tail)
	}
}

func TestReplayWithoutAFinishedCommandHasNoSettledRows(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "plain output\r\n"+zshPrompt("t-1"))

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if strings.Contains(out, "settled=") {
		t.Fatalf("no command has finished, so nothing is settled:\n%q", out)
	}
}

func TestReplayKeepsTheCursorRowOutsideTheSettledRows(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, zshCommand("t-1", "true", "done\r\n"))

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if strings.Contains(out, "settled=") {
		end := strings.Index(out, settledEnd) + len(settledEnd)
		if !strings.Contains(stripSGR(out[end:]), "\r") {
			t.Fatalf("the cursor placement must follow the settled rows:\n%q", out)
		}
		rest := strings.TrimSuffix(out[end:], readyMark)
		if rest == "" {
			t.Fatalf("the last row was swallowed by the settled pair:\n%q", out)
		}
	}
}
