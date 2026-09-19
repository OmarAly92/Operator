package claudecode

import (
	"encoding/json"
	"strconv"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type claudeTranscriptRecord struct {
	Type            string          `json:"type"`
	Subtype         string          `json:"subtype"`
	UUID            string          `json:"uuid"`
	IsSidechain     bool            `json:"isSidechain"`
	AgentID         string          `json:"agentId"`
	Content         json.RawMessage `json:"content"`
	ToolUseResult   json.RawMessage `json:"toolUseResult"`
	CompactMetadata struct {
		Trigger string `json:"trigger"`
	} `json:"compactMetadata"`
	Message struct {
		Model   string          `json:"model"`
		Content json.RawMessage `json:"content"`
	} `json:"message"`
}

type claudeContentBlock struct {
	Type      string          `json:"type"`
	Text      string          `json:"text"`
	Thinking  string          `json:"thinking"`
	ID        string          `json:"id"`
	Name      string          `json:"name"`
	Input     json.RawMessage `json:"input"`
	ToolUseID string          `json:"tool_use_id"`
	Content   json.RawMessage `json:"content"`
	IsError   bool            `json:"is_error"`
}

// claudeIgnoredRecordTypes are bookkeeping records that carry no user-facing
// content. They are listed rather than defaulted so a record type Claude Code
// adds in a future release is reported as unrecognised instead of silently
// dropped.
var claudeIgnoredRecordTypes = map[string]struct{}{
	"attachment":            {},
	"last-prompt":           {},
	"queue-operation":       {},
	"mode":                  {},
	"permission-mode":       {},
	"bridge-session":        {},
	"atis-latch":            {},
	"ai-title":              {},
	"summary":               {},
	"file-history-snapshot": {},
}

// MapTranscriptRecord maps one line of Claude Code's native JSONL transcript
// onto zero or more block transcript events. ok=false means the record type was
// not recognised; the caller counts those so a harness upgrade degrades to
// fewer blocks rather than to a crash.
func MapTranscriptRecord(line []byte) ([]domain.BlockTranscriptEvent, bool) {
	var rec claudeTranscriptRecord
	if err := json.Unmarshal(line, &rec); err != nil {
		return nil, false
	}
	if rec.IsSidechain {
		return nil, true
	}
	return mapClaudeRecord(rec, false)
}

func MapSidechainRecord(agentID string, line []byte) ([]domain.BlockTranscriptEvent, bool) {
	var rec claudeTranscriptRecord
	if err := json.Unmarshal(line, &rec); err != nil {
		return nil, false
	}
	events, ok := mapClaudeRecord(rec, true)
	for i := range events {
		events[i].AgentID = agentID
	}
	return events, ok
}

func mapClaudeRecord(rec claudeTranscriptRecord, sidechain bool) ([]domain.BlockTranscriptEvent, bool) {
	switch rec.Type {
	case "assistant":
		return claudeAssistantEvents(rec), true
	case "user":
		events := claudeUserEvents(rec)
		if sidechain && len(events) == 0 {
			if prompt := strings.TrimSpace(claudeFlattenText(rec.Message.Content)); prompt != "" {
				events = append(events, domain.BlockTranscriptEvent{
					Kind:     domain.BlockEventPromptSubmit,
					SourceID: rec.UUID,
					Text:     prompt,
				})
			}
		}
		return events, true
	case "system":
		if rec.Subtype != "compact_boundary" {
			return nil, true
		}
		return []domain.BlockTranscriptEvent{{
			Kind:     domain.BlockEventCompaction,
			SourceID: rec.UUID,
			Text:     claudeCompactionText(rec),
		}}, true
	default:
		if _, ignored := claudeIgnoredRecordTypes[rec.Type]; ignored {
			return nil, true
		}
		return nil, false
	}
}

func claudeAssistantEvents(rec claudeTranscriptRecord) []domain.BlockTranscriptEvent {
	events := make([]domain.BlockTranscriptEvent, 0, 4)
	if model := strings.TrimSpace(rec.Message.Model); model != "" {
		events = append(events, domain.BlockTranscriptEvent{
			Kind:     domain.BlockEventTurnModel,
			SourceID: rec.UUID,
			Text:     model,
		})
	}
	position := 0
	for _, block := range claudeContentBlocks(rec.Message.Content) {
		switch block.Type {
		case "text":
			if strings.TrimSpace(block.Text) == "" {
				continue
			}
			events = append(events, domain.BlockTranscriptEvent{
				Kind:     domain.BlockEventAssistantText,
				SourceID: claudeContentSourceID(rec.UUID, &position),
				Text:     block.Text,
			})
		case "thinking":
			if strings.TrimSpace(block.Thinking) == "" {
				continue
			}
			events = append(events, domain.BlockTranscriptEvent{
				Kind:     domain.BlockEventReasoning,
				SourceID: claudeContentSourceID(rec.UUID, &position),
				Text:     block.Thinking,
			})
		case "tool_use":
			events = append(events, claudeToolUseEvent(block))
		}
	}
	return events
}

// claudeContentSourceID disambiguates same-record content blocks by a single
// position counter shared across kinds, so a thinking block and a text block
// in the same assistant record never collide on the bare record UUID.
func claudeContentSourceID(uuid string, position *int) string {
	index := *position
	*position++
	if index == 0 {
		return uuid
	}
	return uuid + "#" + strconv.Itoa(index)
}

func claudeToolUseEvent(block claudeContentBlock) domain.BlockTranscriptEvent {
	input := strings.TrimSpace(string(block.Input))
	switch block.Name {
	case "TodoWrite":
		return domain.BlockTranscriptEvent{
			Kind:      domain.BlockEventTodo,
			SourceID:  block.ID,
			ToolUseID: block.ID,
			ToolName:  block.Name,
			ToolInput: input,
			Text:      input,
		}
	case "AskUserQuestion":
		return domain.BlockTranscriptEvent{
			Kind:      domain.BlockEventQuestionAsked,
			SourceID:  block.ID,
			ToolUseID: block.ID,
			ToolName:  block.Name,
			ToolInput: input,
		}
	default:
		return domain.BlockTranscriptEvent{
			Kind:      domain.BlockEventToolStart,
			SourceID:  block.ID,
			ToolUseID: block.ID,
			ToolName:  block.Name,
			ToolInput: input,
		}
	}
}

func claudeUserEvents(rec claudeTranscriptRecord) []domain.BlockTranscriptEvent {
	events := make([]domain.BlockTranscriptEvent, 0, 2)
	for _, block := range claudeContentBlocks(rec.Message.Content) {
		if block.Type != "tool_result" || block.ToolUseID == "" {
			continue
		}
		event := domain.BlockTranscriptEvent{
			Kind:      domain.BlockEventToolResult,
			SourceID:  block.ToolUseID,
			ToolUseID: block.ToolUseID,
			Text:      claudeFlattenText(block.Content),
		}
		if block.IsError {
			event.ErrorType = "tool_failed"
		}
		if detail := claudeAgentResultDetail(rec.ToolUseResult); detail != "" {
			event.Detail = detail
		}
		events = append(events, event)
	}
	return events
}

func claudeAgentResultDetail(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var result struct {
		AgentID           string `json:"agentId"`
		AgentType         string `json:"agentType"`
		Status            string `json:"status"`
		ResolvedModel     string `json:"resolvedModel"`
		TotalDurationMs   int64  `json:"totalDurationMs"`
		TotalToolUseCount int    `json:"totalToolUseCount"`
		TotalTokens       int64  `json:"totalTokens"`
	}
	if err := json.Unmarshal(raw, &result); err != nil || result.AgentID == "" {
		return ""
	}
	encoded, err := json.Marshal(map[string]any{
		"agentId":           result.AgentID,
		"agentType":         result.AgentType,
		"status":            result.Status,
		"resolvedModel":     result.ResolvedModel,
		"totalDurationMs":   result.TotalDurationMs,
		"totalToolUseCount": result.TotalToolUseCount,
		"totalTokens":       result.TotalTokens,
	})
	if err != nil {
		return ""
	}
	return string(encoded)
}

func claudeContentBlocks(raw json.RawMessage) []claudeContentBlock {
	if len(raw) == 0 {
		return nil
	}
	var blocks []claudeContentBlock
	if err := json.Unmarshal(raw, &blocks); err != nil {
		return nil
	}
	return blocks
}

func claudeFlattenText(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return text
	}
	blocks := claudeContentBlocks(raw)
	if blocks == nil {
		return strings.TrimSpace(string(raw))
	}
	parts := make([]string, 0, len(blocks))
	for _, block := range blocks {
		if block.Type == "text" && block.Text != "" {
			parts = append(parts, block.Text)
		}
	}
	return strings.Join(parts, "\n")
}

func claudeCompactionText(rec claudeTranscriptRecord) string {
	text := strings.TrimSpace(claudeFlattenText(rec.Content))
	if text == "" {
		text = "Conversation compacted"
	}
	if trigger := strings.TrimSpace(rec.CompactMetadata.Trigger); trigger != "" {
		text += " (" + trigger + ")"
	}
	return text
}
