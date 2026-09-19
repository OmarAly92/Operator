package tunnel

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

var ErrNgrokAPIUnauthorized = errors.New("tunnel: ngrok rejected the API key")

var ngrokAPIBase = "https://api.ngrok.com"

const ngrokAPITimeout = 10 * time.Second

type NgrokAccountCredential struct {
	ID          string
	Description string
	CreatedAt   string
	IsOperator  bool
}

type NgrokAccountSession struct {
	ID            string
	Region        string
	IP            string
	AgentVersion  string
	OS            string
	StartedAt     string
	IsThisMachine bool
}

type NgrokAccountEndpoint struct {
	ID        string
	PublicURL string
	Proto     string
	CreatedAt string
}

type NgrokReservedDomain struct {
	ID     string
	Domain string
}

type NgrokAccount struct {
	Valid           bool
	Error           string
	Credentials     []NgrokAccountCredential
	Sessions        []NgrokAccountSession
	Endpoints       []NgrokAccountEndpoint
	ReservedDomains []NgrokReservedDomain
}

func ngrokAPIKeyPath(dir string) string { return filepath.Join(dir, "ngrok-api-key") }

func (m *Manager) readAPIKey() (string, error) {
	body, err := os.ReadFile(ngrokAPIKeyPath(m.dir))
	if os.IsNotExist(err) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(body)), nil
}

func operatorCredentialDescription() string {
	host, err := os.Hostname()
	if err != nil || host == "" {
		host = "this machine"
	}
	return "Operator on " + host
}

type ngrokAPI struct {
	key    string
	client *http.Client
}

func (a ngrokAPI) do(ctx context.Context, method, path string, body, out any) error {
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(encoded)
	}
	req, err := http.NewRequestWithContext(ctx, method, ngrokAPIBase+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+a.key)
	req.Header.Set("Ngrok-Version", "2")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	res, err := a.client.Do(req)
	if err != nil {
		return fmt.Errorf("tunnel: ngrok api: %w", err)
	}
	defer func() { _ = res.Body.Close() }()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode == http.StatusUnauthorized || res.StatusCode == http.StatusForbidden {
		return ErrNgrokAPIUnauthorized
	}
	if res.StatusCode < 200 || res.StatusCode > 299 {
		var apiErr struct {
			Msg string `json:"msg"`
		}
		_ = json.Unmarshal(raw, &apiErr)
		if apiErr.Msg == "" {
			apiErr.Msg = fmt.Sprintf("status %d", res.StatusCode)
		}
		return fmt.Errorf("tunnel: ngrok api %s %s: %s", method, path, redact(apiErr.Msg, a.key))
	}
	if out != nil && len(raw) > 0 {
		return json.Unmarshal(raw, out)
	}
	return nil
}

func (m *Manager) api() (ngrokAPI, error) {
	key, err := m.readAPIKey()
	if err != nil {
		return ngrokAPI{}, err
	}
	if key == "" {
		return ngrokAPI{}, errors.New("tunnel: no ngrok API key is stored")
	}
	return ngrokAPI{key: key, client: &http.Client{Timeout: ngrokAPITimeout}}, nil
}

func (m *Manager) SetAPIKey(ctx context.Context, key string) error {
	trimmed := strings.TrimSpace(key)
	if trimmed == "" {
		return errors.New("tunnel: API key must not be empty")
	}
	probe := ngrokAPI{key: trimmed, client: &http.Client{Timeout: ngrokAPITimeout}}
	if err := probe.do(ctx, http.MethodGet, "/api_keys", nil, nil); err != nil {
		return err
	}
	if err := os.MkdirAll(m.dir, 0o700); err != nil {
		return err
	}
	return os.WriteFile(ngrokAPIKeyPath(m.dir), []byte(trimmed+"\n"), 0o600)
}

func (m *Manager) RemoveAPIKey() error {
	err := os.Remove(ngrokAPIKeyPath(m.dir))
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

func (m *Manager) NgrokAccount(ctx context.Context) NgrokAccount {
	api, err := m.api()
	if err != nil {
		return NgrokAccount{Error: err.Error()}
	}
	ctx, cancel := context.WithTimeout(ctx, 2*ngrokAPITimeout)
	defer cancel()

	var creds struct {
		Credentials []struct {
			ID          string `json:"id"`
			Description string `json:"description"`
			CreatedAt   string `json:"created_at"`
		} `json:"credentials"`
	}
	if err := api.do(ctx, http.MethodGet, "/credentials", nil, &creds); err != nil {
		return NgrokAccount{Error: err.Error()}
	}
	var sessions struct {
		Sessions []struct {
			ID           string `json:"id"`
			Region       string `json:"region"`
			IP           string `json:"ip"`
			AgentVersion string `json:"agent_version"`
			OS           string `json:"os"`
			StartedAt    string `json:"started_at"`
		} `json:"tunnel_sessions"`
	}
	if err := api.do(ctx, http.MethodGet, "/tunnel_sessions", nil, &sessions); err != nil {
		return NgrokAccount{Error: err.Error()}
	}
	var endpoints struct {
		Endpoints []struct {
			ID        string `json:"id"`
			PublicURL string `json:"public_url"`
			Proto     string `json:"proto"`
			CreatedAt string `json:"created_at"`
		} `json:"endpoints"`
	}
	if err := api.do(ctx, http.MethodGet, "/endpoints", nil, &endpoints); err != nil {
		return NgrokAccount{Error: err.Error()}
	}
	var domains struct {
		Domains []struct {
			ID     string `json:"id"`
			Domain string `json:"domain"`
		} `json:"reserved_domains"`
	}
	if err := api.do(ctx, http.MethodGet, "/reserved_domains", nil, &domains); err != nil {
		return NgrokAccount{Error: err.Error()}
	}

	ownURL := m.Status().URL
	operator := operatorCredentialDescription()
	acc := NgrokAccount{Valid: true}
	for _, c := range creds.Credentials {
		acc.Credentials = append(acc.Credentials, NgrokAccountCredential{ID: c.ID, Description: c.Description, CreatedAt: c.CreatedAt, IsOperator: c.Description == operator})
	}
	for _, s := range sessions.Sessions {
		acc.Sessions = append(acc.Sessions, NgrokAccountSession{ID: s.ID, Region: s.Region, IP: s.IP, AgentVersion: s.AgentVersion, OS: s.OS, StartedAt: s.StartedAt})
	}
	for _, e := range endpoints.Endpoints {
		acc.Endpoints = append(acc.Endpoints, NgrokAccountEndpoint{ID: e.ID, PublicURL: e.PublicURL, Proto: e.Proto, CreatedAt: e.CreatedAt})
	}
	for _, d := range domains.Domains {
		acc.ReservedDomains = append(acc.ReservedDomains, NgrokReservedDomain{ID: d.ID, Domain: d.Domain})
	}
	if ownURL != "" && len(acc.Sessions) == 1 {
		acc.Sessions[0].IsThisMachine = true
	}
	return acc
}

func (m *Manager) MintOperatorCredential(ctx context.Context) error {
	api, err := m.api()
	if err != nil {
		return err
	}
	description := operatorCredentialDescription()
	var existing struct {
		Credentials []struct {
			ID          string `json:"id"`
			Description string `json:"description"`
		} `json:"credentials"`
	}
	if err := api.do(ctx, http.MethodGet, "/credentials", nil, &existing); err != nil {
		return err
	}
	var minted struct {
		ID    string `json:"id"`
		Token string `json:"token"`
	}
	if err := api.do(ctx, http.MethodPost, "/credentials", map[string]string{"description": description}, &minted); err != nil {
		return err
	}
	if minted.Token == "" {
		return errors.New("tunnel: ngrok returned a credential without a token")
	}
	if err := os.MkdirAll(m.dir, 0o700); err != nil {
		return err
	}
	if err := writeNgrokAuthtoken(ngrokConfigPath(m.dir), minted.Token); err != nil {
		return err
	}
	for _, c := range existing.Credentials {
		if c.Description == description && c.ID != minted.ID {
			_ = api.do(ctx, http.MethodDelete, "/credentials/"+url.PathEscape(c.ID), nil, nil)
		}
	}
	m.mu.Lock()
	delete(m.stickyFrom, "ngrok")
	m.status.NeedsAuthtoken = false
	m.mu.Unlock()
	return nil
}

func (m *Manager) RevokeCredential(ctx context.Context, id string) error {
	api, err := m.api()
	if err != nil {
		return err
	}
	trimmed := strings.TrimSpace(id)
	if trimmed == "" {
		return errors.New("tunnel: credential id must not be empty")
	}
	var existing struct {
		Credentials []struct {
			ID          string `json:"id"`
			Description string `json:"description"`
		} `json:"credentials"`
	}
	if err := api.do(ctx, http.MethodGet, "/credentials", nil, &existing); err != nil {
		return err
	}
	if err := api.do(ctx, http.MethodDelete, "/credentials/"+url.PathEscape(trimmed), nil, nil); err != nil {
		return err
	}
	for _, c := range existing.Credentials {
		if c.ID == trimmed && c.Description == operatorCredentialDescription() {
			return m.RemoveAuthtoken()
		}
	}
	return nil
}

func (m *Manager) SetStableDomain(ctx context.Context, domain string) error {
	trimmed := strings.TrimSpace(domain)
	if trimmed == "" {
		m.SetNgrokDomain("")
		return nil
	}
	acc := m.NgrokAccount(ctx)
	if !acc.Valid {
		return errors.New(acc.Error)
	}
	for _, d := range acc.ReservedDomains {
		if d.Domain == trimmed {
			m.SetNgrokDomain(trimmed)
			return nil
		}
	}
	return fmt.Errorf("tunnel: %s is not a reserved domain on this ngrok account", trimmed)
}
