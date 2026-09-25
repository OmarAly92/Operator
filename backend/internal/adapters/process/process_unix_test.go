//go:build !windows

package process

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"testing"
	"time"
)

func startBackgroundShell(t *testing.T, output string, command string) *exec.Cmd {
	t.Helper()
	file, err := os.Create(output)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = file.Close() })
	cmd := exec.Command("/bin/sh", "-c", "eval '"+command+"' < /dev/null")
	cmd.Stdout = file
	cmd.Stderr = file
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		_, _ = cmd.Process.Wait()
	})
	return cmd
}

func waitExit(t *testing.T, cmd *exec.Cmd) {
	t.Helper()
	done := make(chan struct{})
	go func() {
		_, _ = cmd.Process.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("process did not exit")
	}
}

func TestListProcessesSeesAStartedShell(t *testing.T) {
	cmd := startBackgroundShell(t, filepath.Join(t.TempDir(), "bt1.output"), "sleep 611")
	procs, err := New().ListProcesses(context.Background())
	if err != nil {
		t.Fatalf("ListProcesses: %v", err)
	}
	pid := cmd.Process.Pid
	for _, proc := range procs {
		if proc.PID != pid {
			continue
		}
		if proc.PPID != os.Getpid() || proc.PGID != pid || !strings.Contains(proc.Command, "eval 'sleep 611'") {
			t.Fatalf("proc = %+v", proc)
		}
		return
	}
	t.Fatalf("pid %d not listed", pid)
}

func TestOpenFileHoldersFindsTheRedirectedShell(t *testing.T) {
	output := filepath.Join(t.TempDir(), "bt2.output")
	cmd := startBackgroundShell(t, output, "sleep 612")
	holders, err := New().OpenFileHolders(context.Background(), output)
	if err != nil {
		t.Fatalf("OpenFileHolders: %v", err)
	}
	if !slices.Contains(holders, cmd.Process.Pid) {
		t.Fatalf("holders = %v, want %d", holders, cmd.Process.Pid)
	}
	none, err := New().OpenFileHolders(context.Background(), filepath.Join(t.TempDir(), "absent.output"))
	if err != nil || len(none) != 0 {
		t.Fatalf("absent holders = %v, %v", none, err)
	}
}

func TestTerminateGroupStopsTheShellAndItsChild(t *testing.T) {
	cmd := startBackgroundShell(t, filepath.Join(t.TempDir(), "bt3.output"), "sleep 613")
	signals := New()
	pid := cmd.Process.Pid
	if !signals.Alive(pid) {
		t.Fatal("shell not alive")
	}
	if err := signals.Terminate(pid, true); err != nil {
		t.Fatalf("Terminate: %v", err)
	}
	waitExit(t, cmd)
	if err := signals.Kill(pid, true); err != nil {
		t.Fatalf("Kill after exit must be quiet: %v", err)
	}
}
