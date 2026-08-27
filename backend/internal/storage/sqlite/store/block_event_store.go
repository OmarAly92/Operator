package store

import (
	"context"
	"encoding/json"
	"fmt"

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
		rec := blockeventsvc.Record{
			Seq:            row.Seq,
			SessionID:      row.SessionID,
			SourceID:       row.SourceID,
			Kind:           domain.BlockEventKind(row.Kind),
			RawEvent:       row.RawEvent,
			Harness:        row.Harness,
			ToolName:       row.ToolName,
			ToolUseID:      row.ToolUseID,
			ToolInput:      row.ToolInput,
			Text:           row.Text,
			ErrorType:      row.ErrorType,
			HookVersion:    row.HookVersion,
			TruncatedLines: int(row.TruncatedLines),
			CreatedAt:      row.CreatedAt,
		}
		if row.RedactedSpans != "" {
			var spans []redact.Span
			if err := json.Unmarshal([]byte(row.RedactedSpans), &spans); err == nil {
				rec.RedactedSpans = spans
			}
		}
		out = append(out, rec)
	}
	return out, nil
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
