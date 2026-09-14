package domain

import (
	"errors"
	"time"
)

type ClaudeAccountID string

const (
	DefaultClaudeAccountID ClaudeAccountID = "default"
	ClaudeConfigDirEnv     string          = "CLAUDE_CONFIG_DIR"
)

var (
	ErrClaudeAccountNotFound          = errors.New("claude account not found")
	ErrClaudeAccountExists            = errors.New("claude account already exists")
	ErrClaudeAccountLabelInvalid      = errors.New("claude account label is invalid")
	ErrClaudeAccountDefaultImmutable  = errors.New("the default claude account cannot be removed")
	ErrClaudeAccountInUse             = errors.New("claude account is used by a session")
	ErrClaudeAccountFolderUnavailable = errors.New("claude account folder is unavailable")
	ErrInvalidClaudeAccount           = errors.New("claude account is not valid for this request")
)

type ClaudeAccount struct {
	ID        ClaudeAccountID `json:"id"`
	Label     string          `json:"label"`
	ConfigDir string          `json:"configDir,omitempty"`
	IsDefault bool            `json:"isDefault"`
	CreatedAt time.Time       `json:"createdAt"`
}

func (a ClaudeAccount) ApplyEnv(env map[string]string) {
	if a.IsDefault {
		delete(env, ClaudeConfigDirEnv)
		return
	}
	env[ClaudeConfigDirEnv] = a.ConfigDir
}

func NormalizeClaudeAccountID(id ClaudeAccountID) ClaudeAccountID {
	if id == "" {
		return DefaultClaudeAccountID
	}
	return id
}
