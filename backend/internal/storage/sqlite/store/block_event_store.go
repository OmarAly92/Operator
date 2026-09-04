package store

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/redact"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

var _ blockeventsvc.Store = (*Store)(nil)

// InsertBlockEvent appends one event and returns its assigned sequence.
func (s *Store) InsertBlockEvent(ctx context.Context, rec blockeventsvc.Record) (int64, error) {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	spans := ""
	if len(rec.RedactedSpans) > 0 {
		encoded, err := json.Marshal(rec.RedactedSpans)
		if err != nil {
			return 0, fmt.Errorf("encode redacted spans: %w", err)
		}
		spans = string(encoded)
	}
	row, err := s.qw.InsertBlockEvent(ctx, gen.InsertBlockEventParams{
		SessionID:      rec.SessionID,
		SourceID:       rec.SourceID,
		Kind:           string(rec.Kind),
		RawEvent:       rec.RawEvent,
		Harness:        rec.Harness,
		ToolName:       rec.ToolName,
		ToolUseID:      rec.ToolUseID,
		ToolInput:      rec.ToolInput,
		Text:           rec.Text,
		RedactedSpans:  spans,
		ErrorType:      rec.ErrorType,
		HookVersion:    rec.HookVersion,
		TruncatedLines: int64(rec.TruncatedLines),
		Source:         string(rec.Source),
		CreatedAt:      rec.CreatedAt,
	})
	if err != nil {
		return 0, fmt.Errorf("insert block event for %s: %w", rec.SessionID, err)
	}
	return row.Seq, nil
}

// SelectBlockEventsBySession returns events after afterSeq in ascending order.
func (s *Store) SelectBlockEventsBySession(ctx context.Context, sessionID string, afterSeq int64, limit int) ([]blockeventsvc.Record, error) {
	rows, err := s.qr.SelectBlockEventsBySession(ctx, gen.SelectBlockEventsBySessionParams{
		SessionID: sessionID,
		Seq:       afterSeq,
		Limit:     int64(limit),
	})
	if err != nil {
		return nil, fmt.Errorf("select block events for %s: %w", sessionID, err)
	}
	out := make([]blockeventsvc.Record, 0, len(rows))
	for _, row := range rows {
		out = append(out, blockEventRecordFromRow(blockEventRowFields{
			Seq:            row.Seq,
			SessionID:      row.SessionID,
			SourceID:       row.SourceID,
			Kind:           row.Kind,
			RawEvent:       row.RawEvent,
			Harness:        row.Harness,
			ToolName:       row.ToolName,
			ToolUseID:      row.ToolUseID,
			ToolInput:      row.ToolInput,
			Text:           row.Text,
			RedactedSpans:  row.RedactedSpans,
			ErrorType:      row.ErrorType,
			HookVersion:    row.HookVersion,
			TruncatedLines: row.TruncatedLines,
			Source:         row.Source,
			CreatedAt:      row.CreatedAt,
		}))
	}
	return out, nil
}

// SelectBlockEventsBeforeSeq returns the events immediately older than
// beforeSeq in ascending order so a client whose window has slid forward can
// page backwards into what it dropped instead of losing it.
func (s *Store) SelectBlockEventsBeforeSeq(ctx context.Context, sessionID string, beforeSeq int64, limit int) ([]blockeventsvc.Record, error) {
	rows, err := s.qr.SelectBlockEventsBeforeSeq(ctx, gen.SelectBlockEventsBeforeSeqParams{
		SessionID: sessionID,
		Seq:       beforeSeq,
		Limit:     int64(limit),
	})
	if err != nil {
		return nil, fmt.Errorf("select block events before %d for %s: %w", beforeSeq, sessionID, err)
	}
	out := make([]blockeventsvc.Record, 0, len(rows))
	for _, row := range rows {
		out = append(out, blockEventRecordFromRow(blockEventRowFields{
			Seq:            row.Seq,
			SessionID:      row.SessionID,
			SourceID:       row.SourceID,
			Kind:           row.Kind,
			RawEvent:       row.RawEvent,
			Harness:        row.Harness,
			ToolName:       row.ToolName,
			ToolUseID:      row.ToolUseID,
			ToolInput:      row.ToolInput,
			Text:           row.Text,
			RedactedSpans:  row.RedactedSpans,
			ErrorType:      row.ErrorType,
			HookVersion:    row.HookVersion,
			TruncatedLines: row.TruncatedLines,
			Source:         row.Source,
			CreatedAt:      row.CreatedAt,
		}))
	}
	return out, nil
}

// blockEventRowFields is the field set shared by the generated row types for
// SelectBlockEventsBySession and SelectBlockEventsBeforeSeq, which sqlc emits
// as distinct structs with differing field order.
type blockEventRowFields struct {
	Seq            int64
	SessionID      string
	SourceID       string
	Kind           string
	RawEvent       string
	Harness        string
	ToolName       string
	ToolUseID      string
	ToolInput      string
	Text           string
	RedactedSpans  string
	ErrorType      string
	HookVersion    string
	TruncatedLines int64
	Source         string
	CreatedAt      time.Time
}

func blockEventRecordFromRow(f blockEventRowFields) blockeventsvc.Record {
	rec := blockeventsvc.Record{
		Seq:            f.Seq,
		SessionID:      f.SessionID,
		SourceID:       f.SourceID,
		Kind:           domain.BlockEventKind(f.Kind),
		RawEvent:       f.RawEvent,
		Harness:        f.Harness,
		ToolName:       f.ToolName,
		ToolUseID:      f.ToolUseID,
		ToolInput:      f.ToolInput,
		Text:           f.Text,
		ErrorType:      f.ErrorType,
		HookVersion:    f.HookVersion,
		TruncatedLines: int(f.TruncatedLines),
		Source:         domain.BlockEventSource(f.Source),
		CreatedAt:      f.CreatedAt,
	}
	if f.RedactedSpans != "" {
		var spans []redact.Span
		if err := json.Unmarshal([]byte(f.RedactedSpans), &spans); err == nil {
			rec.RedactedSpans = spans
		}
	}
	return rec
}

// TrimBlockEvents drops all but the newest keep rows for one session. Trimming
// is per session so a busy session cannot evict a quiet one's history.
func (s *Store) TrimBlockEvents(ctx context.Context, sessionID string, keep int) (int64, error) {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.TrimBlockEventsForSession(ctx, gen.TrimBlockEventsForSessionParams{
		SessionID:   sessionID,
		SessionID_2: sessionID,
		Offset:      int64(keep - 1),
	})
	if err != nil {
		return 0, fmt.Errorf("trim block events for %s: %w", sessionID, err)
	}
	return n, nil
}
