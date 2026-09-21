package session

import (
	"context"
	"strings"
	"unicode/utf8"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

const (
	delegatedTaskTitleLimit   = 20
	delegatedTaskUntitledName = "Untitled task"
)

// DelegateTaskInput describes a task Operator should spawn as a worker session. Brief
// may be empty to open an idle worker that the user can instruct later. Empty
// RequestedAgent means the spawn uses the project's worker-agent default.
type DelegateTaskInput struct {
	ProjectID      domain.ProjectID
	Brief          string
	RequestedAgent domain.AgentHarness
	Model          string
	Attachments    []ports.SpawnAttachment
	WorkspaceMode  domain.WorkspaceMode
	// Cols/Rows are the grid of the pane that will show the worker; zero when
	// the caller has no pane (the CLI).
	Cols            int
	Rows            int
	ClaudeAccountID domain.ClaudeAccountID
}

// DelegateTaskOutcome identifies the spawned worker.
type DelegateTaskOutcome struct {
	WorkerID domain.SessionID
}

// DelegateTask spawns the worker directly, matching `opr spawn`, with a
// provisional display name derived from the task brief.
func (s *Service) DelegateTask(ctx context.Context, in DelegateTaskInput) (DelegateTaskOutcome, error) {
	if _, err := s.requireProject(ctx, in.ProjectID); err != nil {
		return DelegateTaskOutcome{}, err
	}
	if in.RequestedAgent != "" && !in.RequestedAgent.IsKnown() {
		return DelegateTaskOutcome{}, apierr.Invalid("UNKNOWN_HARNESS", "Unknown requested agent", nil)
	}
	prompt := in.Brief
	if strings.TrimSpace(prompt) == "" {
		prompt = ""
	}

	worker, _, _, err := s.manager.Spawn(ctx, ports.SpawnConfig{
		ProjectID:       in.ProjectID,
		Harness:         in.RequestedAgent,
		Prompt:          prompt,
		DisplayName:     delegatedTaskDisplayName(in.Brief),
		AgentConfig:     ports.AgentConfig{Model: strings.TrimSpace(in.Model)},
		Attachments:     in.Attachments,
		WorkspaceMode:   in.WorkspaceMode,
		Cols:            in.Cols,
		Rows:            in.Rows,
		ClaudeAccountID: in.ClaudeAccountID,
	})
	if err != nil {
		return DelegateTaskOutcome{}, toAPIError(err)
	}

	return DelegateTaskOutcome{WorkerID: worker.ID}, nil
}

func delegatedTaskDisplayName(brief string) string {
	title := strings.Join(strings.Fields(brief), " ")
	if title == "" {
		return delegatedTaskUntitledName
	}
	if utf8.RuneCountInString(title) <= delegatedTaskTitleLimit {
		return title
	}
	return strings.TrimSpace(string([]rune(title)[:delegatedTaskTitleLimit]))
}
