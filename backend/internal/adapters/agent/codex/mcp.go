package codex

import (
	"fmt"
	"regexp"
	"sort"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

// codexBareKey is what a `-c` key segment may contain: Codex splits key paths
// on every dot without honoring quotes (see appendWorkspaceTrustFlag), so a
// server name or env var name must be a bare TOML key.
var codexBareKey = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)

// appendMCPServerFlags registers the launch's MCP servers as one
// `-c mcp_servers.<name>={...}` override each. Setting only that key merges into
// the user's own mcp_servers table, so their servers still load. The servers'
// tools are pre-approved (default_tools_approval_mode="approve"): Operator only
// registers its own server, whose tools act on the calling session alone, and an
// approval prompt on them would itself park the card in Needs you. Codex versions
// without that key ignore it.
func appendMCPServerFlags(cmd *[]string, servers []ports.MCPServerSpec) error {
	for _, srv := range servers {
		if !codexBareKey.MatchString(srv.Name) {
			return fmt.Errorf("codex: MCP server name %q is not a bare TOML key", srv.Name)
		}
		fields := []string{"command=" + codexTOMLBasicString(srv.Command)}
		if len(srv.Args) > 0 {
			args := make([]string, 0, len(srv.Args))
			for _, a := range srv.Args {
				args = append(args, codexTOMLBasicString(a))
			}
			fields = append(fields, "args=["+strings.Join(args, ",")+"]")
		}
		if len(srv.Env) > 0 {
			keys := make([]string, 0, len(srv.Env))
			for k := range srv.Env {
				if !codexBareKey.MatchString(k) {
					return fmt.Errorf("codex: MCP server env name %q is not a bare TOML key", k)
				}
				keys = append(keys, k)
			}
			sort.Strings(keys)
			env := make([]string, 0, len(keys))
			for _, k := range keys {
				env = append(env, k+"="+codexTOMLBasicString(srv.Env[k]))
			}
			fields = append(fields, "env={"+strings.Join(env, ",")+"}")
		}
		fields = append(fields, `default_tools_approval_mode="approve"`)
		*cmd = append(*cmd, "-c", "mcp_servers."+srv.Name+"={"+strings.Join(fields, ",")+"}")
	}
	return nil
}

// SurfacesMCPServerInstructions: Codex reads an MCP server's instructions as
// server-wide guidance, favouring the first 512 characters.
func (p *Plugin) SurfacesMCPServerInstructions() bool { return true }
