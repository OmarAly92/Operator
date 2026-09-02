//go:build !windows

// Package realpty spawns a real "opr pty-host" process for integration tests
// that need actual runtime behavior instead of a fake or mock. This is the
// same shape internal/adapters/runtime/parity uses to diff ptyhost against
// tmux (build ./cmd/opr once, spawn "pty-host <sessionID> <cwd> <argv...>"
// with Setsid, parse the "READY:<pid> <port>" line) factored out so other
// packages' integration tests can reuse it without importing the parity
// package, which is gated behind the "parity" build tag and requires tmux.
package realpty

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
)

var (
	// buildEnv is captured at package init, before any test can override
	// HOME via IsolateRegistry. Building with a HOME already redirected to a
	// t.TempDir() makes `go build` treat that temp dir as GOPATH and
	// populate a full module cache under it — slow, and the cache's
	// read-only files then make the temp dir's automatic cleanup fail with
	// "permission denied". Building with the real environment reuses the
	// ambient module/build cache instead.
	buildEnv = os.Environ()

	binOnce sync.Once
	binPath string
	binErr  error
)

// Binary builds ./cmd/opr once per test binary and returns its path.
func Binary(t testing.TB) string {
	t.Helper()
	binOnce.Do(func() {
		dir, err := os.MkdirTemp("", "realpty-opr-")
		if err != nil {
			binErr = err
			return
		}
		bin := filepath.Join(dir, "opr")
		cmd := exec.Command("go", "build", "-o", bin, "./cmd/opr")
		cmd.Dir = filepath.Join(repoRoot(), "backend")
		cmd.Env = buildEnv
		if out, err := cmd.CombinedOutput(); err != nil {
			binErr = fmt.Errorf("go build ./cmd/opr: %w: %s", err, out)
			return
		}
		binPath = bin
	})
	if binErr != nil {
		t.Fatalf("build opr binary: %v", binErr)
	}
	return binPath
}

// IsolateRegistry points HOME/USERPROFILE at a scratch directory so the
// pty-host on-disk registry never touches the real ~/.operator during a test.
func IsolateRegistry(t *testing.T) {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	t.Setenv("USERPROFILE", dir)
}

// Runtime returns a ptyhost.Runtime backed by a real "opr pty-host" process.
// Call IsolateRegistry first if the test must not touch the real ~/.operator.
func Runtime(t *testing.T) *ptyhost.Runtime {
	t.Helper()
	return ptyhost.New(ptyhost.Options{Spawner: spawner(Binary(t))})
}

func spawner(bin string) func(ctx context.Context, sessionID, cwd string, argv []string, env map[string]string) (string, int, error) {
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
		go io.Copy(io.Discard, stderr) //nolint:errcheck // integration harness does not assert on host stderr

		if err := cmd.Start(); err != nil {
			return "", 0, fmt.Errorf("ptyhost spawn: start: %w", err)
		}
		// See the reaping comment in ptyhost/spawn_unix.go: the pty-host runs
		// detached and nothing else waits on it, so it zombies without this.
		go func() { _ = cmd.Wait() }()

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

func repoRoot() string {
	_, thisFile, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(thisFile), "..", "..", "..", "..")
}
