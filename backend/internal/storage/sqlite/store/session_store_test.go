package store_test

import (
	"context"
	"testing"

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
