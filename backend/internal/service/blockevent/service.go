package blockevent

import (
	"context"
	"strings"
	"sync/atomic"
	"time"
	"unicode/utf8"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/blockdispatch"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/redact"
)

// maxTextBytes caps one event's text. A single tool result can be enormous and
// this log is replayed to a phone over Tailscale, so the tail is dropped and
// the drop is counted rather than hidden.
const maxTextBytes = 16 << 10

// trimEvery bounds how often a session's log is trimmed. Trimming on every
// insert would put a delete in the path of every hook callback.
const trimEvery = 64

// Service turns hook signals into normalized, redacted, persisted block events.
type Service struct {
	store  Store
	pub    Publisher
	retain int
	// writes counts recorded events to pace trimming. Record is called
	// concurrently from HTTP handlers, so it must be atomic.
	writes atomic.Int64
}

// NewService builds the service. retain is how many events one session keeps.
func NewService(store Store, pub Publisher, retain int) *Service {
	if retain <= 0 {
		retain = 500
	}
	return &Service{store: store, pub: pub, retain: retain}
}

// Record normalizes one activity signal into a block event. A signal carrying
// no event name is not a block event and is ignored: activity and usage still
// consume it independently.
func (s *Service) Record(ctx context.Context, sessionID domain.SessionID, harness string, sig ports.ActivitySignal) error {
	if strings.TrimSpace(sig.Event) == "" {
		return nil
	}
	decision := blockdispatch.Map(harness, sig.Event)
	if decision.Drop {
		return nil
	}

	text := sig.LatestAssistantUpdate
	if text == "" {
		text = sig.LatestUserPrompt
	}
	truncated := 0
	if len(text) > maxTextBytes {
		cut := maxTextBytes
		for cut > 0 && !utf8.RuneStart(text[cut]) {
			cut--
		}
		truncated = strings.Count(text[cut:], "\n") + 1
		text = text[:cut]
	}
	redacted := redact.Text(text)
	redactedInput := redact.Text(sig.ToolInput)

	sourceID := sig.ToolUseID
	if sourceID == "" {
		sourceID = sig.AgentSessionID
	}

	rec := Record{
		SessionID:      string(sessionID),
		SourceID:       sourceID,
		Kind:           decision.Kind,
		Source:         domain.BlockEventSourceHook,
		Harness:        harness,
		ToolName:       sig.ToolName,
		ToolUseID:      sig.ToolUseID,
		ToolInput:      redactedInput.Text,
		Text:           redacted.Text,
		RedactedSpans:  redacted.Spans,
		ErrorType:      decision.ErrorType,
		HookVersion:    sig.HookVersion,
		TruncatedLines: truncated,
		CreatedAt:      time.Now().UTC(),
	}
	if !decision.Known {
		rec.RawEvent = sig.Event
	}

	seq, err := s.store.InsertBlockEvent(ctx, rec)
	if err != nil {
		return err
	}
	rec.Seq = seq

	if s.writes.Add(1)%trimEvery == 0 {
		_, _ = s.store.TrimBlockEvents(ctx, string(sessionID), s.retain)
	}

	if s.pub != nil {
		s.pub.PublishBlockEvent(string(sessionID), rec)
	}
	return nil
}

// History returns persisted events after afterSeq so a reconnecting client can
// replay what it missed instead of only seeing what arrives next.
func (s *Service) History(ctx context.Context, sessionID domain.SessionID, afterSeq int64, limit int) ([]Record, error) {
	if limit <= 0 || limit > s.retain {
		limit = s.retain
	}
	return s.store.SelectBlockEventsBySession(ctx, string(sessionID), afterSeq, limit)
}

// HistoryBefore returns the events immediately older than beforeSeq, ascending,
// so a client whose window has slid forward can page backwards into what it
// dropped instead of losing it.
func (s *Service) HistoryBefore(ctx context.Context, sessionID domain.SessionID, beforeSeq int64, limit int) ([]Record, error) {
	if limit <= 0 || limit > s.retain {
		limit = s.retain
	}
	return s.store.SelectBlockEventsBeforeSeq(ctx, string(sessionID), beforeSeq, limit)
}
