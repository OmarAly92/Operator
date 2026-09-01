//go:build !windows

// spawn_unix.go starts the detached `opr pty-host` process on Darwin/Linux and
// reads back the address it bound. Setsid detaches it from the daemon's process
// group so the host outlives the daemon, matching the Windows spawn's intent.
package ptyhost

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const hostReadyTimeout = 10 * time.Second

func defaultSpawnHost(ctx context.Context, sessionID, cwd string, argv []string, env map[string]string) (string, int, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", 0, fmt.Errorf("ptyhost spawn: resolve executable: %w", err)
	}

	args := append([]string{"pty-host", sessionID, cwd}, argv...)
	cmd := exec.Command(exe, args...)
	cmd.Dir = cwd
	cmd.Env = processEnvironment(env)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return "", 0, fmt.Errorf("ptyhost spawn: stdout pipe: %w", err)
	}
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
			ready <- readyLine{err: fmt.Errorf("ptyhost spawn: malformed ready line %q", line)}
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
	case <-time.After(hostReadyTimeout):
		_ = cmd.Process.Kill()
		return "", 0, fmt.Errorf("ptyhost spawn: host did not report ready in %s", hostReadyTimeout)
	case <-ctx.Done():
		_ = cmd.Process.Kill()
		return "", 0, ctx.Err()
	}
}

func stopHostProcess(pid int) {
	if process, err := os.FindProcess(pid); err == nil {
		_ = process.Signal(syscall.SIGTERM)
	}
}
