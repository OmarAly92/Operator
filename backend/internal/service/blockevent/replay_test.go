package blockevent

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

// TestReplayKindSequence asserts the cycle shape exactly: two full cycles of
// eight events, recording the kind and (for the failure event) the error type.
func TestReplayKindSequence(t *testing.T) {
	store, pub := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, pub, 500)
	r := NewReplay(svc)

	if err := r.Run(context.Background(), ReplayInput{
		SessionID:     "s-1",
		Harness:       "claude-code",
		Events:        16,
		RatePerSecond: 1000,
	}); err != nil {
		t.Fatalf("Run: %v", err)
	}

	if len(store.inserted) != 16 {
		t.Fatalf("recorded %d events, want 16", len(store.inserted))
	}

	wantKinds := []domain.BlockEventKind{
		domain.BlockEventSessionStart,
		domain.BlockEventPromptSubmit,
		domain.BlockEventToolComplete,
		domain.BlockEventToolComplete,
		domain.BlockEventToolComplete,
		domain.BlockEventToolComplete,
		domain.BlockEventToolComplete,
		domain.BlockEventStop,
		domain.BlockEventSessionStart,
		domain.BlockEventPromptSubmit,
		domain.BlockEventToolComplete,
		domain.BlockEventToolComplete,
		domain.BlockEventToolComplete,
		domain.BlockEventToolComplete,
		domain.BlockEventToolComplete,
		domain.BlockEventStop,
	}
	for i, want := range wantKinds {
		if got := store.inserted[i].Kind; got != want {
			t.Errorf("event %d Kind = %q, want %q", i, got, want)
		}
	}

	// The 5th tool-complete of each cycle (index 6 mod 8) is the failure path;
	// its ErrorType must be carried so a client renders the failure.
	for cycle := 0; cycle < 2; cycle++ {
		idx := cycle*8 + 6
		if et := store.inserted[idx].ErrorType; et != "tool_failed" {
			t.Errorf("event %d ErrorType = %q, want tool_failed", idx, et)
		}
	}
}

// TestReplayRespectsEventsCountExactly asserts a partial cycle stops at
// exactly Events, not at the next cycle boundary.
func TestReplayRespectsEventsCountExactly(t *testing.T) {
	store, _ := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, nil, 500)
	r := NewReplay(svc)

	if err := r.Run(context.Background(), ReplayInput{
		SessionID:     "s-1",
		Harness:       "claude-code",
		Events:        5,
		RatePerSecond: 1000,
	}); err != nil {
		t.Fatalf("Run: %v", err)
	}

	if len(store.inserted) != 5 {
		t.Fatalf("recorded %d events, want 5 (a partial cycle, not 8)", len(store.inserted))
	}
	wantFirst := []domain.BlockEventKind{
		domain.BlockEventSessionStart,
		domain.BlockEventPromptSubmit,
		domain.BlockEventToolComplete,
		domain.BlockEventToolComplete,
		domain.BlockEventToolComplete,
	}
	for i, want := range wantFirst {
		if got := store.inserted[i].Kind; got != want {
			t.Errorf("event %d Kind = %q, want %q", i, got, want)
		}
	}
}

// TestReplayContextCancelStopsRun asserts cancelling the context stops the
// replay, not waiting for the next full cycle to finish.
func TestReplayContextCancelStopsRun(t *testing.T) {
	store, _ := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, nil, 500)
	r := NewReplay(svc)

	ctx, cancel := context.WithCancel(context.Background())

	done := make(chan struct{})
	go func() {
		_ = r.Run(ctx, ReplayInput{
			SessionID:     "s-1",
			Harness:       "claude-code",
			Events:        10000,
			RatePerSecond: 50,
		})
		close(done)
	}()

	// Let the first cycle record (8 events at 50/s is 160ms), then cancel.
	time.Sleep(250 * time.Millisecond)
	cancel()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Run did not return after context cancellation")
	}

	if got := len(store.inserted); got == 0 {
		t.Fatal("no events recorded before cancellation")
	}
	if got := len(store.inserted); got > 16 {
		t.Fatalf("recorded %d events after cancel, want at most 16 (a bounded upper bound)", got)
	}
}
