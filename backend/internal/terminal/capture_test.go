package terminal

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakeRecorder struct {
	mu     sync.Mutex
	blocks []recordedBlock
	err    error
}

type recordedBlock struct {
	SessionID string
	Block     ShellBlock
}

func (f *fakeRecorder) RecordShellBlock(_ context.Context, sessionID string, b ShellBlock) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	f.blocks = append(f.blocks, recordedBlock{SessionID: sessionID, Block: b})
	return nil
}

func (f *fakeRecorder) snapshot() []recordedBlock {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := make([]recordedBlock, len(f.blocks))
	copy(out, f.blocks)
	return out
}

type vectorFixture struct {
	Name  string `json:"name"`
	Input string `json:"input"`
}

func loadVector(t *testing.T, name string) vectorFixture {
	t.Helper()
	paths := []string{
		filepath.Join("..", "..", "..", "packages", "terminal", "protocol", "vectors", name),
		filepath.Join("..", "..", "packages", "terminal", "protocol", "vectors", name),
	}
	for _, p := range paths {
		raw, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		var v vectorFixture
		if err := json.Unmarshal(raw, &v); err != nil {
			t.Fatalf("parse %s: %v", p, err)
		}
		return v
	}
	t.Fatalf("vector %s not found under any of %v", name, paths)
	return vectorFixture{}
}

func TestCaptureDrainsExtensionFullBlock(t *testing.T) {
	rec := &fakeRecorder{}
	cap := NewCapture("", "sess-1", rec)
	fix := loadVector(t, "extension-full-block.json")

	if err := cap.Drain(context.Background(), strings.NewReader(fix.Input)); err != nil {
		t.Fatalf("Drain: %v", err)
	}

	got := rec.snapshot()
	if len(got) != 1 {
		t.Fatalf("recorded %d blocks, want 1: %+v", len(got), got)
	}
	if got[0].SessionID != "sess-1" {
		t.Fatalf("session id = %q, want sess-1", got[0].SessionID)
	}
	if got[0].Block.Command != "ls -la" {
		t.Fatalf("command = %q, want ls -la", got[0].Block.Command)
	}
	if got[0].Block.Workdir != "/home/user" {
		t.Fatalf("workdir = %q, want /home/user", got[0].Block.Workdir)
	}
	if got[0].Block.Branch != "main" {
		t.Fatalf("branch = %q, want main", got[0].Block.Branch)
	}
	if got[0].Block.BlockID != "block-001" {
		t.Fatalf("block id = %q, want block-001", got[0].Block.BlockID)
	}
	if got[0].Block.ExitCode == nil || *got[0].Block.ExitCode != 0 {
		t.Fatalf("exit code = %v, want 0", got[0].Block.ExitCode)
	}
	if got[0].Block.Tier1Only {
		t.Fatalf("tier1-only = true, want false (extension mark was present)")
	}
}

func TestCaptureHandlesMarkSplitAcrossFeeds(t *testing.T) {
	rec := &fakeRecorder{}
	cap := NewCapture("", "sess-1", rec)
	fix := loadVector(t, "extension-full-block.json")

	feed := func(s string) {
		if err := cap.Drain(context.Background(), strings.NewReader(s)); err != nil {
			t.Fatalf("Drain: %v", err)
		}
	}
	mid := len(fix.Input) / 2
	feed(fix.Input[:mid])
	feed(fix.Input[mid:])

	got := rec.snapshot()
	if len(got) != 1 {
		t.Fatalf("recorded %d blocks, want 1", len(got))
	}
	if got[0].Block.Command != "ls -la" {
		t.Fatalf("command = %q, want ls -la", got[0].Block.Command)
	}
}

func TestCaptureRotatesSinkFromHeadOnBlockBoundary(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "capture.log")
	if err := os.WriteFile(path, []byte("stale data from a previous run\n"), 0o644); err != nil {
		t.Fatalf("seed sink: %v", err)
	}

	rec := &fakeRecorder{}
	cap := NewCapture(path, "sess-1", rec)
	cap.MaxBytes = 16
	fix := loadVector(t, "extension-full-block.json")

	if err := cap.Drain(context.Background(), strings.NewReader(fix.Input)); err != nil {
		t.Fatalf("Drain: %v", err)
	}

	got := rec.snapshot()
	if len(got) != 1 {
		t.Fatalf("recorded %d blocks, want 1", len(got))
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat sink: %v", err)
	}
	if info.Size() > cap.MaxBytes {
		t.Fatalf("sink size = %d, want <= %d", info.Size(), cap.MaxBytes)
	}
}

type sentinelErr string

func (e sentinelErr) Error() string { return string(e) }

var errSentinel = sentinelErr("sentinel")

func TestCaptureRecorderErrorIsReturned(t *testing.T) {
	rec := &fakeRecorder{err: errSentinel}
	cap := NewCapture("", "sess-1", rec)
	fix := loadVector(t, "extension-full-block.json")
	err := cap.Drain(context.Background(), strings.NewReader(fix.Input))
	if err == nil || !strings.Contains(err.Error(), "sentinel") {
		t.Fatalf("Drain err = %v, want sentinel-wrapped", err)
	}
}

func TestRunTailsSinkUntilCancel(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "capture.log")
	if _, err := OpenSink(path); err != nil {
		t.Fatalf("OpenSink: %v", err)
	}

	rec := &fakeRecorder{}
	cap := NewCapture(path, "sess-1", rec)
	cap.PollInterval = 5 * time.Millisecond
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- cap.Run(ctx) }()

	fix := loadVector(t, "extension-full-block.json")
	if err := os.WriteFile(path, []byte(fix.Input), 0o644); err != nil {
		t.Fatalf("seed sink: %v", err)
	}

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if len(rec.snapshot()) >= 1 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	got := rec.snapshot()
	if len(got) != 1 {
		cancel()
		t.Fatalf("recorded %d blocks, want 1", len(got))
	}
	if got[0].Block.Command != "ls -la" {
		cancel()
		t.Fatalf("command = %q, want ls -la", got[0].Block.Command)
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Run returned: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("Run did not return after cancel")
	}
}
