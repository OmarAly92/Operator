package store

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	terminalblocksvc "github.com/OmarAly92/operator/backend/internal/service/terminalblock"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

var _ terminalblocksvc.Store = (*Store)(nil)

func (s *Store) UpsertTerminalBlock(ctx context.Context, b domain.Block) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	err := s.qw.UpsertTerminalBlock(ctx, gen.UpsertTerminalBlockParams{
		TerminalID:     b.TerminalID,
		SourceID:       b.SourceID,
		SessionID:      b.SessionID,
		Command:        b.Command,
		Cwd:            b.Cwd,
		GitBranch:      b.GitBranch,
		ExitCode:       nullableExitCode(b.ExitCode),
		RawOutput:      b.RawOutput,
		StartedAt:      nullableTime(b.StartedAt),
		FinishedAt:     b.FinishedAt,
		ShellKind:      b.ShellKind,
		ShellVersion:   b.ShellVersion,
		TruncatedLines: int64(b.TruncatedLines),
		TruncatedBytes: int64(b.TruncatedBytes),
		CaptureEpoch:   b.CaptureEpoch,
		StartOffset:    b.StartOffset,
		EndOffset:      b.EndOffset,
		CreatedAt:      b.CreatedAt,
	})
	if err != nil {
		return fmt.Errorf("upsert terminal block %s/%s: %w", b.TerminalID, b.SourceID, err)
	}
	return nil
}

func (s *Store) ListTerminalBlocks(ctx context.Context, terminalID string, limit int) ([]domain.Block, error) {
	if limit <= 0 {
		limit = 100
	}
	rows, err := s.qr.ListTerminalBlocks(ctx, gen.ListTerminalBlocksParams{
		TerminalID: terminalID,
		Limit:      int64(limit),
	})
	if err != nil {
		return nil, fmt.Errorf("list terminal blocks for %s: %w", terminalID, err)
	}
	out := make([]domain.Block, 0, len(rows))
	for _, row := range rows {
		out = append(out, terminalBlockFromGen(row))
	}
	return out, nil
}

func (s *Store) TrimTerminalBlocks(ctx context.Context, terminalID string, keep int) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	err := s.qw.TrimTerminalBlocks(ctx, gen.TrimTerminalBlocksParams{
		TerminalID:   terminalID,
		TerminalID_2: terminalID,
		Limit:        int64(keep),
	})
	if err != nil {
		return fmt.Errorf("trim terminal blocks for %s: %w", terminalID, err)
	}
	return nil
}

func (s *Store) DeleteTerminalBlocks(ctx context.Context, terminalID string) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	if err := s.qw.DeleteTerminalBlocks(ctx, terminalID); err != nil {
		return fmt.Errorf("delete terminal blocks for %s: %w", terminalID, err)
	}
	return nil
}

func nullableExitCode(code *int) sql.NullInt64 {
	if code == nil {
		return sql.NullInt64{}
	}
	return sql.NullInt64{Int64: int64(*code), Valid: true}
}

func nullableTime(t time.Time) sql.NullTime {
	if t.IsZero() {
		return sql.NullTime{}
	}
	return sql.NullTime{Time: t, Valid: true}
}

func terminalBlockFromGen(row gen.TerminalBlock) domain.Block {
	b := domain.Block{
		TerminalID:     row.TerminalID,
		SourceID:       row.SourceID,
		SessionID:      row.SessionID,
		Command:        row.Command,
		Cwd:            row.Cwd,
		GitBranch:      row.GitBranch,
		RawOutput:      row.RawOutput,
		FinishedAt:     row.FinishedAt,
		ShellKind:      row.ShellKind,
		ShellVersion:   row.ShellVersion,
		TruncatedLines: int(row.TruncatedLines),
		TruncatedBytes: int(row.TruncatedBytes),
		CaptureEpoch:   row.CaptureEpoch,
		StartOffset:    row.StartOffset,
		EndOffset:      row.EndOffset,
		CreatedAt:      row.CreatedAt,
	}
	if row.ExitCode.Valid {
		code := int(row.ExitCode.Int64)
		b.ExitCode = &code
	}
	if row.StartedAt.Valid {
		b.StartedAt = row.StartedAt.Time
	}
	return b
}
