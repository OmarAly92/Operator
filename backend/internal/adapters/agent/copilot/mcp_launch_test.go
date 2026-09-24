package copilot

import (
	"context"
	"encoding/json"
	"reflect"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var testMCPServer = ports.MCPServerSpec{Name: "operator", Command: "/opt/operator/opr", Args: []string{"mcp"}, Env: map[string]string{"OPERATOR_SESSION_ID": "opr-1"}}

func flagValue(t *testing.T, cmd []string, flag string) string {
	t.Helper()
	for i := 0; i+1 < len(cmd); i++ {
		if cmd[i] == flag {
			return cmd[i+1]
		}
	}
	t.Fatalf("missing %s in %#v", flag, cmd)
	return ""
}

func TestLaunchAndRestoreRegisterOperatorMCPServer(t *testing.T) {
	p := &Plugin{resolvedBinary: "copilot"}
	launch, err := p.GetLaunchCommand(context.Background(), ports.LaunchConfig{MCPServers: []ports.MCPServerSpec{testMCPServer}})
	if err != nil {
		t.Fatal(err)
	}
	restore, ok, err := p.GetRestoreCommand(context.Background(), ports.RestoreConfig{
		Session:    ports.SessionRef{ID: "opr-1", Metadata: map[string]string{ports.MetadataKeyAgentSessionID: "native-1"}},
		MCPServers: []ports.MCPServerSpec{testMCPServer},
	})
	if err != nil || !ok {
		t.Fatalf("restore = %v, %v", ok, err)
	}
	want := any(map[string]any{"mcpServers": map[string]any{"operator": map[string]any{"command": "/opt/operator/opr", "args": []any{"mcp"}, "env": map[string]any{"OPERATOR_SESSION_ID": "opr-1"}, "type": "local", "tools": []any{"*"}}}})
	for name, cmd := range map[string][]string{"launch": launch, "restore": restore} {
		var got any
		if err := json.Unmarshal([]byte(flagValue(t, cmd, "--additional-mcp-config")), &got); err != nil {
			t.Fatalf("%s: --additional-mcp-config is not JSON: %v", name, err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("%s: --additional-mcp-config = %#v, want %#v", name, got, want)
		}
		if !hasArg(cmd, "--allow-tool=operator") {
			t.Fatalf("%s: operator tools not pre-approved: %#v", name, cmd)
		}
	}
	plain, err := p.GetLaunchCommand(context.Background(), ports.LaunchConfig{})
	if err != nil {
		t.Fatal(err)
	}
	for _, arg := range plain {
		if arg == "--additional-mcp-config" {
			t.Fatalf("launch without servers passed --additional-mcp-config: %#v", plain)
		}
	}
}

func hasArg(cmd []string, arg string) bool {
	for _, a := range cmd {
		if a == arg {
			return true
		}
	}
	return false
}
