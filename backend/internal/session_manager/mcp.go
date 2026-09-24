package sessionmanager

import (
	"os"
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

// ReviewerMCPServers returns the reviewer-role Operator MCP server for a
// reviewer pane: `opr mcp --reviewer` run from the daemon's executable, told
// which worker it reviews through its env. Agent CLIs may start MCP servers
// with a trimmed environment, so everything the server needs is in Env. It
// returns nil when exe is not an `opr` binary.
func ReviewerMCPServers(exe string, worker domain.SessionID, harness domain.ReviewerHarness, dataDir, runFile string) []ports.MCPServerSpec {
	if requireOprExecutable(exe) != nil {
		return nil
	}
	env := map[string]string{
		"OPERATOR_REVIEW_WORKER_SESSION_ID": string(worker),
		"OPERATOR_REVIEW_HARNESS":           string(harness),
		EnvDataDir:                          dataDir,
	}
	if runFile != "" {
		env[EnvRunFile] = runFile
	}
	if port := os.Getenv("OPERATOR_PORT"); port != "" {
		env["OPERATOR_PORT"] = port
	}
	return []ports.MCPServerSpec{{
		Name:    ports.OperatorMCPServerName,
		Command: exe,
		Args:    []string{"mcp", ports.OperatorReviewerMCPArg},
		Env:     env,
	}}
}

// operatorMCPBoardSection is how the board rules appear in a standing system
// prompt, for agents whose CLI does not surface MCP server instructions.
const operatorMCPBoardSection = "## Operator board\n\n" + ports.OperatorMCPInstructions

// withMCPBoardInstructions adds the Operator board rules to a session's standing
// system prompt when the Operator MCP server will be registered and the harness
// cannot be relied on to surface the server's own instructions. Sessions that
// get no server get no rules: this is how the rules reach the model, not a
// fallback for agents without MCP. It is idempotent: an agent switch rebuilds
// its prompt from one that may already carry the section.
func (m *Manager) withMCPBoardInstructions(harness domain.AgentHarness, systemPrompt string) string {
	if !m.harnessHasOperatorMCP(harness) || strings.Contains(systemPrompt, operatorMCPBoardSection) {
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

// harnessHasOperatorMCP reports whether a session of this harness gets the
// Operator MCP server: the daemon can register it and the harness's adapter
// actually loads it into the CLI (ports.MCPServerLoader). Rules or requests
// that name Operator tools go only to such sessions.
func (m *Manager) harnessHasOperatorMCP(harness domain.AgentHarness) bool {
	if !m.registersOperatorMCP() {
		return false
	}
	agent, ok := m.agents.Agent(harness)
	if !ok {
		return false
	}
	loader, ok := agent.(ports.MCPServerLoader)
	return ok && loader.LoadsMCPServers()
}

// registersOperatorMCP reports whether operatorMCPServers will register the
// server, without its logging.
func (m *Manager) registersOperatorMCP() bool {
	exe, err := m.executable()
	return err == nil && requireOprExecutable(exe) == nil
}
