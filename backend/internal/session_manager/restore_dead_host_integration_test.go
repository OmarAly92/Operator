//go:build !windows

package sessionmanager

import (
	"syscall"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/ptyregistry"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/testsupport/realpty"
)

func ptyHostPID(t *testing.T, id string) int {
	t.Helper()
	entries, err := ptyregistry.List()
	if err != nil {
		t.Fatalf("registry list: %v", err)
	}
	for _, e := range entries {
		if e.SessionID == id {
			return e.PtyHostPID
		}
	}
	t.Fatalf("no registry entry for %s", id)
	return 0
}

func waitForHostGone(t *testing.T, rt *ptyhost.Runtime, handle ports.RuntimeHandle) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for {
		alive, err := rt.IsAlive(ctx, handle)
		if err == nil && !alive {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("killed pty-host never reported gone: alive=%v err=%v", alive, err)
		}
		time.Sleep(50 * time.Millisecond)
	}
}

func TestRestoreRelaunchesASessionWhosePtyHostWasKilled(t *testing.T) {
	if testing.Short() {
		t.Skip("spawns a real pty-host")
	}
	realpty.IsolateRegistry(t)
	rt := realpty.Runtime(t)
	wsDir := t.TempDir()
	st := newFakeStore()
	st.projects["mer"] = domain.ProjectRecord{ID: "mer", Config: testRoleAgents()}
	seedTerminal(st, "mer-1", domain.SessionMetadata{WorkspacePath: wsDir, Branch: "b", AgentSessionID: "agent-x"})
	m := New(Deps{
		Runtime:   rt,
		Agents:    singleAgent{agent: launchArgvAgent{argv: []string{"/bin/sh", "-c", "sleep 60"}}},
		Workspace: &fakeWorkspace{path: wsDir},
		Store:     st,
		Messenger: &fakeMessenger{},
		Lifecycle: &fakeLCM{store: st},
		DataDir:   t.TempDir(),
		LookPath:  func(string) (string, error) { return "/bin/sh", nil },
	})

	first, err := m.RestoreWithMode(ctx, "mer-1", ports.PaneGrid{})
	if err != nil {
		t.Fatalf("first restore: %v", err)
	}
	handle := ports.RuntimeHandle{ID: first.Session.Metadata.RuntimeHandleID}
	t.Cleanup(func() { _ = rt.Destroy(ctx, handle) })
	killedPID := ptyHostPID(t, handle.ID)
	if err := syscall.Kill(killedPID, syscall.SIGKILL); err != nil {
		t.Fatalf("kill pty-host %d: %v", killedPID, err)
	}
	waitForHostGone(t, rt, handle)
	rec := st.sessions["mer-1"]
	rec.IsTerminated = true
	rec.Activity = domain.Activity{State: domain.ActivityExited}
	st.sessions["mer-1"] = rec

	second, err := m.RestoreWithMode(ctx, "mer-1", ports.PaneGrid{})
	if err != nil {
		t.Fatalf("restore after the pty-host was killed = %v, want a fresh host", err)
	}
	relaunched := ports.RuntimeHandle{ID: second.Session.Metadata.RuntimeHandleID}
	if alive, err := rt.IsAlive(ctx, relaunched); err != nil || !alive {
		t.Fatalf("relaunched host alive = %v, %v; want true", alive, err)
	}
	if pid := ptyHostPID(t, relaunched.ID); pid == killedPID {
		t.Fatalf("registry still points at the killed pty-host %d", pid)
	}
}
