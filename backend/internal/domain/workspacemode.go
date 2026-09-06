package domain

import (
	"errors"
	"fmt"
)

const (
	WorkspaceModeWorktree WorkspaceMode = "worktree"
	WorkspaceModeInPlace  WorkspaceMode = "in_place"
)

var ErrInvalidWorkspaceMode = errors.New("invalid workspace mode")

type WorkspaceMode string

func (m WorkspaceMode) Valid() bool {
	return m == WorkspaceModeWorktree || m == WorkspaceModeInPlace
}

func ParseWorkspaceMode(raw string) (WorkspaceMode, error) {
	mode := WorkspaceMode(raw)
	if !mode.Valid() {
		return "", fmt.Errorf("%w: %q", ErrInvalidWorkspaceMode, raw)
	}
	return mode, nil
}
