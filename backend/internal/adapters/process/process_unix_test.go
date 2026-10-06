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

func TestOpenFileWritersFindsTheRedirectedShellButNotAReader(t *testing.T) {
	output := filepath.Join(t.TempDir(), "bt2.output")
	cmd := startBackgroundShell(t, output, "sleep 612")
	reader := exec.Command("/bin/sh", "-c", "exec sleep 616 < \""+output+"\"")
	if err := reader.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = reader.Process.Kill()
		_, _ = reader.Process.Wait()
	})
	time.Sleep(200 * time.Millisecond)
	writers, err := New().OpenFileWriters(context.Background(), output)
	if err != nil {
		t.Fatalf("OpenFileWriters: %v", err)
	}
	if !slices.Contains(writers, cmd.Process.Pid) {
		t.Fatalf("writers = %v, want %d", writers, cmd.Process.Pid)
	}
	if slices.Contains(writers, reader.Process.Pid) {
		t.Fatalf("reader %d reported as a writer: %v", reader.Process.Pid, writers)
	}
	none, err := New().OpenFileWriters(context.Background(), filepath.Join(t.TempDir(), "absent.output"))
	if err != nil || len(none) != 0 {
		t.Fatalf("absent writers = %v, %v", none, err)
	}
}

func TestParseLsofWriters(t *testing.T) {
	got := parseLsofWriters("p10\nf1\naw\nf2\naw\np11\nf7\nar\np12\nf3\nau\npbad\naw\n")
	if !slices.Equal(got, []int{10, 12}) {
		t.Fatalf("writers = %v", got)
	}
}

func TestGroupAliveOutlivesItsLeaderAndTheKillReachesIt(t *testing.T) {
	output := filepath.Join(t.TempDir(), "bt4.output")
	cmd := startBackgroundShell(t, output, "sh -c \"trap \\\"\\\" TERM; while :; do sleep 1; done\" & wait")
	pgid := cmd.Process.Pid
	table := New()
	time.Sleep(300 * time.Millisecond)
	if err := table.Terminate(pgid, true); err != nil {
		t.Fatalf("Terminate: %v", err)
	}
	waitExit(t, cmd)
	if table.Alive(pgid, false) {
		t.Fatal("leader survived SIGTERM")
	}
	if !table.Alive(pgid, true) {
		t.Fatal("group reported dead while a TERM-ignoring member lives")
	}
	if err := table.Kill(pgid, true); err != nil {
		t.Fatalf("Kill: %v", err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for table.Alive(pgid, true) {
		if time.Now().After(deadline) {
			t.Fatal("group survived SIGKILL")
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func TestTerminateGroupStopsTheShellAndItsChild(t *testing.T) {
	cmd := startBackgroundShell(t, filepath.Join(t.TempDir(), "bt3.output"), "sleep 613")
	signals := New()
	pid := cmd.Process.Pid
	if !signals.Alive(pid, true) {
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
