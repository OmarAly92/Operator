package ptyhost

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
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
	f, c := newTestHostWithParser(t)
	defer f.cancel()
	defer c.close()

	syncClientRegistered(t, c)

	sink := filepath.Join(t.TempDir(), "capture.log")
	if err := c.startCapture(t, []string{"/bin/sh", "-c", "cat > " + sink}); err != nil {
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
