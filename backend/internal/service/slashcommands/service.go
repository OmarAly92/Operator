package slashcommands

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/slashcommands"
)

var ErrSessionNotFound = errors.New("slash commands: session not found")

type SessionGetter interface {
	GetSession(ctx context.Context, id domain.SessionID) (domain.SessionRecord, bool, error)
}

type ClaudeAccountEnv interface {
	EnvFor(ctx context.Context, id domain.ClaudeAccountID) (map[string]string, error)
}

type Service struct {
	sessions SessionGetter
	agents   ports.AgentResolver
	accounts ClaudeAccountEnv
}

func New(sessions SessionGetter, agents ports.AgentResolver, accounts ClaudeAccountEnv) *Service {
	return &Service{sessions: sessions, agents: agents, accounts: accounts}
}

func (s *Service) List(ctx context.Context, id domain.SessionID) ([]slashcommands.Command, error) {
	rec, ok, err := s.sessions.GetSession(ctx, id)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrSessionNotFound
	}
	if rec.Harness != domain.HarnessClaudeCode {
		return []slashcommands.Command{}, nil
	}
	out := append([]slashcommands.Command{}, slashcommands.Builtin...)
	seen := map[string]struct{}{}
	for _, c := range out {
		seen[c.Name] = struct{}{}
	}

	var custom []slashcommands.Command
	add := func(cmds []slashcommands.Command) {
		for _, c := range cmds {
			if _, dup := seen[c.Name]; dup {
				continue
			}
			seen[c.Name] = struct{}{}
			custom = append(custom, c)
		}
	}

	configDir := s.configDir(ctx, rec)
	if configDir != "" {
		add(commandsIn(filepath.Join(configDir, "commands"), "", slashcommands.SourceUser))
		add(skillsIn(filepath.Join(configDir, "skills"), "", slashcommands.SourceUser))
	}
	if ws := strings.TrimSpace(rec.Metadata.WorkspacePath); ws != "" {
		add(commandsIn(filepath.Join(ws, ".claude", "commands"), "", slashcommands.SourceProject))
		add(skillsIn(filepath.Join(ws, ".claude", "skills"), "", slashcommands.SourceProject))
	}
	if configDir != "" {
		for _, p := range installedPlugins(configDir, rec.Metadata.WorkspacePath) {
			add(skillsIn(filepath.Join(p.installPath, "skills"), p.name+":", slashcommands.SourcePlugin))
			add(commandsIn(filepath.Join(p.installPath, "commands"), p.name+":", slashcommands.SourcePlugin))
		}
	}
	sort.Slice(custom, func(i, j int) bool { return custom[i].Name < custom[j].Name })
	return append(out, custom...), nil
}

func (s *Service) configDir(ctx context.Context, rec domain.SessionRecord) string {
	if s.agents == nil {
		return ""
	}
	agent, found := s.agents.Agent(rec.Harness)
	if !found || agent == nil {
		return ""
	}
	provider, ok := agent.(ports.AgentNativeSessionConfigProvider)
	if !ok {
		return ""
	}
	env := map[string]string{}
	if s.accounts != nil {
		accountEnv, err := s.accounts.EnvFor(ctx, rec.ClaudeAccountID)
		if err != nil {
			return ""
		}
		env = accountEnv
	}
	dir, err := provider.NativeSessionConfigDir(ctx, env)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(dir)
}

func commandsIn(root, prefix, source string) []slashcommands.Command {
	var out []slashcommands.Command
	walkCommands(root, "", map[string]struct{}{}, func(rel, path string) {
		name := strings.ReplaceAll(strings.TrimSuffix(rel, ".md"), "/", ":")
		out = append(out, slashcommands.Command{
			Name:        prefix + name,
			Description: frontMatterDescription(path),
			Source:      source,
		})
	})
	return out
}

func walkCommands(dir, rel string, visited map[string]struct{}, visit func(rel, path string)) {
	resolved, err := filepath.EvalSymlinks(dir)
	if err != nil {
		return
	}
	if _, seen := visited[resolved]; seen {
		return
	}
	visited[resolved] = struct{}{}
	entries, err := os.ReadDir(resolved)
	if err != nil {
		return
	}
	for _, e := range entries {
		path := filepath.Join(resolved, e.Name())
		childRel := e.Name()
		if rel != "" {
			childRel = rel + "/" + e.Name()
		}
		info, err := os.Stat(path)
		if err != nil {
			continue
		}
		if info.IsDir() {
			walkCommands(path, childRel, visited, visit)
			continue
		}
		if !strings.HasSuffix(e.Name(), ".md") || e.Name() == "README.md" {
			continue
		}
		visit(childRel, path)
	}
}

func skillsIn(root, prefix, source string) []slashcommands.Command {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var out []slashcommands.Command
	for _, e := range entries {
		skill := filepath.Join(root, e.Name(), "SKILL.md")
		if info, statErr := os.Stat(skill); statErr != nil || info.IsDir() {
			continue
		}
		out = append(out, slashcommands.Command{
			Name:        prefix + e.Name(),
			Description: frontMatterDescription(skill),
			Source:      source,
		})
	}
	return out
}

type installedPlugin struct {
	name        string
	installPath string
}

func installedPlugins(configDir, workspace string) []installedPlugin {
	raw, err := os.ReadFile(filepath.Join(configDir, "plugins", "installed_plugins.json"))
	if err != nil {
		return nil
	}
	var file struct {
		Plugins map[string][]struct {
			Scope       string `json:"scope"`
			ProjectPath string `json:"projectPath"`
			InstallPath string `json:"installPath"`
		} `json:"plugins"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		return nil
	}
	enabled := enabledPlugins(configDir)
	workspace = filepath.Clean(strings.TrimSpace(workspace))
	var out []installedPlugin
	for key, installs := range file.Plugins {
		if !enabled[key] {
			continue
		}
		name, _, _ := strings.Cut(key, "@")
		for _, in := range installs {
			if strings.TrimSpace(in.InstallPath) == "" {
				continue
			}
			if in.Scope != "user" && (workspace == "." || filepath.Clean(in.ProjectPath) != workspace) {
				continue
			}
			out = append(out, installedPlugin{name: name, installPath: in.InstallPath})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].name < out[j].name })
	return out
}

func enabledPlugins(configDir string) map[string]bool {
	raw, err := os.ReadFile(filepath.Join(configDir, "settings.json"))
	if err != nil {
		return nil
	}
	var file struct {
		EnabledPlugins map[string]bool `json:"enabledPlugins"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		return nil
	}
	return file.EnabledPlugins
}

func frontMatterDescription(path string) string {
	raw, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	body := bytes.TrimLeft(raw, "\xef\xbb\xbf")
	if !bytes.HasPrefix(body, []byte("---")) {
		return ""
	}
	rest := body[3:]
	end := bytes.Index(rest, []byte("\n---"))
	if end < 0 {
		return ""
	}
	var fm struct {
		Description string `yaml:"description"`
	}
	if err := yaml.Unmarshal(rest[:end], &fm); err != nil {
		return ""
	}
	return strings.TrimSpace(fm.Description)
}
