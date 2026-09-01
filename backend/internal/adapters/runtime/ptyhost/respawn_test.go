package ptyhost

import (
	"context"
	"net"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type realInProcHost struct {
	addr   string
	ln     net.Listener
	ring   *Ring
	cancel context.CancelFunc
	done   chan error
}

func realSpawnerFor(t *testing.T, hosts map[string]*realInProcHost) hostSpawner {
	t.Helper()
	return func(ctx context.Context, sessionID, cwd string, argv []string, env map[string]string) (string, int, error) {
		ln, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			return "", 0, err
		}
		pty, err := newPTY(cwd, argv[0], argv[1:])
		if err != nil {
			_ = ln.Close()
			return "", 0, err
		}
		ring := NewRing()
		sctx, cancel := context.WithCancel(context.Background())
		done := make(chan error, 1)
		go func() {
			done <- Serve(sctx, ServeConfig{
				SessionID:   sessionID,
				Listener:    ln,
				PTY:         pty,
				Ring:        ring,
				InitialCols: initialCols,
				InitialRows: initialRows,
			})
		}()
		h := &realInProcHost{addr: ln.Addr().String(), ln: ln, ring: ring, cancel: cancel, done: done}
		if hosts != nil {
			hosts[sessionID] = h
		}
		return h.addr, pty.PID(), nil
	}
}

func restartConfig(t *testing.T) ports.RuntimeConfig {
	t.Helper()
	return ports.RuntimeConfig{
		SessionID:     "sess-restart",
		WorkspacePath: t.TempDir(),
		Argv:          []string{"/bin/sh", "-c", "sleep 30"},
	}
}

func newTestRuntimeSession(t *testing.T) (*Runtime, ports.RuntimeHandle) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("shells out to /bin/sh")
	}
	isolateRegistry(t)
	hosts := map[string]*realInProcHost{}
	rt := New(Options{Spawner: realSpawnerFor(t, hosts)})

	handle, err := rt.Create(context.Background(), restartConfig(t))
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	h := hosts["sess-restart"]
	t.Cleanup(func() {
		h.cancel()
		select {
		case <-h.done:
		case <-time.After(2 * time.Second):
			t.Log("warning: realInProcHost did not stop within 2s")
		}
	})
	return rt, handle
}

func pidOf(t *testing.T, rt *Runtime, handle ports.RuntimeHandle) int {
	t.Helper()
	sess := rt.resolve(handle.ID)
	if sess == nil {
		t.Fatalf("resolve %q: not found", handle.ID)
	}
	status, alive, err := clientStatus(sess.addr)
	if err != nil || !alive {
		t.Fatalf("clientStatus(%q): alive=%v err=%v", handle.ID, alive, err)
	}
	return status.PID
}

func TestRestartReplacesProcessAndKeepsHandle(t *testing.T) {
	rt, handle := newTestRuntimeSession(t)
	before := pidOf(t, rt, handle)

	after, err := rt.Restart(context.Background(), handle, restartConfig(t))
	if err != nil {
		t.Fatalf("Restart: %v", err)
	}
	if after.ID != handle.ID {
		t.Fatalf("handle changed: %q -> %q, want it preserved", handle.ID, after.ID)
	}
	if pidOf(t, rt, after) == before {
		t.Fatal("child pid unchanged, want a replacement process")
	}
	if alive, _ := rt.IsAlive(context.Background(), after); !alive {
		t.Fatal("IsAlive = false after Restart")
	}
}

// markerConfig launches a process that prints marker (via the process's own
// stdout, not typed-input tty echo, so the test does not depend on local-echo
// terminal semantics) and then idles.
func markerConfig(t *testing.T, marker string) ports.RuntimeConfig {
	t.Helper()
	return ports.RuntimeConfig{
		SessionID:     "sess-restart",
		WorkspacePath: t.TempDir(),
		Argv:          []string{"/bin/sh", "-c", "printf '" + marker + "\\n'; sleep 30"},
	}
}

func waitForRingContains(t *testing.T, rt *Runtime, handle ports.RuntimeHandle, want string) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for {
		text, err := rt.GetOutput(context.Background(), handle, 100)
		if err == nil && strings.Contains(text, want) {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("ring never contained %q; last GetOutput = %q (err=%v)", want, text, err)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func TestRestartResetsRingAndKeepsClientAttached(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shells out to /bin/sh")
	}
	isolateRegistry(t)
	hosts := map[string]*realInProcHost{}
	rt := New(Options{Spawner: realSpawnerFor(t, hosts)})

	handle, err := rt.Create(context.Background(), markerConfig(t, "session-marker-A"))
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	h := hosts["sess-restart"]
	t.Cleanup(func() {
		h.cancel()
		select {
		case <-h.done:
		case <-time.After(2 * time.Second):
			t.Log("warning: realInProcHost did not stop within 2s")
		}
	})

	waitForRingContains(t, rt, handle, "session-marker-A")

	sess := rt.resolve(handle.ID)
	client, err := net.Dial("tcp", sess.addr)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer client.Close()

	// Drain whatever this fresh connection already has queued (scrollback
	// snapshot) so the assertion below only sees bytes broadcast after this
	// point, then hand read control to the post-restart wait below.
	_ = client.SetReadDeadline(time.Now().Add(200 * time.Millisecond))
	drainBuf := make([]byte, 4096)
	for {
		if _, err := client.Read(drainBuf); err != nil {
			break
		}
	}
	_ = client.SetReadDeadline(time.Time{})

	if _, err := rt.Restart(context.Background(), handle, markerConfig(t, "session-marker-B")); err != nil {
		t.Fatalf("Restart: %v", err)
	}

	after, err := rt.GetOutput(context.Background(), handle, 100)
	if err != nil {
		t.Fatalf("GetOutput immediately after restart: %v", err)
	}
	if strings.Contains(after, "session-marker-A") {
		t.Fatalf("ring still contains pre-restart output after Restart; got %q", after)
	}

	waitForRingContains(t, rt, handle, "session-marker-B")

	// The client connection opened before Restart must still be usable: the
	// listener, registry entry, and client set are untouched by respawn.
	deadline := time.Now().Add(3 * time.Second)
	var got string
	parser := NewMessageParser(func(msgType byte, payload []byte) {
		if msgType == MsgTerminalData {
			got += string(payload)
		}
	})
	buf := make([]byte, 4096)
	_ = client.SetReadDeadline(deadline)
	for time.Now().Before(deadline) && !strings.Contains(got, "session-marker-B") {
		n, rerr := client.Read(buf)
		if n > 0 {
			parser.Feed(buf[:n])
		}
		if rerr != nil {
			break
		}
	}
	if !strings.Contains(got, "session-marker-B") {
		t.Fatalf("pre-restart client connection never saw post-restart output; got %q", got)
	}
}

// failingRestartConfig names a binary that cannot exist, forcing newPTY to
// fail inside handleRespawn's step 7.
func failingRestartConfig(t *testing.T) ports.RuntimeConfig {
	t.Helper()
	return ports.RuntimeConfig{
		SessionID:     "sess-restart",
		WorkspacePath: t.TempDir(),
		Argv:          []string{"/nonexistent-binary-ptyhost-restart-test"},
	}
}

// TestRestartFailureFallsBackToRing exercises the step-7 newPTY-failure path:
// the host is left alive with no child, and a GetOutput query that arrives
// before a later successful respawn must fall back to the ring rather than
// calling into the closed old parser (which would silently render "" instead
// of erroring, masking the bug).
func TestRestartFailureFallsBackToRing(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shells out to /bin/sh")
	}
	isolateRegistry(t)
	hosts := map[string]*realInProcHost{}
	rt := New(Options{Spawner: realSpawnerFor(t, hosts)})

	handle, err := rt.Create(context.Background(), restartConfig(t))
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	h := hosts["sess-restart"]
	t.Cleanup(func() {
		h.cancel()
		select {
		case <-h.done:
		case <-time.After(2 * time.Second):
			t.Log("warning: realInProcHost did not stop within 2s")
		}
	})

	// A successful respawn first: this is what actually installs a live
	// vtwasm parser on h (Serve started with none in this test harness), so
	// the second, failing respawn below has a real parser to (mis)handle.
	if _, err := rt.Restart(context.Background(), handle, restartConfig(t)); err != nil {
		t.Fatalf("first Restart (setup): %v", err)
	}

	if _, err := rt.Restart(context.Background(), handle, failingRestartConfig(t)); err == nil {
		t.Fatal("Restart with a nonexistent binary: want error, got nil")
	}

	const marker = "post-failure-ring-fallback"
	h.ring.Append([]byte(marker + "\n"))

	text, err := rt.GetOutput(context.Background(), handle, 10)
	if err != nil {
		t.Fatalf("GetOutput after failed restart: %v", err)
	}
	if !strings.Contains(text, marker) {
		t.Fatalf("GetOutput after failed restart = %q, want it to contain the ring-seeded marker %q (parser was likely left non-nil pointing at a closed instance)", text, marker)
	}
}
