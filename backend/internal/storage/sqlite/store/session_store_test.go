package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestCreateSessionSkipsIDsClaimedOutsideTheStore(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "scratch")

	claimed := map[domain.SessionID]bool{"scratch-1": true, "scratch-2": true}
	s.SetSessionIDInUse(func(_ context.Context, id domain.SessionID) bool {
		return claimed[id]
	})

	rec, err := s.CreateSession(ctx, sampleRecord("scratch"))
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	if rec.ID != "scratch-3" {
		t.Fatalf("ID = %q, want scratch-3 (scratch-1 and scratch-2 are claimed elsewhere)", rec.ID)
	}
}

func TestCreateSessionAfterSkippingKeepsNumberingMonotonic(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "scratch")

	claimed := map[domain.SessionID]bool{"scratch-1": true}
	s.SetSessionIDInUse(func(_ context.Context, id domain.SessionID) bool {
		return claimed[id]
	})

	first, err := s.CreateSession(ctx, sampleRecord("scratch"))
	if err != nil {
		t.Fatalf("create first session: %v", err)
	}
	second, err := s.CreateSession(ctx, sampleRecord("scratch"))
	if err != nil {
		t.Fatalf("create second session: %v", err)
	}
	if first.ID != "scratch-2" || second.ID != "scratch-3" {
		t.Fatalf("IDs = %q, %q; want scratch-2, scratch-3", first.ID, second.ID)
	}
}

func TestCreateSessionWithoutProbeUsesNextNum(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "scratch")

	rec, err := s.CreateSession(ctx, sampleRecord("scratch"))
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	if rec.ID != "scratch-1" {
		t.Fatalf("ID = %q, want scratch-1", rec.ID)
	}
}

func TestCreateSessionStopsSkippingAfterBoundedAttempts(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "scratch")

	var probes int
	s.SetSessionIDInUse(func(_ context.Context, _ domain.SessionID) bool {
		probes++
		return true
	})

	if _, err := s.CreateSession(ctx, sampleRecord("scratch")); err == nil {
		t.Fatal("create session succeeded, want an error when every candidate ID is claimed")
	}
	if probes > 128 {
		t.Fatalf("probed %d candidates, want a bounded search", probes)
	}
}

func TestMarkSessionPreviewOpenedAdvancesOnlyToCurrentRevision(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "mer")
	rec, err := s.CreateSession(ctx, sampleRecord("mer"))
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	for _, target := range []string{"http://localhost:5173", "http://localhost:5173/?v=2"} {
		if _, err := s.SetSessionPreviewURL(ctx, rec.ID, target, time.Now().UTC()); err != nil {
			t.Fatalf("set preview url %q: %v", target, err)
		}
	}
	stored, ok, err := s.GetSession(ctx, rec.ID)
	if err != nil || !ok {
		t.Fatalf("get session: ok=%v err=%v", ok, err)
	}
	if stored.Metadata.PreviewRevision != 2 || stored.Metadata.PreviewOpenedRevision != 0 {
		t.Fatalf("seed state revision=%d opened=%d, want revision=2 opened=0",
			stored.Metadata.PreviewRevision, stored.Metadata.PreviewOpenedRevision)
	}

	for _, revision := range []int64{1, 3} {
		applied, err := s.MarkSessionPreviewOpened(ctx, rec.ID, revision, time.Now().UTC())
		if err != nil {
			t.Fatalf("mark preview opened %d: %v", revision, err)
		}
		if applied {
			t.Fatalf("stale/future acknowledgement of revision %d matched a row, want zero rows", revision)
		}
	}

	applied, err := s.MarkSessionPreviewOpened(ctx, rec.ID, 2, time.Now().UTC())
	if err != nil {
		t.Fatalf("mark preview opened current revision: %v", err)
	}
	if !applied {
		t.Fatal("acknowledgement of the current revision matched zero rows, want one row updated")
	}

	repeatApplied, err := s.MarkSessionPreviewOpened(ctx, rec.ID, 2, time.Now().UTC())
	if err != nil {
		t.Fatalf("repeat mark preview opened: %v", err)
	}
	if repeatApplied {
		t.Fatal("idempotent repeat matched a row, want zero rows")
	}

	final, ok, err := s.GetSession(ctx, rec.ID)
	if err != nil || !ok {
		t.Fatalf("final get session: ok=%v err=%v", ok, err)
	}
	if final.Metadata.PreviewOpenedRevision != 2 {
		t.Fatalf("persisted preview_opened_revision = %d, want 2", final.Metadata.PreviewOpenedRevision)
	}
	if final.Metadata.PreviewRevision != 2 {
		t.Fatalf("preview_revision changed to %d, want untouched 2", final.Metadata.PreviewRevision)
	}
}
