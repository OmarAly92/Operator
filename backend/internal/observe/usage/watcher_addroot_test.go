package usage

import (
	"context"
	"testing"
)

func TestTranscriptWatcherAddRootIsIdempotent(t *testing.T) {
	ctx := context.Background()
	first := t.TempDir()
	second := t.TempDir()
	w, err := NewTranscriptWatcher(ctx, []string{first})
	if err != nil {
		t.Fatal(err)
	}
	if err := w.AddRoot(ctx, second); err != nil {
		t.Fatal(err)
	}
	if err := w.AddRoot(ctx, second); err != nil {
		t.Fatal(err)
	}
	w.mu.Lock()
	count := len(w.roots)
	w.mu.Unlock()
	if count != 2 {
		t.Fatalf("roots = %d, want 2", count)
	}
}
