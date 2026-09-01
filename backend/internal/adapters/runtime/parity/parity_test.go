//go:build parity && !windows

// Package parity diffs ptyhost's rendered output against tmux capture-pane on
// identical byte streams. tmux is the oracle; this test is the reason the tmux
// adapter cannot be deleted until it passes.
package parity

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"golang.org/x/sys/unix"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type Scenario struct {
	Name       string
	Bytes      []byte
	Cols, Rows int
	// ResizeAt > 0 splits the stream: feed Bytes[:ResizeAt], resize both
	// runners to NewCols x NewRows, wait for quiescence, feed the rest.
	ResizeAt         int
	NewCols, NewRows int
}

func TestRenderedOutputMatchesTmux(t *testing.T) {
	requireTmux(t)
	for _, sc := range Corpus() {
		t.Run(sc.Name, func(t *testing.T) {
			tmuxRows := runUnderTmux(t, sc)
			hostRows := runUnderPtyHost(t, sc)
			diffRows(t, tmuxRows, hostRows)
		})
	}
}

// replayCommand feeds a recorded vector into a pane with echo off, applied to
// both runners alike. In cooked mode the tty echoes a terminal's own query
// replies back onto the screen: tmux answers XTVERSION and Primary DA, so its
// capture grows a literal "^[P>|tmux 3.6b^[\" that no parser produced and that
// nothing but tmux could ever reproduce. Real agent CLIs run the tty raw, and
// the recordings contain no reply bytes, so echoing them compares line-discipline
// behaviour rather than terminal emulation. Disabling it symmetrically cannot
// mask a parser difference — neither side can echo what neither side is sent.
func replayCommand(fifoPath string) string {
	return "stty -echo; cat < " + fifoPath
}

func requireTmux(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("tmux"); err != nil {
		t.Skip("tmux not found in PATH; skipping differential parity test")
	}
}

var scenarioCounter int64

func uniqueID(prefix string) string {
	n := atomic.AddInt64(&scenarioCounter, 1)
	return fmt.Sprintf("%s-%d-%d", prefix, os.Getpid(), n)
}

func writeSplit(t *testing.T, f *os.File, sc Scenario, resize func()) {
	t.Helper()
	if sc.ResizeAt <= 0 || sc.ResizeAt >= len(sc.Bytes) {
		if _, err := f.Write(sc.Bytes); err != nil {
			t.Fatalf("write bytes: %v", err)
		}
		return
	}
	if _, err := f.Write(sc.Bytes[:sc.ResizeAt]); err != nil {
		t.Fatalf("write first half: %v", err)
	}
	resize()
	if _, err := f.Write(sc.Bytes[sc.ResizeAt:]); err != nil {
		t.Fatalf("write second half: %v", err)
	}
}

func runUnderTmux(t *testing.T, sc Scenario) []string {
	t.Helper()

	dir := t.TempDir()
	fifoPath := filepath.Join(dir, "fifo")
	if err := unix.Mkfifo(fifoPath, 0o600); err != nil {
		t.Fatalf("mkfifo: %v", err)
	}

	label := uniqueID("parity")
	session := "s"

	tmuxCmd := func(args ...string) *exec.Cmd {
		full := append([]string{"-L", label}, args...)
		return exec.Command("tmux", full...)
	}

	newSession := tmuxCmd("-f", "/dev/null", "new-session", "-d", "-s", session,
		"-x", strconv.Itoa(sc.Cols), "-y", strconv.Itoa(sc.Rows),
		replayCommand(fifoPath))
	if out, err := newSession.CombinedOutput(); err != nil {
		t.Fatalf("tmux new-session: %v: %s", err, out)
	}
	t.Cleanup(func() {
		_ = tmuxCmd("kill-server").Run()
	})

	f, err := os.OpenFile(fifoPath, os.O_WRONLY, 0)
	if err != nil {
		t.Fatalf("open fifo write end: %v", err)
	}
	defer f.Close()

	capture := func() string {
		out, err := tmuxCmd("capture-pane", "-t", session, "-p").Output()
		if err != nil {
			return ""
		}
		return string(out)
	}

	writeSplit(t, f, sc, func() {
		waitQuiescent(t, capture)
		resize := tmuxCmd("resize-window", "-t", session, "-x", strconv.Itoa(sc.NewCols), "-y", strconv.Itoa(sc.NewRows))
		if out, err := resize.CombinedOutput(); err != nil {
			t.Fatalf("tmux resize-window: %v: %s", err, out)
		}
	})

	final := waitQuiescent(t, capture)
	return splitRows(final)
}

func runUnderPtyHost(t *testing.T, sc Scenario) []string {
	t.Helper()

	bin := oprBinary(t)
	isolateRegistry(t)

	dir := t.TempDir()
	fifoPath := filepath.Join(dir, "fifo")
	if err := unix.Mkfifo(fifoPath, 0o600); err != nil {
		t.Fatalf("mkfifo: %v", err)
	}
	workDir := t.TempDir()

	rt := ptyhost.New(ptyhost.Options{Spawner: realHostSpawner(bin)})
	ctx := context.Background()

	sessionID := uniqueID("sess")
	handle, err := rt.Create(ctx, ports.RuntimeConfig{
		SessionID:     domain.SessionID(sessionID),
		WorkspacePath: workDir,
		Argv:          []string{"/bin/sh", "-c", replayCommand(fifoPath)},
	})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	t.Cleanup(func() {
		_ = rt.Destroy(context.Background(), handle)
	})

	stream, err := rt.Attach(ctx, handle, uint16(sc.Rows), uint16(sc.Cols))
	if err != nil {
		t.Fatalf("Attach: %v", err)
	}
	defer stream.Close()
	go io.Copy(io.Discard, stream) //nolint:errcheck // draining a live client stream

	f, err := os.OpenFile(fifoPath, os.O_WRONLY, 0)
	if err != nil {
		t.Fatalf("open fifo write end: %v", err)
	}
	defer f.Close()

	rowsNow := sc.Rows
	capture := func() string {
		out, err := rt.GetOutput(ctx, handle, rowsNow)
		if err != nil {
			return ""
		}
		return out
	}

	writeSplit(t, f, sc, func() {
		waitQuiescent(t, capture)
		rowsNow = sc.NewRows
		if err := stream.Resize(uint16(sc.NewRows), uint16(sc.NewCols)); err != nil {
			t.Fatalf("Resize: %v", err)
		}
		time.Sleep(200 * time.Millisecond)
	})

	final := waitQuiescent(t, capture)
	return splitRows(final)
}

func realHostSpawner(bin string) func(ctx context.Context, sessionID, cwd string, argv []string, env map[string]string) (string, int, error) {
	return func(ctx context.Context, sessionID, cwd string, argv []string, env map[string]string) (string, int, error) {
		args := append([]string{"pty-host", sessionID, cwd}, argv...)
		cmd := exec.Command(bin, args...)
		cmd.Dir = cwd
		cmd.Env = os.Environ()
		for key, value := range env {
			cmd.Env = append(cmd.Env, key+"="+value)
		}
		cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}

		stdout, err := cmd.StdoutPipe()
		if err != nil {
			return "", 0, fmt.Errorf("ptyhost spawn: stdout pipe: %w", err)
		}
		stderr, err := cmd.StderrPipe()
		if err != nil {
			return "", 0, fmt.Errorf("ptyhost spawn: stderr pipe: %w", err)
		}
		go io.Copy(io.Discard, stderr) //nolint:errcheck // parity harness does not assert on host stderr

		if err := cmd.Start(); err != nil {
			return "", 0, fmt.Errorf("ptyhost spawn: start: %w", err)
		}

		type readyLine struct {
			port int
			err  error
		}
		ready := make(chan readyLine, 1)
		go func() {
			line, err := bufio.NewReader(stdout).ReadString('\n')
			if err != nil {
				ready <- readyLine{err: err}
				return
			}
			fields := strings.Fields(strings.TrimPrefix(strings.TrimSpace(line), "READY:"))
			if len(fields) != 2 {
				ready <- readyLine{err: fmt.Errorf("malformed ready line %q", line)}
				return
			}
			port, err := strconv.Atoi(fields[1])
			ready <- readyLine{port: port, err: err}
		}()

		select {
		case result := <-ready:
			if result.err != nil {
				_ = cmd.Process.Kill()
				return "", 0, result.err
			}
			return fmt.Sprintf("127.0.0.1:%d", result.port), cmd.Process.Pid, nil
		case <-time.After(10 * time.Second):
			_ = cmd.Process.Kill()
			return "", 0, fmt.Errorf("ptyhost spawn: host did not report ready in 10s")
		case <-ctx.Done():
			_ = cmd.Process.Kill()
			return "", 0, ctx.Err()
		}
	}
}

func isolateRegistry(t *testing.T) {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	t.Setenv("USERPROFILE", dir)
}

var (
	oprBinOnce sync.Once
	oprBinPath string
	oprBinErr  error
)

func oprBinary(t *testing.T) string {
	t.Helper()
	oprBinOnce.Do(func() {
		dir, err := os.MkdirTemp("", "parity-opr-")
		if err != nil {
			oprBinErr = err
			return
		}
		bin := filepath.Join(dir, "opr")
		cmd := exec.Command("go", "build", "-o", bin, "./cmd/opr")
		cmd.Dir = filepath.Join(repoRoot(), "backend")
		if out, err := cmd.CombinedOutput(); err != nil {
			oprBinErr = fmt.Errorf("go build ./cmd/opr: %w: %s", err, out)
			return
		}
		oprBinPath = bin
	})
	if oprBinErr != nil {
		t.Fatalf("build opr binary: %v", oprBinErr)
	}
	return oprBinPath
}

func splitRows(captured string) []string {
	return strings.Split(strings.TrimRight(captured, "\n"), "\n")
}

func waitQuiescent(t *testing.T, capture func() string) string {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	var last string
	stable := 0
	for {
		cur := capture()
		if cur == last {
			stable++
		} else {
			stable = 1
			last = cur
		}
		if stable >= 3 {
			return cur
		}
		if time.Now().After(deadline) {
			t.Fatalf("waitQuiescent: output did not stabilize within 10s (last capture=%q)", cur)
		}
		time.Sleep(50 * time.Millisecond)
	}
}

func normalize(rows []string) []string {
	out := make([]string, len(rows))
	for i, r := range rows {
		out[i] = strings.TrimRight(r, " ")
	}
	for len(out) > 0 && out[len(out)-1] == "" {
		out = out[:len(out)-1]
	}
	return out
}

func diffRows(t *testing.T, tmuxRows, hostRows []string) {
	t.Helper()
	want := normalize(tmuxRows)
	got := normalize(hostRows)
	max := len(want)
	if len(got) > max {
		max = len(got)
	}
	for i := 0; i < max; i++ {
		var w, g string
		if i < len(want) {
			w = want[i]
		}
		if i < len(got) {
			g = got[i]
		}
		if w != g {
			t.Fatalf("row %d differs (tmux rows=%d, ptyhost rows=%d):\n  tmux:    %q\n  ptyhost: %q", i, len(want), len(got), w, g)
		}
	}
}
