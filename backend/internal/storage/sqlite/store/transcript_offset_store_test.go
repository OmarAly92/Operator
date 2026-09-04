package store_test

import (
	"context"
	"testing"
	"time"
)

func TestTranscriptOffsetUpsertGetDelete(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)
	now := time.Now().UTC()

	if _, _, found, err := s.GetTranscriptOffset(ctx, "s-1"); err != nil || found {
		t.Fatalf("empty get = found %v err %v", found, err)
	}

	if err := s.UpsertTranscriptOffset(ctx, "s-1", "/tmp/a.jsonl", 128, now); err != nil {
		t.Fatalf("upsert: %v", err)
	}
	path, offset, found, err := s.GetTranscriptOffset(ctx, "s-1")
	if err != nil || !found || path != "/tmp/a.jsonl" || offset != 128 {
		t.Fatalf("get = %q,%d,%v,%v", path, offset, found, err)
	}

	if err := s.UpsertTranscriptOffset(ctx, "s-1", "/tmp/b.jsonl", 4, now); err != nil {
		t.Fatalf("re-upsert: %v", err)
	}
	path, offset, _, _ = s.GetTranscriptOffset(ctx, "s-1")
	if path != "/tmp/b.jsonl" || offset != 4 {
		t.Fatalf("after re-upsert = %q,%d", path, offset)
	}
}
