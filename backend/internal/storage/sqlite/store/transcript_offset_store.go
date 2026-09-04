package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

// GetTranscriptOffset returns the durable read cursor for one session's native
// transcript. found=false means the session has never been tailed.
func (s *Store) GetTranscriptOffset(ctx context.Context, sessionID string) (string, int64, bool, error) {
	row, err := s.qr.GetTranscriptOffset(ctx, sessionID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", 0, false, nil
	}
	if err != nil {
		return "", 0, false, fmt.Errorf("get transcript offset for %s: %w", sessionID, err)
	}
	return row.Path, row.ByteOffset, true, nil
}

// UpsertTranscriptOffset advances the cursor. A different path replaces the row
// wholesale: an offset from another file cannot be resumed against this one.
func (s *Store) UpsertTranscriptOffset(ctx context.Context, sessionID, path string, offset int64, at time.Time) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	if err := s.qw.UpsertTranscriptOffset(ctx, gen.UpsertTranscriptOffsetParams{
		SessionID:  sessionID,
		Path:       path,
		ByteOffset: offset,
		UpdatedAt:  at,
	}); err != nil {
		return fmt.Errorf("upsert transcript offset for %s: %w", sessionID, err)
	}
	return nil
}
