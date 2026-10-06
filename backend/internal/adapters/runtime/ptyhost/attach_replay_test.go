package ptyhost

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

const readyMark = "\x1b]7000;v=1;ready=1\x1b\\"

// startServeParsed is startServe with a live vt parser, which is what a real
// session always has. The parser's grid — not the output ring — is what a
// connecting client is replayed from.
func startServeParsed(t *testing.T, pid, cols, rows int) *serveFixture {
	t.Helper()
	return startServeWithLimits(t, pid, cols, rows, vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
}

func startServeWithLimits(t *testing.T, pid, cols, rows int, limits vtwasm.Limits) *serveFixture {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	parser, err := vtwasm.New(context.Background(), vtwasm.Module, uint32(cols), uint32(rows), limits)
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	t.Cleanup(func() { _ = parser.Close() })

	pty := newFakePTY(pid)
	ring := NewRing()
	ctx, cancel := context.WithCancel(context.Background())
	h := newHost(ctx, ServeConfig{
		SessionID:   fmt.Sprintf("test-%d", pid),
		Listener:    ln,
		PTY:         pty,
		Ring:        ring,
		Parser:      parser,
		InitialCols: cols,
		InitialRows: rows,
	})
	done := make(chan error, 1)
	go func() {
		done <- h.run(ctx)
	}()
	return &serveFixture{pty: pty, ring: ring, ln: ln, addr: ln.Addr().String(), cancel: cancel, done: done, host: h}
}

// writeOutput pushes PTY output and waits for the host to have parsed it.
func writeOutput(t *testing.T, f *serveFixture, s string) {
	t.Helper()
	if _, err := f.pty.WriteOutput([]byte(s)); err != nil {
		t.Fatalf("write pty output: %v", err)
	}
}

// readReplay returns the payload of the first MsgTerminalData frame.
func readReplay(t *testing.T, c *testClient) string {
	t.Helper()
	for {
		typ, payload := c.readFrame(t)
		if typ == MsgTerminalData {
			return string(payload)
		}
	}
}

// A client that attaches at a DIFFERENT grid than the one the session last ran
// at must be replayed the current screen once. Replaying the raw output ring
// re-emitted every in-place redraw the child had ever done; at the new
// geometry those redraws no longer overwrote each other, so each stale frame
// survived on screen — the duplicated-output bug when reopening an old session.
func TestAttachReplayDoesNotDuplicateRedrawnFrames(t *testing.T) {
	f := startServeParsed(t, 700, 40, 10)
	defer f.cancel()

	// A child that draws a banner, then redraws its footer in place — the
	// shape of every TUI agent UI.
	writeOutput(t, f, "banner\r\nfooter one")
	writeOutput(t, f, "\r\x1b[Kfooter two")
	waitForParsedOutput(t, f, "footer two")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 100, 30)

	replay := readReplay(t, c)
	if strings.Contains(replay, "footer one") {
		t.Fatalf("replay re-emitted an overwritten frame:\n%q", replay)
	}
	if n := strings.Count(replay, "footer two"); n != 1 {
		t.Fatalf("want one copy of the live footer, got %d:\n%q", n, replay)
	}
	if n := strings.Count(replay, "banner"); n != 1 {
		t.Fatalf("want one copy of the banner, got %d:\n%q", n, replay)
	}
}

// The replay is only faithful at the geometry it was rendered for, so the
// client's opening grid must reach the PTY (and the parser) before the
// snapshot is taken — never after, which is what left the client holding a
// stale-geometry paint plus the child's SIGWINCH repaint of the same screen.
func TestAttachAppliesOpeningGridBeforeReplaying(t *testing.T) {
	f := startServeParsed(t, 701, 40, 10)
	defer f.cancel()

	writeOutput(t, f, "hello\r\n")
	waitForParsedOutput(t, f, "hello")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 100, 30)

	_ = readReplay(t, c)
	resizes := f.pty.resizeSnapshot()
	if len(resizes) == 0 {
		t.Fatal("the opening grid never reached the PTY")
	}
	if got := resizes[0]; got.Cols != 100 || got.Rows != 30 {
		t.Fatalf("first PTY resize = %dx%d, want 100x30", got.Cols, got.Rows)
	}
}

// A client that never states a grid still has to be replayed; it just gets the
// host's current one.
func TestAttachReplaysAClientThatNeverResizes(t *testing.T) {
	f := startServeParsed(t, 702, 40, 10)
	defer f.cancel()

	writeOutput(t, f, "quiet client\r\n")
	waitForParsedOutput(t, f, "quiet client")

	c := newTestClient(t, f.addr)
	defer c.close()

	if replay := readReplay(t, c); !strings.Contains(replay, "quiet client") {
		t.Fatalf("replay = %q, want the current screen", replay)
	}
}

func sendResize(t *testing.T, c *testClient, cols, rows int) {
	t.Helper()
	payload, err := json.Marshal(ResizePayload{Cols: cols, Rows: rows})
	if err != nil {
		t.Fatalf("marshal resize: %v", err)
	}
	if err := c.send(MsgResize, payload); err != nil {
		t.Fatalf("send resize: %v", err)
	}
}

func sendResizeWithHistory(t *testing.T, c *testClient, cols, rows int, history bool) {
	t.Helper()
	payload, err := json.Marshal(ResizePayload{Cols: cols, Rows: rows, History: history})
	if err != nil {
		t.Fatalf("marshal resize: %v", err)
	}
	if err := c.send(MsgResize, payload); err != nil {
		t.Fatalf("send resize: %v", err)
	}
}

// A reattaching client must be able to paint as soon as it has the frame.
// The handshake therefore returns at READY, and the history that follows
// arrives on the live stream behind it.
func TestClientPaintsAtReadyBeforeHistory(t *testing.T) {
	f := startServeParsed(t, 710, 20, 4)
	defer f.cancel()

	const rowCount = 1010
	for i := 0; i < rowCount; i++ {
		writeOutput(t, f, fmt.Sprintf("row %04d\r\n", i))
	}
	lastRow := fmt.Sprintf("row %04d", rowCount-1)
	firstRow := fmt.Sprintf("row %04d", 0)
	waitForParsedOutput(t, f, lastRow)

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResizeWithHistory(t, c, 20, 4, true)

	first := readReplay(t, c)
	if !strings.HasPrefix(first, "\x1b]7000;v=1;origin=") {
		t.Fatalf("the first terminal frame does not open with the origin mark:\n%q", first)
	}
	if !strings.HasSuffix(first, readyMark) {
		t.Fatalf("the first terminal frame is not a READY-terminated replay:\n%q", first)
	}
	if strings.Contains(first, "history=") {
		t.Fatalf("history was packed into the frame the client paints:\n%q", first)
	}

	stream := first
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) && !strings.Contains(stream, firstRow) {
		typ, payload := c.readFrame(t)
		if typ == MsgTerminalData {
			stream += string(payload)
		}
	}
	if !strings.Contains(stream, "\x1b]7000;v=1;history=") {
		t.Fatalf("no history chunk followed the replay:\n%q", stream)
	}

	// End to end: the whole stream, fed to a fresh core, must reconstruct the
	// session with the first row at the top. "A chunk arrived" is not the
	// property under test — "the chunks were prepended" is.
	mirror, err := vtwasm.New(context.Background(), vtwasm.Module, 20, 4, vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new mirror: %v", err)
	}
	defer mirror.Close()
	if err := mirror.Feed([]byte(stream)); err != nil {
		t.Fatalf("feed the replay stream: %v", err)
	}
	rendered, err := mirror.RenderTail(200_000)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	rows := strings.Split(strings.TrimRight(rendered, "\n"), "\n")
	if len(rows) == 0 || !strings.Contains(rows[0], firstRow) {
		t.Fatalf("the replayed history was not prepended; first row = %q", rows[0])
	}
	if !strings.Contains(rows[len(rows)-1], lastRow) {
		t.Fatalf("the live frame did not stay at the bottom; last row = %q", rows[len(rows)-1])
	}
}

// A client that does not ask for history gets exactly today's attach. The
// mobile build renders with an xterm fork that would print the rows.
func TestAClientWithoutHistoryOptInGetsNoChunks(t *testing.T) {
	f := startServeParsed(t, 712, 20, 4)
	defer f.cancel()

	for i := 0; i < 60; i++ {
		writeOutput(t, f, fmt.Sprintf("row %02d\r\n", i))
	}
	waitForParsedOutput(t, f, "row 59")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 20, 4)

	replay := readReplay(t, c)
	if strings.Contains(replay, "history=") {
		t.Fatalf("a client that did not opt in was sent history:\n%q", replay)
	}
	writeOutput(t, f, "live after attach\r\n")
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		typ, payload := c.readFrame(t)
		if typ != MsgTerminalData {
			continue
		}
		if strings.Contains(string(payload), "history=") {
			t.Fatalf("a history chunk reached a client that did not opt in:\n%q", payload)
		}
		if strings.Contains(string(payload), "live after attach") {
			return
		}
	}
	t.Fatal("the live byte that proves nothing else was queued first never arrived")
}

// A fresh session whose mirror holds less than one replayed frame must attach
// exactly as it does today: one frame, no history, nothing else.
func TestAFreshSessionAttachIsUnchanged(t *testing.T) {
	f := startServeParsed(t, 711, 80, 24)
	defer f.cancel()

	writeOutput(t, f, "hello\r\n")
	waitForParsedOutput(t, f, "hello")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 80, 24)

	replay := readReplay(t, c)
	if !strings.Contains(replay, "hello") {
		t.Fatalf("replay = %q, want the current screen", replay)
	}
	if strings.Contains(replay, "history=") {
		t.Fatalf("a fresh session sent a history chunk:\n%q", replay)
	}
}

func waitForParsedOutput(t *testing.T, f *serveFixture, want string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if strings.Contains(string(f.ring.Snapshot()), want) {
			return
		}
		time.Sleep(2 * time.Millisecond)
	}
	// The ring only stores completed lines, so a partial tail never lands;
	// give the pump a beat instead.
	time.Sleep(50 * time.Millisecond)
}

// The wrap-dependent case, which is the one users hit: the child's redraw
// counts rows that only exist because its output WRAPPED at the session's
// width. Replayed as raw bytes into a wider grid the line no longer wraps, the
// cursor-up overshoots, and the frame it meant to overwrite survives above the
// new one — two copies of the same UI, the top one mangled.
func TestAttachReplaySurvivesAWidthChangeUnderWrappedRedraws(t *testing.T) {
	f := startServeParsed(t, 703, 20, 10)
	defer f.cancel()

	// 30 columns of text on a 20-column grid: one logical line, two rows.
	writeOutput(t, f, "STALE_AAAAAAAAAAAAAAAAAAAAAAAA\r\n")
	// The child redraws that line in place, as a TUI footer does.
	writeOutput(t, f, "\x1b[2A\rFRESH_BBBBBBBBBBBBBBBBBBBBBBBB\x1b[J\r\n")
	waitForParsedOutput(t, f, "FRESH")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 100, 30)

	replay := readReplay(t, c)
	if strings.Contains(replay, "STALE") {
		t.Fatalf("the redrawn-over frame survived the width change:\n%q", replay)
	}
	if n := strings.Count(replay, "FRESH"); n != 1 {
		t.Fatalf("want one copy of the live frame, got %d:\n%q", n, replay)
	}
}

// The origin the client adopts and the bound the first history chunk is cut
// at must come from the SAME render. Letting the mirror re-derive the bound
// from a later snapshot puts every row the child completed in between between
// them, and the receiver rejects a chunk that does not abut exactly -- every
// chunk after it too, silently.
func TestHistoryStartsAtTheOriginTheFrameDeclared(t *testing.T) {
	f := startServeParsed(t, 716, 20, 4)
	defer f.cancel()

	for i := 0; i < 1010; i++ {
		writeOutput(t, f, fmt.Sprintf("row %04d\r\n", i))
	}
	waitForParsedOutput(t, f, "row 1009")

	f.host.mu.Lock()
	frame, origin := f.host.replayFrameLocked()
	f.host.mu.Unlock()
	if frame == nil || origin == vtwasm.HistoryBefore {
		t.Fatalf("no replay origin was rendered")
	}

	// The race: the child completes more rows between the frame and the first
	// chunk.
	for i := 1010; i < 1030; i++ {
		writeOutput(t, f, fmt.Sprintf("row %04d\r\n", i))
	}
	waitForParsedOutput(t, f, "row 1029")

	cs := newClientState()
	done := make(chan struct{})
	go func() {
		f.host.streamHistory(cs, origin)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("streamHistory never finished")
	}

	cs.outMu.Lock()
	frames := append([][]byte(nil), cs.out...)
	cs.outMu.Unlock()
	if len(frames) == 0 {
		t.Fatal("no history chunk was queued")
	}
	first, count := parseHostHistoryMark(t, string(frames[0][frameHeaderBytes:]))
	if first+uint64(count) != origin {
		t.Fatalf("the first chunk ends at stable row %d, but the frame declared origin %d", first+uint64(count), origin)
	}
}

func parseHostHistoryMark(t *testing.T, chunk string) (uint64, int) {
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

// A client that closes its pane mid-history leaves its stream parked on the
// ack watermark. Without a departure check it parks for the life of the
// process: every later broadcast wakes it onto the same frozen counters.
func TestAckPacedHistoryStopsWhenItsClientLeaves(t *testing.T) {
	f := startServeParsed(t, 717, 20, 4)
	defer f.cancel()

	cs := newClientState()
	f.host.mu.Lock()
	cs.everAcked = true
	cs.delivered = 64 * readBufferSize
	cs.acked = 0
	f.host.mu.Unlock()

	parked := make(chan struct{})
	go func() {
		f.host.awaitAckedHistory(cs)
		close(parked)
	}()

	select {
	case <-parked:
		t.Fatal("the history stream did not park behind the ack watermark")
	case <-time.After(100 * time.Millisecond):
	}

	cs.closeOut()
	f.host.mu.Lock()
	f.host.readCond.Broadcast()
	f.host.mu.Unlock()

	select {
	case <-parked:
	case <-time.After(5 * time.Second):
		t.Fatal("awaitAckedHistory never returned for a client that disconnected")
	}
}

// The rewrap has to see the grid the attach itself settles on. applyLargestLocked
// resizes the shared parser to the attaching client's grid, and every resize
// re-marks the rows below vt-core's hot window stale at the OLD width; a rewrap
// that ran before that resize is undone by it, and the chunks are clipped back
// to the new width with their tails gone (TERMINAL.md §5).
func TestAttachWithHistoryRewrapsAfterTheAttachResize(t *testing.T) {
	f := startServeParsed(t, 718, 120, 4)
	defer f.cancel()

	const lines = 2600
	var input strings.Builder
	for i := 0; i < lines; i++ {
		fmt.Fprintf(&input, "H%05d%sT%05d\r\n", i, strings.Repeat("x", 93), i)
	}
	writeOutput(t, f, input.String())
	waitForParsedOutput(t, f, fmt.Sprintf("T%05d", lines-1))

	c := newTestClient(t, f.addr)
	defer c.close()
	// Narrower than the host's current grid: the resize fires as a consequence
	// of this attach, not before it.
	sendResizeWithHistory(t, c, 40, 4, true)

	stream := readReplay(t, c)
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) && !strings.Contains(stream, "H00000") {
		typ, payload := c.readFrame(t)
		if typ == MsgTerminalData {
			stream += string(payload)
		}
	}
	if !strings.Contains(stream, "H00000") {
		t.Fatal("the oldest history row never arrived")
	}

	mirror, err := vtwasm.New(context.Background(), vtwasm.Module, 40, 4, vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new mirror: %v", err)
	}
	defer mirror.Close()
	if err := mirror.Feed([]byte(stream)); err != nil {
		t.Fatalf("feed the replay stream: %v", err)
	}
	rendered, err := mirror.RenderTail(200_000)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	for _, i := range []int{0, 1, 300, 599} {
		if want := fmt.Sprintf("T%05d", i); !strings.Contains(rendered, want) {
			t.Fatalf("history row %d arrived truncated: its tail %q is missing", i, want)
		}
	}
}
