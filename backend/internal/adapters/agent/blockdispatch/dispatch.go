// Package blockdispatch maps the agent token and event name in
// `opr hooks <agent> <event>` onto the normalized block-event vocabulary.
// It deliberately mirrors activitydispatch: an adapter that installs hooks
// without registering a mapper here still reports activity, it simply
// contributes no blocks.
package blockdispatch

import "github.com/OmarAly92/operator/backend/internal/domain"

// Decision is one harness handler's verdict on one native event. Drop is what
// separates a handler from a parser: a harness that emits a duplicate or a
// useless event suppresses it at its own boundary instead of pushing it into
// the shared vocabulary. Known=false means the name was not recognized and the
// caller must carry the raw name through on the record.
type Decision struct {
	Kind      domain.BlockEventKind
	ErrorType string
	Known     bool
	Drop      bool
}

// MapFunc resolves one harness's native hook name.
type MapFunc func(event string) Decision

type rule struct {
	kind      domain.BlockEventKind
	errorType string
}

func fromTable(table map[string]rule) MapFunc {
	return func(event string) Decision {
		r, found := table[event]
		if !found {
			return Decision{Kind: domain.BlockEventUnknown}
		}
		return Decision{Kind: r.kind, ErrorType: r.errorType, Known: true}
	}
}

var claudeCodeEvents = map[string]rule{
	"session-start":         {kind: domain.BlockEventSessionStart},
	"user-prompt-submit":    {kind: domain.BlockEventPromptSubmit},
	"post-tool-use":         {kind: domain.BlockEventToolComplete},
	"post-tool-use-failure": {kind: domain.BlockEventToolComplete, errorType: "tool_failed"},
	"permission-request":    {kind: domain.BlockEventPermissionRequest},
	"stop":                  {kind: domain.BlockEventStop},
	"notification":          {kind: domain.BlockEventQuestionAsked},
}

var codexEvents = map[string]rule{
	"session-start":      {kind: domain.BlockEventSessionStart},
	"user-prompt-submit": {kind: domain.BlockEventPromptSubmit},
	"permission-request": {kind: domain.BlockEventPermissionRequest},
	"stop":               {kind: domain.BlockEventStop},
}

// Mappers is keyed by the agent token in `opr hooks <agent> <event>`.
var Mappers = map[string]MapFunc{
	"claude-code": fromTable(claudeCodeEvents),
	"grok":        fromTable(claudeCodeEvents),
	"codex":       fromTable(codexEvents),
}

// Map resolves harness and event. An unregistered harness yields an unknown,
// kept decision so the caller can record the event without inventing a kind.
func Map(harness, event string) Decision {
	mapper, found := Mappers[harness]
	if !found {
		return Decision{Kind: domain.BlockEventUnknown}
	}
	return mapper(event)
}
