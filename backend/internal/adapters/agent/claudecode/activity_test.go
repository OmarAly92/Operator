package claudecode

import (
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestDeriveActivityState(t *testing.T) {
	tests := []struct {
		name    string
		event   string
		payload string
		want    domain.ActivityState
		wantOK  bool
	}{
		{"user prompt -> active", "user-prompt-submit", `{}`, domain.ActivityActive, true},
		// The tool-use trio reports active; lifecycle's precedence rule (not
		// this deriver) decides whether it may demote a sticky state.
		{"pre-tool-use -> active", "pre-tool-use", `{"tool_name":"Bash","tool_use_id":"toolu_1"}`, domain.ActivityActive, true},
		{"post-tool-use -> active", "post-tool-use", `{"tool_name":"Bash","tool_use_id":"toolu_1"}`, domain.ActivityActive, true},
		{"post-tool-use-failure -> active", "post-tool-use-failure", `{"tool_name":"Bash","tool_use_id":"toolu_1"}`, domain.ActivityActive, true},
		{"permission-request -> blocked", "permission-request", `{"tool_name":"Bash"}`, domain.ActivityBlocked, true},
		{"stop -> idle", "stop", `{}`, domain.ActivityIdle, true},
		{"notification idle_prompt -> idle", "notification", `{"notification_type":"idle_prompt"}`, domain.ActivityIdle, true},
		{"notification permission_prompt -> blocked", "notification", `{"notification_type":"permission_prompt"}`, domain.ActivityBlocked, true},
		{"notification agent_needs_input -> waiting_input", "notification", `{"notification_type":"agent_needs_input"}`, domain.ActivityWaitingInput, true},
		{"notification agent_completed -> idle", "notification", `{"notification_type":"agent_completed"}`, domain.ActivityIdle, true},
		{"notification auth_success -> no signal", "notification", `{"notification_type":"auth_success"}`, "", false},
		{"notification empty type -> no signal", "notification", `{}`, "", false},
		{"notification malformed payload -> no signal", "notification", `not json`, "", false},
		{"session-end logout -> exited", "session-end", `{"reason":"logout"}`, domain.ActivityExited, true},
		{"session-end prompt_input_exit -> exited", "session-end", `{"reason":"prompt_input_exit"}`, domain.ActivityExited, true},
		{"session-end other -> exited", "session-end", `{"reason":"other"}`, domain.ActivityExited, true},
		{"session-end absent reason -> exited", "session-end", `{}`, domain.ActivityExited, true},
		{"session-end clear -> no signal", "session-end", `{"reason":"clear"}`, "", false},
		{"session-end resume -> no signal", "session-end", `{"reason":"resume"}`, "", false},
		{"session-start -> no signal", "session-start", `{}`, "", false},
		{"unknown event -> no signal", "frobnicate", `{}`, "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := DeriveActivityState(tt.event, []byte(tt.payload))
			if got != tt.want || ok != tt.wantOK {
				t.Fatalf("DeriveActivityState(%q, %q) = (%q, %v), want (%q, %v)",
					tt.event, tt.payload, got, ok, tt.want, tt.wantOK)
			}
		})
	}
}

func TestTranscriptInterruptRecognisesTheInterruptMarker(t *testing.T) {
	cases := []struct {
		name              string
		line              string
		interrupted, turn bool
	}{
		{"mid-response", `{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}`, true, true},
		{"at a tool", `{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}`, true, true},
		{"string content", `{"type":"user","message":{"role":"user","content":"[Request interrupted by user]"}}`, true, true},
		{"next prompt", `{"type":"user","message":{"role":"user","content":"carry on"}}`, false, true},
		{"assistant", `{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}`, false, true},
		{"subagent", `{"type":"user","isSidechain":true,"message":{"content":"[Request interrupted by user]"}}`, false, false},
		{"meta", `{"type":"user","isMeta":true,"message":{"content":"caveat"}}`, false, false},
		{"bookkeeping", `{"type":"file-history-snapshot"}`, false, false},
		{"malformed", `{`, false, false},
	}
	for _, tc := range cases {
		interrupted, turn := TranscriptInterrupt([]byte(tc.line))
		if interrupted != tc.interrupted || turn != tc.turn {
			t.Errorf("%s: got (%v, %v), want (%v, %v)", tc.name, interrupted, turn, tc.interrupted, tc.turn)
		}
	}
}
