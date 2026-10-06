package crush

import (
	"context"
	"encoding/json"
	"os"
	"reflect"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func TestHooksRegisterAndRemoveTheOperatorMCPServer(t *testing.T) {
	ws := t.TempDir()
	cfgPath := crushConfigFile(ws)
	user := `{"mcp":{"mine":{"type":"stdio","command":"/bin/mine"}},"permissions":{"allowed_tools":["view"]}}`
	if err := os.WriteFile(cfgPath, []byte(user), 0o600); err != nil {
		t.Fatal(err)
	}
	server := ports.MCPServerSpec{Name: "operator", Command: "/opt/operator/opr", Args: []string{"mcp"}, Env: map[string]string{"OPERATOR_SESSION_ID": "opr-1"}}
	p := &Plugin{}
	if err := p.GetAgentHooks(context.Background(), ports.WorkspaceHookConfig{WorkspacePath: ws, MCPServers: []ports.MCPServerSpec{server}}); err != nil {
		t.Fatal(err)
	}
	cfg := readJSON(t, cfgPath)
	mcp := cfg["mcp"].(map[string]any)
	if _, ok := mcp["mine"]; !ok {
		t.Fatalf("user server lost: %v", mcp)
	}
	want := map[string]any{"type": "stdio", "command": "/opt/operator/opr", "args": []any{"mcp"}}
	if !reflect.DeepEqual(mcp["operator"], any(want)) {
		t.Fatalf("operator entry = %#v, want %#v (no env: the file is shared by in_place sessions)", mcp["operator"], want)
	}
	allowed := cfg["permissions"].(map[string]any)["allowed_tools"].([]any)
	if allowed[0] != "view" || len(allowed) != 1+len(ports.OperatorMCPToolNames) || allowed[1] != "mcp_operator_board_get" {
		t.Fatalf("allowed_tools = %v", allowed)
	}
	// Idempotent across restores.
	if err := p.GetAgentHooks(context.Background(), ports.WorkspaceHookConfig{WorkspacePath: ws, MCPServers: []ports.MCPServerSpec{server}}); err != nil {
		t.Fatal(err)
	}
	if again := readJSON(t, cfgPath)["permissions"].(map[string]any)["allowed_tools"].([]any); len(again) != len(allowed) {
		t.Fatalf("second install duplicated tools: %v", again)
	}

	if err := p.UninstallHooks(context.Background(), ws); err != nil {
		t.Fatal(err)
	}
	after := readJSON(t, cfgPath)
	if !reflect.DeepEqual(after, readJSONString(t, user)) {
		t.Fatalf("uninstall left %v, want the user's config back", after)
	}
}

func readJSON(t *testing.T, path string) map[string]any {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return readJSONString(t, string(raw))
}

func readJSONString(t *testing.T, raw string) map[string]any {
	t.Helper()
	var out map[string]any
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		t.Fatal(err)
	}
	return out
}
