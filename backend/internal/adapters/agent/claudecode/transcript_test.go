package claudecode

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

type transcriptFixture struct {
	Harness string `json:"harness"`
	Lines   []struct {
		Known  bool `json:"known"`
		Events []struct {
			Kind      string `json:"kind"`
			SourceID  string `json:"sourceId"`
			ToolName  string `json:"toolName"`
			ToolUseID string `json:"toolUseId"`
			ToolInput string `json:"toolInput"`
			Text      string `json:"text"`
			ErrorType string `json:"errorType"`
			RawEvent  string `json:"rawEvent"`
		} `json:"events"`
	} `json:"lines"`
}

func TestMapTranscriptRecordFixtures(t *testing.T) {
	dir := filepath.Join("..", "..", "..", "..", "..", "testdata", "transcripts")
	for _, name := range []string{"claude_code_turn", "claude_code_edge"} {
		t.Run(name, func(t *testing.T) {
			raw, err := os.ReadFile(filepath.Join(dir, name+".expected.json"))
			if err != nil {
				t.Fatalf("read expectations: %v", err)
			}
			var fixture transcriptFixture
			if err := json.Unmarshal(raw, &fixture); err != nil {
				t.Fatalf("decode expectations: %v", err)
			}
			file, err := os.Open(filepath.Join(dir, name+".jsonl"))
			if err != nil {
				t.Fatalf("open transcript: %v", err)
			}
			defer func() { _ = file.Close() }()

			scanner := bufio.NewScanner(file)
			scanner.Buffer(make([]byte, 0, 1<<20), 1<<20)
			index := 0
			for scanner.Scan() {
				if index >= len(fixture.Lines) {
					t.Fatalf("transcript has more lines than expectations (%d)", len(fixture.Lines))
				}
				want := fixture.Lines[index]
				got, known := MapTranscriptRecord(scanner.Bytes())
				if known != want.Known {
					t.Fatalf("line %d known = %v want %v", index+1, known, want.Known)
				}
				if len(got) != len(want.Events) {
					t.Fatalf("line %d produced %d events, want %d: %+v", index+1, len(got), len(want.Events), got)
				}
				for i, expected := range want.Events {
					actual := got[i]
					if string(actual.Kind) != expected.Kind ||
						actual.ToolName != expected.ToolName ||
						actual.ToolUseID != expected.ToolUseID ||
						actual.ToolInput != expected.ToolInput ||
						actual.Text != expected.Text ||
						actual.ErrorType != expected.ErrorType ||
						actual.RawEvent != expected.RawEvent {
						t.Fatalf("line %d event %d = %+v want %+v", index+1, i, actual, expected)
					}
					if expected.SourceID == "*" {
						if actual.SourceID == "" {
							t.Fatalf("line %d event %d has an empty source id", index+1, i)
						}
					} else if actual.SourceID != expected.SourceID {
						t.Fatalf("line %d event %d source id = %q want %q", index+1, i, actual.SourceID, expected.SourceID)
					}
				}
				index++
			}
			if err := scanner.Err(); err != nil {
				t.Fatalf("scan transcript: %v", err)
			}
			if index != len(fixture.Lines) {
				t.Fatalf("consumed %d lines, expectations cover %d", index, len(fixture.Lines))
			}
		})
	}
}
