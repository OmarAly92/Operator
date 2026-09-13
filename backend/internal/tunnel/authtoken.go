package tunnel

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func ngrokConfigPath(dir string) string { return filepath.Join(dir, "ngrok.yml") }

type authtokenReporter interface {
	HasAuthtoken() bool
}

func (m *Manager) HasAuthtoken() bool {
	if configCarriesAuthtoken(ngrokConfigPath(m.dir)) {
		return true
	}
	for _, provider := range m.providers {
		if reporter, ok := provider.(authtokenReporter); ok && reporter.HasAuthtoken() {
			return true
		}
	}
	return false
}

func configCarriesAuthtoken(path string) bool {
	if path == "" {
		return false
	}
	body, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return strings.Contains(string(body), "authtoken:")
}

func (m *Manager) SetAuthtoken(ctx context.Context, token string) error {
	trimmed := strings.TrimSpace(token)
	if trimmed == "" {
		return errors.New("tunnel: authtoken must not be empty")
	}
	provider := m.providerNamed("ngrok")
	if provider == nil {
		return errors.New("tunnel: ngrok provider is not configured")
	}
	binary, err := m.binaries.Ensure(ctx, provider.Binary())
	if err != nil {
		return err
	}
	if err := os.MkdirAll(m.dir, 0o700); err != nil {
		return err
	}
	cmd := newTunnelCommand(binary, "config", "add-authtoken", trimmed, "--config", ngrokConfigPath(m.dir))
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("tunnel: ngrok rejected the authtoken: %s", redact(string(out), trimmed))
	}
	if err := os.Chmod(ngrokConfigPath(m.dir), 0o600); err != nil && !os.IsNotExist(err) {
		return err
	}

	m.mu.Lock()
	delete(m.stickyFrom, "ngrok")
	m.status.NeedsAuthtoken = false
	m.mu.Unlock()
	return nil
}

func (m *Manager) providerNamed(name string) Provider {
	for _, candidate := range m.providers {
		if candidate.Name() == name {
			return candidate
		}
	}
	return nil
}

func redact(text, secret string) string {
	cleaned := strings.ReplaceAll(text, secret, "[redacted]")
	return strings.Join(strings.Fields(cleaned), " ")
}
