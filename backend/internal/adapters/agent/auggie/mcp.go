package auggie

import (
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/agentbase"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// appendMCPConfigFlag registers the launch's MCP servers with --mcp-config,
// which Auggie parses as inline JSON when the value starts with "{" and accepts
// in the {"mcpServers": {...}} shape.
func appendMCPConfigFlag(cmd *[]string, servers []ports.MCPServerSpec) error {
	raw, err := agentbase.MCPServersJSON(servers)
	if err != nil || raw == "" {
		return err
	}
	*cmd = append(*cmd, "--mcp-config", raw)
	return nil
}
