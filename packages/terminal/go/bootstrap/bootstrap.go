package bootstrap

import (
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type Integration string

const (
	IntegrationAuto       Integration = "auto"
	IntegrationOSC133Only Integration = "osc133-only"
	IntegrationOff        Integration = "off"
)

type Options struct {
	Integration    Integration
	SuppressPrompt bool
}

type RecipeResult struct {
	Argv []string
	Env  map[string]string
}

type shellSpec struct {
	Script string   `json:"script"`
	Argv   []string `json:"argv"`
}

type manifest struct {
	Version int                          `json:"version"`
	Shells  map[string]shellSpec         `json:"shells"`
	Env     map[string]map[string]string `json:"env"`
}

var (
	//go:embed recipes.json
	recipesRaw []byte

	//go:embed shell/zsh.sh
	zshScript []byte

	//go:embed shell/bash.sh
	bashScript []byte

	//go:embed shell/fish.fish
	fishScript []byte
)

func loadManifest() (manifest, error) {
	var m manifest
	if err := json.Unmarshal(recipesRaw, &m); err != nil {
		return manifest{}, fmt.Errorf("parse recipes manifest: %w", err)
	}
	return m, nil
}

func scriptBytesFor(name string) ([]byte, error) {
	switch name {
	case "zsh.sh":
		return zshScript, nil
	case "bash.sh":
		return bashScript, nil
	case "fish.fish":
		return fishScript, nil
	default:
		return nil, fmt.Errorf("unknown shell script %q", name)
	}
}

func renderArgv(template []string, scriptPath string) ([]string, error) {
	out := make([]string, len(template))
	for i, piece := range template {
		token, err := renderTemplate(piece, scriptPath)
		if err != nil {
			return nil, err
		}
		out[i] = token
	}
	return out, nil
}

func renderTemplate(piece, scriptPath string) (string, error) {
	const placeholder = "{{script}}"
	if !strings.Contains(piece, placeholder) {
		return piece, nil
	}
	quoted, err := jsonQuote(scriptPath)
	if err != nil {
		return "", fmt.Errorf("quote script path: %w", err)
	}
	return strings.ReplaceAll(piece, placeholder, quoted), nil
}

func jsonQuote(s string) (string, error) {
	b, err := json.Marshal(s)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func materializeScript(dir, name string, body []byte) (string, error) {
	sum := sha256.Sum256(body)
	encoded := hex.EncodeToString(sum[:])
	stem := strings.TrimSuffix(name, filepath.Ext(name))
	target := filepath.Join(dir, fmt.Sprintf("operator-%s-%s%s", stem, encoded, filepath.Ext(name)))
	if info, err := os.Stat(target); err == nil {
		if info.Size() == int64(len(body)) {
			return target, nil
		}
		return "", fmt.Errorf("script %s already exists with different content", target)
	} else if !os.IsNotExist(err) {
		return "", err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp(dir, fmt.Sprintf(".operator-%s-*.tmp", stem))
	if err != nil {
		return "", err
	}
	tmpName := tmp.Name()
	cleanup := true
	defer func() {
		if cleanup {
			_ = os.Remove(tmpName)
		}
	}()
	if _, err := tmp.Write(body); err != nil {
		tmp.Close()
		return "", err
	}
	if err := tmp.Chmod(0o700); err != nil {
		tmp.Close()
		return "", err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return "", err
	}
	if err := tmp.Close(); err != nil {
		return "", err
	}
	if err := os.Rename(tmpName, target); err != nil {
		return "", err
	}
	cleanup = false
	return target, nil
}

func materializeZshStartup(scriptPath string) error {
	quoted, err := jsonQuote(scriptPath)
	if err != nil {
		return err
	}
	body := []byte("typeset __operator_terminal_saved_zdotdir=${OPERATOR_TERMINAL_ORIGINAL_ZDOTDIR:-$HOME}\n" +
		"ZDOTDIR=$__operator_terminal_saved_zdotdir\n" +
		"unset OPERATOR_TERMINAL_ORIGINAL_ZDOTDIR\n" +
		"if [[ -r $ZDOTDIR/.zshrc ]]; then\n" +
		"\tsource \"$ZDOTDIR/.zshrc\"\n" +
		"fi\n" +
		"source " + quoted + "\n" +
		"unset __operator_terminal_saved_zdotdir\n")
	return materializeStartup(filepath.Join(scriptPath+".d", ".zshrc"), body)
}

func materializeBashStartup(scriptPath string) error {
	quoted, err := jsonQuote(scriptPath)
	if err != nil {
		return err
	}
	body := []byte("if [ -r \"$HOME/.bashrc\" ]; then\n" +
		"\tsource \"$HOME/.bashrc\"\n" +
		"fi\n" +
		"source " + quoted + "\n")
	return materializeStartup(filepath.Join(scriptPath+".d", ".bashrc"), body)
}

func materializeStartup(target string, body []byte) error {
	if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
		return err
	}
	if existing, err := os.ReadFile(target); err == nil {
		if string(existing) == string(body) {
			return nil
		}
		return fmt.Errorf("startup file %s already exists with different content", target)
	} else if !os.IsNotExist(err) {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(target), "."+filepath.Base(target)+"-*.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	cleanup := true
	defer func() {
		if cleanup {
			_ = os.Remove(tmpName)
		}
	}()
	if _, err := tmp.Write(body); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Chmod(0o700); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpName, target); err != nil {
		return err
	}
	cleanup = false
	return nil
}

func Recipe(shell string, scriptDir string, opts Options) ([]string, map[string]string, error) {
	if scriptDir == "" {
		return nil, nil, fmt.Errorf("scriptDir must not be empty")
	}
	m, err := loadManifest()
	if err != nil {
		return nil, nil, err
	}
	if opts.Integration == "" {
		opts.Integration = IntegrationAuto
	}
	envKey := string(opts.Integration)
	envMap, ok := m.Env[envKey]
	if !ok {
		return nil, nil, fmt.Errorf("unknown integration %q", opts.Integration)
	}
	env := make(map[string]string, len(envMap))
	for k, v := range envMap {
		env[k] = v
	}
	if opts.Integration == IntegrationAuto {
		if opts.SuppressPrompt {
			env["OPERATOR_TERMINAL_SUPPRESS_PROMPT"] = "1"
		} else {
			env["OPERATOR_TERMINAL_SUPPRESS_PROMPT"] = "0"
		}
	}
	if opts.Integration == IntegrationOff || opts.Integration == IntegrationOSC133Only {
		return []string{shell}, env, nil
	}
	spec, ok := m.Shells[shell]
	if !ok {
		return nil, nil, fmt.Errorf("unknown shell %q", shell)
	}
	body, err := scriptBytesFor(spec.Script)
	if err != nil {
		return nil, nil, err
	}
	written, err := materializeScript(scriptDir, spec.Script, body)
	if err != nil {
		return nil, nil, err
	}
	if shell == "zsh" {
		if err := materializeZshStartup(written); err != nil {
			return nil, nil, err
		}
	} else if shell == "bash" {
		if err := materializeBashStartup(written); err != nil {
			return nil, nil, err
		}
	}
	argv, err := renderArgv(spec.Argv, written)
	if err != nil {
		return nil, nil, err
	}
	return argv, env, nil
}
