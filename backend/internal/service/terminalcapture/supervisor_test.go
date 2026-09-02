package terminalcapture

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/service/shellterm"
	"github.com/OmarAly92/operator/backend/internal/service/terminalblock"
	journal "github.com/OmarAly92/operator/backend/internal/terminalcapture"
)

const testEpoch = "11111111-1111-1111-1111-111111111111"

func block(cmd, out string, exit int) string {
	return "\x1b]133;A\x07guest$ " + cmd + "\x1b]133;C\x07" + out + "\n\x1b]133;D;" + itoa(exit) + "\x07"
}

func itoa(n int) string {
	b, _ := json.Marshal(n)
	return string(b)
}

type eventLog struct {
	mu sync.Mutex
	ev []string
}

func (e *eventLog) add(s string) {
	e.mu.Lock()
	e.ev = append(e.ev, s)
	e.mu.Unlock()
}

func (e *eventLog) snapshot() []string {
	e.mu.Lock()
	defer e.mu.Unlock()
	return append([]string(nil), e.ev...)
}

func (e *eventLog) indexOf(s string) int {
	for i, v := range e.snapshot() {
		if v == s {
			return i
		}
	}
	return -1
}

func (e *eventLog) firstPrefix(p string) int {
	for i, v := range e.snapshot() {
		if len(v) >= len(p) && v[:len(p)] == p {
			return i
		}
	}
	return -1
}

type fakeCapturer struct {
	mu    sync.Mutex
	log   *eventLog
	calls []string

	state       map[string]ports.PaneCaptureState
	stateErr    map[string]error
	unsupported bool
	startErr    error
	sealOnStop  bool

	startCount   int
	stopCount    int
	epochDirByID map[string]string
}

func newFakeCapturer(log *eventLog) *fakeCapturer {
	return &fakeCapturer{
		log:          log,
		state:        map[string]ports.PaneCaptureState{},
		stateErr:     map[string]error{},
		epochDirByID: map[string]string{},
	}
}

func (f *fakeCapturer) CaptureState(_ context.Context, h ports.RuntimeHandle) (ports.PaneCaptureState, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, "state:"+h.ID)
	if f.log != nil {
		f.log.add("state:" + h.ID)
	}
	if f.unsupported {
		return ports.PaneCaptureState{}, ports.ErrCaptureUnsupported
	}
	if err := f.stateErr[h.ID]; err != nil {
		return ports.PaneCaptureState{}, err
	}
	return f.state[h.ID], nil
}

func (f *fakeCapturer) StartCapture(_ context.Context, h ports.RuntimeHandle, argv []string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, "start:"+h.ID)
	if f.log != nil {
		f.log.add("start:" + h.ID)
	}
	if f.unsupported {
		return ports.ErrCaptureUnsupported
	}
	if f.startErr != nil {
		return f.startErr
	}
	f.startCount++
	dir, epoch := parseArgv(argv)
	if dir != "" && epoch != "" {
		f.epochDirByID[h.ID] = filepath.Join(dir, epoch)
	}
	return nil
}

func (f *fakeCapturer) StopCapture(_ context.Context, h ports.RuntimeHandle) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, "stop:"+h.ID)
	if f.log != nil {
		f.log.add("stop:" + h.ID)
	}
	f.stopCount++
	if f.sealOnStop {
		if d := f.epochDirByID[h.ID]; d != "" {
			_ = os.MkdirAll(d, 0o700)
			raw, _ := json.Marshal(journal.Manifest{Epoch: filepath.Base(d)})
			_ = os.WriteFile(filepath.Join(d, journal.ManifestFileName), raw, 0o600)
		}
	}
	return nil
}

func parseArgv(argv []string) (dir, epoch string) {
	for i := 0; i < len(argv)-1; i++ {
		switch argv[i] {
		case "--dir":
			dir = argv[i+1]
		case "--epoch":
			epoch = argv[i+1]
		}
	}
	return dir, epoch
}

type fakeBlockStore struct {
	mu         sync.Mutex
	log        *eventLog
	byKey      map[string]domain.Block
	calls      int
	recordErr  error
	recordErrN int
	blockRec   chan struct{}
}

func newFakeBlockStore(log *eventLog) *fakeBlockStore {
	return &fakeBlockStore{log: log, byKey: map[string]domain.Block{}}
}

func (f *fakeBlockStore) UpsertTerminalBlock(ctx context.Context, b domain.Block) error {
	if f.blockRec != nil {
		select {
		case <-f.blockRec:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	key := b.TerminalID + "\x00" + b.SourceID
	_, seen := f.byKey[key]
	if f.recordErr != nil && !seen {
		if f.recordErrN <= 1 || len(f.byKey) == f.recordErrN-1 {
			if f.log != nil {
				f.log.add("record-err:" + key)
			}
			return f.recordErr
		}
	}
	f.byKey[key] = b
	if f.log != nil {
		f.log.add("record:" + key)
	}
	return nil
}

func (f *fakeBlockStore) ListTerminalBlocks(_ context.Context, _ string, _ int) ([]domain.Block, error) {
	return nil, nil
}
func (f *fakeBlockStore) TrimTerminalBlocks(_ context.Context, _ string, _ int) error { return nil }
func (f *fakeBlockStore) DeleteTerminalBlocks(_ context.Context, _ string) error      { return nil }

func (f *fakeBlockStore) distinct() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.byKey)
}

func testLogger() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func newSupervisor(t *testing.T, capturer *fakeCapturer, store *fakeBlockStore, poll time.Duration) *Supervisor {
	t.Helper()
	sup := NewSupervisor(capturer, terminalblock.NewService(store), t.TempDir(), 3*time.Second, testLogger())
	sup.newEpoch = func() string { return testEpoch }
	sup.pollInterval = poll
	sup.now = func() time.Time { return time.Date(2026, 8, 31, 12, 0, 0, 0, time.UTC) }
	t.Cleanup(func() { _ = sup.DrainAndDetach(context.Background()) })
	return sup
}

func mkEpochDir(t *testing.T, epochDir string, sealed bool) {
	t.Helper()
	if err := os.MkdirAll(epochDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(epochDir, journal.SegmentName(1, journal.OpenSuffix)), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if sealed {
		raw, _ := json.Marshal(journal.Manifest{Epoch: filepath.Base(epochDir)})
		if err := os.WriteFile(filepath.Join(epochDir, journal.ManifestFileName), raw, 0o600); err != nil {
			t.Fatal(err)
		}
	}
}

func writeJournalAt(t *testing.T, epochDir string, seal bool, payload []byte) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(epochDir), 0o700); err != nil {
		t.Fatal(err)
	}
	j, err := journal.Open(epochDir)
	if err != nil {
		t.Fatalf("open journal: %v", err)
	}
	if _, err := j.Write(payload); err != nil {
		t.Fatalf("write journal: %v", err)
	}
	if seal {
		if err := j.Close(); err != nil {
			t.Fatalf("close journal: %v", err)
		}
	}
}

func rec(handle string) shellterm.ShellTerminalRecord {
	return shellterm.ShellTerminalRecord{HandleID: handle}
}

func readCursorOffset(t *testing.T, captureDir string) (int64, bool) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(captureDir, "cursor.json"))
	if err != nil {
		return 0, false
	}
	var pc struct {
		Epoch   string `json:"epoch"`
		Segment uint64 `json:"segment"`
		Offset  int64  `json:"offset"`
	}
	if err := json.Unmarshal(raw, &pc); err != nil {
		t.Fatalf("parse cursor.json: %v", err)
	}
	return journal.CaptureCursor{Epoch: pc.Epoch, Segment: pc.Segment, Offset: pc.Offset}.ByteOffset(), true
}

func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

func TestStartSurfacesCaptureFailureOnSupportedRuntime(t *testing.T) {
	capturer := newFakeCapturer(nil)
	capturer.startErr = errors.New("pipe-pane: server not found")
	sup := newSupervisor(t, capturer, newFakeBlockStore(nil), time.Hour)

	err := sup.Start(context.Background(), rec("shellterm-h1"))
	if err == nil {
		t.Fatal("Start: want an error when a supported runtime's StartCapture fails")
	}
	if errors.Is(err, ports.ErrCaptureUnsupported) {
		t.Fatalf("error must not look unsupported: %v", err)
	}
	if sup.hasWorker("shellterm-h1") {
		t.Fatal("a worker was left registered after a failed Start")
	}
}

func TestStartReportsUnsupportedWithoutStartingAWorker(t *testing.T) {
	capturer := newFakeCapturer(nil)
	capturer.unsupported = true
	sup := newSupervisor(t, capturer, newFakeBlockStore(nil), time.Hour)

	err := sup.Start(context.Background(), rec("shellterm-h1"))
	if !errors.Is(err, ports.ErrCaptureUnsupported) {
		t.Fatalf("error = %v, want ErrCaptureUnsupported", err)
	}
	if sup.hasWorker("shellterm-h1") {
		t.Fatal("unsupported capture must not register a worker")
	}
}

func TestStartIsIdempotentUnderConcurrency(t *testing.T) {
	capturer := newFakeCapturer(nil)
	sup := newSupervisor(t, capturer, newFakeBlockStore(nil), time.Hour)

	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := sup.Start(context.Background(), rec("shellterm-h1")); err != nil {
				t.Errorf("Start: %v", err)
			}
		}()
	}
	wg.Wait()

	capturer.mu.Lock()
	starts := capturer.startCount
	capturer.mu.Unlock()
	if starts != 1 {
		t.Fatalf("StartCapture called %d times, want exactly 1", starts)
	}
	sup.mu.Lock()
	n := len(sup.workers)
	sup.mu.Unlock()
	if n != 1 {
		t.Fatalf("workers = %d, want 1", n)
	}
}

func TestAdoptResumesExistingEpochWhenPipeOpen(t *testing.T) {
	capturer := newFakeCapturer(nil)
	capturer.state["shellterm-h1"] = ports.PaneCaptureState{PipeOpen: true, AlternateOn: true}
	store := newFakeBlockStore(nil)
	sup := newSupervisor(t, capturer, store, time.Hour)

	captureDir := sup.captureDir("shellterm-h1")
	mkEpochDir(t, filepath.Join(captureDir, testEpoch), false)

	if err := sup.Adopt(context.Background(), []shellterm.ShellTerminalRecord{rec("shellterm-h1")}); err != nil {
		t.Fatalf("Adopt: %v", err)
	}

	capturer.mu.Lock()
	starts := capturer.startCount
	capturer.mu.Unlock()
	if starts != 0 {
		t.Fatalf("StartCapture called %d times on an already-piped pane, want 0", starts)
	}
	if !sup.hasWorker("shellterm-h1") {
		t.Fatal("Adopt did not spawn a worker for the piped pane")
	}
	sup.mu.Lock()
	epochDir := sup.workers["shellterm-h1"].epochDir
	sup.mu.Unlock()
	if epochDir != filepath.Join(captureDir, testEpoch) {
		t.Fatalf("resumed epoch dir = %q, want the existing one", epochDir)
	}
}

func TestAdoptStartsFreshEpochWhenNoPipe(t *testing.T) {
	capturer := newFakeCapturer(nil)
	capturer.state["shellterm-h1"] = ports.PaneCaptureState{PipeOpen: false}
	sup := newSupervisor(t, capturer, newFakeBlockStore(nil), time.Hour)

	if err := sup.Adopt(context.Background(), []shellterm.ShellTerminalRecord{rec("shellterm-h1")}); err != nil {
		t.Fatalf("Adopt: %v", err)
	}
	capturer.mu.Lock()
	starts, dir := capturer.startCount, capturer.epochDirByID["shellterm-h1"]
	capturer.mu.Unlock()
	if starts != 1 {
		t.Fatalf("StartCapture called %d times, want 1", starts)
	}
	if dir != filepath.Join(sup.captureDir("shellterm-h1"), testEpoch) {
		t.Fatalf("fresh epoch dir = %q", dir)
	}
}

func TestStopAndDrainStopsWriterBeforeDraining(t *testing.T) {
	log := &eventLog{}
	capturer := newFakeCapturer(log)
	capturer.sealOnStop = true
	store := newFakeBlockStore(log)
	sup := newSupervisor(t, capturer, store, time.Hour)

	idle := make(chan string, 1)
	sup.onWorkerIdle = func(handleID string) {
		select {
		case idle <- handleID:
		default:
		}
	}

	if err := sup.Start(context.Background(), rec("shellterm-h1")); err != nil {
		t.Fatalf("Start: %v", err)
	}
	select {
	case <-idle:
	case <-time.After(5 * time.Second):
		t.Fatal("worker never reached its idle poll wait before the journal was written")
	}
	captureDir := sup.captureDir("shellterm-h1")
	writeJournalAt(t, filepath.Join(captureDir, testEpoch), true, []byte(block("echo hi", "hi", 0)))

	if err := sup.StopAndDrain(context.Background(), "shellterm-h1"); err != nil {
		t.Fatalf("StopAndDrain: %v", err)
	}

	stopIdx := log.indexOf("stop:shellterm-h1")
	recIdx := log.firstPrefix("record:")
	if stopIdx < 0 || recIdx < 0 {
		t.Fatalf("missing events: %v", log.snapshot())
	}
	if stopIdx > recIdx {
		t.Fatalf("StopCapture (idx %d) must precede the first recorded block (idx %d): %v", stopIdx, recIdx, log.snapshot())
	}
	if store.distinct() != 1 {
		t.Fatalf("blocks recorded = %d, want 1", store.distinct())
	}
	if off, ok := readCursorOffset(t, captureDir); !ok || off != int64(len(block("echo hi", "hi", 0))) {
		t.Fatalf("cursor offset = %d (present=%v), want end of the block", off, ok)
	}
	if sup.hasWorker("shellterm-h1") {
		t.Fatal("worker still registered after StopAndDrain")
	}
}

func TestDrainAndDetachDrainsButLeavesPipesRunning(t *testing.T) {
	log := &eventLog{}
	capturer := newFakeCapturer(log)
	store := newFakeBlockStore(log)
	sup := newSupervisor(t, capturer, store, time.Hour)

	for _, h := range []string{"shellterm-a", "shellterm-b"} {
		if err := sup.Start(context.Background(), rec(h)); err != nil {
			t.Fatalf("Start %s: %v", h, err)
		}
		writeJournalAt(t, filepath.Join(sup.captureDir(h), testEpoch), true, []byte(block("cmd", "out", 0)))
	}

	if err := sup.DrainAndDetach(context.Background()); err != nil {
		t.Fatalf("DrainAndDetach: %v", err)
	}

	capturer.mu.Lock()
	stops := capturer.stopCount
	capturer.mu.Unlock()
	if stops != 0 {
		t.Fatalf("StopCapture called %d times, want 0 — pipes must stay running", stops)
	}
	for _, h := range []string{"shellterm-a", "shellterm-b"} {
		if _, ok := readCursorOffset(t, sup.captureDir(h)); !ok {
			t.Fatalf("no cursor.json persisted for %s", h)
		}
	}
}

func TestDrainAndDetachJoinsWorkerErrorsAndIsBounded(t *testing.T) {
	capturer := newFakeCapturer(nil)
	store := newFakeBlockStore(nil)
	store.blockRec = make(chan struct{})
	sup := NewSupervisor(capturer, terminalblock.NewService(store), t.TempDir(), 80*time.Millisecond, testLogger())
	sup.newEpoch = func() string { return testEpoch }
	sup.pollInterval = time.Hour

	if err := sup.Start(context.Background(), rec("shellterm-h1")); err != nil {
		t.Fatalf("Start: %v", err)
	}
	writeJournalAt(t, filepath.Join(sup.captureDir("shellterm-h1"), testEpoch), true, []byte(block("cmd", "out", 0)))

	start := time.Now()
	err := sup.DrainAndDetach(context.Background())
	if err == nil {
		t.Fatal("DrainAndDetach: want a joined worker error when a drain cannot complete")
	}
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("DrainAndDetach took %s, want it bounded by the shutdown timeout", elapsed)
	}

	close(store.blockRec)
	_ = sup.DrainAndDetach(context.Background())
}

func TestSupervisorWorkerLiveTailsUnsealedJournal(t *testing.T) {
	capturer := newFakeCapturer(nil)
	store := newFakeBlockStore(nil)
	sup := newSupervisor(t, capturer, store, 5*time.Millisecond)

	if err := sup.Start(context.Background(), rec("shellterm-h1")); err != nil {
		t.Fatalf("Start: %v", err)
	}
	epochDir := filepath.Join(sup.captureDir("shellterm-h1"), testEpoch)
	if err := os.MkdirAll(filepath.Dir(epochDir), 0o700); err != nil {
		t.Fatal(err)
	}
	j, err := journal.Open(epochDir)
	if err != nil {
		t.Fatalf("open journal: %v", err)
	}
	defer j.Close()

	if _, err := j.Write([]byte(block("echo one", "one", 0))); err != nil {
		t.Fatalf("write: %v", err)
	}
	waitFor(t, "first block tailed", func() bool { return store.distinct() == 1 })

	if _, err := j.Write([]byte(block("echo two", "two", 1))); err != nil {
		t.Fatalf("write: %v", err)
	}
	waitFor(t, "second block tailed", func() bool { return store.distinct() == 2 })

	if _, err := os.Stat(filepath.Join(epochDir, journal.ManifestFileName)); err == nil {
		t.Fatal("journal was sealed; the point is a live tail of an UNSEALED journal")
	}
	capturer.mu.Lock()
	stops := capturer.stopCount
	capturer.mu.Unlock()
	if stops != 0 {
		t.Fatal("no StopCapture should have been issued during a live tail")
	}
}

func TestStopAndDrainMidDrainRecordFailure(t *testing.T) {
	capturer := newFakeCapturer(nil)
	capturer.sealOnStop = true
	store := newFakeBlockStore(nil)
	store.recordErr = errors.New("disk full")
	store.recordErrN = 2
	sup := newSupervisor(t, capturer, store, time.Hour)

	if err := sup.Start(context.Background(), rec("shellterm-h1")); err != nil {
		t.Fatalf("Start: %v", err)
	}
	captureDir := sup.captureDir("shellterm-h1")
	b1 := block("echo one", "one", 0)
	b2 := block("echo two", "two", 1)
	writeJournalAt(t, filepath.Join(captureDir, testEpoch), true, []byte(b1+b2))

	err := sup.StopAndDrain(context.Background(), "shellterm-h1")
	if err == nil {
		t.Fatal("StopAndDrain: want an error when a block Record fails mid-drain")
	}
	if store.distinct() != 1 {
		t.Fatalf("distinct blocks persisted = %d, want only the 1st", store.distinct())
	}
	if off, ok := readCursorOffset(t, captureDir); ok && off > int64(len(b1)) {
		t.Fatalf("cursor advanced to %d, past the 1st block's end %d", off, len(b1))
	}
}

func TestCapturingReflectsWorkerMembership(t *testing.T) {
	capturer := newFakeCapturer(nil)
	capturer.sealOnStop = true
	sup := newSupervisor(t, capturer, newFakeBlockStore(nil), time.Hour)

	if sup.Capturing("shellterm-h1") {
		t.Fatal("Capturing = true before any Start")
	}
	if err := sup.Start(context.Background(), rec("shellterm-h1")); err != nil {
		t.Fatalf("Start: %v", err)
	}
	if !sup.Capturing("shellterm-h1") {
		t.Fatal("Capturing = false after Start registered a worker")
	}
	if sup.Capturing("shellterm-other") {
		t.Fatal("Capturing = true for a handle with no worker")
	}

	captureDir := sup.captureDir("shellterm-h1")
	writeJournalAt(t, filepath.Join(captureDir, testEpoch), true, []byte(block("cmd", "out", 0)))
	if err := sup.StopAndDrain(context.Background(), "shellterm-h1"); err != nil {
		t.Fatalf("StopAndDrain: %v", err)
	}
	if sup.Capturing("shellterm-h1") {
		t.Fatal("Capturing = true after StopAndDrain removed the worker")
	}
}

func TestDrainAndDetachIsIdempotentAndPrompt(t *testing.T) {
	capturer := newFakeCapturer(nil)
	sup := newSupervisor(t, capturer, newFakeBlockStore(nil), time.Hour)

	if err := sup.Start(context.Background(), rec("shellterm-h1")); err != nil {
		t.Fatalf("Start: %v", err)
	}
	writeJournalAt(t, filepath.Join(sup.captureDir("shellterm-h1"), testEpoch), true, []byte(block("cmd", "out", 0)))

	if err := sup.DrainAndDetach(context.Background()); err != nil {
		t.Fatalf("first DrainAndDetach: %v", err)
	}
	start := time.Now()
	if err := sup.DrainAndDetach(context.Background()); err != nil {
		t.Fatalf("second DrainAndDetach: %v", err)
	}
	if elapsed := time.Since(start); elapsed > 200*time.Millisecond {
		t.Fatalf("second DrainAndDetach took %s; a repeat call must not re-wait workers", elapsed)
	}
}
