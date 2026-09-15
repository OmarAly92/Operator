package sessionmanager

import (
	"context"
	"errors"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type ClaudeAccountLauncher interface {
	Get(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error)
	PrepareLaunch(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error)
}

func (m *Manager) applyClaudeAccount(ctx context.Context, env map[string]string, id domain.ClaudeAccountID) error {
	if m.claudeAccounts == nil {
		return nil
	}
	account, err := m.claudeAccounts.Get(ctx, domain.NormalizeClaudeAccountID(id))
	if err != nil {
		return fmt.Errorf("claude account %s: %w", domain.NormalizeClaudeAccountID(id), err)
	}
	account.ApplyEnv(env)
	return nil
}

func (m *Manager) prepareClaudeAccountLaunch(ctx context.Context, harness domain.AgentHarness, id domain.ClaudeAccountID) error {
	if m.claudeAccounts == nil || harness != domain.HarnessClaudeCode {
		return nil
	}
	if _, err := m.claudeAccounts.PrepareLaunch(ctx, domain.NormalizeClaudeAccountID(id)); err != nil {
		return fmt.Errorf("claude account %s: %w", domain.NormalizeClaudeAccountID(id), err)
	}
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

func switchTargetClaudeAccount(rec domain.SessionRecord, cfg SwitchAgentConfig) (domain.ClaudeAccountID, error) {
	current := domain.NormalizeClaudeAccountID(rec.ClaudeAccountID)
	if cfg.TargetHarness != domain.HarnessClaudeCode {
		if cfg.TargetClaudeAccountID != "" {
			return "", fmt.Errorf("%w: only a claude-code target takes an account", domain.ErrInvalidClaudeAccount)
		}
		if rec.Harness == cfg.TargetHarness {
			return "", fmt.Errorf("%w: %s", ErrAlreadyUsingHarness, cfg.TargetHarness)
		}
		return current, nil
	}
	target := current
	if cfg.TargetClaudeAccountID != "" {
		target = cfg.TargetClaudeAccountID
	}
	if rec.Harness == domain.HarnessClaudeCode && target == current {
		return "", fmt.Errorf("%w: %s on account %s", ErrAlreadyUsingHarness, cfg.TargetHarness, target)
	}
	return target, nil
}

func (m *Manager) checkClaudeAccount(ctx context.Context, id domain.ClaudeAccountID) error {
	if m.claudeAccounts == nil {
		return nil
	}
	if _, err := m.claudeAccounts.Get(ctx, id); err != nil {
		if errors.Is(err, domain.ErrClaudeAccountNotFound) {
			return fmt.Errorf("%w: %s", domain.ErrInvalidClaudeAccount, id)
		}
		return err
	}
	return nil
}
