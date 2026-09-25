package blockevent

import (
	"context"
	"encoding/json"
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

// maxTranscriptTextBytes is the transcript channel's body budget. A tool result
// is the largest thing the phone ever sees and truncating it to the hook budget
// would hide most of it, so the transcript gets four times the room; the cut is
// still counted rather than hidden.
const maxTranscriptTextBytes = 64 << 10

// maxTranscriptToolInputBytes caps a tool's full input separately from its
// result: an input that big is a generated file, not something a phone renders.
const maxTranscriptToolInputBytes = 16 << 10

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
	text, truncated := capText(text, maxTextBytes)
	redacted := redact.Text(text)
	redactedInput := redact.Text(sig.ToolInput)

	sourceID := sig.ToolUseID
	if sourceID == "" {
		sourceID = sig.AgentSessionID
	}
	if sig.AgentID != "" {
		sourceID = sig.AgentID
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
		InteractionID:  sig.InteractionID,
		CreatedAt:      time.Now().UTC(),
	}
	if !decision.Known {
		rec.RawEvent = sig.Event
	}

	return s.persist(ctx, rec)
}

// RecordTranscript normalizes one provider-transcript record into a block
// event. It is the body channel's entry point: same redaction, caps, store,
// trim and publish as a hook event, marked so the projection can apply
// precedence between the two channels.
func (s *Service) RecordTranscript(
	ctx context.Context,
	sessionID domain.SessionID,
	harness string,
	ev domain.BlockTranscriptEvent,
) error {
	if ev.Kind == "" {
		return nil
	}
	detail := ev.Detail
	if ev.Kind == domain.BlockEventTaskUpdate {
		redactedDetail, ok := redactTaskDetail(detail)
		if !ok {
			return nil
		}
		detail = redactedDetail
	}
	text, textTruncated := capText(ev.Text, maxTranscriptTextBytes)
	input, inputTruncated := capText(ev.ToolInput, maxTranscriptToolInputBytes)
	redacted := redact.Text(text)
	redactedInput := redact.Text(input)

	return s.persist(ctx, Record{
		SessionID:      string(sessionID),
		SourceID:       ev.SourceID,
		Kind:           ev.Kind,
		Source:         domain.BlockEventSourceTranscript,
		RawEvent:       ev.RawEvent,
		Harness:        harness,
		ToolName:       ev.ToolName,
		ToolUseID:      ev.ToolUseID,
		ToolInput:      redactedInput.Text,
		Text:           redacted.Text,
		RedactedSpans:  redacted.Spans,
		ErrorType:      ev.ErrorType,
		TruncatedLines: textTruncated + inputTruncated,
		AgentID:        ev.AgentID,
		Detail:         detail,
		CreatedAt:      time.Now().UTC(),
	})
}

// LatestModels maps every session with a recorded turn to the model that
// turn ran on. The board shows it next to the harness.
func (s *Service) LatestModels(ctx context.Context) (map[domain.SessionID]string, error) {
	rows, err := s.store.SelectLatestTurnModels(ctx)
	if err != nil {
		return nil, err
	}
	out := make(map[domain.SessionID]string, len(rows))
	for id, model := range rows {
		out[domain.SessionID(id)] = model
	}
	return out, nil
}

// History returns persisted events after afterSeq so a reconnecting client can
// replay what it missed instead of only seeing what arrives next.
func (s *Service) History(ctx context.Context, sessionID domain.SessionID, agentID string, afterSeq int64, limit int) ([]Record, error) {
	if limit <= 0 || limit > s.retain {
		limit = s.retain
	}
	return s.store.SelectBlockEventsBySession(ctx, string(sessionID), agentID, afterSeq, limit)
}

// HistoryBefore returns the events immediately older than beforeSeq, ascending,
// so a client whose window has slid forward can page backwards into what it
// dropped instead of losing it.
func (s *Service) HistoryBefore(ctx context.Context, sessionID domain.SessionID, agentID string, beforeSeq int64, limit int) ([]Record, error) {
	if limit <= 0 || limit > s.retain {
		limit = s.retain
	}
	return s.store.SelectBlockEventsBeforeSeq(ctx, string(sessionID), agentID, beforeSeq, limit)
}

func (s *Service) TaskUpdates(ctx context.Context, sessionID domain.SessionID) ([]Record, error) {
	return s.store.SelectTaskUpdates(ctx, string(sessionID))
}

func redactTaskDetail(detail string) (string, bool) {
	var task domain.BackgroundTask
	if err := json.Unmarshal([]byte(detail), &task); err != nil || task.TaskID == "" {
		return "", false
	}
	task.Description = redact.Text(task.Description).Text
	task.Command = redact.Text(task.Command).Text
	task.Summary = redact.Text(task.Summary).Text
	encoded, err := json.Marshal(task)
	if err != nil {
		return "", false
	}
	return string(encoded), true
}

func capText(s string, limit int) (string, int) {
	if len(s) <= limit {
		return s, 0
	}
	cut := limit
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	return s[:cut], strings.Count(s[cut:], "\n") + 1
}

func (s *Service) persist(ctx context.Context, rec Record) error {
	seq, err := s.store.InsertBlockEvent(ctx, rec)
	if err != nil {
		return err
	}
	rec.Seq = seq

	if s.writes.Add(1)%trimEvery == 0 {
		_, _ = s.store.TrimBlockEvents(ctx, rec.SessionID, rec.AgentID, s.retain)
	}

	if s.pub != nil {
		s.pub.PublishBlockEvent(rec.SessionID, rec)
	}
	return nil
}
