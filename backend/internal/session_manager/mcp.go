package sessionmanager

import (
	"strings"

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

// operatorMCPBoardSection is how the board rules appear in a standing system
// prompt, for agents whose CLI does not surface MCP server instructions.
const operatorMCPBoardSection = "## Operator board\n\n" + ports.OperatorMCPInstructions

// withMCPBoardInstructions adds the Operator board rules to a session's standing
// system prompt when the Operator MCP server will be registered and the harness
// cannot be relied on to surface the server's own instructions. Sessions that
// get no server get no rules: this is how the rules reach the model, not a
// fallback for agents without MCP.
func (m *Manager) withMCPBoardInstructions(harness domain.AgentHarness, systemPrompt string) string {
	if !m.registersOperatorMCP() {
		return systemPrompt
	}
	if agent, ok := m.agents.Agent(harness); ok {
		if s, ok := agent.(ports.MCPInstructionsSurfacer); ok && s.SurfacesMCPServerInstructions() {
			return systemPrompt
		}
	}
	if strings.TrimSpace(systemPrompt) == "" {
		return operatorMCPBoardSection
	}
	return strings.TrimRight(systemPrompt, "\n") + "\n\n" + operatorMCPBoardSection
}

// registersOperatorMCP reports whether operatorMCPServers will register the
// server, without its logging.
func (m *Manager) registersOperatorMCP() bool {
	exe, err := m.executable()
	return err == nil && requireOprExecutable(exe) == nil
}
