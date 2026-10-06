package claudecode

import (
	"encoding/json"
	"regexp"
	"strconv"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type claudeTranscriptRecord struct {
	Type           string `json:"type"`
	Subtype        string `json:"subtype"`
	Operation      string `json:"operation"`
	Timestamp      string `json:"timestamp"`
	Version        string `json:"version"`
	PermissionMode string `json:"permissionMode"`
	Origin         struct {
		Kind string `json:"kind"`
	} `json:"origin"`
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

var claudePermissionModes = map[string]domain.PermissionMode{
	"default":           domain.PermissionModeDefault,
	"acceptEdits":       domain.PermissionModeAcceptEdits,
	"plan":              domain.PermissionModePlan,
	"auto":              domain.PermissionModeAuto,
	"bypassPermissions": domain.PermissionModeBypassPermissions,
}

// MapTranscriptRecord maps one line of Claude Code's native JSONL transcript
// onto zero or more block transcript events. ok=false means the record type was
// not recognised; the caller counts those so a harness upgrade degrades to
// fewer blocks rather than to a crash.
func MapTranscriptRecord(line []byte) ([]domain.BlockTranscriptEvent, bool) {
	return NewTranscriptMapper("").Map(line)
}

func MapSidechainRecord(agentID string, line []byte) ([]domain.BlockTranscriptEvent, bool) {
	return NewTranscriptMapper(agentID).Map(line)
}

func mapClaudeRecord(rec claudeTranscriptRecord, sidechain bool) ([]domain.BlockTranscriptEvent, bool) {
	switch rec.Type {
	case "assistant":
		return claudeAssistantEvents(rec), true
	case "user":
		events := claudeUserEvents(rec)
		if len(events) == 0 {
			text := strings.TrimSpace(claudeFlattenText(rec.Message.Content))
			switch {
			case sidechain && text != "":
				events = append(events, domain.BlockTranscriptEvent{
					Kind:     domain.BlockEventPromptSubmit,
					SourceID: rec.UUID,
					Text:     text,
				})
			case !sidechain:
				if agentID := claudeHandBackAgent(text); agentID != "" {
					events = append(events, domain.BlockTranscriptEvent{
						Kind:     domain.BlockEventAgentStop,
						SourceID: agentID,
						Text:     text,
					})
				}
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

var claudeHandBack = regexp.MustCompile(`<agent-message from="([^"]+)">`)

func claudeHandBackAgent(text string) string {
	match := claudeHandBack.FindStringSubmatch(text)
	if match == nil {
		return ""
	}
	return match[1]
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
	detail := map[string]any{"agentId": result.AgentID}
	for key, value := range map[string]string{
		"agentType":     result.AgentType,
		"status":        result.Status,
		"resolvedModel": result.ResolvedModel,
	} {
		if value != "" {
			detail[key] = value
		}
	}
	if result.TotalDurationMs > 0 {
		detail["totalDurationMs"] = result.TotalDurationMs
	}
	if result.TotalToolUseCount > 0 {
		detail["totalToolUseCount"] = result.TotalToolUseCount
	}
	if result.TotalTokens > 0 {
		detail["totalTokens"] = result.TotalTokens
	}
	encoded, err := json.Marshal(detail)
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
