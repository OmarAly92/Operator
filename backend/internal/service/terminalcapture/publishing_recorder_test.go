package terminalcapture

import (
	"bytes"
	"context"
	"errors"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/service/terminalblock"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/sqlitetest"
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

func TestPublishingRecorderPublishesCappedBytesMatchingPersistedRow(t *testing.T) {
	store := sqlitetest.MustOpen(t)
	svc := terminalblock.NewService(store)
	pub := &capturingPublisher{}
	rec := publishingRecorder{inner: svc, publisher: pub}

	var raw bytes.Buffer
	for i := 0; i < 6000; i++ {
		raw.WriteString("noisy output line\n")
	}
	now := time.Now().UTC()
	in := domain.Block{
		TerminalID: "shellterm-cap",
		SourceID:   "src-cap",
		Command:    "seq 6000",
		RawOutput:  raw.Bytes(),
		StartedAt:  now.Add(-time.Second),
		FinishedAt: now,
		CreatedAt:  now,
	}

	if err := rec.Record(context.Background(), in); err != nil {
		t.Fatalf("Record returned %v", err)
	}
	if len(pub.calls) != 1 {
		t.Fatalf("publish calls = %d, want 1", len(pub.calls))
	}
	published := pub.calls[0]

	hist, err := svc.History(context.Background(), "shellterm-cap", 1)
	if err != nil {
		t.Fatalf("History returned %v", err)
	}
	if len(hist) != 1 {
		t.Fatalf("history rows = %d, want 1", len(hist))
	}
	persisted := hist[0]

	if persisted.TruncatedLines == 0 {
		t.Fatalf("expected the line cap to have trimmed the persisted row")
	}
	if !bytes.Equal(published.RawOutput, persisted.RawOutput) {
		t.Fatalf("published rawOutput %d bytes != persisted %d bytes", len(published.RawOutput), len(persisted.RawOutput))
	}
	if published.TruncatedLines != persisted.TruncatedLines || published.TruncatedBytes != persisted.TruncatedBytes {
		t.Fatalf("published truncation (%d,%d) != persisted (%d,%d)",
			published.TruncatedLines, published.TruncatedBytes, persisted.TruncatedLines, persisted.TruncatedBytes)
	}
}
