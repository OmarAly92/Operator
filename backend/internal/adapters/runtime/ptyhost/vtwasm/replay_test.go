package vtwasm

import (
	"context"
	"strings"
	"testing"
)

func newTestParser(t *testing.T, cols, rows uint32) *Parser {
	t.Helper()
	p, err := New(context.Background(), Module, cols, rows, 1000)
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	t.Cleanup(func() { _ = p.Close() })
	return p
}

func feed(t *testing.T, p *Parser, s string) {
	t.Helper()
	if err := p.Feed([]byte(s)); err != nil {
		t.Fatalf("feed: %v", err)
	}
}

// A pane whose child redraws in place must replay as ONE copy of the final
// screen, never as the log of every frame that produced it.
func TestReplayCollapsesInPlaceRedraws(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "frame one\r\n")
	feed(t, p, "\x1b[1A\rframe two\x1b[K\r\n")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if strings.Contains(out, "frame one") {
		t.Fatalf("replay re-emitted an overwritten frame:\n%q", out)
	}
	if strings.Count(out, "frame two") != 1 {
		t.Fatalf("want exactly one copy of the live frame, got:\n%q", out)
	}
}

// Rows are separated by CR-LF: the receiving terminal has LNM off, so a bare
// LF stair-steps every row of the repaint.
func TestReplayTerminatesRowsWithCRLF(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "alpha\r\nbravo\r\n")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if strings.Contains(strings.ReplaceAll(out, "\r\n", ""), "\n") {
		t.Fatalf("replay contains a bare LF:\n%q", out)
	}
}

// The child's next in-place redraw counts rows up from the cursor, so the
// replay has to leave the cursor where the host's grid has it.
func TestReplayRestoresCursorColumn(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "done\r\n> hi")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if !strings.HasSuffix(out, "\r\x1b[4C") {
		t.Fatalf("want the cursor parked at column 4, got:\n%q", out)
	}
}

// A full-screen child owns the alternate grid, so the replay must put the
// client back into it before painting.
func TestReplayEntersAlternateScreen(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "\x1b[?1049h\x1b[HTUI")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if !strings.HasPrefix(out, "\x1b[?1049h\x1b[H") {
		t.Fatalf("want an alt-screen entry, got:\n%q", out)
	}
	if !strings.Contains(out, "\x1b[1;4H") {
		t.Fatalf("want an absolute cursor address, got:\n%q", out)
	}
}

func TestReplayOfAnUntouchedTerminalIsEmpty(t *testing.T) {
	p := newTestParser(t, 80, 24)

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if out != "" {
		t.Fatalf("want an empty replay, got:\n%q", out)
	}
}

func TestReplayAfterAShrinkFitsTheGridAndKeepsEveryCell(t *testing.T) {
	const wide, narrow = 90, 85
	p := newTestParser(t, wide, 5)
	for i := 0; i < 8; i++ {
		feed(t, p, strings.Repeat("X", wide)+"\r\n")
	}
	if err := p.Resize(narrow, 5); err != nil {
		t.Fatalf("resize: %v", err)
	}

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}

	client := newTestParser(t, narrow, 5)
	feed(t, client, out)
	rendered, err := client.RenderTail(1000)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	lines := strings.Split(strings.TrimRight(rendered, "\n"), "\n")
	for i, line := range lines {
		if width := len([]rune(line)); width > narrow {
			t.Fatalf("row %d is %d columns wide in a %d-column grid: %q", i, width, narrow, line)
		}
	}
	const scrolledOff, onScreen = 4, 4
	if got, want := strings.Count(rendered, "X"), scrolledOff*wide+onScreen*narrow; got != want {
		t.Fatalf("client holds %d cells of content, want %d (scrollback rewrapped whole, the live frame clipped for the app to repaint)", got, want)
	}
	continuations := 0
	for _, line := range lines {
		if line == strings.Repeat("X", wide-narrow) {
			continuations++
		}
	}
	if continuations != scrolledOff {
		t.Fatalf("want %d continuation rows of %d cells, got %d:\n%s", scrolledOff, wide-narrow, continuations, rendered)
	}
}
