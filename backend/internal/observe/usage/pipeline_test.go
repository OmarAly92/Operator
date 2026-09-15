package usage

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"
)

func TestPipelineRetriesWatcherCreation(t *testing.T) {
	pipeline := NewPipeline(
		&coordinatorTestStore{},
		coordinatorTestIngestor(func(context.Context, int64) (IngestResult, error) {
			return IngestResult{}, nil
		}),
		[]string{t.TempDir()},
		CoordinatorConfig{Workers: 1},
	)
	pipeline.restartWait = time.Millisecond
	created := make(chan struct{})
	var calls atomic.Int64
	pipeline.newWatcher = func(context.Context, []string) (transcriptWatcher, error) {
		if calls.Add(1) == 1 {
			return nil, errors.New("temporary watcher failure")
		}
		select {
		case <-created:
		default:
			close(created)
		}
		return newCoordinatorTestWatcher(), nil
	}

	ctx, cancel := context.WithCancel(context.Background())
	done := pipeline.Start(ctx)
	waitForCoordinatorSignal(t, created, "pipeline did not retry watcher creation")
	cancel()
	waitForCoordinatorSignal(t, done, "pipeline did not stop")
	if got := calls.Load(); got < 2 {
		t.Fatalf("watcher creation calls = %d, want at least 2", got)
	}
}

type rootRecordingWatcher struct {
	transcriptWatcher
	roots []string
}

func (w *rootRecordingWatcher) AddRoot(_ context.Context, root string) error {
	w.roots = append(w.roots, root)
	return nil
}

func TestPipelineAddRootDuringWatcherBuildReachesNewWatcher(t *testing.T) {
	pipeline := NewPipeline(
		&coordinatorTestStore{},
		coordinatorTestIngestor(func(context.Context, int64) (IngestResult, error) {
			return IngestResult{}, nil
		}),
		[]string{t.TempDir()},
		CoordinatorConfig{Workers: 1},
	)
	watcher := &rootRecordingWatcher{transcriptWatcher: newCoordinatorTestWatcher()}
	building := make(chan struct{})
	added := make(chan struct{})
	var calls atomic.Int64
	pipeline.newWatcher = func(context.Context, []string) (transcriptWatcher, error) {
		if calls.Add(1) == 1 {
			close(building)
			<-added
		}
		return watcher, nil
	}

	ctx, cancel := context.WithCancel(context.Background())
	done := pipeline.Start(ctx)
	waitForCoordinatorSignal(t, building, "pipeline did not start building the watcher")
	pipeline.AddRoot(ctx, "/late/root")
	close(added)
	cancel()
	waitForCoordinatorSignal(t, done, "pipeline did not stop")
	if len(watcher.roots) != 1 || watcher.roots[0] != "/late/root" {
		t.Fatalf("watcher roots = %v, want the root added during the build", watcher.roots)
	}
}
