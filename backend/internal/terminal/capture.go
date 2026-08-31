package terminal

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/terminalcapture"
	"github.com/OmarAly92/operator/packages/terminal/go/marks"
)

const defaultCapturePollInterval = 25 * time.Millisecond

type BlockRecorder interface {
	Record(ctx context.Context, b domain.Block) error
}

type persistedCursor struct {
	Epoch   string `json:"epoch"`
	Segment uint64 `json:"segment"`
	Offset  int64  `json:"offset"`
}

type CaptureWorkerConfig struct {
	TerminalID   string
	SessionID    string
	CaptureDir   string
	Epoch        string
	AlternateOn  bool
	Recorder     BlockRecorder
	Now          func() time.Time
	PollInterval time.Duration
}

type CaptureWorker struct {
	terminalID string
	sessionID  string
	epoch      string
	cursorPath string
	poll       time.Duration

	reader    *terminalcapture.Reader
	decoder   *marks.StreamDecoder
	assembler *BlockAssembler
	recorder  BlockRecorder
	now       func() time.Time

	mu         sync.Mutex
	started    bool
	cursor     terminalcapture.CaptureCursor
	checkpoint terminalcapture.CaptureCursor
}

func NewCaptureWorker(cfg CaptureWorkerConfig) *CaptureWorker {
	now := cfg.Now
	if now == nil {
		now = func() time.Time { return time.Now().UTC() }
	}
	poll := cfg.PollInterval
	if poll <= 0 {
		poll = defaultCapturePollInterval
	}
	epochDir := filepath.Join(cfg.CaptureDir, cfg.Epoch)
	return &CaptureWorker{
		terminalID: cfg.TerminalID,
		sessionID:  cfg.SessionID,
		epoch:      cfg.Epoch,
		cursorPath: filepath.Join(cfg.CaptureDir, "cursor.json"),
		poll:       poll,
		reader:     terminalcapture.NewReader(epochDir),
		decoder:    marks.NewStreamDecoder(),
		assembler:  NewBlockAssembler(cfg.TerminalID, cfg.SessionID, cfg.Epoch, cfg.AlternateOn, now),
		recorder:   cfg.Recorder,
		now:        now,
	}
}

func (w *CaptureWorker) Run(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			return w.drain(context.WithoutCancel(ctx), false)
		default:
		}
		progressed, err := w.pump(ctx)
		if err != nil {
			return err
		}
		if progressed {
			continue
		}
		timer := time.NewTimer(w.poll)
		select {
		case <-ctx.Done():
			timer.Stop()
			return w.drain(context.WithoutCancel(ctx), false)
		case <-timer.C:
		}
	}
}

func (w *CaptureWorker) Drain(ctx context.Context, final bool) error {
	return w.drain(ctx, final)
}

func (w *CaptureWorker) Cursor() terminalcapture.CaptureCursor {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.checkpoint
}

func (w *CaptureWorker) pump(ctx context.Context) (bool, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.pumpLocked(ctx, false)
}

func (w *CaptureWorker) drain(ctx context.Context, final bool) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.ensureStartedLocked()
	if _, err := w.pumpLocked(ctx, true); err != nil {
		return err
	}
	if final {
		if err := w.consumeLocked(ctx, w.assembler.Finish(true)); err != nil {
			return err
		}
	}
	return w.persistCheckpointLocked()
}

func (w *CaptureWorker) pumpLocked(ctx context.Context, drainAll bool) (bool, error) {
	w.ensureStartedLocked()
	progressed := false
	for {
		res, err := w.reader.Read(w.cursor)
		if err != nil {
			return progressed, err
		}
		if res.Gap != nil {
			w.assembler.Gap()
			w.cursor = *res.Gap
			if res.Gap.ByteOffset() > w.checkpoint.ByteOffset() {
				w.checkpoint = *res.Gap
			}
			w.decoder.ResetAt(w.cursor.ByteOffset())
			progressed = true
			continue
		}
		if len(res.Data) > 0 {
			w.cursor = res.Cursor
			if err := w.consumeLocked(ctx, w.assembler.Consume(w.decoder.Feed(res.Data))); err != nil {
				return progressed, err
			}
			progressed = true
		}
		if drainAll && res.Sealed {
			if flushed := w.decoder.Flush(); len(flushed) > 0 {
				if err := w.consumeLocked(ctx, w.assembler.Consume(flushed)); err != nil {
					return progressed, err
				}
			}
		}
		if len(res.Data) == 0 || !drainAll {
			return progressed, nil
		}
	}
}

func (w *CaptureWorker) consumeLocked(ctx context.Context, blocks []domain.Block) error {
	for _, b := range blocks {
		if err := w.recorder.Record(ctx, b); err != nil {
			return err
		}
		w.advanceCheckpointLocked(b.EndOffset)
	}
	return nil
}

func (w *CaptureWorker) advanceCheckpointLocked(endOffset int64) {
	c := terminalcapture.CursorAtOffset(w.epoch, endOffset)
	if c.ByteOffset() > w.checkpoint.ByteOffset() {
		w.checkpoint = c
	}
}

func (w *CaptureWorker) ensureStartedLocked() {
	if w.started {
		return
	}
	w.started = true
	start := terminalcapture.CaptureCursor{Epoch: w.epoch, Segment: terminalcapture.FirstSequence}
	if pc, ok := w.loadCheckpoint(); ok && pc.Epoch == w.epoch && pc.Segment >= terminalcapture.FirstSequence {
		start = pc
	}
	w.cursor = start
	w.checkpoint = start
	w.decoder.ResetAt(start.ByteOffset())
}

func (w *CaptureWorker) loadCheckpoint() (terminalcapture.CaptureCursor, bool) {
	raw, err := os.ReadFile(w.cursorPath)
	if err != nil {
		return terminalcapture.CaptureCursor{}, false
	}
	var pc persistedCursor
	if err := json.Unmarshal(raw, &pc); err != nil {
		return terminalcapture.CaptureCursor{}, false
	}
	return terminalcapture.CaptureCursor{Epoch: pc.Epoch, Segment: pc.Segment, Offset: pc.Offset}, true
}

func (w *CaptureWorker) persistCheckpointLocked() error {
	c := w.checkpoint
	if c.Epoch == "" {
		c.Epoch = w.epoch
	}
	if c.Segment < terminalcapture.FirstSequence {
		c.Segment = terminalcapture.FirstSequence
	}
	data, err := json.Marshal(persistedCursor{Epoch: c.Epoch, Segment: c.Segment, Offset: c.Offset})
	if err != nil {
		return err
	}
	dir := filepath.Dir(w.cursorPath)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, "cursor-*.json.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpName)
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpName)
		return err
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpName)
		return err
	}
	return os.Rename(tmpName, w.cursorPath)
}
