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
const MCPBoardInstructions = `You are running inside an Operator session. Operator shows every session as a card on a kanban board with the columns Working (includes Idle), Needs you, In review and Ready to merge. Your card moves automatically from your activity and from the pull requests attributed to your session: a failing check, requested changes or an agent that stopped responding put it in Needs you; an open or draft PR puts it in In review; an approved or mergeable PR puts it in Ready to merge.

Use the operator tools to see the board:
- session_get: your own card — status, column, the reason you are in that column, your branch and your PRs with CI and review detail.
- board_get: every card in a project, grouped by column. Check it before starting broad work so you do not duplicate what another session in the project is already doing.
- ticket_get: the ticket and plan your session belongs to, when it was started from one.

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
	return server
}
