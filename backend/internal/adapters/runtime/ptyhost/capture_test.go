package ptyhost

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"
)

func (tc *testClient) startCapture(t *testing.T, argv []string) error {
	t.Helper()
	payload, err := json.Marshal(CaptureStartReq{Argv: argv})
	if err != nil {
		t.Fatalf("marshal CaptureStartReq: %v", err)
	}
	return tc.send(MsgCaptureStartReq, payload)
}

func (tc *testClient) stopCapture(t *testing.T) error {
	t.Helper()
	return tc.send(MsgCaptureStopReq, nil)
}

func (tc *testClient) captureState(t *testing.T) CaptureStateRes {
	t.Helper()
	if err := tc.send(MsgCaptureStateReq, nil); err != nil {
		t.Fatalf("send: %v", err)
	}
	for {
		typ, payload := tc.readFrame(t)
		if typ == MsgCaptureStateRes {
			var state CaptureStateRes
			if err := json.Unmarshal(payload, &state); err != nil {
				t.Fatalf("unmarshal CaptureStateRes: %v", err)
			}
			return state
		}
	}
}

func waitForFileContaining(t *testing.T, path, want string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		data, err := os.ReadFile(path)
		if err == nil && strings.Contains(string(data), want) {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s to contain %q", path, want)
}

func TestStartCaptureTeesOutputToArgv(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shells out to /bin/sh")
	}
	prevExecutable := captureExecutablePath
	captureExecutablePath = func() (string, error) { return "/bin/sh", nil }
	defer func() { captureExecutablePath = prevExecutable }()

	f, c := newTestHostWithParser(t)
	defer f.cancel()
	defer c.close()

	syncClientRegistered(t, c)

	sink := filepath.Join(t.TempDir(), "capture.log")
	if err := c.startCapture(t, []string{"-c", "cat > " + sink}); err != nil {
		t.Fatalf("startCapture: %v", err)
	}
	state := c.captureState(t)
	if !state.PipeOpen {
		t.Fatal("PipeOpen = false, want true immediately after StartCapture")
	}

	f.feedPTY(t, "captured bytes\n")

	waitForFileContaining(t, sink, "captured bytes")

	state = c.captureState(t)
	if !state.PipeOpen {
		t.Fatal("PipeOpen = false, want true while capture is armed")
	}
	if err := c.stopCapture(t); err != nil {
		t.Fatalf("stopCapture: %v", err)
	}
	if c.captureState(t).PipeOpen {
		t.Fatal("PipeOpen = true after StopCapture, want false")
	}
}

// TestCaptureBackpressureDoesNotStallDelivery pins the fix for a hot-path
// stall: write() used to write straight into the capture subprocess's stdin
// pipe from inside deliver(), the same call that appends to the ring and
// broadcasts to clients. A capture consumer that doesn't drain fast enough
// (slow disk, or here a subprocess that never reads stdin at all) fills the
// OS pipe buffer and blocks that write — and since it ran inside deliver(),
// it blocked pumpPTY itself, freezing ring append and client broadcast for
// every byte after it, for reasons having nothing to do with capture.
func TestCaptureBackpressureDoesNotStallDelivery(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shells out to /bin/sh")
	}
	prevExecutable := captureExecutablePath
	captureExecutablePath = func() (string, error) { return "/bin/sh", nil }
	defer func() { captureExecutablePath = prevExecutable }()

	f, c := newTestHostWithParser(t)
	defer f.cancel()
	defer c.close()

	syncClientRegistered(t, c)

	// A subprocess that never reads stdin: any write past the OS pipe's
	// buffer (typically 64KiB) blocks forever.
	if err := c.startCapture(t, []string{"-c", "sleep 30"}); err != nil {
		t.Fatalf("startCapture: %v", err)
	}

	// Feed well past a pipe buffer's worth of output, which used to be
	// enough to wedge deliver() on the capture write.
	filler := strings.Repeat("x", 4096) + "\n"
	for i := 0; i < 64; i++ {
		f.feedPTY(t, filler)
	}

	f.feedPTY(t, "AFTER-BACKPRESSURE-MARKER\n")

	// Read the ring directly rather than round-tripping GetOutput: c is a
	// registered client under a flood of broadcasts, and this only needs to
	// know deliver()'s ring-append side (not the wire protocol) kept moving.
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if strings.Contains(f.ring.Tail(5), "AFTER-BACKPRESSURE-MARKER") {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("marker fed after filling the capture pipe never reached the ring; deliver() is stalled on the capture write")
}

func TestCaptureStateReportsAlternateScreen(t *testing.T) {
	f, c := newTestHostWithParser(t)
	defer f.cancel()
	defer c.close()

	syncClientRegistered(t, c)
	f.feedPTY(t, "\x1b[?1049h")

	if !c.captureState(t).AlternateOn {
		t.Fatal("AlternateOn = false after entering the alternate screen")
	}
}

// TestCaptureQueueIsBounded pins the memory ceiling on a stalled capture
// consumer. Decoupling write() from stdin keeps a slow consumer from stalling
// the pump, but an unbounded queue would trade that stall for the daemon
// buffering the entire session: a consumer that is stopped rather than slow
// never drains, and deliver() would keep appending. Past the cap, write() must
// block instead — back-pressure at a fixed cost.
func TestCaptureQueueIsBounded(t *testing.T) {
	block := make(chan struct{})
	c := &captureSink{}
	c.queueCond = sync.NewCond(&c.queueMu)
	c.stdin = blockingWriteCloser{block}
	c.cmd = &exec.Cmd{}
	c.drained = make(chan struct{})
	go c.forward(c.stdin, c.drained)
	var unblockOnce sync.Once
	unblock := func() { unblockOnce.Do(func() { close(block) }) }
	defer unblock()

	batch := make([]byte, readBufferSize)

	// Fill past the cap. forward() parks on the first Write, so nothing drains.
	deadline := time.Now().Add(5 * time.Second)
	for {
		c.queueMu.Lock()
		queued := c.queueBytes
		c.queueMu.Unlock()
		if queued >= maxQueuedCaptureBytes {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("queue never reached the cap; queued=%d cap=%d", queued, maxQueuedCaptureBytes)
		}
		c.write(batch)
	}

	// Further writes must park rather than grow the queue. forward() always
	// holds one already-dequeued batch in flight, so a single write can still
	// land; what must hold is that the queue never exceeds the cap and that a
	// run of writes cannot all complete while the consumer is stopped.
	done := make(chan struct{})
	go func() {
		for range 8 {
			c.write(batch)
		}
		close(done)
	}()

	deadline = time.Now().Add(300 * time.Millisecond)
	for time.Now().Before(deadline) {
		c.queueMu.Lock()
		queued := c.queueBytes
		c.queueMu.Unlock()
		if queued > maxQueuedCaptureBytes {
			t.Fatalf("queue grew past the cap: queued=%d cap=%d", queued, maxQueuedCaptureBytes)
		}
		select {
		case <-done:
			t.Fatalf("8 writes all completed against a stopped consumer; the cap is not applying back-pressure")
		default:
		}
		time.Sleep(10 * time.Millisecond)
	}

	// Unblocking the consumer must let the parked writers through.
	unblock()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("parked writers never resumed after the consumer drained")
	}
}

type blockingWriteCloser struct{ block chan struct{} }

func (b blockingWriteCloser) Write(p []byte) (int, error) { <-b.block; return len(p), nil }
func (b blockingWriteCloser) Close() error                { return nil }
