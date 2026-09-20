package vtwasm

import (
	"context"
	"fmt"
	"strings"
	"testing"
)

const readyMark = "\x1b]7000;v=1;ready=1\x1b\\"

func newTestParser(t *testing.T, cols, rows uint32) *Parser {
	t.Helper()
	p, err := New(context.Background(), Module, cols, rows, Limits{Rows: 1000, Bytes: 0xffffffff})
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
	if !strings.HasSuffix(strings.TrimSuffix(out, readyMark), "\r\x1b[4C") {
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
	if !strings.HasPrefix(out, "\x1b]7000;v=1;origin=") {
		t.Fatalf("want an origin mark before the alt-screen entry, got:\n%q", out)
	}
	if !strings.Contains(out, "\x1b[?1049h\x1b[H") {
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

func TestReplayNeverStartsInsideASyncBlock(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "frame one\r\n")
	partial := "\x1b[?2026h\x1b[1A\rhalf"
	feed(t, p, partial)

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	painted := out[:strings.Index(out, "\x1b[?2026h")]
	if !strings.Contains(painted, "frame one") {
		t.Fatalf("replay must paint the last complete frame, got:\n%q", out)
	}
	if strings.Contains(painted, "half") {
		t.Fatalf("replay painted bytes from an open sync block:\n%q", out)
	}
	if !strings.HasSuffix(strings.TrimSuffix(out, readyMark), partial) {
		t.Fatalf("replay must end with the buffered sync bytes so the client can complete the frame:\n%q", out)
	}
}

// The replay states the stable row its first row sits at, so the receiving
// core can adopt the host's row space. Without it the two stable spaces never
// meet and every history chunk is dropped as out of order.
func TestReplayOpensWithTheOriginMark(t *testing.T) {
	p := newTestParser(t, 20, 4)
	for i := 0; i < 40; i++ {
		feed(t, p, fmt.Sprintf("row %02d\r\n", i))
	}

	out, err := p.Replay(4)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if !strings.HasPrefix(out, "\x1b]7000;v=1;origin=") {
		t.Fatalf("the replay does not open with an origin mark:\n%q", out)
	}
	origin := out[len("\x1b]7000;v=1;origin="):strings.Index(out, "\x1b\\")]
	if origin != "36" {
		t.Fatalf("origin = %q, want 36 (40 rows of history and screen, a 4-row frame)", origin)
	}
}

// The replay opens with the modes the child had set, so a reattached client
// encodes the mouse and paste the same way the child expects. xterm.js's
// SerializeAddon writes its mode list first for the same reason
// (xterm.js/src/common/addons/SerializeAddon.ts).
func TestReplayEmitsTheModesTheChildSet(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1006h\x1b[?2004h\x1b[?1004h\x1b[?1h")
	feed(t, p, "hello\r\n")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	// mouse_tracking_level is a bitmask: all three tracking modes are set, so
	// all three must be replayed (crates/vt-core/src/parser.rs:341-350).
	for _, mode := range []string{"\x1b[?1000h", "\x1b[?1002h", "\x1b[?1003h", "\x1b[?1006h", "\x1b[?2004h", "\x1b[?1004h", "\x1b[?1h"} {
		if !strings.Contains(out, mode) {
			t.Fatalf("replay is missing %q:\n%q", mode, out)
		}
		if strings.Index(out, mode) > strings.Index(out, "hello") {
			t.Fatalf("mode %q came after the frame:\n%q", mode, out)
		}
	}
}

// The client paints at READY, so READY must be the last byte of the frame —
// everything before it is one complete screen (Ghostty's READY-first snapshot,
// ghostty/src/termio/Termio.zig).
func TestReplayEndsWithTheReadyMark(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "done\r\n> hi")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if !strings.HasSuffix(out, readyMark) {
		t.Fatalf("replay does not end at READY:\n%q", out)
	}
	if !strings.HasSuffix(strings.TrimSuffix(out, readyMark), "\r\x1b[4C") {
		t.Fatalf("the cursor placement must still be the last thing before READY:\n%q", out)
	}
}

// A terminal that has drawn nothing replays nothing — a READY mark alone is a
// mark with no frame, and the host reads an empty replay as "send nothing".
func TestAnEmptyTerminalStillReplaysNothing(t *testing.T) {
	p := newTestParser(t, 80, 24)
	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if out != "" {
		t.Fatalf("an untouched terminal replayed %q", out)
	}
}
