package sessionmanager

import (
	"reflect"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func mcpTestManager(st *fakeStore, agent ports.Agent, executable string) *Manager {
	return New(Deps{
		Runtime: &fakeRuntime{}, Agents: singleAgent{agent: agent}, Workspace: &fakeWorkspace{}, Store: st,
		Messenger: &fakeMessenger{}, Lifecycle: &fakeLCM{store: st},
		LookPath:   func(string) (string, error) { return "/bin/true", nil },
		Executable: func() (string, error) { return executable, nil },
	})
}

func assertOperatorMCPServer(t *testing.T, got []ports.MCPServerSpec, session domain.SessionID) {
	t.Helper()
	if len(got) != 1 {
		t.Fatalf("mcp servers = %#v, want the operator server", got)
	}
	srv := got[0]
	if srv.Name != "operator" || srv.Command != "/opt/operator/opr" || !reflect.DeepEqual(srv.Args, []string{"mcp"}) {
		t.Fatalf("mcp server = %#v", srv)
	}
	if srv.Env[EnvSessionID] != string(session) || srv.Env[EnvProjectID] != "mer" {
		t.Fatalf("mcp server env = %#v, want session %s in project mer", srv.Env, session)
	}
	for _, key := range []string{EnvDataDir, EnvRunFile} {
		if _, ok := srv.Env[key]; !ok {
			t.Fatalf("mcp server env missing %s: %#v", key, srv.Env)
		}
	}
}

func TestSpawnRegistersOperatorMCPServerFromDaemonExecutable(t *testing.T) {
	st := newFakeStore()
	st.projects["mer"] = domain.ProjectRecord{ID: "mer", Config: testRoleAgents()}
	agent := &recordingAgent{}
	m := mcpTestManager(st, agent, "/opt/operator/opr")

	rec, _, _, err := m.Spawn(ctx, ports.SpawnConfig{ProjectID: "mer", Prompt: "fix it"})
	if err != nil {
		t.Fatal(err)
	}
	assertOperatorMCPServer(t, agent.lastLaunch.MCPServers, rec.ID)
}

func TestSpawnRegistersNoMCPServerWhenDaemonIsNotOpr(t *testing.T) {
	st := newFakeStore()
	st.projects["mer"] = domain.ProjectRecord{ID: "mer", Config: testRoleAgents()}
	agent := &recordingAgent{}
	m := mcpTestManager(st, agent, "/tmp/go-build/session_manager.test")

	if _, _, _, err := m.Spawn(ctx, ports.SpawnConfig{ProjectID: "mer", Prompt: "fix it"}); err != nil {
		t.Fatal(err)
	}
	if agent.lastLaunch.MCPServers != nil {
		t.Fatalf("mcp servers = %#v, want none for a non-opr daemon", agent.lastLaunch.MCPServers)
	}
}

func TestRestoreReappliesOperatorMCPServer(t *testing.T) {
	st := newFakeStore()
	st.projects["mer"] = domain.ProjectRecord{ID: "mer", Config: testRoleAgents()}
	seedTerminal(st, "mer-1", domain.SessionMetadata{WorkspacePath: "/ws/mer-1", Branch: "b", AgentSessionID: "agent-x", Prompt: "fix it"})
	agent := &recordingAgent{}
	m := mcpTestManager(st, agent, "/opt/operator/opr")

	if _, err := m.RestoreWithMode(ctx, "mer-1", ports.PaneGrid{}); err != nil {
		t.Fatal(err)
	}
	if agent.restoreCalls != 1 {
		t.Fatalf("restore calls = %d, want a native resume", agent.restoreCalls)
	}
	assertOperatorMCPServer(t, agent.lastRestore.MCPServers, "mer-1")
}

func TestRestoreFreshLaunchReappliesOperatorMCPServer(t *testing.T) {
	st := newFakeStore()
	st.projects["mer"] = domain.ProjectRecord{ID: "mer", Config: testRoleAgents()}
	seedTerminal(st, "mer-1", domain.SessionMetadata{WorkspacePath: "/ws/mer-1", Branch: "b", Prompt: "fix it"})
	agent := &recordingAgent{}
	m := mcpTestManager(st, agent, "/opt/operator/opr")

	if _, err := m.RestoreWithMode(ctx, "mer-1", ports.PaneGrid{}); err != nil {
		t.Fatal(err)
	}
	if agent.launchCalls != 1 {
		t.Fatalf("launch calls = %d, want the fresh-launch fallback", agent.launchCalls)
	}
	assertOperatorMCPServer(t, agent.lastLaunch.MCPServers, "mer-1")
}
