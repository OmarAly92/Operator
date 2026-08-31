package terminalcapture

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/service/shellterm"
	"github.com/OmarAly92/operator/backend/internal/service/terminalblock"
	"github.com/OmarAly92/operator/backend/internal/terminal"
	journal "github.com/OmarAly92/operator/backend/internal/terminalcapture"
)

const sealPollInterval = 10 * time.Millisecond

type Supervisor struct {
	capturer        ports.PaneCapturer
	blocks          *terminalblock.Service
	dataDir         string
	shutdownTimeout time.Duration
	log             *slog.Logger

	now          func() time.Time
	newEpoch     func() string
	pollInterval time.Duration

	mu      sync.Mutex
	workers map[string]*captureHandle
	hlocks  map[string]*sync.Mutex
}

type captureHandle struct {
	worker   *terminal.CaptureWorker
	cancel   context.CancelFunc
	done     chan error
	epochDir string
}

func NewSupervisor(capturer ports.PaneCapturer, blocks *terminalblock.Service, dataDir string, shutdownTimeout time.Duration, log *slog.Logger) *Supervisor {
	if log == nil {
		log = slog.Default()
	}
	if shutdownTimeout <= 0 {
		shutdownTimeout = 10 * time.Second
	}
	return &Supervisor{
		capturer:        capturer,
		blocks:          blocks,
		dataDir:         dataDir,
		shutdownTimeout: shutdownTimeout,
		log:             log,
		now:             func() time.Time { return time.Now().UTC() },
		newEpoch:        uuid.NewString,
		workers:         map[string]*captureHandle{},
		hlocks:          map[string]*sync.Mutex{},
	}
}

func (s *Supervisor) Start(ctx context.Context, rec shellterm.ShellTerminalRecord) error {
	unlock := s.lockHandle(rec.HandleID)
	defer unlock()

	if s.hasWorker(rec.HandleID) {
		return nil
	}

	handle := ports.RuntimeHandle{ID: rec.HandleID}
	state, err := s.capturer.CaptureState(ctx, handle)
	if err != nil {
		return fmt.Errorf("capture state %s: %w", rec.HandleID, err)
	}

	captureDir := s.captureDir(rec.HandleID)
	epoch := s.newEpoch()
	if err := s.capturer.StartCapture(ctx, handle, paneCaptureArgv(captureDir, epoch)); err != nil {
		return fmt.Errorf("start capture %s: %w", rec.HandleID, err)
	}
	s.spawnWorker(ctx, rec, captureDir, epoch, state.AlternateOn)
	return nil
}

func (s *Supervisor) Adopt(ctx context.Context, recs []shellterm.ShellTerminalRecord) error {
	var errs []error
	for _, rec := range recs {
		if err := s.adoptOne(ctx, rec); err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", rec.HandleID, err))
		}
	}
	return errors.Join(errs...)
}

func (s *Supervisor) adoptOne(ctx context.Context, rec shellterm.ShellTerminalRecord) error {
	unlock := s.lockHandle(rec.HandleID)
	defer unlock()

	if s.hasWorker(rec.HandleID) {
		return nil
	}

	handle := ports.RuntimeHandle{ID: rec.HandleID}
	state, err := s.capturer.CaptureState(ctx, handle)
	if err != nil {
		if errors.Is(err, ports.ErrCaptureUnsupported) {
			return nil
		}
		return fmt.Errorf("capture state: %w", err)
	}

	captureDir := s.captureDir(rec.HandleID)
	var epoch string
	if state.PipeOpen {
		epoch = s.existingEpoch(captureDir)
		if epoch == "" {
			return fmt.Errorf("pane is piped but no journal epoch was found under %s", captureDir)
		}
	} else {
		epoch = s.newEpoch()
		if err := s.capturer.StartCapture(ctx, handle, paneCaptureArgv(captureDir, epoch)); err != nil {
			return fmt.Errorf("start capture: %w", err)
		}
	}
	s.spawnWorker(ctx, rec, captureDir, epoch, state.AlternateOn)
	return nil
}

func (s *Supervisor) StopAndDrain(ctx context.Context, handleID string) error {
	unlock := s.lockHandle(handleID)
	defer unlock()

	ctx, cancel := context.WithTimeout(ctx, s.shutdownTimeout)
	defer cancel()

	s.mu.Lock()
	h := s.workers[handleID]
	delete(s.workers, handleID)
	s.mu.Unlock()

	var errs []error
	if err := s.capturer.StopCapture(ctx, ports.RuntimeHandle{ID: handleID}); err != nil && !errors.Is(err, ports.ErrCaptureUnsupported) {
		errs = append(errs, fmt.Errorf("stop capture: %w", err))
	}

	if h != nil {
		s.waitForSeal(ctx, h.epochDir)
		h.cancel()
		var runErr error
		select {
		case runErr = <-h.done:
		case <-ctx.Done():
			errs = append(errs, ctx.Err())
		}
		if runErr != nil && !errors.Is(runErr, context.Canceled) {
			errs = append(errs, fmt.Errorf("capture worker: %w", runErr))
		}
		if err := h.worker.Drain(ctx, true); err != nil {
			errs = append(errs, fmt.Errorf("final drain: %w", err))
		}
		return errors.Join(errs...)
	}

	if w := s.reconcileWorker(handleID); w != nil {
		if err := w.Drain(ctx, true); err != nil {
			errs = append(errs, fmt.Errorf("reconcile drain: %w", err))
		}
	}
	return errors.Join(errs...)
}

func (s *Supervisor) DrainAndDetach(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, s.shutdownTimeout)
	defer cancel()

	s.mu.Lock()
	handles := make([]*captureHandle, 0, len(s.workers))
	for _, h := range s.workers {
		handles = append(handles, h)
	}
	s.mu.Unlock()

	var errs []error
	for _, h := range handles {
		if err := h.worker.Drain(ctx, false); err != nil {
			errs = append(errs, err)
		}
		h.cancel()
	}
	for _, h := range handles {
		select {
		case <-h.done:
		case <-ctx.Done():
			errs = append(errs, ctx.Err())
		}
	}
	return errors.Join(errs...)
}

func (s *Supervisor) spawnWorker(parent context.Context, rec shellterm.ShellTerminalRecord, captureDir, epoch string, alternateOn bool) {
	w := terminal.NewCaptureWorker(terminal.CaptureWorkerConfig{
		TerminalID:   rec.HandleID,
		SessionID:    string(rec.SessionID),
		CaptureDir:   captureDir,
		Epoch:        epoch,
		AlternateOn:  alternateOn,
		Recorder:     s.blocks,
		Now:          s.now,
		PollInterval: s.pollInterval,
	})
	runCtx, cancel := context.WithCancel(context.WithoutCancel(parent))
	done := make(chan error, 1)
	s.mu.Lock()
	s.workers[rec.HandleID] = &captureHandle{
		worker:   w,
		cancel:   cancel,
		done:     done,
		epochDir: filepath.Join(captureDir, epoch),
	}
	s.mu.Unlock()
	go func() { done <- w.Run(runCtx) }()
}

func (s *Supervisor) reconcileWorker(handleID string) *terminal.CaptureWorker {
	captureDir := s.captureDir(handleID)
	epoch := s.existingEpoch(captureDir)
	if epoch == "" {
		return nil
	}
	return terminal.NewCaptureWorker(terminal.CaptureWorkerConfig{
		TerminalID:   handleID,
		CaptureDir:   captureDir,
		Epoch:        epoch,
		Recorder:     s.blocks,
		Now:          s.now,
		PollInterval: s.pollInterval,
	})
}

func (s *Supervisor) waitForSeal(ctx context.Context, epochDir string) {
	manifest := filepath.Join(epochDir, journal.ManifestFileName)
	deadline := time.Now().Add(s.shutdownTimeout)
	for {
		if _, err := os.Stat(manifest); err == nil {
			return
		}
		if time.Now().After(deadline) {
			s.log.Warn("shell capture: journal seal not observed before timeout", "epochDir", epochDir)
			return
		}
		timer := time.NewTimer(sealPollInterval)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
	}
}

func (s *Supervisor) existingEpoch(captureDir string) string {
	if raw, err := os.ReadFile(filepath.Join(captureDir, "cursor.json")); err == nil {
		var pc struct {
			Epoch string `json:"epoch"`
		}
		if json.Unmarshal(raw, &pc) == nil && pc.Epoch != "" {
			if _, err := os.Stat(filepath.Join(captureDir, pc.Epoch)); err == nil {
				return pc.Epoch
			}
		}
	}
	entries, err := os.ReadDir(captureDir)
	if err != nil {
		return ""
	}
	var dirs []string
	for _, e := range entries {
		if e.IsDir() {
			dirs = append(dirs, e.Name())
		}
	}
	if len(dirs) == 0 {
		return ""
	}
	sort.Strings(dirs)
	for _, d := range dirs {
		if _, err := os.Stat(filepath.Join(captureDir, d, journal.ManifestFileName)); err != nil {
			return d
		}
	}
	return dirs[len(dirs)-1]
}

func (s *Supervisor) captureDir(handleID string) string {
	return filepath.Join(journal.CaptureRoot(s.dataDir), handleID)
}

func (s *Supervisor) hasWorker(handleID string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.workers[handleID]
	return ok
}

func (s *Supervisor) lockHandle(handleID string) func() {
	s.mu.Lock()
	m, ok := s.hlocks[handleID]
	if !ok {
		m = &sync.Mutex{}
		s.hlocks[handleID] = m
	}
	s.mu.Unlock()
	m.Lock()
	return m.Unlock
}

func paneCaptureArgv(captureDir, epoch string) []string {
	return []string{"pane-capture", "--dir", captureDir, "--epoch", epoch}
}
