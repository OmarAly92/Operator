package blocktranscript

import "testing"

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
