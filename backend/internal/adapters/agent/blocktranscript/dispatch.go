// Package blocktranscript maps a harness token onto the function that projects
// that harness's native transcript records into block events. It deliberately
// mirrors blockdispatch, which does the same job for hook events: a harness
// with no mapper registered here still contributes hook blocks, it simply adds
// nothing from its transcript.
package blocktranscript

import (
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/codex"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

// MapFunc projects one raw transcript line. ok=false means the record type was
// not recognised.
type MapFunc func(line []byte) ([]domain.BlockTranscriptEvent, bool)

// Mappers is keyed by the harness token, which is the same string as the agent
// token in `opr hooks <agent> <event>`. grok is deliberately absent: it reuses
// Claude Code's hook table but its transcript shape is unverified — see
// todo_without_tmux.md section 15.1.
var Mappers = map[string]MapFunc{
	"claude-code": claudecode.MapTranscriptRecord,
	"codex":       codex.MapTranscriptRecord,
}

// Supports reports whether a harness has a transcript mapper at all. The tailer
// uses it to decide whether a session is worth watching.
func Supports(harness string) bool {
	_, found := Mappers[harness]
	return found
}

// Map resolves the harness and applies its mapper. An unregistered harness
// yields no events and ok=false.
func Map(harness string, line []byte) ([]domain.BlockTranscriptEvent, bool) {
	mapper, found := Mappers[harness]
	if !found {
		return nil, false
	}
	return mapper(line)
}
