package cli

import (
	"context"
	"encoding/json"
	"slices"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

// mcpToolCalledPath is the daemon's loopback route that counts Operator MCP
// tool calls into a daily rollup (httpd/mcp_telemetry.go).
const mcpToolCalledPath = "/internal/telemetry/mcp-tool-called"

type mcpToolCalledRequest struct {
	SessionID string `json:"sessionId,omitempty"`
	Tool      string `json:"tool"`
	Outcome   string `json:"outcome"`
	State     string `json:"state,omitempty"`
	// Role is "reviewer" for `opr mcp --reviewer`, whose calls count under the
	// reviewer's own Harness rather than the worker session's.
	Role    string `json:"role,omitempty"`
	Harness string `json:"harness,omitempty"`
}

// mcpTelemetryMiddleware reports each Operator tool call to the daemon: the
// tool name, whether it succeeded, and for session_report the report state.
// Nothing else from the arguments leaves this process: a reason, a name or a
// summary is the agent's prose about the user's work. The report is
// best-effort and never changes the tool result.
func (c *commandContext) mcpTelemetryMiddleware(id mcpIdentity) mcp.Middleware {
	return func(next mcp.MethodHandler) mcp.MethodHandler {
		return func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error) {
			result, err := next(ctx, method, req)
			if call, ok := req.(*mcp.CallToolRequest); ok && call.Params != nil {
				if event, ok := mcpToolCalledEvent(id, call.Params, result, err); ok {
					reqCtx, cancel := context.WithTimeout(ctx, probeTimeout)
					_ = c.postLoopbackJSON(reqCtx, mcpToolCalledPath, event)
					cancel()
				}
			}
			return result, err
		}
	}
}

func mcpToolCalledEvent(id mcpIdentity, params *mcp.CallToolParamsRaw, result mcp.Result, err error) (mcpToolCalledRequest, bool) {
	event := mcpToolCalledRequest{SessionID: id.SessionID, Tool: params.Name, Outcome: "ok"}
	names := ports.OperatorMCPToolNames
	if id.Reviewer != nil {
		names = ports.OperatorReviewerMCPToolNames
		event = mcpToolCalledRequest{Tool: params.Name, Outcome: "ok", Role: "reviewer", Harness: id.Reviewer.Harness}
	}
	if !slices.Contains(names, params.Name) {
		return mcpToolCalledRequest{}, false
	}
	if res, ok := result.(*mcp.CallToolResult); err != nil || !ok || res.IsError {
		event.Outcome = "error"
	}
	if params.Name == "session_report" {
		var args struct {
			State string `json:"state"`
		}
		if json.Unmarshal(params.Arguments, &args) == nil && slices.Contains(mcpReportStates, args.State) {
			event.State = args.State
		}
	}
	return event, true
}

// mcpReportStates is session_report's closed state vocabulary; anything else
// is dropped rather than forwarded.
var mcpReportStates = []string{"needs_you", "ready_for_review", "clear"}
