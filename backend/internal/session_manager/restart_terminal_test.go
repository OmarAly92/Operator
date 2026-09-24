package sessionmanager

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func newHungTerminalManager(t *testing.T, runtime *fakeRuntime) (*Manager, *fakeStore) {
	t.Helper()
	agent := supervisedLaunchAgent{launchArgvAgent{argv: []string{"codex", "resume", "agent-x"}}}
	m, st, _ := newExitedResumeManager(t, runtime, agent)
	rec := st.sessions["mer-1"]
	rec.Activity.State = domain.ActivityIdle
	st.sessions["mer-1"] = rec
	return m, st
}

func TestRestartTerminal_StopsTheHungHostAndStartsAFreshOne(t *testing.T) {
	runtime := &fakeRuntime{aliveByHandle: map[string]bool{"pty-mer-1": true}, aliveErr: errors.New("read tcp 127.0.0.1:1: i/o timeout")}
	runtime.onDestroy = func(int, ports.RuntimeHandle) { runtime.aliveErr = nil }
	m, st := newHungTerminalManager(t, runtime)

	result, err := m.RestartTerminal(ctx, "mer-1", ports.PaneGrid{Cols: 132, Rows: 43})
	if err != nil {
		t.Fatalf("RestartTerminal: %v", err)
	}
	if !reflect.DeepEqual(runtime.destroyedIDs, []string{"pty-mer-1"}) || runtime.created != 1 {
		t.Fatalf("runtime lifecycle: destroyed=%v created=%d, want the hung host destroyed and one fresh host", runtime.destroyedIDs, runtime.created)
	}
	if runtime.lastCfg.Cols != 132 || runtime.lastCfg.Rows != 43 {
		t.Fatalf("fresh host grid = %dx%d, want 132x43", runtime.lastCfg.Cols, runtime.lastCfg.Rows)
	}
	got := st.sessions["mer-1"]
	if got.IsTerminated {
		t.Fatalf("restart terminated the session: %+v", got)
	}
	if got.Metadata.RuntimeHandleID != "h1" || got.Metadata.RuntimeLaunchID != "launch-new" {
		t.Fatalf("restarted metadata = %+v, want the fresh host's handle and launch", got.Metadata)
	}
	if result.Mode != RestoreModeNative {
		t.Fatalf("restart mode = %q, want native", result.Mode)
	}
}

func TestRestartTerminal_RejectsATerminatedSession(t *testing.T) {
	runtime := &fakeRuntime{aliveByHandle: map[string]bool{"pty-mer-1": true}}
	m, st := newHungTerminalManager(t, runtime)
	rec := st.sessions["mer-1"]
	rec.IsTerminated = true
	st.sessions["mer-1"] = rec

	if _, err := m.RestartTerminal(ctx, "mer-1", ports.PaneGrid{}); !errors.Is(err, ErrTerminated) {
		t.Fatalf("restart of a terminated session = %v, want ErrTerminated", err)
	}
	if runtime.destroyed != 0 || runtime.created != 0 {
		t.Fatalf("a rejected restart touched the runtime: destroyed=%d created=%d", runtime.destroyed, runtime.created)
	}
}

func TestRestartTerminal_KeepsTheSessionWhenTheHostCannotBeStopped(t *testing.T) {
	runtime := &fakeRuntime{
		aliveByHandle: map[string]bool{"pty-mer-1": true},
		destroyErr:    errors.New("ptyhost: pty-host pid 42 is still alive after teardown"),
	}
	m, st := newHungTerminalManager(t, runtime)

	_, err := m.RestartTerminal(ctx, "mer-1", ports.PaneGrid{})
	if err == nil || !strings.Contains(err.Error(), "still alive") {
		t.Fatalf("restart error = %v, want the teardown failure", err)
	}
	if runtime.created != 0 {
		t.Fatalf("created %d hosts after the old one could not be stopped", runtime.created)
	}
	got := st.sessions["mer-1"]
	if got.IsTerminated || got.Metadata.RuntimeHandleID != "pty-mer-1" || got.Metadata.RuntimeLaunchID != "launch-old" {
		t.Fatalf("a failed restart changed the session: %+v", got)
	}
}

func TestRestartTerminal_RejectsAConcurrentOperation(t *testing.T) {
	entered := make(chan struct{})
	release := make(chan struct{})
	runtime := &fakeRuntime{aliveByHandle: map[string]bool{"pty-mer-1": true}}
	runtime.onDestroy = func(int, ports.RuntimeHandle) {
		close(entered)
		<-release
	}
	m, _ := newHungTerminalManager(t, runtime)

	firstDone := make(chan error, 1)
	go func() {
		_, err := m.RestartTerminal(ctx, "mer-1", ports.PaneGrid{})
		firstDone <- err
	}()
	<-entered
	if !m.SessionMutationInProgress("mer-1") {
		t.Fatal("a restart in progress must suppress observation-driven termination")
	}
	if _, err := m.RestartTerminal(ctx, "mer-1", ports.PaneGrid{}); !errors.Is(err, ErrSwitchInProgress) {
		t.Fatalf("concurrent restart = %v, want ErrSwitchInProgress", err)
	}
	close(release)
	if err := <-firstDone; err != nil {
		t.Fatalf("first restart: %v", err)
	}
}
