package ptyhost

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestRunHostRejectsMissingWorkingDirectory(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "missing")
	code := RunHost([]string{"sess-1", missing, "agent.exe"}, io.Discard)
	if code != 1 {
		t.Fatalf("RunHost code = %d, want 1", code)
	}
}

func TestHostArgsRoundTripTheGrid(t *testing.T) {
	args := hostArgs("sess-1", "/tmp/ws", []string{"claude", "--resume"}, 120, 40)
	parsed, err := parseHostArgs(args[1:])
	if err != nil {
		t.Fatalf("parseHostArgs: %v", err)
	}
	want := hostArgv{cols: 120, rows: 40, sessionID: "sess-1", cwd: "/tmp/ws", shellCmd: "claude", shellArgs: []string{"--resume"}}
	if parsed.cols != want.cols || parsed.rows != want.rows || parsed.sessionID != want.sessionID ||
		parsed.cwd != want.cwd || parsed.shellCmd != want.shellCmd || len(parsed.shellArgs) != 1 || parsed.shellArgs[0] != "--resume" {
		t.Fatalf("parsed = %+v, want %+v", parsed, want)
	}
}

func TestHostArgsWithoutAGridKeepTheDefault(t *testing.T) {
	args := hostArgs("sess-1", "/tmp/ws", []string{"claude"}, 0, 0)
	if len(args) != 4 {
		t.Fatalf("args = %q, want no grid flag", args)
	}
	parsed, err := parseHostArgs(args[1:])
	if err != nil {
		t.Fatalf("parseHostArgs: %v", err)
	}
	if parsed.cols != initialCols || parsed.rows != initialRows {
		t.Fatalf("grid = %dx%d, want %dx%d", parsed.cols, parsed.rows, initialCols, initialRows)
	}
}

func TestRecordEnvTeesOutputAndSizes(t *testing.T) {
	dir := t.TempDir()
	t.Setenv(recordEnv, dir)
	rec := recorderFromEnv("sess-rec", 80, 24)
	if rec == nil {
		t.Fatal("recorderFromEnv returned nil with the env set")
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	pty := newFakePTY(300)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- Serve(ctx, ServeConfig{SessionID: "sess-rec", Listener: ln, PTY: pty, Ring: NewRing(), Recorder: rec})
	}()
	c := newTestClient(t, ln.Addr().String())
	syncClientRegistered(t, c)
	if _, err := pty.WriteOutput([]byte("first\r\n")); err != nil {
		t.Fatalf("write: %v", err)
	}
	c.readFrame(t)
	waitFor(t, 2*time.Second, func() bool {
		info, err := os.Stat(filepath.Join(dir, "sess-rec.recording"))
		return err == nil && info.Size() == 7
	})
	payload, _ := json.Marshal(ResizePayload{Cols: 100, Rows: 30})
	if err := c.send(MsgResize, payload); err != nil {
		t.Fatalf("resize: %v", err)
	}
	pty.waitResizes(t, 1)
	if _, err := pty.WriteOutput([]byte("second\r\n")); err != nil {
		t.Fatalf("write: %v", err)
	}
	c.readFrame(t)
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Serve did not return")
	}
	c.close()

	got, err := os.ReadFile(filepath.Join(dir, "sess-rec.recording"))
	if err != nil {
		t.Fatalf("read recording: %v", err)
	}
	if string(got) != "first\r\nsecond\r\n" {
		t.Fatalf("recording = %q", got)
	}
	raw, _ := os.ReadFile(filepath.Join(dir, "sess-rec.size.json"))
	var sizes []recordSize
	if err := json.Unmarshal(raw, &sizes); err != nil {
		t.Fatalf("size.json: %v", err)
	}
	if len(sizes) != 2 || sizes[1] != (recordSize{Offset: 7, Cols: 100, Rows: 30}) {
		t.Fatalf("sizes = %+v", sizes)
	}
}

func TestRecorderFromEnvIsNilWhenUnset(t *testing.T) {
	t.Setenv(recordEnv, "")
	if rec := recorderFromEnv("sess-none", 80, 24); rec != nil {
		t.Fatal("expected no recorder without the env")
	}
}

func TestParseHostArgsRejectsAMalformedGrid(t *testing.T) {
	for _, spec := range []string{"120", "0x24", "80x0", "80x1001", "axb"} {
		if _, err := parseHostArgs([]string{"--grid", spec, "sess-1", "/tmp", "sh"}); err == nil {
			t.Fatalf("--grid %q was accepted", spec)
		}
	}
}
