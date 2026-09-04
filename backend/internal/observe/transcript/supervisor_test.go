package transcript

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	usagepipeline "github.com/OmarAly92/operator/backend/internal/observe/usage"
)

type fakeSessions struct{ sessions []domain.SessionRecord }

func (f *fakeSessions) ListAllSessions(context.Context) ([]domain.SessionRecord, error) {
	return f.sessions, nil
}

type fakeWatcher struct {
	events chan usagepipeline.TranscriptEvent
	errors chan error
	built  [][]string
}

func newFakeWatcher() *fakeWatcher {
	return &fakeWatcher{
		events: make(chan usagepipeline.TranscriptEvent, 4),
		errors: make(chan error, 4),
	}
}

func (w *fakeWatcher) Events() <-chan usagepipeline.TranscriptEvent { return w.events }
func (w *fakeWatcher) Errors() <-chan error                         { return w.errors }
func (w *fakeWatcher) Start(context.Context) <-chan struct{} {
	done := make(chan struct{})
	close(done)
	return done
}

func (w *fakeWatcher) Rebuild(_ context.Context, paths []string) error {
	w.built = append(w.built, append([]string(nil), paths...))
	return nil
}

func session(id, harness, transcriptPath string, terminated bool) domain.SessionRecord {
	rec := domain.SessionRecord{
		ID:           domain.SessionID(id),
		Harness:      domain.AgentHarness(harness),
		IsTerminated: terminated,
	}
	rec.Metadata.NativeTranscriptPath = transcriptPath
	return rec
}

func newSupervisor(t *testing.T, sessions *fakeSessions, sink Sink, offsets OffsetStore, watcher Watcher, configDir string) *Supervisor {
	t.Helper()
	return NewSupervisor(Deps{
		Sessions: sessions,
		Offsets:  offsets,
		Sink:     sink,
		Resolver: NewResolver(fakeResolver{agent: &fakeAgent{configDir: configDir}}),
		Watcher:  watcher,
	})
}

func TestReconcileTailsOnlyLiveMappedSessions(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	live := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "live.jsonl")
	dead := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "dead.jsonl")

	sessions := &fakeSessions{sessions: []domain.SessionRecord{
		session("s-live", "claude-code", live, false),
		session("s-dead", "claude-code", dead, true),
		session("s-unmapped", "opencode", live, false),
	}}
	watcher := newFakeWatcher()
	sup := newSupervisor(t, sessions, &fakeSink{}, &fakeOffsets{}, watcher, configDir)

	sup.reconcile(context.Background())

	if len(sup.tails) != 1 {
		t.Fatalf("tails = %d, want only the live mapped session", len(sup.tails))
	}
	if _, ok := sup.tails["s-live"]; !ok {
		t.Fatalf("tails = %+v", sup.tails)
	}
	if len(watcher.built) != 1 || len(watcher.built[0]) != 1 {
		t.Fatalf("watch set = %+v", watcher.built)
	}
}

func TestReconcileSeedsTheCursorFromTheStore(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "live.jsonl")
	resolved, _ := filepath.EvalSymlinks(path)
	appendLines(t, path, assistantLine)

	sessions := &fakeSessions{sessions: []domain.SessionRecord{session("s-1", "claude-code", path, false)}}
	offsets := &fakeOffsets{path: resolved, offset: 3, found: true}
	sup := newSupervisor(t, sessions, &fakeSink{}, offsets, newFakeWatcher(), configDir)

	sup.reconcile(context.Background())

	if got := sup.tails["s-1"].offset; got != 3 {
		t.Fatalf("offset = %d want the persisted 3", got)
	}
}

func TestReconcileResetsTheCursorWhenThePathChanges(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "live.jsonl")

	sessions := &fakeSessions{sessions: []domain.SessionRecord{session("s-1", "claude-code", path, false)}}
	offsets := &fakeOffsets{path: "/somewhere/else.jsonl", offset: 9000, found: true}
	sup := newSupervisor(t, sessions, &fakeSink{}, offsets, newFakeWatcher(), configDir)

	sup.reconcile(context.Background())

	if got := sup.tails["s-1"].offset; got != 0 {
		t.Fatalf("offset = %d want 0 for a different file", got)
	}
}

func TestReconcileSkipsResolutionForAnAlreadyTrackedLivePath(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "sessions"), "rollout.jsonl")

	agent := &fakeAgent{configDir: configDir, located: path, found: true}
	sessions := &fakeSessions{sessions: []domain.SessionRecord{session("s-1", "codex", "", false)}}
	sessions.sessions[0].Metadata.AgentSessionID = "native-1"
	sup := NewSupervisor(Deps{
		Sessions: sessions,
		Offsets:  &fakeOffsets{},
		Sink:     &fakeSink{},
		Resolver: NewResolver(fakeResolver{agent: agent}),
		Watcher:  newFakeWatcher(),
	})

	sup.reconcile(context.Background())
	if agent.pathCalls != 1 || agent.locateCall != 1 {
		t.Fatalf("first reconcile: pathCalls=%d locateCall=%d, want 1 each", agent.pathCalls, agent.locateCall)
	}

	sup.reconcile(context.Background())
	if agent.pathCalls != 1 || agent.locateCall != 1 {
		t.Fatalf("second reconcile re-resolved an already-tracked live path: pathCalls=%d locateCall=%d, want unchanged at 1 each", agent.pathCalls, agent.locateCall)
	}
	if _, ok := sup.tails["s-1"]; !ok {
		t.Fatalf("tails = %+v", sup.tails)
	}
}

func TestReconcileReResolvesWhenTheTrackedPathDisappears(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	dir := filepath.Join(configDir, "sessions")
	oldPath := writeTranscript(t, dir, "old.jsonl")
	newPath := writeTranscript(t, dir, "new.jsonl")

	agent := &fakeAgent{configDir: configDir, located: oldPath, found: true}
	sessions := &fakeSessions{sessions: []domain.SessionRecord{session("s-1", "codex", "", false)}}
	sessions.sessions[0].Metadata.AgentSessionID = "native-1"
	sup := NewSupervisor(Deps{
		Sessions: sessions,
		Offsets:  &fakeOffsets{},
		Sink:     &fakeSink{},
		Resolver: NewResolver(fakeResolver{agent: agent}),
		Watcher:  newFakeWatcher(),
	})

	sup.reconcile(context.Background())
	if agent.locateCall != 1 {
		t.Fatalf("first reconcile: locateCall=%d, want 1", agent.locateCall)
	}

	if err := os.Remove(oldPath); err != nil {
		t.Fatalf("remove: %v", err)
	}
	agent.located = newPath

	sup.reconcile(context.Background())
	if agent.locateCall != 2 {
		t.Fatalf("reconcile after path disappeared did not re-resolve: locateCall=%d, want 2", agent.locateCall)
	}
	want, _ := filepath.EvalSymlinks(newPath)
	if got := sup.tails["s-1"].path; got != want {
		t.Fatalf("path = %q want %q", got, want)
	}
	if got := sup.tails["s-1"].offset; got != 0 {
		t.Fatalf("offset = %d want 0 after the path changed", got)
	}
}

func TestPumpAllEmitsForEveryTail(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "live.jsonl")
	appendLines(t, path, assistantLine)

	sessions := &fakeSessions{sessions: []domain.SessionRecord{session("s-1", "claude-code", path, false)}}
	sink := &fakeSink{}
	sup := newSupervisor(t, sessions, sink, &fakeOffsets{}, newFakeWatcher(), configDir)

	sup.reconcile(context.Background())
	sup.pumpAll(context.Background())

	if len(sink.recorded()) == 0 {
		t.Fatal("pumpAll emitted nothing")
	}
	before := len(sink.recorded())
	sup.pumpAll(context.Background())
	if len(sink.recorded()) != before {
		t.Fatal("a second pump with no new bytes must emit nothing")
	}
}

func TestStartStopsWithTheContext(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "live.jsonl")
	appendLines(t, path, assistantLine)

	sessions := &fakeSessions{sessions: []domain.SessionRecord{session("s-1", "claude-code", path, false)}}
	sink := &fakeSink{}
	sup := NewSupervisor(Deps{
		Sessions: sessions,
		Offsets:  &fakeOffsets{},
		Sink:     sink,
		Resolver: NewResolver(fakeResolver{agent: &fakeAgent{configDir: configDir}}),
		Watcher:  newFakeWatcher(),
		Interval: 10 * time.Millisecond,
	})

	ctx, cancel := context.WithCancel(context.Background())
	done := sup.Start(ctx)
	deadline := time.After(2 * time.Second)
	for len(sink.recorded()) == 0 {
		select {
		case <-deadline:
			cancel()
			<-done
			t.Fatal("supervisor emitted nothing before the deadline")
		case <-time.After(5 * time.Millisecond):
		}
	}
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("supervisor did not stop with its context")
	}
	_ = os.Remove(path)
}
