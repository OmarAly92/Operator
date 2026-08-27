// Package blockdispatch maps the agent token and event name in
// `opr hooks <agent> <event>` onto the normalized block-event vocabulary.
// It deliberately mirrors activitydispatch: an adapter that installs hooks
// without registering a mapper here still reports activity, it simply
// contributes no blocks.
package blockdispatch

import "github.com/OmarAly92/operator/backend/internal/domain"

// MapFunc resolves one harness's native hook name. ok=false means the event is
// unknown to this harness's mapper and must be carried through as
// domain.BlockEventUnknown with its raw name preserved.
type MapFunc func(event string) (domain.BlockEventKind, bool)

func fromTable(table map[string]domain.BlockEventKind) MapFunc {
	return func(event string) (domain.BlockEventKind, bool) {
		kind, found := table[event]
		if !found {
			return domain.BlockEventUnknown, false
		}
		return kind, true
	}
}

var claudeCodeEvents = map[string]domain.BlockEventKind{
	"session-start":         domain.BlockEventSessionStart,
	"user-prompt-submit":    domain.BlockEventPromptSubmit,
	"post-tool-use":         domain.BlockEventToolComplete,
	"post-tool-use-failure": domain.BlockEventToolComplete,
	"permission-request":    domain.BlockEventPermissionRequest,
	"stop":                  domain.BlockEventStop,
	"notification":          domain.BlockEventQuestionAsked,
}

var codexEvents = map[string]domain.BlockEventKind{
	"session-start":      domain.BlockEventSessionStart,
	"user-prompt-submit": domain.BlockEventPromptSubmit,
	"permission-request": domain.BlockEventPermissionRequest,
	"stop":               domain.BlockEventStop,
}

// Mappers is keyed by the agent token in `opr hooks <agent> <event>`.
var Mappers = map[string]MapFunc{
	"claude-code": fromTable(claudeCodeEvents),
	"grok":        fromTable(claudeCodeEvents),
	"codex":       fromTable(codexEvents),
}

// Map resolves harness and event. An unregistered harness yields
// BlockEventUnknown so the caller can record the event without inventing a kind.
func Map(harness, event string) (domain.BlockEventKind, bool) {
	mapper, found := Mappers[harness]
	if !found {
		return domain.BlockEventUnknown, false
	}
	return mapper(event)
}
