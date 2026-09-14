package claudeaccounts

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"strings"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/domain"
	aoprocess "github.com/OmarAly92/operator/backend/internal/process"
)

type AuthStatus struct {
	LoggedIn         *bool
	SubscriptionType string
	ReportedEmail    string
	CheckedAt        time.Time
}

type AuthProber interface {
	Probe(ctx context.Context, env map[string]string) (AuthStatus, error)
}

type commandProber struct {
	timeout time.Duration
}

func NewCommandProber(timeout time.Duration) AuthProber {
	return commandProber{timeout: timeout}
}

func (p commandProber) Probe(ctx context.Context, env map[string]string) (AuthStatus, error) {
	binary, err := claudecode.ResolveClaudeBinary(ctx)
	if err != nil {
		return AuthStatus{}, err
	}
	probeCtx, cancel := context.WithTimeout(ctx, p.timeout)
	defer cancel()
	cmd := aoprocess.CommandContext(probeCtx, binary, "auth", "status")
	cmd.Env = processEnv(os.Environ(), env)
	out, _ := cmd.CombinedOutput()
	if probeCtx.Err() != nil {
		return AuthStatus{}, probeCtx.Err()
	}
	status, _ := parseAuthStatus(out)
	return status, nil
}

func processEnv(base []string, env map[string]string) []string {
	out := make([]string, 0, len(base)+len(env))
	for _, kv := range base {
		if strings.HasPrefix(kv, domain.ClaudeConfigDirEnv+"=") {
			continue
		}
		out = append(out, kv)
	}
	for key, value := range env {
		out = append(out, key+"="+value)
	}
	return out
}

func parseAuthStatus(out []byte) (AuthStatus, bool) {
	start := bytes.IndexByte(out, '{')
	end := bytes.LastIndexByte(out, '}')
	if start < 0 || end < start {
		return AuthStatus{}, false
	}
	var raw struct {
		LoggedIn         *bool  `json:"loggedIn"`
		SubscriptionType string `json:"subscriptionType"`
		Email            string `json:"email"`
	}
	if json.Unmarshal(out[start:end+1], &raw) != nil || raw.LoggedIn == nil {
		return AuthStatus{}, false
	}
	return AuthStatus{LoggedIn: raw.LoggedIn, SubscriptionType: raw.SubscriptionType, ReportedEmail: raw.Email}, true
}
