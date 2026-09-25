//go:build !windows

package backgroundtask

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/process"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestStopShellEndsARealBackgroundProcessGroup(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "tasks")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	output := filepath.Join(dir, "breal1.output")
	file, err := os.Create(output)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = file.Close() }()
	cmd := exec.Command("/bin/sh", "-c", "eval 'sleep 614' < /dev/null")
	cmd.Stdout, cmd.Stderr = file, file
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }()
	exited := make(chan struct{})
	go func() {
		_, _ = cmd.Process.Wait()
		close(exited)
	}()

	events := &fakeEvents{}
	events.add(t, domain.BackgroundTask{
		TaskID: "breal1", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskRunning,
		Command: "sleep 614", OutputFile: output,
	})
	table := process.New()
	svc := New(Deps{
		Events:    events,
		Sessions:  &fakeSessions{found: true, rec: domain.SessionRecord{ID: "s-1", Metadata: domain.SessionMetadata{RuntimeHandleID: "h"}}},
		Runtime:   &fakeRuntime{pid: os.Getpid()},
		Processes: table,
		Signals:   table,
		Grace:     time.Second,
	})
	if _, err := svc.Stop(context.Background(), "s-1", "breal1"); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	select {
	case <-exited:
	case <-time.After(5 * time.Second):
		t.Fatal("background process group survived the stop")
	}
}
