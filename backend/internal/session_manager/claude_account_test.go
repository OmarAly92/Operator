package sessionmanager

import (
	"context"
	"errors"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeClaudeAccounts struct {
	accounts map[domain.ClaudeAccountID]domain.ClaudeAccount
	prepared []domain.ClaudeAccountID
	err      error
}

func newFakeClaudeAccounts() *fakeClaudeAccounts {
	return &fakeClaudeAccounts{accounts: map[domain.ClaudeAccountID]domain.ClaudeAccount{
		domain.DefaultClaudeAccountID: {ID: domain.DefaultClaudeAccountID, IsDefault: true},
		"personal":                    {ID: "personal", ConfigDir: "/Users/u/.claude-personal"},
	}}
}

func (f *fakeClaudeAccounts) Get(_ context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error) {
	account, ok := f.accounts[domain.NormalizeClaudeAccountID(id)]
	if !ok {
		return domain.ClaudeAccount{}, domain.ErrClaudeAccountNotFound
	}
	return account, nil
}

func (f *fakeClaudeAccounts) Preferred(ctx context.Context) (domain.ClaudeAccount, error) {
	for _, account := range f.accounts {
		if account.IsPreferred {
			return account, nil
		}
	}
	return f.Get(ctx, domain.DefaultClaudeAccountID)
}

func (f *fakeClaudeAccounts) PrepareLaunch(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error) {
	f.prepared = append(f.prepared, domain.NormalizeClaudeAccountID(id))
	if f.err != nil {
		return domain.ClaudeAccount{}, f.err
	}
	return f.Get(ctx, id)
}

type fakeSessionReader struct {
	Store
	sessions map[domain.SessionID]domain.SessionRecord
}

func (f fakeSessionReader) GetSession(_ context.Context, id domain.SessionID) (domain.SessionRecord, bool, error) {
	rec, ok := f.sessions[id]
	return rec, ok, nil
}

func TestRuntimeEnvAppliesAccount(t *testing.T) {
	m := New(Deps{ClaudeAccounts: newFakeClaudeAccounts(), Executable: func() (string, error) { return "/opt/opr/opr", nil }})
	rec := domain.SessionRecord{ID: "proj-1", ProjectID: "proj"}
	projectEnv := map[string]string{domain.ClaudeConfigDirEnv: "/project/override"}

	env, err := m.runtimeEnv(context.Background(), rec, "personal", projectEnv)
	if err != nil || env[domain.ClaudeConfigDirEnv] != "/Users/u/.claude-personal" {
		t.Fatalf("personal env = %q err=%v", env[domain.ClaudeConfigDirEnv], err)
	}

	env, err = m.runtimeEnv(context.Background(), rec, domain.DefaultClaudeAccountID, projectEnv)
	if err != nil {
		t.Fatal(err)
	}
	if value, ok := env[domain.ClaudeConfigDirEnv]; ok {
		t.Fatalf("default env kept %s=%q", domain.ClaudeConfigDirEnv, value)
	}

	if _, err := m.runtimeEnv(context.Background(), rec, "missing", nil); !errors.Is(err, domain.ErrClaudeAccountNotFound) {
		t.Fatalf("missing err = %v", err)
	}
}

func TestLaunchRuntimeEnvPreparesClaudeLaunchOnly(t *testing.T) {
	accounts := newFakeClaudeAccounts()
	accounts.err = domain.ErrClaudeAccountFolderUnavailable
	m := New(Deps{ClaudeAccounts: accounts, Executable: func() (string, error) { return "/opt/opr/opr", nil }})
	ctx := context.Background()

	if _, err := m.runtimeEnv(ctx, domain.SessionRecord{ID: "proj-1", Harness: domain.HarnessClaudeCode}, "personal", nil); err != nil {
		t.Fatalf("runtimeEnv err = %v", err)
	}
	if _, _, err := m.launchRuntimeEnv(ctx, domain.SessionRecord{ID: "proj-1", Harness: domain.HarnessCodex}, "personal", nil); err != nil {
		t.Fatalf("codex launch err = %v", err)
	}
	if len(accounts.prepared) != 0 {
		t.Fatalf("prepared = %v, want none", accounts.prepared)
	}
	_, _, err := m.launchRuntimeEnv(ctx, domain.SessionRecord{ID: "proj-1", Harness: domain.HarnessClaudeCode}, "personal", nil)
	if !errors.Is(err, domain.ErrClaudeAccountFolderUnavailable) || len(accounts.prepared) != 1 {
		t.Fatalf("claude launch err = %v prepared = %v", err, accounts.prepared)
	}
}

func TestResolveSpawnClaudeAccount(t *testing.T) {
	store := fakeSessionReader{sessions: map[domain.SessionID]domain.SessionRecord{
		"orch-1": {ID: "orch-1", ClaudeAccountID: "personal"},
	}}
	m := New(Deps{Store: store, ClaudeAccounts: newFakeClaudeAccounts()})
	ctx := context.Background()

	cases := []struct {
		name string
		cfg  ports.SpawnConfig
		want domain.ClaudeAccountID
		err  error
	}{
		{name: "claude default", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode}, want: domain.DefaultClaudeAccountID},
		{name: "claude explicit", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode, ClaudeAccountID: "personal"}, want: "personal"},
		{name: "claude unknown", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode, ClaudeAccountID: "missing"}, err: domain.ErrInvalidClaudeAccount},
		{name: "codex explicit", cfg: ports.SpawnConfig{Harness: domain.HarnessCodex, ClaudeAccountID: "personal"}, err: domain.ErrInvalidClaudeAccount},
		{name: "codex omitted", cfg: ports.SpawnConfig{Harness: domain.HarnessCodex}, want: domain.DefaultClaudeAccountID},
		{name: "worker inherits orchestrator", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode, RequestedBy: "orch-1"}, want: "personal"},
		{name: "explicit beats orchestrator", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode, RequestedBy: "orch-1", ClaudeAccountID: "default"}, want: domain.DefaultClaudeAccountID},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := m.resolveSpawnClaudeAccount(ctx, tc.cfg)
			if tc.err != nil {
				if !errors.Is(err, tc.err) {
					t.Fatalf("err = %v, want %v", err, tc.err)
				}
				return
			}
			if err != nil || got != tc.want {
				t.Fatalf("got %q err=%v, want %q", got, err, tc.want)
			}
		})
	}
}

func TestResolveSpawnClaudeAccountUsesPreferred(t *testing.T) {
	accounts := newFakeClaudeAccounts()
	accounts.accounts["personal"] = domain.ClaudeAccount{ID: "personal", ConfigDir: "/Users/u/.claude-personal", IsPreferred: true}
	store := fakeSessionReader{sessions: map[domain.SessionID]domain.SessionRecord{
		"orch-1": {ID: "orch-1", ClaudeAccountID: "default"},
	}}
	m := New(Deps{Store: store, ClaudeAccounts: accounts})
	ctx := context.Background()

	cases := []struct {
		name string
		cfg  ports.SpawnConfig
		want domain.ClaudeAccountID
		err  error
	}{
		{name: "omitted uses preferred", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode}, want: "personal"},
		{name: "explicit beats preferred", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode, ClaudeAccountID: "default"}, want: domain.DefaultClaudeAccountID},
		{name: "orchestrator beats preferred", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode, RequestedBy: "orch-1"}, want: domain.DefaultClaudeAccountID},
		{name: "codex ignores preferred", cfg: ports.SpawnConfig{Harness: domain.HarnessCodex}, want: domain.DefaultClaudeAccountID},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := m.resolveSpawnClaudeAccount(ctx, tc.cfg)
			if tc.err != nil {
				if !errors.Is(err, tc.err) {
					t.Fatalf("err = %v, want %v", err, tc.err)
				}
				return
			}
			if err != nil || got != tc.want {
				t.Fatalf("got %q err=%v, want %q", got, err, tc.want)
			}
		})
	}
}

func TestSwitchTargetClaudeAccount(t *testing.T) {
	claudeOnPersonal := domain.SessionRecord{Harness: domain.HarnessClaudeCode, ClaudeAccountID: "personal"}
	codexSession := domain.SessionRecord{Harness: domain.HarnessCodex, ClaudeAccountID: ""}

	cases := []struct {
		name string
		rec  domain.SessionRecord
		cfg  SwitchAgentConfig
		want domain.ClaudeAccountID
		err  error
	}{
		{name: "claude to other account", rec: claudeOnPersonal, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessClaudeCode, TargetClaudeAccountID: "default"}, want: domain.DefaultClaudeAccountID},
		{name: "claude same account rejected", rec: claudeOnPersonal, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessClaudeCode, TargetClaudeAccountID: "personal"}, err: ErrAlreadyUsingHarness},
		{name: "claude omitted account rejected", rec: claudeOnPersonal, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessClaudeCode}, err: ErrAlreadyUsingHarness},
		{name: "claude to codex keeps account", rec: claudeOnPersonal, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessCodex}, want: "personal"},
		{name: "codex target with account rejected", rec: claudeOnPersonal, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessCodex, TargetClaudeAccountID: "default"}, err: domain.ErrInvalidClaudeAccount},
		{name: "codex to claude on account", rec: codexSession, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessClaudeCode, TargetClaudeAccountID: "personal"}, want: "personal"},
		{name: "codex to claude default", rec: codexSession, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessClaudeCode}, want: domain.DefaultClaudeAccountID},
		{name: "codex to codex rejected", rec: codexSession, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessCodex}, err: ErrAlreadyUsingHarness},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := switchTargetClaudeAccount(tc.rec, tc.cfg)
			if tc.err != nil {
				if !errors.Is(err, tc.err) {
					t.Fatalf("err = %v, want %v", err, tc.err)
				}
				return
			}
			if err != nil || got != tc.want {
				t.Fatalf("got %q err=%v, want %q", got, err, tc.want)
			}
		})
	}
}
