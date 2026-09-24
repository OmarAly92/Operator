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
	// Reviewer is set for `opr mcp --reviewer`: the server then acts for the
	// worker whose pull requests this reviewer pane reviews, and serves only
	// the reviewer's tools.
	Reviewer *mcpReviewerIdentity
}

// mcpReviewerIdentity is the worker a reviewer pane reviews and the reviewer's
// own harness, both from the environment the review launcher sets.
type mcpReviewerIdentity struct {
	WorkerSessionID string
	Harness         string
}

func newMCPCommand(ctx *commandContext) *cobra.Command {
	var reviewer bool
	cmd := &cobra.Command{
		Use:    "mcp",
		Short:  "Serve the Operator MCP server over stdio (launched by agents)",
		Long:   "Serve the Operator MCP server over stdio. Operator registers this command with every agent session it launches; it is not meant to be run by hand.",
		Hidden: true,
		Args:   noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			identity := mcpIdentityFromEnv
			if reviewer {
				identity = mcpReviewerIdentityFromEnv
			}
			id, err := identity()
			if err != nil {
				return err
			}
			return newOperatorMCPServer(ctx, id).Run(cmd.Context(), &mcp.StdioTransport{})
		},
	}
	cmd.Flags().BoolVar(&reviewer, strings.TrimPrefix(ports.OperatorReviewerMCPArg, "--"), false, "serve the code reviewer's tools")
	return cmd
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

// mcpReviewerIdentityFromEnv reads the reviewer pane's environment. The review
// launcher removes OPERATOR_SESSION_ID from it, so a reviewer can never be
// mistaken for the worker it reviews.
func mcpReviewerIdentityFromEnv() (mcpIdentity, error) {
	worker := strings.TrimSpace(os.Getenv("OPERATOR_REVIEW_WORKER_SESSION_ID"))
	if !sessionIDPattern.MatchString(worker) {
		return mcpIdentity{}, usageError{errors.New("opr mcp --reviewer must run inside an Operator reviewer pane (OPERATOR_REVIEW_WORKER_SESSION_ID is not set)")}
	}
	harness := strings.TrimSpace(os.Getenv("OPERATOR_REVIEW_HARNESS"))
	if !sessionIDPattern.MatchString(harness) {
		harness = ""
	}
	return mcpIdentity{Reviewer: &mcpReviewerIdentity{WorkerSessionID: worker, Harness: harness}}, nil
}

func newOperatorMCPServer(ctx *commandContext, id mcpIdentity) *mcp.Server {
	instructions := MCPBoardInstructions
	if id.Reviewer != nil {
		instructions = ports.OperatorReviewerMCPInstructions
	}
	server := mcp.NewServer(
		&mcp.Implementation{Name: MCPServerName, Title: "Operator", Version: VersionString()},
		&mcp.ServerOptions{Instructions: instructions},
	)
	server.AddReceivingMiddleware(ctx.mcpTelemetryMiddleware(id))
	tools := &mcpTools{ctx: ctx, id: id}
	if id.Reviewer != nil {
		tools.registerReviewer(server)
		return server
	}
	tools.register(server)
	tools.registerActions(server)
	return server
}
