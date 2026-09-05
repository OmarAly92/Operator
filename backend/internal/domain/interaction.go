package domain

import "time"

// PendingInteraction is a dialog the agent is waiting on a human for. Its ID is
// minted by the daemon, not lifted from the harness: Claude Code's permission
// hook carries the blocking tool's NAME but not its tool_use_id, and there is
// only ever one dialog on screen, so no correlation is needed to answer it.
type PendingInteraction struct {
	ID        string
	Kind      string
	ToolName  string
	ToolInput string
	Lines     []string
	CreatedAt time.Time
}

const (
	InteractionPermission = "permission"
	InteractionQuestion   = "question"
)
