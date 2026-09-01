package bootstrap

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type vector struct {
	Shell       string            `json:"shell"`
	Integration string            `json:"integration"`
	Suppress    bool              `json:"suppressPrompt"`
	WantArgv    []string          `json:"argv"`
	WantEnv     map[string]string `json:"env"`
}

func fixturePath(t *testing.T, name string) string {
	t.Helper()
	root, err := findRepoRoot()
	if err != nil {
		t.Fatalf("locate repo root: %v", err)
	}
	return filepath.Join(root, "protocol", "fixtures", name)
}

func findRepoRoot() (string, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	dir := cwd
	for {
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", os.ErrNotExist
		}
		dir = parent
		if _, err := os.Stat(filepath.Join(dir, "protocol", "recipes.json")); err == nil {
			return dir, nil
		}
	}
}

type vectorFixture struct {
	Shells map[string]struct {
		Script string   `json:"script"`
		Argv   []string `json:"argv"`
	} `json:"shells"`
	Cases []vector `json:"cases"`
}

func TestRecipeMatchesVector(t *testing.T) {
	raw, err := os.ReadFile(fixturePath(t, "recipe-vectors.json"))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	var fixture vectorFixture
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatalf("parse fixture: %v", err)
	}
	dir := t.TempDir()
	for _, v := range fixture.Cases {
		t.Run(v.Shell+"-"+v.Integration, func(t *testing.T) {
			argv, env, err := Recipe(v.Shell, dir, Options{
				Integration:    Integration(v.Integration),
				SuppressPrompt: v.Suppress,
			})
			if err != nil {
				t.Fatalf("Recipe: %v", err)
			}
			wantArgv := substituteScript(t, v.WantArgv, v.Shell, dir)
			if !argvEqual(argv, wantArgv) {
				t.Errorf("argv mismatch: got %v, want %v", argv, wantArgv)
			}
			if !envEqual(env, v.WantEnv) {
				t.Errorf("env mismatch: got %v, want %v", env, v.WantEnv)
			}
		})
	}
}

func substituteScript(t *testing.T, want []string, shell, dir string) []string {
	t.Helper()
	spec, ok := fixtureScriptFor(t, shell)
	if !ok {
		t.Fatalf("fixture has no shell %q", shell)
	}
	scriptPath, err := scriptPathForMaterialized(dir, spec)
	if err != nil {
		t.Fatalf("expected script path: %v", err)
	}
	out := make([]string, len(want))
	for i, piece := range want {
		out[i] = strings.ReplaceAll(piece, "__SCRIPT__", scriptPath)
	}
	return out
}

func fixtureScriptFor(t *testing.T, shell string) (string, bool) {
	t.Helper()
	raw, err := os.ReadFile(fixturePath(t, "recipe-vectors.json"))
	if err != nil {
		return "", false
	}
	var fixture vectorFixture
	if err := json.Unmarshal(raw, &fixture); err != nil {
		return "", false
	}
	spec, ok := fixture.Shells[shell]
	if !ok {
		return "", false
	}
	return spec.Script, true
}

func scriptPathForMaterialized(dir, scriptName string) (string, error) {
	for _, ext := range []string{".sh", ".fish"} {
		if strings.HasSuffix(scriptName, ext) {
			pattern := filepath.Join(dir, "operator-"+strings.TrimSuffix(scriptName, ext)+"-*"+ext)
			matches, err := filepath.Glob(pattern)
			if err != nil {
				return "", err
			}
			if len(matches) == 0 {
				return "", os.ErrNotExist
			}
			return matches[0], nil
		}
	}
	return "", os.ErrInvalid
}

func argvEqual(got, want []string) bool {
	if len(got) != len(want) {
		return false
	}
	for i := range got {
		if got[i] != want[i] {
			return false
		}
	}
	return true
}

func envEqual(got, want map[string]string) bool {
	if len(got) != len(want) {
		return false
	}
	for k, v := range want {
		if got[k] != v {
			return false
		}
	}
	return true
}

func TestRecipeMaterializesScript(t *testing.T) {
	dir := t.TempDir()
	argv, env, err := Recipe("zsh", dir, Options{Integration: IntegrationAuto})
	if err != nil {
		t.Fatalf("Recipe: %v", err)
	}
	if len(argv) != 3 {
		t.Fatalf("argv length = %d, want 3", len(argv))
	}
	const suffix = `"; OPERATOR_TERMINAL_ORIGINAL_ZDOTDIR="${ZDOTDIR:-$HOME}" ZDOTDIR=`
	if !strings.HasPrefix(argv[2], `source "`) || !strings.Contains(argv[2], suffix) || !strings.HasSuffix(argv[2], `.d exec zsh`) {
		t.Fatalf("argv[2] = %q; want source plus exec zsh through the generated ZDOTDIR", argv[2])
	}
	scriptPath := strings.SplitN(strings.TrimPrefix(argv[2], `source "`), suffix, 2)[0]
	if !filepath.IsAbs(scriptPath) {
		t.Fatalf("script path not absolute: %q", scriptPath)
	}
	if filepath.Dir(scriptPath) != dir {
		t.Errorf("script path %q not in scriptDir %q", scriptPath, dir)
	}
	if filepath.Ext(scriptPath) != ".sh" {
		t.Errorf("script basename = %q, want *.sh", filepath.Base(scriptPath))
	}
	if !strings.HasPrefix(filepath.Base(scriptPath), "operator-zsh-") {
		t.Errorf("script basename = %q, want operator-zsh-*.sh", filepath.Base(scriptPath))
	}
	info, err := os.Stat(scriptPath)
	if err != nil {
		t.Fatalf("stat materialized script: %v", err)
	}
	mode := info.Mode().Perm()
	if mode != 0o700 {
		t.Errorf("script perm = %o, want 0o700", mode)
	}
	startupPath := filepath.Join(scriptPath+".d", ".zshrc")
	startup, err := os.ReadFile(startupPath)
	if err != nil {
		t.Fatalf("read generated zsh startup: %v", err)
	}
	if !strings.Contains(string(startup), `source "`+scriptPath+`"`) {
		t.Fatalf("generated zsh startup does not source %q: %q", scriptPath, startup)
	}
	if env["OPERATOR_TERMINAL_INTEGRATION"] != "auto" {
		t.Errorf("env integration = %q, want auto", env["OPERATOR_TERMINAL_INTEGRATION"])
	}
}

func TestRecipeMaterializesBashStartup(t *testing.T) {
	dir := t.TempDir()
	argv, _, err := Recipe("bash", dir, Options{Integration: IntegrationAuto})
	if err != nil {
		t.Fatalf("Recipe: %v", err)
	}
	if len(argv) != 3 || argv[0] != "bash" || argv[1] != "-c" {
		t.Fatalf("argv = %q, want bash -c <startup command>", argv)
	}
	const prefix = `exec bash --rcfile "`
	const suffix = `".d/.bashrc -i`
	if !strings.HasPrefix(argv[2], prefix) || !strings.HasSuffix(argv[2], suffix) {
		t.Fatalf("argv[2] = %q, want generated bash rcfile startup", argv[2])
	}
	scriptPath := strings.TrimSuffix(strings.TrimPrefix(argv[2], prefix), suffix)
	startupPath := filepath.Join(scriptPath+".d", ".bashrc")
	startup, err := os.ReadFile(startupPath)
	if err != nil {
		t.Fatalf("read generated bash startup: %v", err)
	}
	if !strings.Contains(string(startup), `source "`+scriptPath+`"`) {
		t.Fatalf("generated bash startup does not source %q: %q", scriptPath, startup)
	}
}

func TestRecipeIdempotentMaterialization(t *testing.T) {
	dir := t.TempDir()
	first, _, err := Recipe("bash", dir, Options{Integration: IntegrationAuto})
	if err != nil {
		t.Fatalf("Recipe first call: %v", err)
	}
	second, _, err := Recipe("bash", dir, Options{Integration: IntegrationAuto})
	if err != nil {
		t.Fatalf("Recipe second call: %v", err)
	}
	if first[2] != second[2] {
		t.Errorf("expected same script path, got %q then %q", first[2], second[2])
	}
}

func TestRecipeBareShellForOsc133(t *testing.T) {
	dir := t.TempDir()
	argv, env, err := Recipe("zsh", dir, Options{Integration: IntegrationOSC133Only})
	if err != nil {
		t.Fatalf("Recipe: %v", err)
	}
	if !argvEqual(argv, []string{"zsh"}) {
		t.Errorf("argv = %v, want [zsh]", argv)
	}
	if env["OPERATOR_TERMINAL_INTEGRATION"] != "osc133-only" {
		t.Errorf("env = %v", env)
	}
}

func TestRecipeBareShellForOff(t *testing.T) {
	dir := t.TempDir()
	argv, env, err := Recipe("fish", dir, Options{Integration: IntegrationOff})
	if err != nil {
		t.Fatalf("Recipe: %v", err)
	}
	if !argvEqual(argv, []string{"fish"}) {
		t.Errorf("argv = %v, want [fish]", argv)
	}
	if env["OPERATOR_TERMINAL_INTEGRATION"] != "off" {
		t.Errorf("env = %v", env)
	}
}

func TestRecipeSuppressPrompt(t *testing.T) {
	dir := t.TempDir()
	_, env, err := Recipe("zsh", dir, Options{
		Integration:    IntegrationAuto,
		SuppressPrompt: true,
	})
	if err != nil {
		t.Fatalf("Recipe: %v", err)
	}
	if env["OPERATOR_TERMINAL_SUPPRESS_PROMPT"] != "1" {
		t.Errorf("env = %v", env)
	}
	_, env, err = Recipe("zsh", dir, Options{Integration: IntegrationAuto})
	if err != nil {
		t.Fatalf("Recipe: %v", err)
	}
	if env["OPERATOR_TERMINAL_SUPPRESS_PROMPT"] != "0" {
		t.Errorf("env = %v", env)
	}
}

func TestRecipeRejectsUnknownShell(t *testing.T) {
	dir := t.TempDir()
	if _, _, err := Recipe("powershell", dir, Options{Integration: IntegrationAuto}); err == nil {
		t.Fatal("expected error for unknown shell")
	}
}

func TestRecipeRejectsEmptyScriptDir(t *testing.T) {
	if _, _, err := Recipe("zsh", "", Options{Integration: IntegrationAuto}); err == nil {
		t.Fatal("expected error for empty scriptDir")
	}
}

func TestScriptCopyIsInSyncWithShellDir(t *testing.T) {
	root, err := findRepoRoot()
	if err != nil {
		t.Fatalf("locate repo root: %v", err)
	}
	pairs := []struct{ src, dst string }{
		{filepath.Join(root, "shell", "zsh.sh"), filepath.Join(root, "go", "bootstrap", "shell", "zsh.sh")},
		{filepath.Join(root, "shell", "bash.sh"), filepath.Join(root, "go", "bootstrap", "shell", "bash.sh")},
		{filepath.Join(root, "shell", "fish.fish"), filepath.Join(root, "go", "bootstrap", "shell", "fish.fish")},
		{filepath.Join(root, "protocol", "recipes.json"), filepath.Join(root, "go", "bootstrap", "recipes.json")},
	}
	for _, p := range pairs {
		body, err := os.ReadFile(p.src)
		if err != nil {
			t.Fatalf("read %s: %v", p.src, err)
		}
		copyBody, err := os.ReadFile(p.dst)
		if err != nil {
			t.Fatalf("read %s: %v", p.dst, err)
		}
		if !bytes.Equal(body, copyBody) {
			t.Errorf("drift between %s and %s", p.src, p.dst)
		}
	}
}

func TestManifestEmbedded(t *testing.T) {
	root, err := findRepoRoot()
	if err != nil {
		t.Fatalf("locate repo root: %v", err)
	}
	onDisk, err := os.ReadFile(filepath.Join(root, "protocol", "recipes.json"))
	if err != nil {
		t.Fatalf("read on-disk manifest: %v", err)
	}
	if !bytes.Equal(recipesRaw, onDisk) {
		t.Errorf("embedded recipes.json does not match protocol/recipes.json")
	}
}
