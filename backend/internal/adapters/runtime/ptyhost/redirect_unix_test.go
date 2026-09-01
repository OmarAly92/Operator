//go:build !windows

package ptyhost

import (
	"bufio"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestRedirectStdioSurvivesClosedPipe simulates the daemon exiting: it spawns
// a probe process with both its stdout and stderr piped back (mirroring how a
// spawner can hold both fds of a detached pty-host), reads the probe's READY
// line, then closes its own read end of both pipes (the daemon exiting drops
// them). The probe keeps writing to stdout/stderr after redirecting fds 1/2
// to a log file. Without a real fd-level dup2, those writes would hit the
// closed pipes, EPIPE, and the Go runtime would SIGPIPE the process.
func TestRedirectStdioSurvivesClosedPipe(t *testing.T) {
	exe, err := os.Executable()
	if err != nil {
		t.Fatalf("os.Executable: %v", err)
	}

	logPath := filepath.Join(t.TempDir(), "probe.log")
	cmd := exec.Command(exe, "redirect-probe", logPath)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatalf("StdoutPipe: %v", err)
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		t.Fatalf("StderrPipe: %v", err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatalf("Start: %v", err)
	}
	waited := false
	defer func() {
		_ = cmd.Process.Kill()
		if !waited {
			_ = cmd.Wait()
		}
	}()

	// Drain stderr concurrently so the probe never blocks on a full pipe
	// buffer before we close it below.
	go func() { _, _ = io.Copy(io.Discard, stderr) }()

	line, err := bufio.NewReader(stdout).ReadString('\n')
	if err != nil {
		t.Fatalf("read READY: %v", err)
	}
	if strings.TrimSpace(line) != "READY" {
		t.Fatalf("line = %q, want READY", line)
	}

	// Simulate the daemon exiting: drop our end of both pipes the probe's
	// original stdout/stderr pointed at.
	if err := stdout.Close(); err != nil {
		t.Fatalf("close stdout pipe: %v", err)
	}
	if err := stderr.Close(); err != nil {
		t.Fatalf("close stderr pipe: %v", err)
	}

	// Poll liveness while the probe is mid-loop (kill(pid, 0) also reports
	// "alive" for an unreaped zombie, so this alone would not catch a SIGPIPE
	// death — the exit-status check below via cmd.Wait is what actually
	// proves it).
	time.Sleep(200 * time.Millisecond)
	if !pidAlive(cmd.Process.Pid) {
		t.Fatalf("probe process died after its original stdout/stderr pipes closed (likely SIGPIPE)")
	}

	waitErr := cmd.Wait()
	waited = true
	if waitErr != nil {
		t.Fatalf("probe did not exit cleanly, likely killed by a signal: %v", waitErr)
	}
	if !cmd.ProcessState.Success() {
		t.Fatalf("probe exited with %v, want success", cmd.ProcessState)
	}

	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatalf("read log file: %v", err)
	}
	if !strings.Contains(string(data), "probe log line") {
		t.Fatalf("log file = %q, want it to contain redirected probe output", data)
	}
}
