package codex

import (
	"context"
	"reflect"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var operatorServer = ports.MCPServerSpec{
	Name:    "operator",
	Command: `/Applications/Operator.app/Contents/MacOS/opr`,
	Args:    []string{"mcp"},
	Env:     map[string]string{"OPERATOR_SESSION_ID": "opr-1", "OPERATOR_DATA_DIR": `C:\Users\me\.operator`},
}

const wantOperatorFlag = `mcp_servers.operator={command="/Applications/Operator.app/Contents/MacOS/opr",args=["mcp"],` +
	`env={OPERATOR_DATA_DIR="C:\\Users\\me\\.operator",OPERATOR_SESSION_ID="opr-1"},default_tools_approval_mode="approve"}`

func TestAppendMCPServerFlagsRendersOneMergingOverride(t *testing.T) {
	var cmd []string
	if err := appendMCPServerFlags(&cmd, []ports.MCPServerSpec{operatorServer}); err != nil {
		t.Fatal(err)
	}
	if want := []string{"-c", wantOperatorFlag}; !reflect.DeepEqual(cmd, want) {
		t.Fatalf("flags\nwant %#v\n got %#v", want, cmd)
	}
}

func TestAppendMCPServerFlagsRejectsDottedKeys(t *testing.T) {
	for _, srv := range []ports.MCPServerSpec{
		{Name: "op.erator", Command: "/x"},
		{Name: "operator", Command: "/x", Env: map[string]string{"A.B": "1"}},
	} {
		var cmd []string
		if err := appendMCPServerFlags(&cmd, []ports.MCPServerSpec{srv}); err == nil {
			t.Fatalf("accepted %+v: %#v", srv, cmd)
		}
	}
}

func TestLaunchAndRestoreRegisterMCPServers(t *testing.T) {
	p := &Plugin{resolvedBinary: "codex"}
	launch, err := p.GetLaunchCommand(context.Background(), ports.LaunchConfig{Prompt: "go", MCPServers: []ports.MCPServerSpec{operatorServer}})
	if err != nil {
		t.Fatal(err)
	}
	if !containsPair(launch, "-c", wantOperatorFlag) {
		t.Fatalf("launch missing MCP override: %#v", launch)
	}
	restore, ok, err := p.GetRestoreCommand(context.Background(), ports.RestoreConfig{
		Session:    ports.SessionRef{Metadata: map[string]string{ports.MetadataKeyAgentSessionID: "native-1"}},
		MCPServers: []ports.MCPServerSpec{operatorServer},
	})
	if err != nil || !ok {
		t.Fatalf("restore = %v, %v", ok, err)
	}
	if !containsPair(restore, "-c", wantOperatorFlag) {
		t.Fatalf("restore missing MCP override: %#v", restore)
	}
	plain, err := p.GetLaunchCommand(context.Background(), ports.LaunchConfig{Prompt: "go"})
	if err != nil {
		t.Fatal(err)
	}
	for _, arg := range plain {
		if len(arg) > 12 && arg[:12] == "mcp_servers." {
			t.Fatalf("launch without servers registered one: %#v", plain)
		}
	}
}

func containsPair(cmd []string, flag, value string) bool {
	for i := 0; i+1 < len(cmd); i++ {
		if cmd[i] == flag && cmd[i+1] == value {
			return true
		}
	}
	return false
}
