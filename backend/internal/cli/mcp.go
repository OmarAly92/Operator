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
// connects (ports.OperatorMCPInstructions).
const MCPBoardInstructions = ports.OperatorMCPInstructions

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
