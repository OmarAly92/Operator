package sessionmanager

import (
	"context"
	"errors"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type ClaudeAccountLauncher interface {
	PrepareLaunch(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error)
}

func (m *Manager) applyClaudeAccount(ctx context.Context, env map[string]string, id domain.ClaudeAccountID) error {
	if m.claudeAccounts == nil {
		return nil
	}
	account, err := m.claudeAccounts.PrepareLaunch(ctx, domain.NormalizeClaudeAccountID(id))
	if err != nil {
		return fmt.Errorf("claude account %s: %w", domain.NormalizeClaudeAccountID(id), err)
	}
	account.ApplyEnv(env)
	return nil
}

func (m *Manager) resolveSpawnClaudeAccount(ctx context.Context, cfg ports.SpawnConfig) (domain.ClaudeAccountID, error) {
	if cfg.ClaudeAccountID != "" {
		if cfg.Harness != domain.HarnessClaudeCode {
			return "", fmt.Errorf("%w: only claude-code sessions take an account", domain.ErrInvalidClaudeAccount)
		}
		if err := m.checkClaudeAccount(ctx, cfg.ClaudeAccountID); err != nil {
			return "", err
		}
		return cfg.ClaudeAccountID, nil
	}
	if cfg.Harness == domain.HarnessClaudeCode && cfg.RequestedBy != "" && m.store != nil {
		parent, ok, err := m.store.GetSession(ctx, cfg.RequestedBy)
		if err == nil && ok && parent.ClaudeAccountID != "" {
			return parent.ClaudeAccountID, nil
		}
	}
	return domain.DefaultClaudeAccountID, nil
}

func (m *Manager) checkClaudeAccount(ctx context.Context, id domain.ClaudeAccountID) error {
	if m.claudeAccounts == nil {
		return nil
	}
	if _, err := m.claudeAccounts.PrepareLaunch(ctx, id); err != nil {
		if errors.Is(err, domain.ErrClaudeAccountNotFound) {
			return fmt.Errorf("%w: %s", domain.ErrInvalidClaudeAccount, id)
		}
		return err
	}
	return nil
}
