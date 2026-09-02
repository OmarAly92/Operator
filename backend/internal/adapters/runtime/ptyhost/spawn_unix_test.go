//go:build !windows

package ptyhost

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"
)

// TestMain lets defaultSpawnHost's os.Executable()-based exec of "pty-host
// <sessionID> <cwd> <argv...>" work against the test binary itself: when
// re-exec'd with that argv shape it dispatches straight into RunHost instead
// of running the test suite (which would otherwise recurse into this same
// test and spawn further copies of itself). "redirect-probe" is a second
// re-exec branch used by TestRedirectStdioSurvivesClosedPipe to exercise
// redirectStdio directly.
func TestMain(m *testing.M) {
	switch {
	case len(os.Args) > 1 && os.Args[1] == "pty-host":
		os.Exit(RunHost(os.Args[2:], os.Stdout))
	case len(os.Args) > 2 && os.Args[1] == "redirect-probe":
		os.Exit(runRedirectProbe(os.Args[2]))
	}
	os.Exit(m.Run())
}

// runRedirectProbe prints READY on the original stdout pipe, then redirects
// fds 1/2 to logPath (mirroring host_main.go's post-READY redirect) and keeps
// writing to stdout and stderr afterward. If redirectStdio did not really
// dup2 the fds, closing the parent's read end of the original stdout/stderr
// pipes before this loop runs would EPIPE these writes and the Go runtime
// would SIGPIPE this process.
func runRedirectProbe(logPath string) int {
	fmt.Fprintln(os.Stdout, "READY")

	f, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		f = nil
	}
	redirectStdio(f)

	for i := 0; i < 20; i++ {
		fmt.Fprintln(os.Stdout, "probe log line (stdout)", i)
		fmt.Fprintln(os.Stderr, "probe log line (stderr)", i)
		time.Sleep(50 * time.Millisecond)
	}
	return 0
}

func TestDefaultSpawnHostDetachesAndReportsAddress(t *testing.T) {
	addr, pid, err := defaultSpawnHost(
		context.Background(),
		"spawn-test",
		t.TempDir(),
		[]string{"/bin/sh", "-c", "sleep 5"},
		nil,
	)
	if err != nil {
		t.Fatalf("defaultSpawnHost: %v", err)
	}
	defer stopHostProcess(pid)

	if pid <= 0 {
		t.Fatalf("pid = %d, want > 0", pid)
	}
	if !strings.HasPrefix(addr, "127.0.0.1:") {
		t.Fatalf("addr = %q, want a 127.0.0.1 address", addr)
	}
}

// TestDefaultSpawnHostReapsExitedProcess pins the fix for a zombie leak:
// defaultSpawnHost detaches the pty-host (Setsid) and returns without ever
// waiting on it, so nothing else in the daemon collects its exit status.
// pidAlive uses kill(pid, 0), which still succeeds against an unreaped
// zombie, so without a background Wait() the pty-host process leaks a zombie
// table entry for the daemon's lifetime and Destroy can spuriously report
// "still alive after teardown" for a process that has actually exited.
func TestDefaultSpawnHostReapsExitedProcess(t *testing.T) {
	_, pid, err := defaultSpawnHost(
		context.Background(),
		"spawn-reap-test",
		t.TempDir(),
		[]string{"/bin/sh", "-c", "sleep 5"},
		nil,
	)
	if err != nil {
		t.Fatalf("defaultSpawnHost: %v", err)
	}
	stopHostProcess(pid) // SIGTERM the detached pty-host

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if !pidAlive(pid) {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("pid %d still reports alive 2s after SIGTERM; defaultSpawnHost must reap its detached child or it zombies and pidAlive never goes false", pid)
}
