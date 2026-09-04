package domain

import "testing"

func TestParseBlockEventKind(t *testing.T) {
	tests := []struct {
		in   string
		want BlockEventKind
		ok   bool
	}{
		{"session_start", BlockEventSessionStart, true},
		{"prompt_submit", BlockEventPromptSubmit, true},
		{"tool_complete", BlockEventToolComplete, true},
		{"stop", BlockEventStop, true},
		{"stop_failure", BlockEventStopFailure, true},
		{"permission_request", BlockEventPermissionRequest, true},
		{"permission_replied", BlockEventPermissionReplied, true},
		{"question_asked", BlockEventQuestionAsked, true},
		{"idle_prompt", BlockEventIdlePrompt, true},
		{"something_new", BlockEventUnknown, false},
		{"", BlockEventUnknown, false},
	}
	for _, tt := range tests {
		got, ok := ParseBlockEventKind(tt.in)
		if got != tt.want || ok != tt.ok {
			t.Fatalf("ParseBlockEventKind(%q) = %q,%v want %q,%v", tt.in, got, ok, tt.want, tt.ok)
		}
	}
}

func TestParseBlockEventKindAcceptsTranscriptKinds(t *testing.T) {
	for _, name := range []string{
		"assistant_text", "reasoning", "tool_start", "tool_result",
		"todo", "turn_model", "compaction",
	} {
		got, ok := ParseBlockEventKind(name)
		if !ok || string(got) != name {
			t.Fatalf("ParseBlockEventKind(%q) = %q,%v want %q,true", name, got, ok, name)
		}
	}
}

func TestBlockEventSourceValues(t *testing.T) {
	if BlockEventSourceHook != "hook" || BlockEventSourceTranscript != "transcript" {
		t.Fatalf("source constants = %q,%q", BlockEventSourceHook, BlockEventSourceTranscript)
	}
}
