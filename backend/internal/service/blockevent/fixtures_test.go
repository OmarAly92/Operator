package blockevent

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fixtureFile struct {
	Harness string `json:"harness"`
	Signals []struct {
		Event                 string `json:"event"`
		ToolName              string `json:"toolName"`
		ToolUseID             string `json:"toolUseId"`
		LatestUserPrompt      string `json:"latestUserPrompt"`
		LatestAssistantUpdate string `json:"latestAssistantUpdate"`
	} `json:"signals"`
	Expected []struct {
		Kind               string `json:"kind"`
		RawEvent           string `json:"rawEvent"`
		ToolName           string `json:"toolName"`
		ToolUseID          string `json:"toolUseId"`
		SourceID           string `json:"sourceId"`
		Text               string `json:"text"`
		RedactedSpansCount int    `json:"redactedSpansCount"`
		ErrorType          string `json:"errorType"`
	} `json:"expected"`
}

func TestSharedFixtures(t *testing.T) {
	dir := filepath.Join("..", "..", "..", "..", "testdata", "blocks")
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read fixtures: %v", err)
	}
	const hookFixturePrefix = "hook_stream_"
	seen := 0
	for _, entry := range entries {
		if !strings.HasPrefix(entry.Name(), hookFixturePrefix) {
			continue
		}
		seen++
		t.Run(entry.Name(), func(t *testing.T) {
			raw, err := os.ReadFile(filepath.Join(dir, entry.Name()))
			if err != nil {
				t.Fatalf("read: %v", err)
			}
			var fixture fixtureFile
			if err := json.Unmarshal(raw, &fixture); err != nil {
				t.Fatalf("decode: %v", err)
			}

			store := &fakeStore{}
			svc := NewService(store, nil, 500)
			for _, sig := range fixture.Signals {
				err := svc.Record(context.Background(), "s-1", fixture.Harness, ports.ActivitySignal{
					Event:                 sig.Event,
					ToolName:              sig.ToolName,
					ToolUseID:             sig.ToolUseID,
					LatestUserPrompt:      sig.LatestUserPrompt,
					LatestAssistantUpdate: sig.LatestAssistantUpdate,
				})
				if err != nil {
					t.Fatalf("Record: %v", err)
				}
			}
			if len(store.inserted) != len(fixture.Expected) {
				t.Fatalf("produced %d records, fixture expects %d", len(store.inserted), len(fixture.Expected))
			}
			for i, want := range fixture.Expected {
				got := store.inserted[i]
				if string(got.Kind) != want.Kind {
					t.Errorf("record %d Kind = %q, want %q", i, got.Kind, want.Kind)
				}
				if got.RawEvent != want.RawEvent {
					t.Errorf("record %d RawEvent = %q, want %q", i, got.RawEvent, want.RawEvent)
				}
				if got.Text != want.Text {
					t.Errorf("record %d Text = %q, want %q", i, got.Text, want.Text)
				}
				if want.SourceID != "" && got.SourceID != want.SourceID {
					t.Errorf("record %d SourceID = %q, want %q", i, got.SourceID, want.SourceID)
				}
				if len(got.RedactedSpans) != want.RedactedSpansCount {
					t.Errorf("record %d spans = %d, want %d", i, len(got.RedactedSpans), want.RedactedSpansCount)
				}
				if got.ErrorType != want.ErrorType {
					t.Errorf("record %d ErrorType = %q, want %q", i, got.ErrorType, want.ErrorType)
				}
			}
		})
	}
	if seen == 0 {
		t.Fatal("no hook_stream_* fixtures found; the clients have nothing to agree with")
	}
}
