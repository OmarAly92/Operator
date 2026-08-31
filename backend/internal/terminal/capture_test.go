package terminal

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/terminalcapture"
)

const testEpoch = "11111111-1111-1111-1111-111111111111"

type fakeBlockStore struct {
	mu    sync.Mutex
	calls []domain.Block
	byKey map[string]domain.Block
	err   error
}

func (f *fakeBlockStore) Record(_ context.Context, b domain.Block) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	if f.byKey == nil {
		f.byKey = map[string]domain.Block{}
	}
	f.calls = append(f.calls, b)
	f.byKey[b.TerminalID+"\x00"+b.SourceID] = b
	return nil
}

func (f *fakeBlockStore) snapshot() []domain.Block {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := make([]domain.Block, len(f.calls))
	copy(out, f.calls)
	return out
}

func (f *fakeBlockStore) distinct() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.byKey)
}

func writeJournal(t *testing.T, captureDir, epoch string, seal bool, payload []byte) {
	t.Helper()
	j, err := terminalcapture.Open(filepath.Join(captureDir, epoch))
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

func newWorker(t *testing.T, captureDir string, store *fakeBlockStore, alt bool) *CaptureWorker {
	t.Helper()
	return NewCaptureWorker(CaptureWorkerConfig{
		TerminalID:   "term-1",
		SessionID:    "sess-1",
		CaptureDir:   captureDir,
		Epoch:        testEpoch,
		AlternateOn:  alt,
		Recorder:     store,
		Now:          fixedClock(),
		PollInterval: 5 * time.Millisecond,
	})
}

func readCursorFile(t *testing.T, captureDir string) persistedCursor {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(captureDir, "cursor.json"))
	if err != nil {
		t.Fatalf("read cursor.json: %v", err)
	}
	var pc persistedCursor
	if err := json.Unmarshal(raw, &pc); err != nil {
		t.Fatalf("parse cursor.json: %v", err)
	}
	return pc
}

func twoTier1Blocks() ([]byte, string, string) {
	first := "\x1b]133;A\x07guest$ echo one\x1b]133;C\x07one\n\x1b]133;D;0\x07"
	second := "\x1b]133;A\x07guest$ echo two\x1b]133;C\x07two\n\x1b]133;D;1\x07"
	id1 := "osc133-" + testEpoch + "-0"
	id2 := "osc133-" + testEpoch + "-" + itoa(len(first))
	return []byte(first + second), id1, id2
}

func itoa(n int) string {
	return string(jsonNumber(n))
}

func jsonNumber(n int) []byte {
	b, _ := json.Marshal(n)
	return b
}

func TestCaptureWorkerTailsSealedJournalInOrder(t *testing.T) {
	dir := t.TempDir()
	payload, id1, id2 := twoTier1Blocks()
	writeJournal(t, dir, testEpoch, true, payload)

	store := &fakeBlockStore{}
	w := newWorker(t, dir, store, false)
	if err := w.Drain(context.Background(), false); err != nil {
		t.Fatalf("drain: %v", err)
	}

	got := store.snapshot()
	if len(got) != 2 {
		t.Fatalf("recorded %d blocks, want 2", len(got))
	}
	if got[0].SourceID != id1 || got[1].SourceID != id2 {
		t.Fatalf("source ids = %q, %q; want %q, %q", got[0].SourceID, got[1].SourceID, id1, id2)
	}
	if got[0].ExitCode == nil || *got[0].ExitCode != 0 || got[1].ExitCode == nil || *got[1].ExitCode != 1 {
		t.Fatalf("exit codes = %v, %v", got[0].ExitCode, got[1].ExitCode)
	}
	pc := readCursorFile(t, dir)
	if pc.Epoch != testEpoch {
		t.Fatalf("cursor epoch = %q", pc.Epoch)
	}
	if got := (terminalcapture.CaptureCursor{Epoch: pc.Epoch, Segment: pc.Segment, Offset: pc.Offset}).ByteOffset(); got != int64(len(payload)) {
		t.Fatalf("cursor byte offset = %d, want %d", got, len(payload))
	}
}

func TestCaptureWorkerFlushOnlyWhenSealed(t *testing.T) {
	trailing := "\x1b]133;A\x07host$ run\x1b]133;C\x07partial output\x1b]133;"

	t.Run("unsealed writer keeps the incomplete tail out of raw_output", func(t *testing.T) {
		dir := t.TempDir()
		writeJournal(t, dir, testEpoch, false, []byte(trailing))
		store := &fakeBlockStore{}
		w := newWorker(t, dir, store, false)
		if err := w.Drain(context.Background(), true); err != nil {
			t.Fatalf("drain: %v", err)
		}
		got := store.snapshot()
		if len(got) != 1 {
			t.Fatalf("recorded %d blocks, want 1", len(got))
		}
		if bytes.HasSuffix(got[0].RawOutput, []byte("\x1b]133;")) {
			t.Fatalf("unsealed drain must not Flush the pending mark into raw_output: %q", got[0].RawOutput)
		}
	})

	t.Run("sealed writer flushes the incomplete tail into raw_output", func(t *testing.T) {
		dir := t.TempDir()
		writeJournal(t, dir, testEpoch, true, []byte(trailing))
		store := &fakeBlockStore{}
		w := newWorker(t, dir, store, false)
		if err := w.Drain(context.Background(), true); err != nil {
			t.Fatalf("drain: %v", err)
		}
		got := store.snapshot()
		if len(got) != 1 {
			t.Fatalf("recorded %d blocks, want 1", len(got))
		}
		if !bytes.HasSuffix(got[0].RawOutput, []byte("\x1b]133;")) {
			t.Fatalf("sealed drain must Flush the pending mark into raw_output: %q", got[0].RawOutput)
		}
	})
}

func TestCaptureWorkerDrainWithoutFinalLeavesInFlightRecoverable(t *testing.T) {
	dir := t.TempDir()
	complete := "\x1b]133;A\x07u$ done\x1b]133;C\x07ok\n\x1b]133;D;0\x07"
	inflight := "\x1b]133;A\x07u$ sleeping\x1b]133;C\x07still running"
	writeJournal(t, dir, testEpoch, false, []byte(complete+inflight))

	store := &fakeBlockStore{}
	w := newWorker(t, dir, store, false)
	if err := w.Drain(context.Background(), false); err != nil {
		t.Fatalf("drain: %v", err)
	}
	got := store.snapshot()
	if len(got) != 1 {
		t.Fatalf("recorded %d blocks, want 1 (the in-flight command stays recoverable)", len(got))
	}
	if !bytes.Contains(got[0].RawOutput, []byte("ok\n")) {
		t.Fatalf("wrong block persisted: %q", got[0].RawOutput)
	}
}

func TestCaptureWorkerCancellationThenFinalDrainPersistsLastBlock(t *testing.T) {
	dir := t.TempDir()
	j, err := terminalcapture.Open(filepath.Join(dir, testEpoch))
	if err != nil {
		t.Fatalf("open journal: %v", err)
	}

	store := &fakeBlockStore{}
	w := NewCaptureWorker(CaptureWorkerConfig{
		TerminalID:   "term-1",
		SessionID:    "sess-1",
		CaptureDir:   dir,
		Epoch:        testEpoch,
		Recorder:     store,
		Now:          fixedClock(),
		PollInterval: time.Hour,
	})

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- w.Run(ctx) }()

	time.Sleep(50 * time.Millisecond)

	complete := "\x1b]133;A\x07me$ ship\x1b]133;C\x07shipped\n\x1b]133;D;0\x07"
	if _, err := j.Write([]byte(complete)); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := j.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}

	cancel()
	if err := <-done; err != nil && err != context.Canceled {
		t.Fatalf("Run returned %v", err)
	}

	got := store.snapshot()
	if len(got) != 1 {
		t.Fatalf("after cancel the shutdown drain must persist the last complete block, got %d", len(got))
	}
	if !bytes.Contains(got[0].RawOutput, []byte("shipped\n")) {
		t.Fatalf("persisted block = %q", got[0].RawOutput)
	}
	pc := readCursorFile(t, dir)
	if (terminalcapture.CaptureCursor{Epoch: pc.Epoch, Segment: pc.Segment, Offset: pc.Offset}).ByteOffset() != int64(len(complete)) {
		t.Fatalf("cursor not advanced past the drained block: %+v", pc)
	}

	if err := w.Drain(context.Background(), true); err != nil {
		t.Fatalf("explicit final drain: %v", err)
	}
	if store.distinct() != 1 || len(store.snapshot()) != 1 {
		t.Fatalf("final drain must be idempotent: calls=%d distinct=%d", len(store.snapshot()), store.distinct())
	}
}

func TestCaptureWorkerReplayFromOldCursorUpsertsNotDuplicates(t *testing.T) {
	dir := t.TempDir()
	payload, id1, id2 := twoTier1Blocks()
	writeJournal(t, dir, testEpoch, true, payload)

	store := &fakeBlockStore{}
	w1 := newWorker(t, dir, store, false)
	if err := w1.Drain(context.Background(), false); err != nil {
		t.Fatalf("first drain: %v", err)
	}
	if len(store.snapshot()) != 2 {
		t.Fatalf("first run recorded %d, want 2", len(store.snapshot()))
	}

	if err := os.WriteFile(filepath.Join(dir, "cursor.json"),
		mustJSON(t, persistedCursor{Epoch: testEpoch, Segment: terminalcapture.FirstSequence, Offset: 0}), 0o600); err != nil {
		t.Fatalf("rewind cursor: %v", err)
	}

	w2 := newWorker(t, dir, store, false)
	if err := w2.Drain(context.Background(), false); err != nil {
		t.Fatalf("replay drain: %v", err)
	}

	calls := store.snapshot()
	if len(calls) != 4 {
		t.Fatalf("replay should re-Record both blocks, got %d calls", len(calls))
	}
	if store.distinct() != 2 {
		t.Fatalf("replay must upsert the same (terminal, source) keys, distinct=%d want 2", store.distinct())
	}
	if calls[2].SourceID != id1 || calls[3].SourceID != id2 {
		t.Fatalf("replayed source ids = %q, %q; want %q, %q", calls[2].SourceID, calls[3].SourceID, id1, id2)
	}
	if calls[2].StartOffset != calls[0].StartOffset || calls[3].StartOffset != calls[1].StartOffset {
		t.Fatalf("replayed start offsets diverged from the first run")
	}
}

func TestCaptureWorkerRecoversAcrossJournalGap(t *testing.T) {
	dir := t.TempDir()
	epochPath := filepath.Join(dir, testEpoch)
	if err := os.MkdirAll(epochPath, 0o700); err != nil {
		t.Fatal(err)
	}

	clean := "\x1b]133;A\x07x$ after gap\x1b]133;C\x07recovered\n\x1b]133;D;0\x07"
	seg4 := append([]byte("orphaned tail of a block that lost its prompt\n"), clean...)
	if err := os.WriteFile(filepath.Join(epochPath, terminalcapture.SegmentName(4, terminalcapture.ReadySuffix)), seg4, 0o600); err != nil {
		t.Fatal(err)
	}
	writeGapJSON(t, epochPath, 4)
	writeManifestJSON(t, epochPath, 4)

	store := &fakeBlockStore{}
	w := newWorker(t, dir, store, false)
	if err := w.Drain(context.Background(), false); err != nil {
		t.Fatalf("drain: %v", err)
	}
	got := store.snapshot()
	if len(got) != 1 {
		t.Fatalf("recorded %d blocks, want 1", len(got))
	}
	if bytes.Contains(got[0].RawOutput, []byte("orphaned tail")) {
		t.Fatalf("pre-gap bytes spliced into the recovered block: %q", got[0].RawOutput)
	}
	wantStart := int64(3)*terminalcapture.SegmentSize + int64(len("orphaned tail of a block that lost its prompt\n"))
	if got[0].StartOffset != wantStart {
		t.Fatalf("recovered block start offset = %d, want %d", got[0].StartOffset, wantStart)
	}
}

func mustJSON(t *testing.T, v any) []byte {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	return b
}

func writeGapJSON(t *testing.T, dir string, firstRetained uint64) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, terminalcapture.GapFileName),
		mustJSON(t, terminalcapture.Gap{Epoch: filepath.Base(dir), FirstRetainedSequence: firstRetained}), 0o600); err != nil {
		t.Fatalf("write gap.json: %v", err)
	}
}

func writeManifestJSON(t *testing.T, dir string, finalSeq uint64) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, terminalcapture.ManifestFileName),
		mustJSON(t, terminalcapture.Manifest{Epoch: filepath.Base(dir), FinalSequence: finalSeq, FirstRetainedSequence: finalSeq}), 0o600); err != nil {
		t.Fatalf("write manifest.json: %v", err)
	}
}
