package transcript

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeAgent struct {
	ports.Agent
	configDir string
	located   string
	found     bool
}

func (a *fakeAgent) NativeSessionConfigDir(context.Context, map[string]string) (string, error) {
	return a.configDir, nil
}

func (a *fakeAgent) LocateTranscript(context.Context, ports.NativeSessionRef) (string, bool, error) {
	return a.located, a.found, nil
}

type fakeResolver struct{ agent *fakeAgent }

func (r fakeResolver) Agent(domain.AgentHarness) (ports.Agent, bool) {
	if r.agent == nil {
		return nil, false
	}
	return r.agent, true
}

func writeTranscript(t *testing.T, dir, name string) string {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte("{}\n"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	return path
}

func TestPathPrefersTheHookReportedTranscript(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "native.jsonl")

	resolver := NewResolver(fakeResolver{agent: &fakeAgent{configDir: configDir}})
	rec := domain.SessionRecord{Harness: "claude-code"}
	rec.Metadata.NativeTranscriptPath = path

	got := resolver.Path(context.Background(), rec)
	want, _ := filepath.EvalSymlinks(path)
	if got != want {
		t.Fatalf("Path = %q want %q", got, want)
	}
}

func TestPathFallsBackToTheAdapterLocator(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "sessions"), "rollout.jsonl")

	resolver := NewResolver(fakeResolver{agent: &fakeAgent{configDir: configDir, located: path, found: true}})
	rec := domain.SessionRecord{Harness: "codex"}
	rec.Metadata.AgentSessionID = "native-1"

	got := resolver.Path(context.Background(), rec)
	want, _ := filepath.EvalSymlinks(path)
	if got != want {
		t.Fatalf("Path = %q want %q", got, want)
	}
}

func TestPathRejectsAPathOutsideTheConfigDir(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	outside := writeTranscript(t, filepath.Join(root, "elsewhere"), "evil.jsonl")

	resolver := NewResolver(fakeResolver{agent: &fakeAgent{configDir: configDir}})
	rec := domain.SessionRecord{Harness: "claude-code"}
	rec.Metadata.NativeTranscriptPath = outside

	if got := resolver.Path(context.Background(), rec); got != "" {
		t.Fatalf("Path = %q, want empty for a path outside the provider config dir", got)
	}
}

func TestPathIsEmptyWithoutAnAdapter(t *testing.T) {
	resolver := NewResolver(fakeResolver{})
	if got := resolver.Path(context.Background(), domain.SessionRecord{Harness: "nope"}); got != "" {
		t.Fatalf("Path = %q", got)
	}
}
