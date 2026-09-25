package terminal

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type programSource struct {
	*fakeSource
	mu        sync.Mutex
	titles    map[string]string
	listeners []func(string, ports.TerminalProgramEvent)
	stopped   bool
}

func newProgramSource(src *fakeSource) *programSource {
	return &programSource{fakeSource: src, titles: map[string]string{}}
}

func (s *programSource) TerminalTitles() map[string]string {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make(map[string]string, len(s.titles))
	for id, title := range s.titles {
		out[id] = title
	}
	return out
}

func (s *programSource) WatchTerminalPrograms(fn func(string, ports.TerminalProgramEvent)) func() {
	s.mu.Lock()
	s.listeners = append(s.listeners, fn)
	s.mu.Unlock()
	return func() {
		s.mu.Lock()
		s.stopped = true
		s.listeners = nil
		s.mu.Unlock()
	}
}

func (s *programSource) emit(id string, event ports.TerminalProgramEvent) {
	s.mu.Lock()
	if event.Kind == ports.TerminalProgramTitle {
		s.titles[id] = event.Title
	}
	listeners := append([]func(string, ports.TerminalProgramEvent){}, s.listeners...)
	s.mu.Unlock()
	for _, fn := range listeners {
		fn(id, event)
	}
}

func (s *programSource) watchStopped() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.stopped
}

func assertNoProgramFrame(t *testing.T, c *fakeConn, d time.Duration) {
	t.Helper()
	deadline := time.After(d)
	for {
		select {
		case m := <-c.out:
			if m.Ch == chPrograms {
				t.Fatalf("unexpected program frame %+v", m)
			}
		case <-deadline:
			return
		}
	}
}

func subscribePrograms(t *testing.T, mgr *Manager, c *fakeConn) {
	t.Helper()
	c.in <- clientMsg{Ch: chPrograms, Type: msgSubscribe}
	eventually(t, time.Second, func() bool {
		mgr.mu.Lock()
		defer mgr.mu.Unlock()
		for conn := range mgr.conns {
			conn.mu.Lock()
			subscribed := conn.programsSubscribed
			conn.mu.Unlock()
			if subscribed {
				return true
			}
		}
		return false
	})
}

func TestProgramEventsReachOnlySubscribedConnections(t *testing.T) {
	src := newProgramSource(&fakeSource{alive: true})
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	subscribed := serveConn(t, mgr, false)
	other := serveConn(t, mgr, false)
	subscribePrograms(t, mgr, subscribed)

	src.emit("sess-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "Number list"})
	title := recv(t, subscribed, chPrograms, msgTitle, time.Second)
	if title.ID != "sess-1" || title.Title != "Number list" {
		t.Fatalf("title frame = %+v", title)
	}
	src.emit("sess-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramNotification, Title: "Build", Body: "done"})
	note := recv(t, subscribed, chPrograms, msgNotification, time.Second)
	if note.ID != "sess-1" || note.Title != "Build" || note.Body != "done" {
		t.Fatalf("notification frame = %+v", note)
	}
	assertNoProgramFrame(t, other, 100*time.Millisecond)
}

func TestSubscribingToProgramsSendsEveryKnownTitle(t *testing.T) {
	src := newProgramSource(&fakeSource{alive: true})
	src.titles["sess-1"] = "Refactor"
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := serveConn(t, mgr, false)
	conn.in <- clientMsg{Ch: chPrograms, Type: msgSubscribe}
	got := recv(t, conn, chPrograms, msgTitle, time.Second)
	if got.ID != "sess-1" || got.Title != "Refactor" {
		t.Fatalf("snapshot frame = %+v", got)
	}
	conn.in <- clientMsg{Ch: chPrograms, Type: msgSubscribe}
	assertNoProgramFrame(t, conn, 100*time.Millisecond)
}

func TestUnsubscribingFromProgramsStopsTheFrames(t *testing.T) {
	src := newProgramSource(&fakeSource{alive: true})
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := serveConn(t, mgr, false)
	subscribePrograms(t, mgr, conn)
	conn.in <- clientMsg{Ch: chPrograms, Type: msgUnsubscribe}
	eventually(t, time.Second, func() bool {
		mgr.mu.Lock()
		defer mgr.mu.Unlock()
		for c := range mgr.conns {
			c.mu.Lock()
			subscribed := c.programsSubscribed
			c.mu.Unlock()
			if subscribed {
				return false
			}
		}
		return true
	})
	src.emit("sess-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "ignored"})
	assertNoProgramFrame(t, conn, 100*time.Millisecond)
}

func TestClosingTheManagerStopsTheProgramWatch(t *testing.T) {
	src := newProgramSource(&fakeSource{alive: true})
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	if src.watchStopped() {
		t.Fatal("watch stopped before Close")
	}
	mgr.Close()
	if !src.watchStopped() {
		t.Fatal("Close left the program watch running")
	}
}

type appearancePTY struct {
	*fakePTY
	mu      sync.Mutex
	applied []ports.TerminalAppearance
}

func (p *appearancePTY) SetAppearance(appearance ports.TerminalAppearance) error {
	p.mu.Lock()
	p.applied = append(p.applied, appearance)
	p.mu.Unlock()
	return nil
}

func (p *appearancePTY) appearances() []ports.TerminalAppearance {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]ports.TerminalAppearance(nil), p.applied...)
}

func TestAppearanceReachesTheStreamAndIsReappliedOnReattach(t *testing.T) {
	first := &appearancePTY{fakePTY: newFakePTY()}
	second := &appearancePTY{fakePTY: newFakePTY()}
	streams := []*appearancePTY{first, second}
	var mu sync.Mutex
	next := 0
	src := &fakeSource{alive: true}
	src.attachFn = func(context.Context, uint16, uint16) (ports.Stream, error) {
		mu.Lock()
		defer mu.Unlock()
		if next < len(streams) {
			stream := streams[next]
			next++
			return stream, nil
		}
		return newFakePTY(), nil
	}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := serveConn(t, mgr, false)
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen, Cols: 80, Rows: 24}
	recv(t, conn, chTerminal, msgOpened, time.Second)

	want := ports.TerminalAppearance{CellWidth: 16, CellHeight: 34, Foreground: "#ffffff", Background: "#1d2022"}
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgAppearance, CellWidth: 16, CellHeight: 34, Foreground: "#ffffff", Background: "#1d2022"}
	eventually(t, time.Second, func() bool {
		got := first.appearances()
		return len(got) == 1 && got[0] == want
	})

	_ = first.Close()
	eventually(t, 3*time.Second, func() bool {
		got := second.appearances()
		return len(got) == 1 && got[0] == want
	})
}

func TestAppearanceForAnUnknownTerminalIsIgnored(t *testing.T) {
	src := &fakeSource{alive: true}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := serveConn(t, mgr, false)
	conn.in <- clientMsg{Ch: chTerminal, ID: "missing", Type: msgAppearance, CellWidth: 8, CellHeight: 16}
	conn.in <- clientMsg{Ch: chSystem, Type: msgPing}
	recv(t, conn, chSystem, msgPong, time.Second)
}

type slowSnapshotSource struct {
	*programSource
	entered chan struct{}
	release chan struct{}
}

func (s *slowSnapshotSource) TerminalTitles() map[string]string {
	snapshot := s.programSource.TerminalTitles()
	close(s.entered)
	<-s.release
	return snapshot
}

func TestATitleClearedDuringSubscribeIsNotOverwrittenByTheSnapshot(t *testing.T) {
	src := &slowSnapshotSource{programSource: newProgramSource(&fakeSource{alive: true}), entered: make(chan struct{}), release: make(chan struct{})}
	src.titles["sess-1"] = "Task"
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := serveConn(t, mgr, false)
	conn.in <- clientMsg{Ch: chPrograms, Type: msgSubscribe}
	<-src.entered
	go src.emit("sess-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle})
	time.Sleep(50 * time.Millisecond)
	close(src.release)
	first := recv(t, conn, chPrograms, msgTitle, time.Second)
	second := recv(t, conn, chPrograms, msgTitle, time.Second)
	if first.Title != "Task" || second.Title != "" {
		t.Fatalf("title frames = %q then %q, want the snapshot then the clear", first.Title, second.Title)
	}
}
