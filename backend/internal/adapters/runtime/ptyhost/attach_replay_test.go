package ptyhost

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

// startServeParsed is startServe with a live vt parser, which is what a real
// session always has. The parser's grid — not the output ring — is what a
// connecting client is replayed from.
func startServeParsed(t *testing.T, pid, cols, rows int) *serveFixture {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	parser, err := vtwasm.New(context.Background(), vtwasm.Module, uint32(cols), uint32(rows), MaxOutputLines)
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	t.Cleanup(func() { _ = parser.Close() })

	pty := newFakePTY(pid)
	ring := NewRing()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- Serve(ctx, ServeConfig{
			SessionID:   fmt.Sprintf("test-%d", pid),
			Listener:    ln,
			PTY:         pty,
			Ring:        ring,
			Parser:      parser,
			InitialCols: cols,
			InitialRows: rows,
		})
	}()
	return &serveFixture{pty: pty, ring: ring, ln: ln, addr: ln.Addr().String(), cancel: cancel, done: done}
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
