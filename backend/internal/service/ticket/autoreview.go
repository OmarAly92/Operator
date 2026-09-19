package ticket

import (
	"context"
	"log/slog"

	"github.com/OmarAly92/operator/backend/internal/cdc"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

type autoReviewSource interface {
	AutoReview(ctx context.Context, sessionID domain.SessionID) error
}

type AutoReviewer struct {
	svc autoReviewSource
	log *slog.Logger
}

func NewAutoReviewer(svc autoReviewSource, log *slog.Logger) *AutoReviewer {
	if log == nil {
		log = slog.Default()
	}
	return &AutoReviewer{svc: svc, log: log}
}

func (a *AutoReviewer) Subscribe(ctx context.Context, b *cdc.Broadcaster) func() {
	return b.Subscribe(func(e cdc.Event) {
		if e.Type != cdc.EventPRCreated || e.SessionID == "" {
			return
		}
		id := domain.SessionID(e.SessionID)
		go func() {
			if err := a.svc.AutoReview(ctx, id); err != nil {
				a.log.Warn("ticket auto-review failed", "session", id, "err", err)
			}
		}()
	})
}
