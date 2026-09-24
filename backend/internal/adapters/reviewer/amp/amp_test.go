package amp

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func TestReviewCommandWritesDenyByDefaultSettings(t *testing.T) {
	r := &Reviewer{resolveBinary: func(context.Context) (string, error) { return "/opt/amp", nil }}
	root := t.TempDir()
	inv := ports.ReviewInvocation{
		TaskPromptRoot: root, SystemPromptFile: "/opr/system.md", Prompt: "Read task.",
		MCPServers: []ports.MCPServerSpec{{Name: "operator", Command: "/opt/opr", Args: []string{"mcp", "--reviewer"}}},
	}
	spec, err := r.ReviewCommand(context.Background(), inv)
	if err != nil {
		t.Fatal(err)
	}
	settingsPath := filepath.Join(root, "amp-settings.json")
	if !slices.Equal(spec.Argv, []string{"/opt/amp", "--settings-file", settingsPath}) {
		t.Fatalf("argv = %#v", spec.Argv)
	}
	if spec.InitialMessage != "First read and follow the reviewer role in `/opr/system.md`. Then Read task." {
		t.Fatalf("initial message = %q", spec.InitialMessage)
	}
	raw, err := os.ReadFile(settingsPath)
	if err != nil {
		t.Fatal(err)
	}
	var settings map[string]any
	if err := json.Unmarshal(raw, &settings); err != nil {
		t.Fatal(err)
	}
	if settings["amp.dangerouslyAllowAll"] != false || settings["amp.remoteThreadCreation.enabled"] != false {
		t.Fatalf("unsafe settings = %#v", settings)
	}
	permissions, ok := settings["amp.permissions"].([]any)
	if !ok || len(permissions) != 8 {
		t.Fatalf("permissions = %#v", settings["amp.permissions"])
	}
	// review_submit is how the reviewer records its result; the catch-all
	// below still rejects every other MCP tool.
	if p := permissions[3].(map[string]any); p["tool"] != "mcp__operator__*" || p["action"] != "allow" {
		t.Fatalf("operator MCP permission = %#v", p)
	}
	servers, _ := settings["amp.mcpServers"].(map[string]any)
	if operator, _ := servers["operator"].(map[string]any); len(servers) != 1 || operator["command"] != "/opt/opr" {
		t.Fatalf("mcp servers = %#v, want only the Operator reviewer server", settings["amp.mcpServers"])
	}
	last := permissions[len(permissions)-1].(map[string]any)
	if last["tool"] != "*" || last["action"] != "reject" {
		t.Fatalf("catch-all permission = %#v", last)
	}
}

func TestReviewCommandPreflightShapeAndCancellation(t *testing.T) {
	r := &Reviewer{resolveBinary: func(context.Context) (string, error) { return "/opt/amp", nil }}
	spec, err := r.ReviewCommand(context.Background(), ports.ReviewInvocation{})
	if err != nil || !slices.Equal(spec.Argv, []string{"/opt/amp"}) || spec.InitialMessage != "" {
		t.Fatalf("spec = %#v, %v", spec, err)
	}
	cancel, err := r.ReviewCancel(context.Background())
	if err != nil || cancel.Mode != ports.ReviewCancelInterrupt || cancel.Interrupts != 2 {
		t.Fatalf("cancel = %#v, %v", cancel, err)
	}
}
