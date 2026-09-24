package terminal

import (
	"context"
	"encoding/base64"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type healthSource struct {
	*fakeSource
	mu       sync.Mutex
	health   map[string]ports.TerminalHealth
	watchers []func(string, ports.TerminalHealth)
	stopped  bool
}

func newHealthSource(src *fakeSource) *healthSource {
	return &healthSource{fakeSource: src, health: map[string]ports.TerminalHealth{}}
}

func (s *healthSource) TerminalHealth(handle ports.RuntimeHandle) ports.TerminalHealth {
	s.mu.Lock()
	defer s.mu.Unlock()
	if health, ok := s.health[handle.ID]; ok {
		return health
	}
	return ports.TerminalHealthy
}

func (s *healthSource) WatchTerminalHealth(fn func(string, ports.TerminalHealth)) func() {
	s.mu.Lock()
	s.watchers = append(s.watchers, fn)
	s.mu.Unlock()
	return func() {
		s.mu.Lock()
		s.stopped = true
		s.mu.Unlock()
	}
}

func (s *healthSource) set(id string, health ports.TerminalHealth) {
	s.mu.Lock()
	s.health[id] = health
	watchers := make([]func(string, ports.TerminalHealth), len(s.watchers))
	copy(watchers, s.watchers)
	s.mu.Unlock()
	for _, fn := range watchers {
		fn(id, health)
	}
}

func (s *healthSource) watchStopped() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.stopped
}

func awaitFrames(t *testing.T, c *fakeConn, d time.Duration, done func(serverMsg) bool) []serverMsg {
	t.Helper()
	deadline := time.After(d)
	var seen []serverMsg
	for {
		select {
		case m := <-c.out:
			seen = append(seen, m)
			if done(m) {
				return seen
			}
		case <-deadline:
			t.Fatalf("condition not met within %s; frames seen: %+v", d, seen)
			return nil
		}
	}
}

func assertNoHealthFrame(t *testing.T, c *fakeConn, d time.Duration) {
	t.Helper()
	deadline := time.After(d)
	for {
		select {
		case m := <-c.out:
			if m.Type == msgHealth {
				t.Fatalf("unexpected health frame %+v", m)
			}
		case <-deadline:
			return
		}
	}
}

func isHealth(id, health string) func(serverMsg) bool {
	return func(m serverMsg) bool {
		return m.Ch == chTerminal && m.Type == msgHealth && m.ID == id && m.Health == health
	}
}

func TestServePushesAHungTerminalToItsViewersOnly(t *testing.T) {
	src := newHealthSource(&fakeSource{alive: true, spawner: &fakeSpawner{}})
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	viewer := newFakeConn()
	go mgr.Serve(ctx, viewer)
	viewer.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, viewer, chTerminal, msgOpened, time.Second)

	bystander := newFakeConn()
	go mgr.Serve(ctx, bystander)
	bystander.in <- clientMsg{Ch: chTerminal, ID: "t2", Type: msgOpen}
	recv(t, bystander, chTerminal, msgOpened, time.Second)

	src.set("t1", ports.TerminalHung)
	awaitFrames(t, viewer, time.Second, isHealth("t1", "hung"))
	assertNoHealthFrame(t, bystander, 100*time.Millisecond)

	src.set("t1", ports.TerminalHealthy)
	awaitFrames(t, viewer, time.Second, isHealth("t1", "ok"))
}

func TestServeTellsANewViewerOfAHungTerminalAtOnce(t *testing.T) {
	src := newHealthSource(&fakeSource{alive: true, spawner: &fakeSpawner{}})
	src.health["t1"] = ports.TerminalHung
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	conn := newFakeConn()
	go mgr.Serve(ctx, conn)
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	awaitFrames(t, conn, time.Second, isHealth("t1", "hung"))
}

func TestServeKeepsTheClientAttachedAcrossAHostRestart(t *testing.T) {
	before := newFakePTY()
	after := newFakePTY()
	src := newHealthSource(&fakeSource{alive: true, spawner: &fakeSpawner{ptys: []*fakePTY{before, after}}})
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	conn := newFakeConn()
	go mgr.Serve(ctx, conn)
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, conn, chTerminal, msgOpened, time.Second)

	src.set("t1", ports.TerminalHung)
	awaitFrames(t, conn, time.Second, isHealth("t1", "hung"))

	_ = before.Close()
	src.set("t1", ports.TerminalHealthy)
	after.push([]byte("after restart"))
	seen := awaitFrames(t, conn, 3*time.Second, func(m serverMsg) bool {
		if m.Type != msgData {
			return false
		}
		got, _ := base64.StdEncoding.DecodeString(m.Data)
		return string(got) == "after restart"
	})
	sawHealthy := false
	for _, m := range seen {
		if m.Type == msgExited {
			t.Fatalf("the client was told the terminal exited during a host restart: %+v", seen)
		}
		if isHealth("t1", "ok")(m) {
			sawHealthy = true
		}
	}
	if !sawHealthy {
		t.Fatalf("the client never heard the restarted host is healthy: %+v", seen)
	}
}

func TestManagerCloseStopsTheHealthWatch(t *testing.T) {
	src := newHealthSource(&fakeSource{alive: true, spawner: &fakeSpawner{}})
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	mgr.Close()
	if !src.watchStopped() {
		t.Fatal("Close left the runtime health watch running")
	}
}
