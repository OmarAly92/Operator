package blockretention

import (
	"context"
	"log/slog"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

const DefaultRawOutputGrace = 7 * 24 * time.Hour

const DefaultRowGrace = 30 * 24 * time.Hour

const DefaultTickInterval = 6 * time.Hour

type Config struct {
	Tick           time.Duration
	Clock          func() time.Time
	Logger         *slog.Logger
	RawOutputGrace time.Duration
	RowGrace       time.Duration
	KeepCommands   int
}

type store interface {
	ClearOldOrphanedRawOutput(ctx context.Context, now, finishedBefore time.Time) (int64, error)
	DeleteFullyClearedOrphanedBlocks(ctx context.Context, cutoff time.Time, keepCommands int) (int64, error)
}

type Retention struct {
	store          store
	tick           time.Duration
	clock          func() time.Time
	logger         *slog.Logger
	rawOutputGrace time.Duration
	rowGrace       time.Duration
	keepCommands   int
}

func New(store store, cfg Config) *Retention {
	r := &Retention{
		store:          store,
		tick:           cfg.Tick,
		clock:          cfg.Clock,
		logger:         cfg.Logger,
		rawOutputGrace: cfg.RawOutputGrace,
		rowGrace:       cfg.RowGrace,
		keepCommands:   cfg.KeepCommands,
	}
	if r.tick <= 0 {
		r.tick = DefaultTickInterval
	}
	if r.clock == nil {
		r.clock = time.Now
	}
	if r.logger == nil {
		r.logger = slog.Default()
	}
	if r.rawOutputGrace <= 0 {
		r.rawOutputGrace = DefaultRawOutputGrace
	}
	if r.rowGrace <= 0 {
		r.rowGrace = DefaultRowGrace
	}
	if r.keepCommands <= 0 {
		r.keepCommands = domain.SharedHistoryScan
	}
	return r
}

func (r *Retention) Start(ctx context.Context) <-chan struct{} {
	done := make(chan struct{})
	go r.loop(ctx, done)
	return done
}

func (r *Retention) loop(ctx context.Context, done chan<- struct{}) {
	defer close(done)
	t := time.NewTicker(r.tick)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if _, _, err := r.Tick(ctx); err != nil {
				r.logger.Error("blockretention: tick failed", "err", err)
			}
		}
	}
}

func (r *Retention) Tick(ctx context.Context) (cleared, deleted int64, err error) {
	now := r.clock().UTC()

	cleared, err = r.store.ClearOldOrphanedRawOutput(ctx, now, now.Add(-r.rawOutputGrace))
	if err != nil {
		return 0, 0, err
	}
	deleted, err = r.store.DeleteFullyClearedOrphanedBlocks(ctx, now.Add(-r.rowGrace), r.keepCommands)
	if err != nil {
		return cleared, 0, err
	}

	if cleared != 0 {
		r.logger.Info("blockretention: cleared raw output of orphaned terminal blocks", "rows", cleared)
	}
	if deleted != 0 {
		r.logger.Info("blockretention: deleted fully cleared orphaned terminal blocks", "rows", deleted)
	}
	return cleared, deleted, nil
}
