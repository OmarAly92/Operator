package codex

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type codexRolloutRecord struct {
	Timestamp string          `json:"timestamp"`
	Type      string          `json:"type"`
	Payload   json.RawMessage `json:"payload"`
}

type codexRolloutPayload struct {
	Type      string          `json:"type"`
	ID        string          `json:"id"`
	Role      string          `json:"role"`
	Phase     string          `json:"phase"`
	Content   []codexTextPart `json:"content"`
	Summary   []codexTextPart `json:"summary"`
	Name      string          `json:"name"`
	CallID    string          `json:"call_id"`
	Arguments string          `json:"arguments"`
	Input     string          `json:"input"`
	Output    json.RawMessage `json:"output"`
	Model     string          `json:"model"`
}

type codexTextPart struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

// codexIgnoredEventMsgTypes are UI events that duplicate a response_item or a
// hook. token_count is the usage observer's business and sub_agent_activity is
// deferred with Claude's sidechain records.
var codexIgnoredEventMsgTypes = map[string]struct{}{
	"task_started":            {},
	"task_complete":           {},
	"user_message":            {},
	"agent_message":           {},
	"agent_reasoning":         {},
	"exec_command_end":        {},
	"patch_apply_end":         {},
	"token_count":             {},
	"sub_agent_activity":      {},
	"turn_aborted":            {},
	"item_completed":          {},
	"web_search_end":          {},
	"thread_settings_applied": {},
	"thread_rolled_back":      {},
	"error":                   {},
}

var codexIgnoredRecordTypes = map[string]struct{}{
	"session_meta":                       {},
	"token_usage_record":                 {},
	"world_state":                        {},
	"inter_agent_communication_metadata": {},
}

// MapTranscriptRecord maps one line of Codex's rollout JSONL onto zero or more
// block transcript events. ok=false means the record or event type was not
// recognised; the caller counts those.
func MapTranscriptRecord(line []byte) ([]domain.BlockTranscriptEvent, bool) {
	var rec codexRolloutRecord
	if err := json.Unmarshal(line, &rec); err != nil {
		return nil, false
	}
	switch rec.Type {
	case "response_item":
		return codexResponseItemEvents(rec, line)
	case "turn_context":
		var payload codexRolloutPayload
		if err := json.Unmarshal(rec.Payload, &payload); err != nil {
			return nil, false
		}
		if strings.TrimSpace(payload.Model) == "" {
			return nil, true
		}
		return []domain.BlockTranscriptEvent{{
			Kind:     domain.BlockEventTurnModel,
			SourceID: codexLineID(line),
			Text:     payload.Model,
		}}, true
	case "compacted":
		return []domain.BlockTranscriptEvent{codexCompactionEvent(rec)}, true
	case "event_msg":
		var payload codexRolloutPayload
		if err := json.Unmarshal(rec.Payload, &payload); err != nil {
			return nil, false
		}
		if payload.Type == "context_compacted" {
			return []domain.BlockTranscriptEvent{codexCompactionEvent(rec)}, true
		}
		if _, ignored := codexIgnoredEventMsgTypes[payload.Type]; ignored {
			return nil, true
		}
		return nil, false
	default:
		if _, ignored := codexIgnoredRecordTypes[rec.Type]; ignored {
			return nil, true
		}
		return nil, false
	}
}

func codexResponseItemEvents(rec codexRolloutRecord, line []byte) ([]domain.BlockTranscriptEvent, bool) {
	var payload codexRolloutPayload
	if err := json.Unmarshal(rec.Payload, &payload); err != nil {
		return nil, false
	}
	id := strings.TrimSpace(payload.ID)
	if id == "" {
		id = codexLineID(line)
	}
	switch payload.Type {
	case "message":
		if payload.Role != "assistant" {
			return nil, true
		}
		text := codexJoinText(payload.Content)
		if strings.TrimSpace(text) == "" {
			return nil, true
		}
		return []domain.BlockTranscriptEvent{{
			Kind:     domain.BlockEventAssistantText,
			SourceID: id,
			Text:     text,
			RawEvent: payload.Phase,
		}}, true
	case "reasoning":
		text := codexJoinText(payload.Summary)
		if strings.TrimSpace(text) == "" {
			return nil, true
		}
		return []domain.BlockTranscriptEvent{{
			Kind:     domain.BlockEventReasoning,
			SourceID: id,
			Text:     text,
		}}, true
	case "function_call", "custom_tool_call":
		input := payload.Arguments
		if input == "" {
			input = payload.Input
		}
		return []domain.BlockTranscriptEvent{{
			Kind:      domain.BlockEventToolStart,
			SourceID:  payload.CallID,
			ToolUseID: payload.CallID,
			ToolName:  payload.Name,
			ToolInput: input,
		}}, true
	case "function_call_output", "custom_tool_call_output":
		return []domain.BlockTranscriptEvent{{
			Kind:      domain.BlockEventToolResult,
			SourceID:  payload.CallID,
			ToolUseID: payload.CallID,
			Text:      codexOutputText(payload.Output),
		}}, true
	default:
		return nil, false
	}
}

// codexCompactionEvent keys both halves of one compaction — the `compacted`
// history record and its `context_compacted` UI event, written milliseconds
// apart — on the same second, so the projection collapses them into one block.
func codexCompactionEvent(rec codexRolloutRecord) domain.BlockTranscriptEvent {
	timestamp := rec.Timestamp
	if len(timestamp) >= 19 {
		timestamp = timestamp[:19]
	}
	return domain.BlockTranscriptEvent{
		Kind:     domain.BlockEventCompaction,
		SourceID: "compaction:" + timestamp,
		Text:     "Conversation compacted",
	}
}

func codexJoinText(parts []codexTextPart) string {
	texts := make([]string, 0, len(parts))
	for _, part := range parts {
		if part.Text != "" {
			texts = append(texts, part.Text)
		}
	}
	return strings.Join(texts, "\n")
}

func codexOutputText(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return text
	}
	return string(raw)
}

func codexLineID(line []byte) string {
	sum := sha256.Sum256(line)
	return hex.EncodeToString(sum[:8])
}
