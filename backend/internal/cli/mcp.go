package cli

import (
	"errors"
	"os"
	"strings"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/spf13/cobra"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

// MCPServerName is the name the server reports; the session manager registers
// it with agents under the same name.
const MCPServerName = ports.OperatorMCPServerName

// MCPBoardInstructions is the Operator MCP server's `instructions`: the always-on
// board rules an agent CLI places in the model's context when the server
// connects. It is the only place those rules live — Operator adds nothing to
// the standing system prompt for the board.
const MCPBoardInstructions = `You are an agent in an Operator session; your session is a card on the user's kanban board. Before you end a turn waiting on the user (a question, a decision, missing access), call session_report with state needs_you and a one-line reason, or your card reads Idle and nobody is alerted. When the work is done and there is no pull request to review, call session_report with ready_for_review. Use session_get for your column and why, board_get for other sessions.

The board columns are Working (includes Idle), Needs you, In review and Ready to merge. Your card moves automatically from your activity and from the pull requests attributed to your session: a failing check, requested changes or an agent that stopped responding put it in Needs you; an open or draft PR puts it in In review; an approved or mergeable PR puts it in Ready to merge. A session_report clears itself when the user next messages you; use state clear only to withdraw a report you made by mistake.

Tools:
- session_get: your own card — status, column, the reason you are in that column, your branch and your PRs with CI and review detail.
- board_get: every card in a project, grouped by column. Check it before starting broad work so you do not duplicate what another session in the project is already doing.
- ticket_get: the ticket and plan your session belongs to, when it was started from one.
- session_rename, pr_claim (a PR whose branch is outside your session's namespace), review_request (Operator's code reviewer) and, when you are reviewing a ticket plan, ticket_mark_merge_ready.

Never try to move, stop or change another session's card.`

// mcpIdentity is the Operator session an `opr mcp` process serves. It comes from
// the environment Operator launches the agent with, never from tool arguments,
// so self-scoped tools cannot be aimed at another session.
type mcpIdentity struct {
	SessionID string
	ProjectID string
}

func newMCPCommand(ctx *commandContext) *cobra.Command {
	return &cobra.Command{
		Use:    "mcp",
		Short:  "Serve the Operator MCP server over stdio (launched by agents)",
		Long:   "Serve the Operator MCP server over stdio. Operator registers this command with every agent session it launches; it is not meant to be run by hand.",
		Hidden: true,
		Args:   noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			id, err := mcpIdentityFromEnv()
			if err != nil {
				return err
			}
			return newOperatorMCPServer(ctx, id).Run(cmd.Context(), &mcp.StdioTransport{})
		},
	}
}

func mcpIdentityFromEnv() (mcpIdentity, error) {
	sessionID := strings.TrimSpace(os.Getenv("OPERATOR_SESSION_ID"))
	if !sessionIDPattern.MatchString(sessionID) {
		return mcpIdentity{}, usageError{errors.New("opr mcp must run inside an Operator session (OPERATOR_SESSION_ID is not set)")}
	}
	projectID := strings.TrimSpace(os.Getenv("OPERATOR_PROJECT_ID"))
	if !sessionIDPattern.MatchString(projectID) {
		projectID = ""
	}
	return mcpIdentity{SessionID: sessionID, ProjectID: projectID}, nil
}

func newOperatorMCPServer(ctx *commandContext, id mcpIdentity) *mcp.Server {
	server := mcp.NewServer(
		&mcp.Implementation{Name: MCPServerName, Title: "Operator", Version: VersionString()},
		&mcp.ServerOptions{Instructions: MCPBoardInstructions},
	)
	tools := &mcpTools{ctx: ctx, id: id}
	tools.register(server)
	tools.registerActions(server)
	return server
}
