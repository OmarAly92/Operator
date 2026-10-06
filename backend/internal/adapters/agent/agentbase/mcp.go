package agentbase

import (
	"encoding/json"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

// StdioMCPServer is the {command, args, env} server entry most agent CLIs
// accept under an "mcpServers" object (Claude Code's shape, adopted by Gemini
// forks, Copilot, Amp, Auggie and others).
type StdioMCPServer struct {
	Type    string            `json:"type,omitempty"`
	Command string            `json:"command"`
	Args    []string          `json:"args,omitempty"`
	Env     map[string]string `json:"env,omitempty"`
	// Trust is Gemini-family's "skip tool confirmation" switch for a server.
	Trust bool `json:"trust,omitempty"`
}

// MCPServersOption tweaks an entry for a CLI's dialect.
type MCPServersOption func(*StdioMCPServer)

// WithStdioType sets "type":"stdio" on every entry.
func WithStdioType(s *StdioMCPServer) { s.Type = "stdio" }

// WithTrust marks every entry trusted (Gemini-family confirmation bypass).
func WithTrust(s *StdioMCPServer) { s.Trust = true }

// MCPServersMap renders the launch's servers as an "mcpServers" object.
func MCPServersMap(servers []ports.MCPServerSpec, opts ...MCPServersOption) map[string]StdioMCPServer {
	out := make(map[string]StdioMCPServer, len(servers))
	for _, srv := range servers {
		entry := StdioMCPServer{Command: srv.Command, Args: srv.Args, Env: srv.Env}
		for _, opt := range opts {
			opt(&entry)
		}
		out[srv.Name] = entry
	}
	return out
}

// MCPServersJSON renders {"mcpServers": {...}} for a CLI flag that takes
// inline JSON. It returns "" when there are no servers.
func MCPServersJSON(servers []ports.MCPServerSpec, opts ...MCPServersOption) (string, error) {
	if len(servers) == 0 {
		return "", nil
	}
	raw, err := json.Marshal(map[string]any{"mcpServers": MCPServersMap(servers, opts...)})
	if err != nil {
		return "", fmt.Errorf("encode mcp servers: %w", err)
	}
	return string(raw), nil
}

// WithoutEnv strips each server's Env. Adapters that write a workspace file
// (shared by every session of an in_place checkout) register the server this
// way and let `opr mcp` inherit the session identity from the agent process,
// exactly as the workspace hooks do.
func WithoutEnv(servers []ports.MCPServerSpec) []ports.MCPServerSpec {
	out := make([]ports.MCPServerSpec, 0, len(servers))
	for _, srv := range servers {
		srv.Env = nil
		out = append(out, srv)
	}
	return out
}

// MCPServerNames lists the servers' names, e.g. for per-server tool approval.
func MCPServerNames(servers []ports.MCPServerSpec) []string {
	out := make([]string, 0, len(servers))
	for _, srv := range servers {
		out = append(out, srv.Name)
	}
	return out
}
