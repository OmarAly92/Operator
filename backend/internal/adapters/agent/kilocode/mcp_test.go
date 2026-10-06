package kilocode

import (
	"context"
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func TestLaunchAndRestoreCarryMCPServersInTheInlineConfig(t *testing.T) {
	server := ports.MCPServerSpec{Name: "operator", Command: "/opt/operator/opr", Args: []string{"mcp"}, Env: map[string]string{"OPERATOR_SESSION_ID": "opr-1"}}
	p := &Plugin{resolvedBinary: "kilocode"}
	launch, err := p.GetLaunchCommand(context.Background(), ports.LaunchConfig{MCPServers: []ports.MCPServerSpec{server}})
	if err != nil {
		t.Fatal(err)
	}
	restore, ok, err := p.GetRestoreCommand(context.Background(), ports.RestoreConfig{
		Session:    ports.SessionRef{ID: "opr-1", Metadata: map[string]string{ports.MetadataKeyAgentSessionID: "ses_1"}},
		MCPServers: []ports.MCPServerSpec{server},
	})
	if err != nil || !ok {
		t.Fatalf("restore = %v, %v", ok, err)
	}
	for name, cmd := range map[string][]string{"launch": launch, "restore": restore} {
		if len(cmd) < 2 || cmd[0] != "env" || !strings.HasPrefix(cmd[1], kilocodePermissionEnvVar+"=") {
			t.Fatalf("%s: no inline config: %#v", name, cmd)
		}
		var cfg map[string]any
		if err := json.Unmarshal([]byte(strings.TrimPrefix(cmd[1], kilocodePermissionEnvVar+"=")), &cfg); err != nil {
			t.Fatal(err)
		}
		want := map[string]any{"operator": map[string]any{
			"type": "local", "command": []any{"/opt/operator/opr", "mcp"},
			"environment": map[string]any{"OPERATOR_SESSION_ID": "opr-1"}, "enabled": true,
		}}
		if !reflect.DeepEqual(cfg["mcp"], any(want)) {
			t.Fatalf("%s: mcp = %#v", name, cfg["mcp"])
		}
		if cfg["permission"].(map[string]any)["operator_*"] != "allow" {
			t.Fatalf("%s: operator tools not pre-approved: %#v", name, cfg["permission"])
		}
	}
}
