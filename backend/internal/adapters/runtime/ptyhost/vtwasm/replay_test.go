package vtwasm

import (
	"context"
	"fmt"
	"regexp"
	"strconv"
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

var sgrRE = regexp.MustCompile("\x1b\\[[0-9;:]*m")

func stripSGR(s string) string {
	return sgrRE.ReplaceAllString(s, "")
}

// Attributes the child set must come back on reopen, or an italic tool name,
// an underlined link and a struck diff line turn plain after every reattach.
func TestReplayKeepsSgrAttributesAndTheUnderlineColour(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "\x1b[3;4:3;9;58;5;196mstyled\x1b[0m plain\r\n")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	for _, want := range []string{"[3;", "4:3", ";9", "58;5;196"} {
		if !strings.Contains(out, want) {
			t.Fatalf("replay lost %q:\n%q", want, out)
		}
	}
	if !strings.Contains(stripSGR(out), "styled plain") {
		t.Fatalf("replay text changed:\n%q", stripSGR(out))
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

// The whole replay, in order: modes, the live frame, READY, then history
// newest→oldest. A client can paint at READY and prepend the rest behind it.
func TestReplayOrderIsModesFrameReadyHistory(t *testing.T) {
	p := newTestParser(t, 20, 4)
	feed(t, p, "\x1b[?1006h")
	for i := 0; i < 40; i++ {
		feed(t, p, fmt.Sprintf("row %02d\r\n", i))
	}

	frame, err := p.Replay(4)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if !strings.HasSuffix(frame, readyMark) {
		t.Fatalf("the frame does not end at READY:\n%q", frame)
	}
	if !strings.HasPrefix(frame, "\x1b]7000;v=1;origin=") {
		t.Fatalf("the origin mark is not the first bytes of the frame:\n%q", frame)
	}
	if strings.Index(frame, "\x1b[?1006h") > strings.Index(frame, "row 3") {
		t.Fatalf("the modes did not come first:\n%q", frame)
	}
	origin := frame[len("\x1b]7000;v=1;origin="):strings.Index(frame, "\x1b\\")]

	var chunks []string
	before := HistoryBefore
	for i := 0; i < 20; i++ {
		chunk, next, ok, err := p.HistoryChunk(before, 4, 8)
		if err != nil {
			t.Fatalf("history chunk: %v", err)
		}
		if !ok {
			break
		}
		if !strings.HasPrefix(chunk, "\x1b]7000;v=1;history=") {
			t.Fatalf("chunk %d is not framed by a history mark:\n%q", i, chunk)
		}
		if !strings.HasSuffix(chunk, "\r\n") {
			t.Fatalf("chunk %d does not terminate its last row:\n%q", i, chunk)
		}
		chunks = append(chunks, chunk)
		before = next
	}
	if len(chunks) == 0 {
		t.Fatal("no history chunk was produced for a 40-row session on a 4-row grid")
	}
	if !strings.Contains(chunks[0], "row 3") {
		t.Fatalf("the first chunk is not the newest history:\n%q", chunks[0])
	}
	if !strings.Contains(chunks[len(chunks)-1], "row 00") {
		t.Fatalf("the last chunk is not the oldest history:\n%q", chunks[len(chunks)-1])
	}
	// The first chunk must abut the frame: its history mark's first stable row
	// plus its count is the origin the frame declared.
	first, count := parseHistoryMark(t, chunks[0])
	if got := strconv.FormatUint(first+uint64(count), 10); got != origin {
		t.Fatalf("the first chunk ends at stable row %s, but the frame starts at %s", got, origin)
	}
}

// A block's closing mark belongs inside its last row. Anything written after a
// chunk's final CR-LF falls through to the live parser, where an exit mark
// closes the live agent's block (BlockGrid::close_block,
// crates/vt-core/src/block_grid.rs:118-127).
func TestAHistoryChunkEndsAtARowTerminator(t *testing.T) {
	p := newTestParser(t, 20, 2)
	feed(t, p, "\x1b]133;A\x07\x1b]7000;v=1;cmd=ls\x1b\\")
	for i := 0; i < 8; i++ {
		feed(t, p, fmt.Sprintf("out %02d\r\n", i))
	}
	feed(t, p, "\x1b]133;D;0\x07")
	for i := 0; i < 20; i++ {
		feed(t, p, fmt.Sprintf("tail %02d\r\n", i))
	}

	before := HistoryBefore
	for {
		chunk, next, ok, err := p.HistoryChunk(before, 2, HistoryChunkRows)
		if err != nil {
			t.Fatalf("history chunk: %v", err)
		}
		if !ok {
			break
		}
		if !strings.HasSuffix(chunk, "\r\n") {
			t.Fatalf("a chunk ends past its last row terminator:\n%q", chunk)
		}
		if strings.Contains(chunk, "\x1b\\\r\n\x1b]7000;v=1;exit=") {
			t.Fatalf("an exit mark was written after a row terminator:\n%q", chunk)
		}
		before = next
	}
}

func parseHistoryMark(t *testing.T, chunk string) (uint64, int) {
	t.Helper()
	const prefix = "\x1b]7000;v=1;history="
	end := strings.Index(chunk, "\x1b\\")
	if !strings.HasPrefix(chunk, prefix) || end < 0 {
		t.Fatalf("not a history chunk: %q", chunk)
	}
	parts := strings.Split(chunk[len(prefix):end], ",")
	if len(parts) != 2 {
		t.Fatalf("malformed history mark: %q", chunk[:end])
	}
	first, err := strconv.ParseUint(parts[0], 10, 64)
	if err != nil {
		t.Fatalf("history mark first row: %v", err)
	}
	count, err := strconv.Atoi(parts[1])
	if err != nil {
		t.Fatalf("history mark count: %v", err)
	}
	return first, count
}

// The common case: a fresh session whose mirror holds less than the frame.
// Nothing about its attach may change.
func TestAFreshSessionProducesNoHistoryChunk(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "just started\r\n")
	_, _, ok, err := p.HistoryChunk(HistoryBefore, 1000, HistoryChunkRows)
	if err != nil {
		t.Fatalf("history chunk: %v", err)
	}
	if ok {
		t.Fatal("a session smaller than one replayed frame produced a history chunk")
	}
}

// Every replayed row is clipped to the grid, history included: a row wider
// than the client's grid wraps into two and shifts every row below it
// (TERMINAL.md §4.7).
func TestHistoryChunkRowsAreClippedToTheGrid(t *testing.T) {
	p := newTestParser(t, 10, 2)
	for i := 0; i < 12; i++ {
		feed(t, p, "ABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n")
	}
	chunk, _, ok, err := p.HistoryChunk(HistoryBefore, 2, HistoryChunkRows)
	if err != nil || !ok {
		t.Fatalf("history chunk: %v ok=%v", err, ok)
	}
	body := chunk[strings.Index(chunk, "\x1b\\")+2:]
	for _, row := range strings.Split(strings.TrimSuffix(body, "\r\n"), "\r\n") {
		plain := stripSGR(row)
		if len([]rune(plain)) > 10 {
			t.Fatalf("a history row is %d columns wide on a 10-column grid: %q", len([]rune(plain)), plain)
		}
	}
}

// Lazy rewrap (vt-core's HOT_ROWS window) leaves every history row below the
// hot region cut at the width it had before the resize. clip_row truncates
// anything wider than the current grid, so a chunk built straight off those
// rows silently loses their tails. The mirror must rewrap its history before
// it serialises it.
func TestHistoryChunksRewrapColdRowsAfterANarrowingResize(t *testing.T) {
	p, err := New(context.Background(), Module, 120, 4, Limits{Rows: 20000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	t.Cleanup(func() { _ = p.Close() })

	const lines = 2600
	var input strings.Builder
	for i := 0; i < lines; i++ {
		fmt.Fprintf(&input, "%s%05d\r\n", strings.Repeat("x", 100), i)
	}
	feed(t, p, input.String())
	if err := p.Resize(40, 4); err != nil {
		t.Fatalf("resize: %v", err)
	}
	if err := p.TouchHistory(); err != nil {
		t.Fatalf("touch history: %v", err)
	}

	frame, err := p.Replay(4)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	abut, err := strconv.ParseUint(frame[len("\x1b]7000;v=1;origin="):strings.Index(frame, "\x1b\\")], 10, 64)
	if err != nil {
		t.Fatalf("frame origin: %v", err)
	}

	var body []string
	before := HistoryBefore
	for i := 0; i < 5000; i++ {
		chunk, next, ok, err := p.HistoryChunk(before, 4, HistoryChunkRows)
		if err != nil {
			t.Fatalf("history chunk: %v", err)
		}
		if !ok {
			break
		}
		first, count := parseHistoryMark(t, chunk)
		if first+uint64(count) != abut {
			t.Fatalf("chunk %d ends at stable row %d, but the rows above it start at %d", i, first+uint64(count), abut)
		}
		abut = first
		body = append([]string{chunk[strings.Index(chunk, "\x1b\\")+2:]}, body...)
		before = next
	}
	plain := strings.ReplaceAll(stripSGR(strings.Join(body, "")), "\r\n", "")
	plain = stripOSC(plain)
	for _, i := range []int{0, 1, 300, 599} {
		want := fmt.Sprintf("%s%05d", strings.Repeat("x", 100), i)
		if !strings.Contains(plain, want) {
			t.Fatalf("history row %d arrived truncated: its tail %q is missing", i, want[95:])
		}
	}
}

var oscRE = regexp.MustCompile("\x1b\\]7000;v=1;[^\x1b]*\x1b\\\\")

func stripOSC(s string) string {
	return oscRE.ReplaceAllString(s, "")
}

func TestReplayBracketsALinkedRunWithOsc8(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "see \x1b]8;;https://x.y/doc\x1b\\here\x1b]8;;\x1b\\ now\r\n")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	want := "\x1b]8;;https://x.y/doc\x1b\\"
	if !strings.Contains(out, want+"here") {
		t.Fatalf("replay lost the hyperlink open before its run:\n%q", out)
	}
	if !strings.Contains(out, "here\x1b[0m\x1b]8;;\x1b\\") && !strings.Contains(out, "here\x1b]8;;\x1b\\") {
		t.Fatalf("replay lost the hyperlink close after its run:\n%q", out)
	}
	if strings.Count(out, "\x1b]8;;") != 2 {
		t.Fatalf("expected exactly one open and one close, got %d in:\n%q", strings.Count(out, "\x1b]8;;"), out)
	}
}

func TestHistoryChunksCarryOsc8(t *testing.T) {
	p := newTestParser(t, 20, 2)
	feed(t, p, "\x1b]8;;https://old\x1b\\older\x1b]8;;\x1b\\\r\nx\r\ny\r\nz\r\n")

	chunk, _, _, err := p.HistoryChunk(HistoryBefore, 2, 512)
	if err != nil {
		t.Fatalf("history chunk: %v", err)
	}
	if !strings.Contains(chunk, "\x1b]8;;https://old\x1b\\older") {
		t.Fatalf("history chunk lost the hyperlink:\n%q", chunk)
	}
}
