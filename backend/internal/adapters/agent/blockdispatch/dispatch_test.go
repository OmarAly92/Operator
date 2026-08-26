package blockdispatch

import (
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestMap(t *testing.T) {
	tests := []struct {
		harness string
		event   string
		want    domain.BlockEventKind
		ok      bool
	}{
		{"claude-code", "user-prompt-submit", domain.BlockEventPromptSubmit, true},
		{"claude-code", "post-tool-use", domain.BlockEventToolComplete, true},
		{"claude-code", "permission-request", domain.BlockEventPermissionRequest, true},
		{"claude-code", "stop", domain.BlockEventStop, true},
		{"claude-code", "session-start", domain.BlockEventSessionStart, true},
		{"claude-code", "brand-new-hook", domain.BlockEventUnknown, false},
		{"codex", "user-prompt-submit", domain.BlockEventPromptSubmit, true},
		{"codex", "permission-request", domain.BlockEventPermissionRequest, true},
		{"unregistered-harness", "stop", domain.BlockEventUnknown, false},
	}
	for _, tt := range tests {
		got, ok := Map(tt.harness, tt.event)
		if got != tt.want || ok != tt.ok {
			t.Fatalf("Map(%q,%q) = %q,%v want %q,%v", tt.harness, tt.event, got, ok, tt.want, tt.ok)
		}
	}
}
