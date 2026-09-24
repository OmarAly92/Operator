package crush

import (
	"errors"
	"os"
	"slices"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/agentbase"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// crushMCPToolName is Crush's name for an MCP tool ("mcp_%s_%s" in the Crush
// binary), which is what permissions.allowed_tools matches exactly.
func crushMCPToolName(server, tool string) string { return "mcp_" + server + "_" + tool }

// mergeCrushMCPServers registers the launch's MCP servers in the project-local
// .crush.json and pre-approves the Operator server's tools. The file is shared
// by every session of an in_place checkout, so the entry carries no Env: `opr
// mcp` inherits the session identity from the agent process, like the hooks.
// User entries and other keys are preserved.
func mergeCrushMCPServers(configPath string, servers []ports.MCPServerSpec) error {
	if len(servers) == 0 {
		return nil
	}
	cfg, err := readCrushConfig(configPath)
	if err != nil {
		return err
	}
	mcp := crushConfigObject(cfg, "mcp")
	for name, entry := range agentbase.MCPServersMap(agentbase.WithoutEnv(servers), agentbase.WithStdioType) {
		mcp[name] = entry
	}
	cfg["mcp"] = mcp
	permissions := crushConfigObject(cfg, "permissions")
	allowed := crushStringSlice(permissions["allowed_tools"])
	for _, srv := range servers {
		if srv.Name != ports.OperatorMCPServerName {
			continue
		}
		for _, tool := range ports.OperatorMCPToolNames {
			if name := crushMCPToolName(srv.Name, tool); !slices.Contains(allowed, name) {
				allowed = append(allowed, name)
			}
		}
	}
	permissions["allowed_tools"] = allowed
	cfg["permissions"] = permissions
	return writeCrushConfig(configPath, cfg)
}

// removeCrushMCPServers drops the Operator server and its pre-approved tools,
// leaving the user's own MCP servers and permissions alone.
func removeCrushMCPServers(configPath string) error {
	if _, err := os.Stat(configPath); errors.Is(err, os.ErrNotExist) {
		return nil
	}
	cfg, err := readCrushConfig(configPath)
	if err != nil {
		return err
	}
	changed := false
	if mcp, ok := cfg["mcp"].(map[string]any); ok {
		if _, ok := mcp[ports.OperatorMCPServerName]; ok {
			delete(mcp, ports.OperatorMCPServerName)
			changed = true
			if len(mcp) == 0 {
				delete(cfg, "mcp")
			}
		}
	}
	if permissions, ok := cfg["permissions"].(map[string]any); ok {
		allowed := crushStringSlice(permissions["allowed_tools"])
		kept := slices.DeleteFunc(slices.Clone(allowed), func(name string) bool {
			for _, tool := range ports.OperatorMCPToolNames {
				if name == crushMCPToolName(ports.OperatorMCPServerName, tool) {
					return true
				}
			}
			return false
		})
		if len(kept) != len(allowed) {
			changed = true
			if len(kept) == 0 {
				delete(permissions, "allowed_tools")
			} else {
				permissions["allowed_tools"] = kept
			}
			if len(permissions) == 0 {
				delete(cfg, "permissions")
			}
		}
	}
	if !changed {
		return nil
	}
	return writeCrushConfig(configPath, cfg)
}
