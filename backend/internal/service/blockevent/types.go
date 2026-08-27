package blockevent

import (
	"context"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/redact"
)

// Record is one normalized, redacted block event. Seq is assigned by the store
// and is the resume cursor a reconnecting client sends back.
//
// SourceID is minted by whatever produced the event — a hook's tool_use_id
// today, a shell mark's counter later. It is never invented here: a consumer
// that invents ids cannot deduplicate on reconnect and cannot correlate a
// tool completion with the prompt that caused it.
type Record struct {
	Seq            int64                 `json:"seq"`
	SessionID      string                `json:"sessionId"`
	SourceID       string                `json:"sourceId,omitempty"`
	Kind           domain.BlockEventKind `json:"kind"`
	RawEvent       string                `json:"rawEvent,omitempty"`
	Harness        string                `json:"harness,omitempty"`
	ToolName       string                `json:"toolName,omitempty"`
	ToolUseID      string                `json:"toolUseId,omitempty"`
	ToolInput      string                `json:"toolInput,omitempty"`
	Text           string                `json:"text,omitempty"`
	RedactedSpans  []redact.Span         `json:"redactedSpans,omitempty"`
	ErrorType      string                `json:"errorType,omitempty"`
	HookVersion    string                `json:"hookVersion,omitempty"`
	TruncatedLines int                   `json:"truncatedLines,omitempty"`
	CreatedAt      time.Time             `json:"createdAt"`
}

// Store is the persistence slice the service needs.
type Store interface {
	InsertBlockEvent(ctx context.Context, rec Record) (int64, error)
	SelectBlockEventsBySession(ctx context.Context, sessionID string, afterSeq int64, limit int) ([]Record, error)
	TrimBlockEvents(ctx context.Context, sessionID string, keep int) (int64, error)
}

// Publisher fans a recorded event out to live clients.
type Publisher interface {
	PublishBlockEvent(sessionID string, rec Record)
}
