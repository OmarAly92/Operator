package copilot

import (
	"encoding/json"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

// copilotMCPServer is Copilot's local-server entry, the shape `copilot mcp add`
// writes to ~/.copilot/mcp-config.json.
type copilotMCPServer struct {
	Type    string            `json:"type"`
	Command string            `json:"command"`
	Args    []string          `json:"args,omitempty"`
	Env     map[string]string `json:"env,omitempty"`
	Tools   []string          `json:"tools"`
}

// appendMCPServerFlags registers the launch's MCP servers with
// --additional-mcp-config, which augments the user's mcp-config.json for this
// session only, and pre-approves each server's tools with --allow-tool=<server>
// (Copilot's "all tools from that server" permission pattern).
func appendMCPServerFlags(cmd *[]string, servers []ports.MCPServerSpec) error {
	if len(servers) == 0 {
		return nil
	}
	entries := make(map[string]copilotMCPServer, len(servers))
	for _, srv := range servers {
		entries[srv.Name] = copilotMCPServer{Type: "local", Command: srv.Command, Args: srv.Args, Env: srv.Env, Tools: []string{"*"}}
	}
	raw, err := json.Marshal(map[string]any{"mcpServers": entries})
	if err != nil {
		return fmt.Errorf("copilot: encode mcp servers: %w", err)
	}
	*cmd = append(*cmd, "--additional-mcp-config", string(raw))
	for _, srv := range servers {
		*cmd = append(*cmd, "--allow-tool="+srv.Name)
	}
	return nil
}
