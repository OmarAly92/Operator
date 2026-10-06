package blocktranscript

import (
	"strings"
	"testing"
)

func TestSupportsOnlyMappedHarnesses(t *testing.T) {
	for _, harness := range []string{"claude-code", "codex"} {
		if !Supports(harness) {
			t.Fatalf("%s must have a transcript mapper", harness)
		}
	}
	for _, harness := range []string{"grok", "opencode", "", "unknown"} {
		if Supports(harness) {
			t.Fatalf("%s must not have a transcript mapper", harness)
		}
	}
}

func TestMapUnregisteredHarnessIsUnknown(t *testing.T) {
	events, known := Map("grok", []byte(`{"type":"assistant"}`))
	if known || len(events) != 0 {
		t.Fatalf("Map(grok) = %+v,%v", events, known)
	}
}

func TestMapRoutesToTheHarnessMapper(t *testing.T) {
	events, known := Map("claude-code", []byte(`{"type":"assistant","uuid":"u-1","message":{"model":"m","content":[]}}`))
	if !known || len(events) != 1 || events[0].Text != "m" {
		t.Fatalf("Map(claude-code) = %+v,%v", events, known)
	}
	events, known = Map("codex", []byte(`{"timestamp":"2026-09-04T10:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}`))
	if !known || len(events) != 1 || events[0].Text != "gpt-5.4" {
		t.Fatalf("Map(codex) = %+v,%v", events, known)
	}
}

func TestMapSidechainIsClaudeCodeOnly(t *testing.T) {
	if !SupportsSidechain("claude-code") || SupportsSidechain("codex") {
		t.Fatal("sidechain projection is claude-code only")
	}
	line := []byte(`{"type":"user","isSidechain":true,"agentId":"a1","uuid":"u1","message":{"content":"go"}}`)
	events, ok := MapSidechain("claude-code", "a1", line)
	if !ok || len(events) != 1 || events[0].AgentID != "a1" {
		t.Fatalf("MapSidechain = %+v, %v", events, ok)
	}
	if events, ok := MapSidechain("codex", "a1", line); ok || len(events) != 0 {
		t.Fatal("codex has no sidechain mapper")
	}
}

func TestNewMapperKeepsLaunchStateAcrossLines(t *testing.T) {
	mapper := NewMapper("claude-code", "")
	if mapper == nil {
		t.Fatal("claude-code must have a mapper")
	}
	use := []byte(`{"type":"assistant","uuid":"u1","timestamp":"2026-09-25T00:00:00Z","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"sleep 5","run_in_background":true}}]}}`)
	result := []byte(`{"type":"user","uuid":"u2","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"Command running in background with ID: b1. Output is being written to: /tmp/tasks/b1.output."}]},"toolUseResult":{"backgroundTaskId":"b1"}}`)
	mapper(use)
	events, known := mapper(result)
	if !known || len(events) != 2 || events[1].ToolName != "Bash" || events[1].Detail == "" {
		t.Fatalf("events = %+v", events)
	}
	if !strings.Contains(events[1].Detail, `"command":"sleep 5"`) {
		t.Fatalf("detail lost the launch: %s", events[1].Detail)
	}
}

func TestNewMapperSidechainAndFallbacks(t *testing.T) {
	sidechain := NewMapper("claude-code", "a1")
	events, ok := sidechain([]byte(`{"type":"user","isSidechain":true,"uuid":"u1","message":{"content":"go"}}`))
	if !ok || len(events) != 1 || events[0].AgentID != "a1" {
		t.Fatalf("sidechain = %+v,%v", events, ok)
	}
	codex := NewMapper("codex", "")
	if codex == nil {
		t.Fatal("codex must have a mapper")
	}
	if NewMapper("codex", "a1") != nil || NewMapper("grok", "") != nil {
		t.Fatal("unsupported harness or scope must have no mapper")
	}
}
