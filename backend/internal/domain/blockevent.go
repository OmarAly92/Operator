package domain

// BlockEventKind is the harness-independent vocabulary a block event is
// normalized into. Harness-native names are mapped onto it by per-harness
// mappers; an unrecognized name becomes BlockEventUnknown and keeps its raw
// name alongside, so a harness update degrades to less detail rather than a gap.
type BlockEventKind string

const (
	BlockEventSessionStart      BlockEventKind = "session_start"
	BlockEventPromptSubmit      BlockEventKind = "prompt_submit"
	BlockEventToolComplete      BlockEventKind = "tool_complete"
	BlockEventStop              BlockEventKind = "stop"
	BlockEventStopFailure       BlockEventKind = "stop_failure"
	BlockEventPermissionRequest BlockEventKind = "permission_request"
	BlockEventPermissionReplied BlockEventKind = "permission_replied"
	BlockEventQuestionAsked     BlockEventKind = "question_asked"
	BlockEventIdlePrompt        BlockEventKind = "idle_prompt"
	BlockEventUnknown           BlockEventKind = "unknown"
)

// ParseBlockEventKind resolves a normalized name. ok=false means the caller
// must keep the raw name on the event and emit BlockEventUnknown.
func ParseBlockEventKind(s string) (BlockEventKind, bool) {
	switch BlockEventKind(s) {
	case BlockEventSessionStart, BlockEventPromptSubmit, BlockEventToolComplete,
		BlockEventStop, BlockEventStopFailure, BlockEventPermissionRequest,
		BlockEventPermissionReplied, BlockEventQuestionAsked, BlockEventIdlePrompt:
		return BlockEventKind(s), true
	default:
		return BlockEventUnknown, false
	}
}
