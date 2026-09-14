package transcript

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type oneAgent struct{ agent ports.Agent }

func (o oneAgent) Agent(domain.AgentHarness) (ports.Agent, bool) { return o.agent, true }

type accountEnv map[domain.ClaudeAccountID]map[string]string

func (a accountEnv) EnvFor(_ context.Context, id domain.ClaudeAccountID) (map[string]string, error) {
	if env, ok := a[domain.NormalizeClaudeAccountID(id)]; ok {
		return env, nil
	}
	return nil, domain.ErrClaudeAccountNotFound
}

func TestResolverReadsSessionAccountFolder(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv(domain.ClaudeConfigDirEnv, "")
	personal := filepath.Join(t.TempDir(), ".claude-personal")
	nativeID := claudecode.SessionUUID("proj-3")
	transcript := filepath.Join(personal, "projects", "-repo", nativeID+".jsonl")
	if err := os.MkdirAll(filepath.Dir(transcript), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(transcript, []byte("{}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	accounts := accountEnv{
		domain.DefaultClaudeAccountID: {},
		"personal":                    {domain.ClaudeConfigDirEnv: personal},
	}
	resolver := NewResolver(oneAgent{agent: claudecode.New()}, accounts)
	rec := domain.SessionRecord{ID: "proj-3", Harness: domain.HarnessClaudeCode, ClaudeAccountID: "personal", Metadata: domain.SessionMetadata{AgentSessionID: nativeID}}

	got := resolver.Path(context.Background(), rec)
	want, _ := filepath.EvalSymlinks(transcript)
	if got != want {
		t.Fatalf("path = %q, want %q", got, want)
	}

	rec.ClaudeAccountID = domain.DefaultClaudeAccountID
	if got := resolver.Path(context.Background(), rec); got != "" {
		t.Fatalf("default account resolved another account's transcript: %q", got)
	}
}
