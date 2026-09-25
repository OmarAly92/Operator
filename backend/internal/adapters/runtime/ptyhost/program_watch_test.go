package ptyhost

import (
	"context"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type programRecorder struct {
	mu     sync.Mutex
	events []programRecord
}

type programRecord struct {
	id    string
	event ports.TerminalProgramEvent
}

func (p *programRecorder) record(id string, event ports.TerminalProgramEvent) {
	p.mu.Lock()
	p.events = append(p.events, programRecord{id: id, event: event})
	p.mu.Unlock()
}

func (p *programRecorder) waitFor(t *testing.T, want programRecord) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for {
		p.mu.Lock()
		for _, got := range p.events {
			if reflect.DeepEqual(got, want) {
				p.mu.Unlock()
				return
			}
		}
		seen := append([]programRecord(nil), p.events...)
		p.mu.Unlock()
		if time.Now().After(deadline) {
			t.Fatalf("never saw %+v; saw %+v", want, seen)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func (p *programRecorder) count() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.events)
}

func watchedRuntime(t *testing.T, id string, f *serveFixture) (*Runtime, *programRecorder) {
	t.Helper()
	isolateRegistry(t)
	rt := New(Options{})
	sess := &hostSession{addr: f.addr, pid: livePID()}
	rt.sessions[id] = sess
	rec := &programRecorder{}
	stop := rt.WatchTerminalPrograms(rec.record)
	t.Cleanup(stop)
	t.Cleanup(func() { rt.stopProgramWatch(id) })
	rt.ensureProgramWatch(id, sess)
	waitWatchers(t, f, 1)
	return rt, rec
}

func waitWatchers(t *testing.T, f *serveFixture, want int) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for watcherCount(f) != want {
		if time.Now().After(deadline) {
			t.Fatalf("host watchers = %d, want %d", watcherCount(f), want)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestTheProgramWatchDeliversStrippedTitlesAndNotifications(t *testing.T) {
	f := startServeParsed(t, 921, 80, 24)
	defer f.cancel()
	rt, rec := watchedRuntime(t, "sess-a", f)

	writeOutput(t, f, "\x1b]0;◐ Number list 1 to 3000\x07\x1b]9;done\x07")
	rec.waitFor(t, programRecord{id: "sess-a", event: ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "Number list 1 to 3000"}})
	rec.waitFor(t, programRecord{id: "sess-a", event: ports.TerminalProgramEvent{Kind: ports.TerminalProgramNotification, Body: "done"}})
	if got := rt.TerminalTitles(); !reflect.DeepEqual(got, map[string]string{"sess-a": "Number list 1 to 3000"}) {
		t.Fatalf("titles = %v", got)
	}
}

func TestStoppingTheProgramWatchClosesItAndClearsTheTitle(t *testing.T) {
	f := startServeParsed(t, 922, 80, 24)
	defer f.cancel()
	rt, rec := watchedRuntime(t, "sess-b", f)
	writeOutput(t, f, "\x1b]2;◐ Task\x07")
	rec.waitFor(t, programRecord{id: "sess-b", event: ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "Task"}})

	rt.stopProgramWatch("sess-b")
	waitWatchers(t, f, 0)
	rec.waitFor(t, programRecord{id: "sess-b", event: ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle}})
	if got := rt.TerminalTitles(); len(got) != 0 {
		t.Fatalf("titles after stop = %v, want none", got)
	}
	rt.programMu.Lock()
	_, running := rt.programWatches["sess-b"]
	rt.programMu.Unlock()
	if running {
		t.Fatal("stopped watch is still registered")
	}
}

func TestEnsuringAWatchTwiceOpensOneConnection(t *testing.T) {
	f := startServeParsed(t, 923, 80, 24)
	defer f.cancel()
	rt, _ := watchedRuntime(t, "sess-c", f)
	rt.mu.Lock()
	sess := rt.sessions["sess-c"]
	rt.mu.Unlock()
	rt.ensureProgramWatch("sess-c", sess)
	rt.ensureProgramWatch("sess-c", sess)
	time.Sleep(50 * time.Millisecond)
	if got := watcherCount(f); got != 1 {
		t.Fatalf("host watchers = %d, want 1", got)
	}
}

func TestAnUnsubscribedListenerHearsNothing(t *testing.T) {
	f := startServeParsed(t, 924, 80, 24)
	defer f.cancel()
	rt, rec := watchedRuntime(t, "sess-d", f)
	late := &programRecorder{}
	stop := rt.WatchTerminalPrograms(late.record)
	stop()
	writeOutput(t, f, "\x1b]2;◐ After\x07")
	rec.waitFor(t, programRecord{id: "sess-d", event: ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "After"}})
	if got := late.count(); got != 0 {
		t.Fatalf("unsubscribed listener got %d events", got)
	}
	rt.programMu.Lock()
	listeners := len(rt.programListeners)
	rt.programMu.Unlock()
	if listeners != 1 {
		t.Fatalf("listeners = %d, want 1", listeners)
	}
}

func TestAWatchThatDropsIsRestartedByTheNextLiveProbe(t *testing.T) {
	f := startServeParsed(t, 925, 80, 24)
	defer f.cancel()
	rt, rec := watchedRuntime(t, "sess-e", f)
	f.host.mu.Lock()
	for conn := range f.host.watchers {
		_ = conn.Close()
	}
	f.host.mu.Unlock()
	waitWatchers(t, f, 0)
	deadline := time.Now().Add(2 * time.Second)
	for {
		rt.programMu.Lock()
		_, running := rt.programWatches["sess-e"]
		rt.programMu.Unlock()
		if !running {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("dropped watch never unregistered")
		}
		time.Sleep(5 * time.Millisecond)
	}

	alive, err := rt.IsAlive(context.Background(), ports.RuntimeHandle{ID: "sess-e"})
	if err != nil || !alive {
		t.Fatalf("IsAlive = %v, %v", alive, err)
	}
	waitWatchers(t, f, 1)
	writeOutput(t, f, "\x1b]2;◐ Back\x07")
	rec.waitFor(t, programRecord{id: "sess-e", event: ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "Back"}})
}

func TestAStreamSendsItsAppearanceToTheHost(t *testing.T) {
	f := startServeParsed(t, 926, 80, 24)
	defer f.cancel()
	isolateRegistry(t)
	rt := New(Options{})
	rt.sessions["sess-f"] = &hostSession{addr: f.addr, pid: livePID()}
	t.Cleanup(func() { rt.stopProgramWatch("sess-f") })
	stream, err := rt.Attach(context.Background(), ports.RuntimeHandle{ID: "sess-f"}, 24, 80)
	if err != nil {
		t.Fatalf("attach: %v", err)
	}
	defer stream.Close()
	setter, ok := stream.(ports.AppearanceSetter)
	if !ok {
		t.Fatal("the loopback stream does not accept an appearance")
	}
	if err := setter.SetAppearance(ports.TerminalAppearance{CellWidth: 7, CellHeight: 15}); err != nil {
		t.Fatalf("set appearance: %v", err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for {
		f.host.mu.Lock()
		appearance := f.host.appearance
		f.host.mu.Unlock()
		if appearance != nil {
			if appearance.CellWidth != 7 || appearance.CellHeight != 15 {
				t.Fatalf("host appearance = %+v", *appearance)
			}
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("host never received the appearance")
		}
		time.Sleep(5 * time.Millisecond)
	}
}
