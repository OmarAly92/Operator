package daemon

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	shelltermsvc "github.com/OmarAly92/operator/backend/internal/service/shellterm"
	terminalblocksvc "github.com/OmarAly92/operator/backend/internal/service/terminalblock"
	capturesvc "github.com/OmarAly92/operator/backend/internal/service/terminalcapture"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite"
	journal "github.com/OmarAly92/operator/backend/internal/terminalcapture"
)

// fakeSessionGetter stands in for the real session service so sessionWorkspaceLocator
// can be tested without a full session stack.
type fakeSessionGetter struct {
	sessions map[domain.SessionID]domain.Session
	err      error
}

func (f *fakeSessionGetter) Get(_ context.Context, id domain.SessionID) (domain.Session, error) {
	if f.err != nil {
		return domain.Session{}, f.err
	}
	sess, ok := f.sessions[id]
	if !ok {
		return domain.Session{}, errors.New("session not found")
	}
	return sess, nil
}

// TestSessionWorkspaceLocator_ReturnsPathWhenItStillExists is the ordinary
// live-session case: the worktree is still on disk, so the shell opens there.
func TestSessionWorkspaceLocator_ReturnsPathWhenItStillExists(t *testing.T) {
	dir := t.TempDir()
	getter := &fakeSessionGetter{sessions: map[domain.SessionID]domain.Session{
		"mer-1": {SessionRecord: domain.SessionRecord{
			ID: "mer-1", ProjectID: "mer",
			Metadata: domain.SessionMetadata{WorkspacePath: dir},
		}},
	}}
	loc := &sessionWorkspaceLocator{sessions: getter}

	path, projectID, err := loc.SessionWorkspace(context.Background(), "mer-1")
	if err != nil {
		t.Fatalf("SessionWorkspace: %v", err)
	}
	if path != dir {
		t.Errorf("path = %q, want %q", path, dir)
	}
	if projectID != "mer" {
		t.Errorf("projectID = %q, want mer", projectID)
	}
}

// TestSessionWorkspaceLocator_FallsBackWhenRecordedPathWasRemoved is the
// regression this covers: Kill/Cleanup can reclaim a worktree without
// clearing the session's durable Metadata.WorkspacePath (that field doubles
// as "what to recreate on restore"). A shell opened against an archived
// session must not trust a path that no longer exists — it must signal "no
// workspace" so the caller falls back to the project root instead of trying
// to chdir into nothing.
func TestSessionWorkspaceLocator_FallsBackWhenRecordedPathWasRemoved(t *testing.T) {
	dir := t.TempDir()
	removed := filepath.Join(dir, "worktree-that-is-gone")
	getter := &fakeSessionGetter{sessions: map[domain.SessionID]domain.Session{
		"mer-1": {SessionRecord: domain.SessionRecord{
			ID: "mer-1", ProjectID: "mer",
			Metadata: domain.SessionMetadata{WorkspacePath: removed},
		}},
	}}
	loc := &sessionWorkspaceLocator{sessions: getter}

	path, projectID, err := loc.SessionWorkspace(context.Background(), "mer-1")
	if err != nil {
		t.Fatalf("SessionWorkspace: %v", err)
	}
	if path != "" {
		t.Errorf("path = %q, want empty so the caller falls back to the project root", path)
	}
	if projectID != "mer" {
		t.Errorf("projectID = %q, want mer even on fallback", projectID)
	}
}

// TestSessionWorkspaceLocator_KeepsDirtyPreservedWorktree: a worktree Kill
// refused to remove because of uncommitted work still exists on disk, so it
// must be returned as-is, not treated as reclaimed.
func TestSessionWorkspaceLocator_KeepsDirtyPreservedWorktree(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "uncommitted.txt"), []byte("wip"), 0o644); err != nil {
		t.Fatal(err)
	}
	getter := &fakeSessionGetter{sessions: map[domain.SessionID]domain.Session{
		"mer-1": {SessionRecord: domain.SessionRecord{
			ID: "mer-1", ProjectID: "mer",
			Metadata: domain.SessionMetadata{WorkspacePath: dir},
		}},
	}}
	loc := &sessionWorkspaceLocator{sessions: getter}

	path, _, err := loc.SessionWorkspace(context.Background(), "mer-1")
	if err != nil {
		t.Fatalf("SessionWorkspace: %v", err)
	}
	if path != dir {
		t.Errorf("path = %q, want the preserved worktree %q", path, dir)
	}
}

func TestSessionWorkspaceLocator_NoWorkspacePathPassesThrough(t *testing.T) {
	getter := &fakeSessionGetter{sessions: map[domain.SessionID]domain.Session{
		"mer-orch": {SessionRecord: domain.SessionRecord{ID: "mer-orch", ProjectID: "mer"}},
	}}
	loc := &sessionWorkspaceLocator{sessions: getter}

	path, projectID, err := loc.SessionWorkspace(context.Background(), "mer-orch")
	if err != nil {
		t.Fatalf("SessionWorkspace: %v", err)
	}
	if path != "" {
		t.Errorf("path = %q, want empty", path)
	}
	if projectID != "mer" {
		t.Errorf("projectID = %q, want mer", projectID)
	}
}

func TestSessionWorkspaceLocator_PropagatesUnknownSessionError(t *testing.T) {
	loc := &sessionWorkspaceLocator{sessions: &fakeSessionGetter{}}

	if _, _, err := loc.SessionWorkspace(context.Background(), "ghost"); err == nil {
		t.Fatal("SessionWorkspace: want error for an unknown session")
	}
}

type wiringLog struct {
	mu sync.Mutex
	ev []string
}

func (l *wiringLog) add(s string) {
	l.mu.Lock()
	l.ev = append(l.ev, s)
	l.mu.Unlock()
}

func (l *wiringLog) index(s string) int {
	l.mu.Lock()
	defer l.mu.Unlock()
	for i, v := range l.ev {
		if v == s {
			return i
		}
	}
	return -1
}

type wiringFakeRuntime struct {
	log   *wiringLog
	alive map[string]bool
}

func (f *wiringFakeRuntime) Create(context.Context, ports.RuntimeConfig) (ports.RuntimeHandle, error) {
	return ports.RuntimeHandle{}, errors.New("not used")
}

func (f *wiringFakeRuntime) Destroy(_ context.Context, h ports.RuntimeHandle) error {
	f.log.add("destroy:" + h.ID)
	delete(f.alive, h.ID)
	return nil
}

func (f *wiringFakeRuntime) IsAlive(_ context.Context, h ports.RuntimeHandle) (bool, error) {
	f.log.add("isalive:" + h.ID)
	return f.alive[h.ID], nil
}

type wiringFakeCapturer struct {
	log        *wiringLog
	state      map[string]ports.PaneCaptureState
	startCount int
}

func (f *wiringFakeCapturer) CaptureState(_ context.Context, h ports.RuntimeHandle) (ports.PaneCaptureState, error) {
	f.log.add("state:" + h.ID)
	return f.state[h.ID], nil
}

func (f *wiringFakeCapturer) StartCapture(_ context.Context, h ports.RuntimeHandle, _ []string) error {
	f.log.add("start:" + h.ID)
	f.startCount++
	return nil
}

func (f *wiringFakeCapturer) StopCapture(_ context.Context, h ports.RuntimeHandle) error {
	f.log.add("stop:" + h.ID)
	return nil
}

func wiringLogger() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func TestStartShellTerminalsAdoptsCurrentRunCaptureOnBoot(t *testing.T) {
	dataDir := t.TempDir()
	store, err := sqlite.Open(dataDir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { _ = store.Close() })
	ctx := context.Background()

	const handleID = "shellterm-live"
	const epoch = "11111111-1111-1111-1111-111111111111"
	cfg := config.Config{DataDir: dataDir, AppRunID: "run-current", ShutdownTimeout: 3 * time.Second}

	if err := store.InsertShellTerminal(ctx, shelltermsvc.ShellTerminalRecord{
		HandleID: handleID, WorkingDir: dataDir, Title: "live", AppRunID: cfg.AppRunID, CreatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("insert shell terminal: %v", err)
	}
	if err := store.InsertShellTerminal(ctx, shelltermsvc.ShellTerminalRecord{
		HandleID: "shellterm-orphan", WorkingDir: dataDir, Title: "orphan", AppRunID: "run-old", CreatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("insert orphan: %v", err)
	}

	epochDir := filepath.Join(journal.CaptureRoot(dataDir), handleID, epoch)
	if err := os.MkdirAll(epochDir, 0o700); err != nil {
		t.Fatal(err)
	}
	blockBytes := []byte("\x1b]133;A\x07guest$ echo hi\x1b]133;C\x07hi\n\x1b]133;D;0\x07")
	if err := os.WriteFile(filepath.Join(epochDir, journal.SegmentName(1, journal.OpenSuffix)), blockBytes, 0o600); err != nil {
		t.Fatal(err)
	}

	log := &wiringLog{}
	rt := &wiringFakeRuntime{log: log, alive: map[string]bool{handleID: true}}
	capr := &wiringFakeCapturer{log: log, state: map[string]ports.PaneCaptureState{handleID: {PipeOpen: true}}}
	blocks := terminalblocksvc.NewService(store)
	sup := capturesvc.NewSupervisor(capr, blocks, dataDir, 3*time.Second, wiringLogger())
	t.Cleanup(func() { _ = sup.DrainAndDetach(context.Background()) })

	_ = startShellTerminals(ctx, cfg, rt, store, nil, nil, sup, wiringLogger())

	deadline := time.Now().Add(3 * time.Second)
	var got []domain.Block
	for time.Now().Before(deadline) {
		got, err = blocks.History(ctx, handleID, 10)
		if err != nil {
			t.Fatalf("History: %v", err)
		}
		if len(got) > 0 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if len(got) == 0 {
		t.Fatal("no terminal block recorded — the boot path did not adopt the current run's capture")
	}

	if di, si := log.index("destroy:shellterm-orphan"), log.index("state:"+handleID); di < 0 || si < 0 || di > si {
		t.Fatalf("event order = %v, want reap (destroy orphan) before Adopt (state query)", log.ev)
	}
	if ai, si := log.index("isalive:"+handleID), log.index("state:"+handleID); ai < 0 || si < 0 || ai > si {
		t.Fatalf("event order = %v, want liveness probe before Adopt", log.ev)
	}
	if capr.startCount != 0 {
		t.Fatalf("StartCapture called %d times for an already-piped pane, want 0", capr.startCount)
	}
}
