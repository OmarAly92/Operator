// Package codex adapts the codex worker agent for code-review sessions.
package codex

import (
	"context"

	workeragent "github.com/OmarAly92/operator/backend/internal/adapters/agent/codex"
	"github.com/OmarAly92/operator/backend/internal/adapters/reviewer/agentrestore"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// Reviewer is the codex code-review adapter.
type Reviewer struct {
	agent ports.Agent
}

// New builds the codex reviewer adapter.
func New() *Reviewer {
	return &Reviewer{agent: workeragent.New()}
}

// Harness identifies this reviewer in the reviewer registry.
func (r *Reviewer) Harness() domain.ReviewerHarness {
	return domain.ReviewerCodex
}

var _ ports.Reviewer = (*Reviewer)(nil)
var _ ports.ReviewerCanceller = (*Reviewer)(nil)
var _ ports.ReviewerRestorer = (*Reviewer)(nil)

// ReviewCommand launches the reviewer with an enforced read-only filesystem
// sandbox. Auto approval lets the headless session request the narrowly needed
// network access for posting the review. The result is recorded through the
// Operator MCP server's review_submit tool; Codex runs MCP servers itself, so
// the shell sandbox does not reach them.
func (r *Reviewer) ReviewCommand(ctx context.Context, inv ports.ReviewInvocation) (ports.ReviewCommandSpec, error) {
	argv, err := r.agent.GetLaunchCommand(ctx, ports.LaunchConfig{
		SessionID:        inv.ReviewerID,
		WorkspacePath:    inv.WorkspacePath,
		Prompt:           inv.Prompt,
		SystemPrompt:     inv.SystemPrompt,
		SystemPromptFile: inv.SystemPromptFile,
		Permissions:      ports.PermissionModeAuto,
		MCPServers:       inv.MCPServers,
	})
	if err != nil {
		return ports.ReviewCommandSpec{}, err
	}
	return ports.ReviewCommandSpec{Argv: insertBeforePrompt(argv, codexReadOnlyArgs()...)}, nil
}

// ReviewRestoreCommand resumes the reviewer Codex conversation captured from
// Codex hooks when Operator recreates the reviewer pane after worker restore.
func (r *Reviewer) ReviewRestoreCommand(ctx context.Context, inv ports.ReviewInvocation) (ports.ReviewCommandSpec, bool, error) {
	cmd, ok, err := agentrestore.Command(ctx, r.agent, inv, agentrestore.Options{Permissions: ports.PermissionModeAuto})
	if err != nil || !ok {
		return cmd, ok, err
	}
	cmd.Argv = insertBeforeLastArg(cmd.Argv, codexReadOnlyArgs()...)
	return cmd, true, nil
}

// ReviewMessage returns the centrally-authored task for an existing pane.
func (r *Reviewer) ReviewMessage(_ context.Context, inv ports.ReviewInvocation) (string, error) {
	return inv.Prompt, nil
}

// ReviewCancel stops the active Codex reviewer turn while preserving the
// terminal pane for inspection. Codex advertises "esc to interrupt", and a
// single Escape stops the active turn without queuing prompt text.
func (r *Reviewer) ReviewCancel(context.Context) (ports.ReviewCancelSpec, error) {
	return ports.ReviewCancelSpec{
		Mode:  ports.ReviewCancelInput,
		Input: "\x1b",
	}, nil
}

func insertBeforePrompt(argv []string, extra ...string) []string {
	for i, arg := range argv {
		if arg == "--" {
			out := make([]string, 0, len(argv)+len(extra))
			out = append(out, argv[:i]...)
			out = append(out, extra...)
			return append(out, argv[i:]...)
		}
	}
	return append(argv, extra...)
}

func insertBeforeLastArg(argv []string, extra ...string) []string {
	if len(argv) == 0 {
		return append([]string{}, extra...)
	}
	out := make([]string, 0, len(argv)+len(extra))
	out = append(out, argv[:len(argv)-1]...)
	out = append(out, extra...)
	return append(out, argv[len(argv)-1])
}

func codexReadOnlyArgs() []string {
	return []string{"--sandbox", "read-only"}
}
