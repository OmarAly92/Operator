package sessionmanager

import (
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// operatorMCPServers returns the Operator MCP server registration for a worker
// session: `opr mcp` run from the daemon's own executable, the same binary the
// hook PATH pin resolves to, so the MCP server always matches the daemon.
// Identity travels in the server's env, never in tool arguments. When the daemon
// executable is not an `opr` binary (tests, unusual installs) no server is
// registered, and the session runs without board tools.
func (m *Manager) operatorMCPServers(id domain.SessionID, project domain.ProjectID) []ports.MCPServerSpec {
	exe, err := m.executable()
	if err != nil {
		m.logger.Warn("operator MCP server not registered: daemon executable unresolved", "session", id, "error", err)
		return nil
	}
	if err := requireOprExecutable(exe); err != nil {
		m.logger.Warn("operator MCP server not registered", "session", id, "error", err)
		return nil
	}
	return []ports.MCPServerSpec{{
		Name:    ports.OperatorMCPServerName,
		Command: exe,
		Args:    []string{"mcp"},
		Env: map[string]string{
			EnvSessionID: string(id),
			EnvProjectID: string(project),
			EnvDataDir:   m.dataDir,
			EnvRunFile:   m.runFilePath,
		},
	}}
}
