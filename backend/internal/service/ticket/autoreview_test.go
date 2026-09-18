package ticket

import (
	"context"
	"io"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/cdc"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

type recordingReviewer struct {
	mu  sync.Mutex
	ids []domain.SessionID
}

func (r *recordingReviewer) AutoReview(_ context.Context, id domain.SessionID) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.ids = append(r.ids, id)
	return nil
}

func TestAutoReviewerReactsToPRCreatedOnly(t *testing.T) {
	rec := &recordingReviewer{}
	b := cdc.NewBroadcaster()
	ar := NewAutoReviewer(rec, slog.New(slog.NewTextHandler(io.Discard, nil)))
	unsub := ar.Subscribe(context.Background(), b)
	defer unsub()
	b.Publish(cdc.Event{Type: cdc.EventPRCreated, SessionID: "tk-1"})
	b.Publish(cdc.Event{Type: cdc.EventPRUpdated, SessionID: "tk-1"})
	b.Publish(cdc.Event{Type: cdc.EventSessionUpdated, SessionID: "tk-2"})
	b.Publish(cdc.Event{Type: cdc.EventPRCreated})
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		rec.mu.Lock()
		n := len(rec.ids)
		rec.mu.Unlock()
		if n == 1 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	rec.mu.Lock()
	defer rec.mu.Unlock()
	if len(rec.ids) != 1 || rec.ids[0] != "tk-1" {
		t.Fatalf("ids = %v", rec.ids)
	}
}
