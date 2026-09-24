package auggie

import (
	"context"
	"slices"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func TestReviewCommandUsesRulesAndUserPermissions(t *testing.T) {
	r := &Reviewer{resolveBinary: func(context.Context) (string, error) { return "/opt/auggie", nil }}
	spec, err := r.ReviewCommand(context.Background(), ports.ReviewInvocation{
		TaskPromptRoot: "/opr/prompts", SystemPromptFile: "/opr/prompts/system.md", Prompt: "read task",
	})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"/opt/auggie", "--rules", "/opr/prompts/system.md"}
	if !slices.Equal(spec.Argv, want) {
		t.Fatalf("argv = %#v, want %#v", spec.Argv, want)
	}
	if spec.InitialMessage != "read task" {
		t.Fatalf("initial message = %q, want interactive task", spec.InitialMessage)
	}
	if r.ReviewProcessReusable() {
		t.Fatal("Auggie reviewer must force a fresh process for each pass")
	}
}

func TestReviewCommandRegistersOperatorMCPServer(t *testing.T) {
	r := &Reviewer{resolveBinary: func(context.Context) (string, error) { return "/opt/auggie", nil }}
	spec, err := r.ReviewCommand(context.Background(), ports.ReviewInvocation{
		TaskPromptRoot: "/opr/prompts", SystemPromptFile: "/opr/prompts/system.md", Prompt: "Read task.",
		MCPServers: []ports.MCPServerSpec{{Name: "operator", Command: "/opt/opr", Args: []string{"mcp", "--reviewer"}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"/opt/auggie", "--rules", "/opr/prompts/system.md", "--mcp-config", `{"mcpServers":{"operator":{"command":"/opt/opr","args":["mcp","--reviewer"]}}}`}
	if !slices.Equal(spec.Argv, want) {
		t.Fatalf("argv = %#v, want %#v", spec.Argv, want)
	}
}
