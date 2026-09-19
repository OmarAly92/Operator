package tunnel

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

type NgrokCredential struct {
	Present          bool
	Source           string
	SystemConfigPath string
	Suffix           string
}

type NgrokAgent struct {
	BinaryPath      string
	Source          string
	Version         string
	UpdateAvailable bool
}

type NgrokSession struct {
	Status       string
	Region       string
	Latency      string
	PublicURL    string
	Connections  int
	HTTPRequests int
}

type NgrokLogLine struct {
	Time    string
	Level   string
	Message string
}

type NgrokInfo struct {
	Credential NgrokCredential
	Agent      NgrokAgent
	Session    NgrokSession
	Domain     string
	APIKey     bool
	Logs       []NgrokLogLine
}

type binaryResolver interface {
	Resolve(spec BinarySpec) (string, string, bool)
}

var authtokenLine = regexp.MustCompile(`(?m)^\s*authtoken:\s*(\S+)`)

func readAuthtoken(path string) string {
	if path == "" {
		return ""
	}
	body, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	match := authtokenLine.FindStringSubmatch(string(body))
	if match == nil {
		return ""
	}
	return strings.Trim(match[1], `"'`)
}

func tokenSuffix(token string) string {
	if len(token) <= 4 {
		return ""
	}
	return token[len(token)-4:]
}

func (m *Manager) ngrokConfig() (NgrokConfig, bool) {
	p, ok := m.ngrokProvider().(ngrokProvider)
	if !ok {
		return NgrokConfig{}, false
	}
	return p.cfg, true
}

func (m *Manager) ngrokCredential() (NgrokCredential, string) {
	cfg, _ := m.ngrokConfig()
	cred := NgrokCredential{SystemConfigPath: cfg.UserConfigPath}
	if token := readAuthtoken(ngrokConfigPath(m.dir)); token != "" {
		cred.Present, cred.Source, cred.Suffix = true, "operator", tokenSuffix(token)
		return cred, token
	}
	if token := readAuthtoken(cfg.UserConfigPath); token != "" {
		cred.Present, cred.Source, cred.Suffix = true, "system", tokenSuffix(token)
		return cred, token
	}
	return cred, ""
}

func (m *Manager) ngrokAgent(lines []string) NgrokAgent {
	agent := NgrokAgent{}
	provider := m.ngrokProvider()
	if provider == nil {
		return agent
	}
	if resolver, ok := m.binaries.(binaryResolver); ok {
		if path, source, ok := resolver.Resolve(provider.Binary()); ok {
			agent.BinaryPath, agent.Source = path, source
			agent.Version = m.ngrokVersion(path)
		}
	}
	for _, line := range lines {
		if strings.Contains(line, `"msg":"update available"`) {
			agent.UpdateAvailable = true
			break
		}
	}
	return agent
}

func (m *Manager) ngrokVersion(path string) string {
	m.mu.Lock()
	cached, ok := m.agentVersions[path]
	m.mu.Unlock()
	if ok {
		return cached
	}
	version := ""
	if out, err := exec.Command(path, "version").Output(); err == nil {
		version = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(string(out)), "ngrok version "))
	}
	m.mu.Lock()
	m.agentVersions[path] = version
	m.mu.Unlock()
	return version
}

func readNgrokSession(ctx context.Context, controlPort int) NgrokSession {
	var session NgrokSession
	if controlPort == 0 {
		return session
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	var status struct {
		Status  string `json:"status"`
		Session struct {
			Legs []struct {
				Region  string      `json:"region"`
				Latency json.Number `json:"latency"`
			} `json:"legs"`
		} `json:"session"`
	}
	if err := getJSON(ctx, controlURL(controlPort, "/api/status"), &status); err != nil {
		return session
	}
	session.Status = status.Status
	if len(status.Session.Legs) > 0 {
		leg := status.Session.Legs[0]
		session.Region = leg.Region
		if ns, err := leg.Latency.Int64(); err == nil && ns > 0 {
			session.Latency = fmt.Sprintf("%dms", (ns+500000)/1000000)
		}
	}
	var tunnels struct {
		Tunnels []struct {
			PublicURL string `json:"public_url"`
			Metrics   struct {
				Conns struct {
					Count int `json:"count"`
				} `json:"conns"`
				HTTP struct {
					Count int `json:"count"`
				} `json:"http"`
			} `json:"metrics"`
		} `json:"tunnels"`
	}
	if err := getJSON(ctx, controlURL(controlPort, "/api/tunnels"), &tunnels); err != nil {
		return session
	}
	for _, tun := range tunnels.Tunnels {
		if strings.HasPrefix(tun.PublicURL, "https://") {
			session.PublicURL = tun.PublicURL
			session.Connections = tun.Metrics.Conns.Count
			session.HTTPRequests = tun.Metrics.HTTP.Count
			break
		}
	}
	return session
}

func parseNgrokLogLines(lines []string, secrets ...string) []NgrokLogLine {
	out := make([]NgrokLogLine, 0, len(lines))
	for _, line := range lines {
		var rec struct {
			T   string `json:"t"`
			Lvl string `json:"lvl"`
			Msg string `json:"msg"`
			Err string `json:"err"`
		}
		entry := NgrokLogLine{Message: line}
		if json.Unmarshal([]byte(line), &rec) == nil && rec.Msg != "" {
			entry = NgrokLogLine{Time: rec.T, Level: rec.Lvl, Message: rec.Msg}
			if rec.Err != "" && rec.Err != "<nil>" {
				entry.Message += ": " + tidyProviderError(rec.Err)
			}
		}
		for _, secret := range secrets {
			if secret != "" {
				entry.Message = strings.ReplaceAll(entry.Message, secret, "[redacted]")
			}
		}
		out = append(out, entry)
	}
	return out
}

func (m *Manager) NgrokInfo(ctx context.Context) NgrokInfo {
	lines := m.ProviderLogs("ngrok")
	cred, token := m.ngrokCredential()
	apiKey, _ := m.readAPIKey()
	return NgrokInfo{
		Credential: cred,
		Agent:      m.ngrokAgent(lines),
		Session:    readNgrokSession(ctx, m.ProviderControlPort("ngrok")),
		Domain:     m.NgrokDomain(),
		APIKey:     apiKey != "",
		Logs:       parseNgrokLogLines(lines, token, apiKey),
	}
}
