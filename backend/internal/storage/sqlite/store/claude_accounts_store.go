package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

func claudeAccountFromGen(row gen.ClaudeAccount) domain.ClaudeAccount {
	return domain.ClaudeAccount{
		ID:        row.ID,
		Label:     row.Label,
		ConfigDir: row.ConfigDir.String,
		IsDefault: row.IsDefault,
		CreatedAt: row.CreatedAt,
	}
}

func (s *Store) ListClaudeAccounts(ctx context.Context) ([]domain.ClaudeAccount, error) {
	rows, err := s.qr.ListClaudeAccounts(ctx)
	if err != nil {
		return nil, fmt.Errorf("list claude accounts: %w", err)
	}
	out := make([]domain.ClaudeAccount, 0, len(rows))
	for _, row := range rows {
		out = append(out, claudeAccountFromGen(row))
	}
	return out, nil
}

func (s *Store) GetClaudeAccount(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error) {
	row, err := s.qr.GetClaudeAccount(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.ClaudeAccount{}, domain.ErrClaudeAccountNotFound
	}
	if err != nil {
		return domain.ClaudeAccount{}, fmt.Errorf("get claude account %s: %w", id, err)
	}
	return claudeAccountFromGen(row), nil
}

func (s *Store) InsertClaudeAccount(ctx context.Context, account domain.ClaudeAccount) error {
	if strings.TrimSpace(account.ConfigDir) == "" {
		return fmt.Errorf("insert claude account %s: %w", account.ID, domain.ErrClaudeAccountFolderUnavailable)
	}
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	err := s.qw.InsertClaudeAccount(ctx, gen.InsertClaudeAccountParams{
		ID:        account.ID,
		Label:     account.Label,
		ConfigDir: sql.NullString{String: account.ConfigDir, Valid: true},
		CreatedAt: account.CreatedAt,
	})
	if err != nil {
		return fmt.Errorf("insert claude account %s: %w", account.ID, err)
	}
	return nil
}

func (s *Store) RenameClaudeAccount(ctx context.Context, id domain.ClaudeAccountID, label string) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.RenameClaudeAccount(ctx, gen.RenameClaudeAccountParams{Label: label, ID: id})
	if err != nil {
		return fmt.Errorf("rename claude account %s: %w", id, err)
	}
	if n == 0 {
		return domain.ErrClaudeAccountNotFound
	}
	return nil
}

func (s *Store) DeleteClaudeAccount(ctx context.Context, id domain.ClaudeAccountID) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	tx, err := s.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin delete claude account %s: %w", id, err)
	}
	defer func() { _ = tx.Rollback() }()
	q := s.qw.WithTx(tx)
	row, err := q.GetClaudeAccount(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.ErrClaudeAccountNotFound
	}
	if err != nil {
		return fmt.Errorf("delete claude account %s: read: %w", id, err)
	}
	if row.IsDefault {
		return domain.ErrClaudeAccountDefaultImmutable
	}
	count, err := q.CountSessionsByClaudeAccount(ctx, id)
	if err != nil {
		return fmt.Errorf("delete claude account %s: count sessions: %w", id, err)
	}
	if count > 0 {
		return domain.ErrClaudeAccountInUse
	}
	if _, err := q.DeleteClaudeAccount(ctx, id); err != nil {
		return fmt.Errorf("delete claude account %s: %w", id, err)
	}
	return tx.Commit()
}
