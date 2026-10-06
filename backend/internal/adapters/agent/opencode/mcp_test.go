package opencode

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func TestLaunchAndRestoreWriteMCPServersIntoTheSessionConfig(t *testing.T) {
	dir := t.TempDir()
	systemFile := filepath.Join(dir, "system.md")
	if err := os.WriteFile(systemFile, []byte("standing"), 0o600); err != nil {
		t.Fatal(err)
	}
	server := ports.MCPServerSpec{Name: "operator", Command: "/opt/operator/opr", Args: []string{"mcp"}, Env: map[string]string{"OPERATOR_SESSION_ID": "opr-1"}}
	want := map[string]any{"operator": map[string]any{
		"type": "local", "command": []any{"/opt/operator/opr", "mcp"},
		"environment": map[string]any{"OPERATOR_SESSION_ID": "opr-1"}, "enabled": true,
	}}
	p := &Plugin{resolvedBinary: "opencode"}

	launch, err := p.GetLaunchCommand(context.Background(), ports.LaunchConfig{
		SessionID: "opr-1", SystemPromptFile: systemFile, MCPServers: []ports.MCPServerSpec{server},
	})
	if err != nil {
		t.Fatal(err)
	}
	assertOpencodeMCP(t, launch, want)

	restore, ok, err := p.GetRestoreCommand(context.Background(), ports.RestoreConfig{
		Session:          ports.SessionRef{ID: "opr-1", Metadata: map[string]string{opencodeAgentSessionIDMetadataKey: "ses_1"}},
		SystemPromptFile: systemFile,
		MCPServers:       []ports.MCPServerSpec{server},
	})
	if err != nil || !ok {
		t.Fatalf("restore = %v, %v", ok, err)
	}
	assertOpencodeMCP(t, restore, want)
}

func assertOpencodeMCP(t *testing.T, cmd []string, want map[string]any) {
	t.Helper()
	if len(cmd) < 2 || cmd[0] != "env" || !strings.HasPrefix(cmd[1], opencodeConfigEnvVar+"=") {
		t.Fatalf("command does not point OPENCODE_CONFIG at the session config: %#v", cmd)
	}
	raw, err := os.ReadFile(strings.TrimPrefix(cmd[1], opencodeConfigEnvVar+"="))
	if err != nil {
		t.Fatal(err)
	}
	var cfg map[string]any
	if err := json.Unmarshal(raw, &cfg); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(cfg["mcp"], any(want)) {
		t.Fatalf("mcp block = %#v, want %#v", cfg["mcp"], want)
	}
	if _, ok := cfg["agent"]; !ok {
		t.Fatalf("the Operator agent must stay in the config: %s", raw)
	}
}

func TestSessionConfigOmitsMCPWithoutServers(t *testing.T) {
	dir := t.TempDir()
	systemFile := filepath.Join(dir, "system.md")
	if err := os.WriteFile(systemFile, []byte("standing"), 0o600); err != nil {
		t.Fatal(err)
	}
	cmd, err := (&Plugin{resolvedBinary: "opencode"}).GetLaunchCommand(context.Background(), ports.LaunchConfig{SessionID: "opr-1", SystemPromptFile: systemFile})
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(strings.TrimPrefix(cmd[1], opencodeConfigEnvVar+"="))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), `"mcp"`) {
		t.Fatalf("config without servers carries an mcp block: %s", raw)
	}
}
