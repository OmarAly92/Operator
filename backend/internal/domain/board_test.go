package domain

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// boardColumnFixture is testdata/board/columns.json, shared with the desktop's
// session-presentation test so the Go and TypeScript column maps cannot drift.
type boardColumnFixture struct {
	Live       map[SessionStatus]BoardColumn `json:"live"`
	Terminated map[SessionStatus]BoardColumn `json:"terminated"`
}

func loadBoardColumnFixture(t *testing.T) boardColumnFixture {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", "..", "..", "testdata", "board", "columns.json"))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	var f boardColumnFixture
	if err := json.Unmarshal(data, &f); err != nil {
		t.Fatalf("decode fixture: %v", err)
	}
	return f
}

func TestBoardColumnForMatchesSharedFixture(t *testing.T) {
	f := loadBoardColumnFixture(t)
	for status, want := range f.Live {
		if got := BoardColumnFor(status, false); got != want {
			t.Errorf("BoardColumnFor(%q, live) = %q, want %q", status, got, want)
		}
	}
	for status, want := range f.Terminated {
		if got := BoardColumnFor(status, true); got != want {
			t.Errorf("BoardColumnFor(%q, terminated) = %q, want %q", status, got, want)
		}
	}
}

// Every status the API can emit must have a fixture row, so a new status forces
// a deliberate column decision on both sides.
func TestBoardColumnFixtureCoversEveryStatus(t *testing.T) {
	f := loadBoardColumnFixture(t)
	statuses := []SessionStatus{
		StatusWorking, StatusPROpen, StatusDraft, StatusCIFailed, StatusReviewPending,
		StatusChangesRequested, StatusApproved, StatusMergeable, StatusMerged,
		StatusNeedsInput, StatusExited, StatusIdle, StatusTerminated, StatusNoSignal,
	}
	var missing []SessionStatus
	for _, s := range statuses {
		if _, ok := f.Live[s]; !ok {
			missing = append(missing, s)
		}
	}
	if len(missing) > 0 {
		t.Fatalf("fixture has no live row for %v", missing)
	}
	if len(f.Live) != len(statuses) {
		t.Fatalf("fixture has %d live rows, want %d", len(f.Live), len(statuses))
	}
}
