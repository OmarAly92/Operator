package claudecode

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
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

func TestMapSidechainRecordFixture(t *testing.T) {
	dir := filepath.Join("..", "..", "..", "..", "..", "testdata", "transcripts")
	raw, err := os.ReadFile(filepath.Join(dir, "claude_code_subagent.expected.json"))
	if err != nil {
		t.Fatal(err)
	}
	var fixture transcriptFixture
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	file, err := os.Open(filepath.Join(dir, "claude_code_subagent.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = file.Close() }()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 1<<20), 1<<20)
	index := 0
	for scanner.Scan() {
		want := fixture.Lines[index]
		got, known := MapSidechainRecord("a17c0aebd85b89c55", scanner.Bytes())
		if known != want.Known || len(got) != len(want.Events) {
			t.Fatalf("line %d: known=%v events=%+v; want known=%v %d events", index+1, known, got, want.Known, len(want.Events))
		}
		for i, expected := range want.Events {
			if string(got[i].Kind) != expected.Kind || got[i].Text != expected.Text || got[i].ToolName != expected.ToolName {
				t.Fatalf("line %d event %d = %+v want %+v", index+1, i, got[i], expected)
			}
			if got[i].AgentID != "a17c0aebd85b89c55" {
				t.Fatalf("line %d event %d has agent id %q", index+1, i, got[i].AgentID)
			}
		}
		if mainEvents, _ := MapTranscriptRecord(scanner.Bytes()); len(mainEvents) != 0 {
			t.Fatalf("line %d: the main mapper must still drop sidechain records, got %+v", index+1, mainEvents)
		}
		index++
	}
}

func TestSidechainMapperEmitsPromptSubmitOnlyForTheFirstUserText(t *testing.T) {
	first := `{"type":"user","isSidechain":true,"agentId":"a1","uuid":"u1","message":{"role":"user","content":"Implement task 1"}}`
	events, ok := MapSidechainRecord("a1", []byte(first))
	if !ok || len(events) != 1 || events[0].Kind != domain.BlockEventPromptSubmit || events[0].Text != "Implement task 1" {
		t.Fatalf("first user record = %+v, %v", events, ok)
	}
	result := `{"type":"user","isSidechain":true,"agentId":"a1","uuid":"u2","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"ok"}]}}`
	events, _ = MapSidechainRecord("a1", []byte(result))
	if len(events) != 1 || events[0].Kind != domain.BlockEventToolResult {
		t.Fatalf("tool result record = %+v", events)
	}
}

func TestAgentToolResultCarriesTheAgentDetail(t *testing.T) {
	line := `{"type":"user","uuid":"u9","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_A","content":"done"}]},"toolUseResult":{"agentId":"a17c","agentType":"general-purpose","status":"completed","resolvedModel":"claude-sonnet-5","totalDurationMs":61234,"totalToolUseCount":7,"totalTokens":12345,"usage":{"input_tokens":1}}}`
	events, ok := MapTranscriptRecord([]byte(line))
	if !ok || len(events) != 1 {
		t.Fatalf("events = %+v, %v", events, ok)
	}
	var detail map[string]any
	if err := json.Unmarshal([]byte(events[0].Detail), &detail); err != nil {
		t.Fatalf("detail %q: %v", events[0].Detail, err)
	}
	if detail["agentId"] != "a17c" || detail["agentType"] != "general-purpose" || detail["status"] != "completed" || detail["totalToolUseCount"] != float64(7) {
		t.Fatalf("detail = %v", detail)
	}
	if _, present := detail["usage"]; present {
		t.Fatal("usage must not be forwarded")
	}
	plain := `{"type":"user","uuid":"u10","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_B","content":"x"}]},"toolUseResult":{"stdout":"x"}}`
	events, _ = MapTranscriptRecord([]byte(plain))
	if events[0].Detail != "" {
		t.Fatalf("non-agent result must carry no detail, got %q", events[0].Detail)
	}
}

func TestAnAsyncLaunchDetailOmitsUnknownTotalsAndEmptyType(t *testing.T) {
	line := `{"type":"user","uuid":"u11","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_C","content":"Async agent launched"}]},"toolUseResult":{"agentId":"af9f","status":"async_launched","resolvedModel":"claude-sonnet-5","totalDurationMs":0,"totalToolUseCount":0,"totalTokens":0}}`
	events, _ := MapTranscriptRecord([]byte(line))
	var detail map[string]any
	if err := json.Unmarshal([]byte(events[0].Detail), &detail); err != nil {
		t.Fatal(err)
	}
	for _, absent := range []string{"agentType", "totalDurationMs", "totalToolUseCount", "totalTokens"} {
		if _, present := detail[absent]; present {
			t.Fatalf("%s must be omitted when unknown, detail = %v", absent, detail)
		}
	}
	if detail["status"] != "async_launched" || detail["agentId"] != "af9f" {
		t.Fatalf("detail = %v", detail)
	}
}

func TestASubagentHandBackInTheMainTranscriptStopsTheAgent(t *testing.T) {
	line := `{"type":"user","uuid":"u12","message":{"role":"user","content":[{"type":"text","text":"Another Claude session sent a message:\n<agent-message from=\"a3da2ef9b48210e44\">\n[Subagent hand-back] The text below is the final report."}]}}`
	events, ok := MapTranscriptRecord([]byte(line))
	if !ok || len(events) != 1 || events[0].Kind != domain.BlockEventAgentStop || events[0].SourceID != "a3da2ef9b48210e44" || events[0].AgentID != "" {
		t.Fatalf("events = %+v, %v", events, ok)
	}
	plain := `{"type":"user","uuid":"u13","message":{"role":"user","content":"just a human prompt"}}`
	if events, _ := MapTranscriptRecord([]byte(plain)); len(events) != 0 {
		t.Fatalf("an ordinary user record must still produce nothing, got %+v", events)
	}
	sidechain := `{"type":"user","isSidechain":true,"agentId":"a1","uuid":"u14","message":{"role":"user","content":"<agent-message from=\"zz\">hi"}}`
	if events, _ := MapSidechainRecord("a1", []byte(sidechain)); len(events) != 1 || events[0].Kind != domain.BlockEventPromptSubmit {
		t.Fatalf("inside an agent transcript a text record is its prompt, got %+v", events)
	}
}
