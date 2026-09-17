package slashcommands_test

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	svc "github.com/OmarAly92/operator/backend/internal/service/slashcommands"
	catalogue "github.com/OmarAly92/operator/backend/internal/slashcommands"
)

type fakeSessions struct {
	recs map[domain.SessionID]domain.SessionRecord
}

func (f fakeSessions) GetSession(_ context.Context, id domain.SessionID) (domain.SessionRecord, bool, error) {
	rec, ok := f.recs[id]
	return rec, ok, nil
}

type fakeAccounts struct{ configDir string }

func (f fakeAccounts) EnvFor(context.Context, domain.ClaudeAccountID) (map[string]string, error) {
	return map[string]string{"CLAUDE_CONFIG_DIR": f.configDir}, nil
}

type configDirAgent struct{ ports.Agent }

func (configDirAgent) NativeSessionConfigDir(_ context.Context, env map[string]string) (string, error) {
	return env["CLAUDE_CONFIG_DIR"], nil
}

type fakeAgents struct{ agent ports.Agent }

func (f fakeAgents) Agent(h domain.AgentHarness) (ports.Agent, bool) {
	if h != "claude-code" {
		return nil, false
	}
	return f.agent, true
}

func write(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func fixture(t *testing.T) (configDir, workspace string) {
	t.Helper()
	root := t.TempDir()
	configDir = filepath.Join(root, "claude")
	workspace = filepath.Join(root, "ws")
	pluginDir := filepath.Join(root, "plugin-cache", "superpowers", "6.3.0")

	write(t, filepath.Join(configDir, "commands", "sc", "analyze.md"), "---\nname: analyze\ndescription: \"Comprehensive code analysis\"\n---\nbody\n")
	write(t, filepath.Join(configDir, "commands", "sc", "README.md"), "# not a command\n")
	write(t, filepath.Join(configDir, "commands", "zeta.md"), "no front matter\n")
	write(t, filepath.Join(configDir, "skills", "paseo", "SKILL.md"), "---\nname: paseo\ndescription: Paseo reference\n---\n")
	write(t, filepath.Join(workspace, ".claude", "skills", "bug-triage", "SKILL.md"), "---\ndescription: Triage bugs\n---\n")
	write(t, filepath.Join(workspace, ".claude", "commands", "deploy.md"), "---\ndescription: Deploy it\n---\n")
	write(t, filepath.Join(pluginDir, "skills", "brainstorming", "SKILL.md"), "---\ndescription: Brainstorm first\n---\n")
	write(t, filepath.Join(pluginDir, "commands", "review.md"), "---\ndescription: Plugin review\n---\n")
	disabledDir := filepath.Join(root, "plugin-cache", "disabled", "1.0.0")
	write(t, filepath.Join(disabledDir, "skills", "hidden", "SKILL.md"), "---\ndescription: installed but not enabled\n---\n")
	localDir := filepath.Join(root, "plugin-cache", "frontend-design", "unknown")
	write(t, filepath.Join(localDir, "skills", "frontend-design", "SKILL.md"), "---\ndescription: enabled for another project\n---\n")
	installed, _ := json.Marshal(map[string]any{
		"version": 2,
		"plugins": map[string]any{
			"superpowers@claude-plugins-official":     []map[string]any{{"installPath": pluginDir, "scope": "user"}},
			"disabled@claude-plugins-official":        []map[string]any{{"installPath": disabledDir, "scope": "user"}},
			"frontend-design@claude-plugins-official": []map[string]any{{"installPath": localDir, "scope": "local", "projectPath": filepath.Join(root, "elsewhere")}},
		},
	})
	write(t, filepath.Join(configDir, "plugins", "installed_plugins.json"), string(installed))
	settings, _ := json.Marshal(map[string]any{
		"enabledPlugins": map[string]any{
			"superpowers@claude-plugins-official":     true,
			"frontend-design@claude-plugins-official": true,
		},
	})
	write(t, filepath.Join(configDir, "settings.json"), string(settings))
	return configDir, workspace
}

func TestListDiscoversEverySource(t *testing.T) {
	configDir, workspace := fixture(t)
	sessions := fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{
		"s1": {ID: "s1", Harness: "claude-code", Metadata: domain.SessionMetadata{WorkspacePath: workspace}},
	}}
	s := svc.New(sessions, fakeAgents{agent: configDirAgent{}}, fakeAccounts{configDir: configDir})

	got, err := s.List(context.Background(), "s1")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) < len(catalogue.Builtin) {
		t.Fatalf("got %d commands, want at least the %d built-ins", len(got), len(catalogue.Builtin))
	}
	for i, b := range catalogue.Builtin {
		if got[i] != b {
			t.Fatalf("got[%d] = %+v, want built-in %+v in table order", i, got[i], b)
		}
	}
	rest := got[len(catalogue.Builtin):]
	want := []catalogue.Command{
		{Name: "bug-triage", Description: "Triage bugs", Source: "project"},
		{Name: "deploy", Description: "Deploy it", Source: "project"},
		{Name: "paseo", Description: "Paseo reference", Source: "user"},
		{Name: "sc:analyze", Description: "Comprehensive code analysis", Source: "user"},
		{Name: "superpowers:brainstorming", Description: "Brainstorm first", Source: "plugin"},
		{Name: "superpowers:review", Description: "Plugin review", Source: "plugin"},
		{Name: "zeta", Description: "", Source: "user"},
	}
	if len(rest) != len(want) {
		t.Fatalf("custom commands = %+v\nwant %+v", rest, want)
	}
	for i := range want {
		if rest[i] != want[i] {
			t.Errorf("rest[%d] = %+v, want %+v", i, rest[i], want[i])
		}
	}
}

func TestListDropsDuplicatesKeepingEarlierSource(t *testing.T) {
	configDir, workspace := fixture(t)
	write(t, filepath.Join(configDir, "commands", "compact.md"), "---\ndescription: shadows a built-in\n---\n")
	write(t, filepath.Join(workspace, ".claude", "commands", "paseo.md"), "---\ndescription: shadows a user skill\n---\n")
	sessions := fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{
		"s1": {ID: "s1", Harness: "claude-code", Metadata: domain.SessionMetadata{WorkspacePath: workspace}},
	}}
	s := svc.New(sessions, fakeAgents{agent: configDirAgent{}}, fakeAccounts{configDir: configDir})

	got, err := s.List(context.Background(), "s1")
	if err != nil {
		t.Fatal(err)
	}
	counts := map[string]int{}
	for _, c := range got {
		counts[c.Name]++
		if c.Name == "compact" && c.Source != "builtin" {
			t.Errorf("compact source = %q, want builtin", c.Source)
		}
		if c.Name == "paseo" && c.Source != "user" {
			t.Errorf("paseo source = %q, want user", c.Source)
		}
	}
	for name, n := range counts {
		if n != 1 {
			t.Errorf("%s listed %d times", name, n)
		}
	}
}

func TestListTakesALocalScopePluginOnlyInItsProject(t *testing.T) {
	configDir, workspace := fixture(t)
	elsewhere := filepath.Join(filepath.Dir(configDir), "elsewhere")
	sessions := fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{
		"s1": {ID: "s1", Harness: "claude-code", Metadata: domain.SessionMetadata{WorkspacePath: elsewhere}},
		"s2": {ID: "s2", Harness: "claude-code", Metadata: domain.SessionMetadata{WorkspacePath: workspace}},
	}}
	s := svc.New(sessions, fakeAgents{agent: configDirAgent{}}, fakeAccounts{configDir: configDir})

	has := func(id domain.SessionID, name string) bool {
		got, err := s.List(context.Background(), id)
		if err != nil {
			t.Fatal(err)
		}
		for _, c := range got {
			if c.Name == name {
				return true
			}
		}
		return false
	}
	if !has("s1", "frontend-design:frontend-design") {
		t.Error("the local-scope plugin is missing from the project it was installed for")
	}
	if has("s2", "frontend-design:frontend-design") {
		t.Error("the local-scope plugin leaked into another project")
	}
	if has("s1", "disabled:hidden") || has("s2", "disabled:hidden") {
		t.Error("a plugin without an enabledPlugins entry was listed")
	}
}

func TestListIsEmptyForOtherHarnesses(t *testing.T) {
	configDir, _ := fixture(t)
	sessions := fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{"s1": {ID: "s1", Harness: "codex"}}}
	s := svc.New(sessions, fakeAgents{agent: configDirAgent{}}, fakeAccounts{configDir: configDir})

	got, err := s.List(context.Background(), "s1")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Fatalf("got %d commands for codex, want 0", len(got))
	}
}

func TestListToleratesMissingFolders(t *testing.T) {
	sessions := fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{"s1": {ID: "s1", Harness: "claude-code"}}}
	s := svc.New(sessions, fakeAgents{agent: configDirAgent{}}, fakeAccounts{configDir: filepath.Join(t.TempDir(), "nope")})

	got, err := s.List(context.Background(), "s1")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != len(catalogue.Builtin) {
		t.Fatalf("got %d, want just the %d built-ins", len(got), len(catalogue.Builtin))
	}
}

func TestListFrontMatterWithoutDescriptionIsEmpty(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "claude")
	write(t, filepath.Join(configDir, "commands", "foo.md"), "---\nname: foo\n---\nbody\n")
	sessions := fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{
		"s1": {ID: "s1", Harness: "claude-code"},
	}}
	s := svc.New(sessions, fakeAgents{agent: configDirAgent{}}, fakeAccounts{configDir: configDir})

	got, err := s.List(context.Background(), "s1")
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range got {
		if c.Name == "foo" {
			if c.Description != "" {
				t.Errorf("Description = %q, want empty for front matter with no description key", c.Description)
			}
			return
		}
	}
	t.Fatal("foo command not found in results")
}

func TestListUnknownSession(t *testing.T) {
	s := svc.New(fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{}}, fakeAgents{}, fakeAccounts{})
	if _, err := s.List(context.Background(), "ghost"); err != svc.ErrSessionNotFound {
		t.Fatalf("err = %v, want ErrSessionNotFound", err)
	}
}

func TestListFollowsSymlinkedFoldersLikeAnAdoptedAccount(t *testing.T) {
	root := t.TempDir()
	shared := filepath.Join(root, "shared")
	write(t, filepath.Join(shared, "commands", "sc", "analyze.md"), "---\ndescription: Analyze\n---\n")
	write(t, filepath.Join(shared, "one-skill", "SKILL.md"), "---\ndescription: Linked skill\n---\n")
	write(t, filepath.Join(shared, "nested", "deploy.md"), "---\ndescription: Nested via link\n---\n")

	configDir := filepath.Join(root, "claude-personal")
	if err := os.MkdirAll(filepath.Join(configDir, "skills"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(shared, "commands"), filepath.Join(configDir, "commands")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(shared, "one-skill"), filepath.Join(configDir, "skills", "linked")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(shared, "nested"), filepath.Join(shared, "commands", "extra")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(root, "missing"), filepath.Join(configDir, "skills", "dangling")); err != nil {
		t.Fatal(err)
	}

	sessions := fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{"s1": {ID: "s1", Harness: "claude-code"}}}
	s := svc.New(sessions, fakeAgents{agent: configDirAgent{}}, fakeAccounts{configDir: configDir})

	got, err := s.List(context.Background(), "s1")
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, c := range got {
		if c.Source == catalogue.SourceUser {
			names = append(names, c.Name)
		}
	}
	want := []string{"extra:deploy", "linked", "sc:analyze"}
	if len(names) != len(want) {
		t.Fatalf("user commands = %v, want %v", names, want)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Fatalf("user commands = %v, want %v", names, want)
		}
	}
}
