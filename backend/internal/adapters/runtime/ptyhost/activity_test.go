package ptyhost

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

func fastActivityTick(t *testing.T) {
	t.Helper()
	previous := activityTick
	activityTick = 20 * time.Millisecond
	t.Cleanup(func() { activityTick = previous })
}

func newActivityWatcher(t *testing.T, addr string) *testClient {
	t.Helper()
	w := newTestClient(t, addr)
	if err := w.send(MsgWatchReq, []byte(`{"activity":true}`)); err != nil {
		t.Fatalf("send watch: %v", err)
	}
	return w
}

func readActivity(t *testing.T, c *testClient, within time.Duration) ProgramEventPayload {
	t.Helper()
	deadline := time.After(within)
	for {
		select {
		case frame, ok := <-c.frameC:
			if !ok {
				t.Fatal("watcher closed")
			}
			if frame.typ != MsgProgramEvent {
				continue
			}
			event := decodeProgramEvent(t, frame.payload)
			if event.Kind == ProgramEventActivity {
				return event
			}
		case <-deadline:
			t.Fatalf("no activity event within %v", within)
		}
	}
}

func expectNoActivity(t *testing.T, c *testClient, within time.Duration) {
	t.Helper()
	deadline := time.After(within)
	for {
		select {
		case frame, ok := <-c.frameC:
			if !ok {
				return
			}
			if frame.typ == MsgProgramEvent && decodeProgramEvent(t, frame.payload).Kind == ProgramEventActivity {
				t.Fatalf("unexpected activity event %q", frame.payload)
			}
		case <-deadline:
			return
		}
	}
}

func TestActivityIsPublishedWithNoAttachedClient(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 941, 80, 24)
	defer f.cancel()
	w := newActivityWatcher(t, f.addr)
	defer w.close()
	writeOutput(t, f, "building the index\r\n")
	if event := readActivity(t, w, 2*time.Second); event.Activity != "active" || event.Tail != "" || event.Seq != 1 {
		t.Fatalf("first event = %+v, want active with no tail", event)
	}
	event := readActivity(t, w, 3*time.Second)
	if event.Activity != "idle" || !strings.Contains(event.Tail, "building the index") || event.Seq != 2 || event.AtMs == 0 {
		t.Fatalf("second event = %+v, want idle with the screen tail", event)
	}
}

func TestAQuestionIsPublishedAsPromptingWithItsCursorLine(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 942, 80, 24)
	defer f.cancel()
	w := newActivityWatcher(t, f.addr)
	defer w.close()
	writeOutput(t, f, "Overwrite build.log? (y/n) ")
	readActivity(t, w, 2*time.Second)
	event := readActivity(t, w, 2*time.Second)
	if event.Activity != "prompting" || event.CursorLine != "Overwrite build.log? (y/n) " {
		t.Fatalf("event = %+v, want prompting with the cursor line", event)
	}
}

func TestAPlainWatcherGetsNoActivity(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 943, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	defer w.close()
	readProgramEvent(t, w)
	writeOutput(t, f, "output\r\n")
	expectNoFrame(t, w, 2*time.Second)
}

func TestALateActivityWatcherGetsTheCurrentStateOnce(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 944, 80, 24)
	defer f.cancel()
	first := newActivityWatcher(t, f.addr)
	defer first.close()
	writeOutput(t, f, "done for now\r\n")
	readActivity(t, first, 2*time.Second)
	idle := readActivity(t, first, 3*time.Second)
	late := newActivityWatcher(t, f.addr)
	defer late.close()
	if event := readActivity(t, late, time.Second); event.Seq != idle.Seq || event.Activity != "idle" {
		t.Fatalf("late watcher got %+v, want the idle event %d", event, idle.Seq)
	}
	expectNoActivity(t, late, 600*time.Millisecond)
}

func TestTypingEchoIsNotActivity(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 945, 80, 24)
	defer f.cancel()
	w := newActivityWatcher(t, f.addr)
	defer w.close()
	go func() { _, _ = io.ReadAll(f.pty.inR) }()
	f.host.handleClientMsg(nil, MsgTerminalInput, []byte("x"))
	writeOutput(t, f, "x")
	expectNoActivity(t, w, time.Second)
}

func TestASeededHostPublishesNoActivity(t *testing.T) {
	fastActivityTick(t)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	parser, err := vtwasm.New(context.Background(), vtwasm.Module, 80, 24, vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	t.Cleanup(func() { _ = parser.Close() })
	if err := parser.Feed([]byte("output from before the relaunch\r\n" + string(respawnBoundary(0, false)))); err != nil {
		t.Fatalf("seed: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	h := newHost(ctx, ServeConfig{SessionID: fmt.Sprintf("test-%d", 946), Listener: ln, PTY: newFakePTY(946), Ring: NewRing(), Parser: parser, InitialCols: 80, InitialRows: 24})
	go func() { _ = h.run(ctx) }()
	w := newActivityWatcher(t, ln.Addr().String())
	defer w.close()
	expectNoActivity(t, w, 2*time.Second)
}

func TestASettledTransitionCarriesACompactSummary(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 947, 80, 24)
	defer f.cancel()
	w := newActivityWatcher(t, f.addr)
	defer w.close()
	writeOutput(t, f, "edited greet.py\r\n✽ Thinking… (1s)\r\nall 42 tests pass\r\n")
	readActivity(t, w, 2*time.Second)
	event := readActivity(t, w, 3*time.Second)
	if event.Activity != "idle" || event.Summary != "edited greet.py\nall 42 tests pass" {
		t.Fatalf("event = %+v, want a compact summary", event)
	}
}

func decodeProgramEvent(t *testing.T, payload []byte) ProgramEventPayload {
	t.Helper()
	var event ProgramEventPayload
	if err := json.Unmarshal(payload, &event); err != nil {
		t.Fatalf("decode program event: %v", err)
	}
	return event
}
