package domain

// BlockEventKind is the harness-independent vocabulary a block event is
// normalized into. Harness-native names are mapped onto it by per-harness
// mappers; an unrecognized name becomes BlockEventUnknown and keeps its raw
// name alongside, so a harness update degrades to less detail rather than a gap.
type BlockEventKind string

// BlockEventKind values are the harness-independent vocabulary a block event is
// normalized into. The recognized names are everything above BlockEventUnknown,
// which carries an unrecognized event through with its raw name preserved.
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
	BlockEventAssistantText     BlockEventKind = "assistant_text"
	BlockEventReasoning         BlockEventKind = "reasoning"
	BlockEventToolStart         BlockEventKind = "tool_start"
	BlockEventToolResult        BlockEventKind = "tool_result"
	BlockEventTodo              BlockEventKind = "todo"
	BlockEventTurnModel         BlockEventKind = "turn_model"
	BlockEventCompaction        BlockEventKind = "compaction"
	BlockEventUnknown           BlockEventKind = "unknown"
)

// ParseBlockEventKind resolves a normalized name. ok=false means the caller
// must keep the raw name on the event and emit BlockEventUnknown.
func ParseBlockEventKind(s string) (BlockEventKind, bool) {
	switch BlockEventKind(s) {
	case BlockEventSessionStart, BlockEventPromptSubmit, BlockEventToolComplete,
		BlockEventStop, BlockEventStopFailure, BlockEventPermissionRequest,
		BlockEventPermissionReplied, BlockEventQuestionAsked, BlockEventIdlePrompt,
		BlockEventAssistantText, BlockEventReasoning, BlockEventToolStart,
		BlockEventToolResult, BlockEventTodo, BlockEventTurnModel, BlockEventCompaction:
		return BlockEventKind(s), true
	default:
		return BlockEventUnknown, false
	}
}

// BlockEventSource names the channel a block event came from. Hooks are the
// status source and the native transcript is the body source; the projection
// applies precedence between them, so a client must be able to tell them apart.
type BlockEventSource string

// BlockEventSource values.
const (
	BlockEventSourceHook       BlockEventSource = "hook"
	BlockEventSourceTranscript BlockEventSource = "transcript"
)

// BlockTranscriptEvent is one per-harness transcript mapper's output. It lives
// in domain so an adapter package can produce it and the block-event service can
// consume it without either importing the other.
type BlockTranscriptEvent struct {
	Kind      BlockEventKind
	SourceID  string
	ToolName  string
	ToolUseID string
	ToolInput string
	Text      string
	ErrorType string
	RawEvent  string
}
