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

	_ = startShellTerminals(ctx, cfg, rt, store, nil, sup, wiringLogger())

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
