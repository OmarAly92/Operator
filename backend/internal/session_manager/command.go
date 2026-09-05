package sessionmanager

import (
	"context"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

const keyEscape = "\x1b"

type CommandResult struct {
	Wrote  bool
	Models []string
}

func (m *Manager) Command(ctx context.Context, id domain.SessionID, cmd domain.SessionCommand, model string) (CommandResult, error) {
	rec, ok, err := m.store.GetSession(ctx, id)
	if err != nil {
		return CommandResult{}, fmt.Errorf("command %s: %w", id, err)
	}
	if !ok {
		return CommandResult{}, ErrNotFound
	}
	if rec.IsTerminated {
		return CommandResult{}, ErrTerminated
	}
	if rec.Activity.State == domain.ActivityExited {
		return CommandResult{}, ErrAgentExited
	}
	if rec.Metadata.RuntimeHandleID == "" {
		return CommandResult{}, ErrIncompleteHandle
	}

	switch cmd {
	case domain.CommandStop:
		return m.commandStop(ctx, rec)
	case domain.CommandCompact:
		return m.commandTyped(ctx, rec, "/compact")
	default:
		return CommandResult{}, fmt.Errorf("command %s: %w", id, ErrWrongActivityState)
	}
}

func (m *Manager) commandStop(ctx context.Context, rec domain.SessionRecord) (CommandResult, error) {
	if rec.Activity.State != domain.ActivityActive {
		return CommandResult{}, ErrWrongActivityState
	}
	if err := m.runtime.SendInput(ctx, runtimeHandle(rec.Metadata), keyEscape); err != nil {
		return CommandResult{}, fmt.Errorf("command stop %s: %w", rec.ID, err)
	}
	return CommandResult{Wrote: true}, nil
}

func (m *Manager) commandTyped(ctx context.Context, rec domain.SessionRecord, text string) (CommandResult, error) {
	if rec.Activity.State == domain.ActivityBlocked {
		return CommandResult{}, ErrAwaitingDecision
	}
	if rec.Activity.State != domain.ActivityIdle {
		return CommandResult{}, ErrWrongActivityState
	}
	if err := m.runtime.SendInput(ctx, runtimeHandle(rec.Metadata), text+"\r"); err != nil {
		return CommandResult{}, fmt.Errorf("command %s %s: %w", text, rec.ID, err)
	}
	return CommandResult{Wrote: true}, nil
}
