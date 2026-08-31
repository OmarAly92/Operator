package terminalcapture

import (
	"context"
	"errors"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type recordFunc func(context.Context, domain.Block) error

func (f recordFunc) Record(ctx context.Context, b domain.Block) error { return f(ctx, b) }

type capturingPublisher struct {
	calls []domain.Block
}

func (p *capturingPublisher) PublishTerminalBlock(_ string, b domain.Block) {
	p.calls = append(p.calls, b)
}

func TestPublishingRecorderPublishesAfterCommit(t *testing.T) {
	pub := &capturingPublisher{}
	var recorded domain.Block
	rec := publishingRecorder{
		inner: recordFunc(func(_ context.Context, b domain.Block) error {
			recorded = b
			return nil
		}),
		publisher: pub,
	}

	in := domain.Block{TerminalID: "shellterm-1", SourceID: "src-1"}
	if err := rec.Record(context.Background(), in); err != nil {
		t.Fatalf("Record returned %v", err)
	}
	if recorded.SourceID != "src-1" {
		t.Fatalf("inner recorder not called with the block: %+v", recorded)
	}
	if len(pub.calls) != 1 || pub.calls[0].SourceID != "src-1" {
		t.Fatalf("publish calls = %+v, want exactly the committed block", pub.calls)
	}
}

func TestPublishingRecorderDoesNotPublishWhenRecordErrors(t *testing.T) {
	pub := &capturingPublisher{}
	wantErr := errors.New("upsert failed")
	rec := publishingRecorder{
		inner:     recordFunc(func(_ context.Context, _ domain.Block) error { return wantErr }),
		publisher: pub,
	}

	if err := rec.Record(context.Background(), domain.Block{TerminalID: "shellterm-1"}); !errors.Is(err, wantErr) {
		t.Fatalf("Record error = %v, want %v", err, wantErr)
	}
	if len(pub.calls) != 0 {
		t.Fatalf("published despite a failed commit: %+v", pub.calls)
	}
}
