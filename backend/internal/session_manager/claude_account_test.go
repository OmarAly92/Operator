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

func (f *fakeClaudeAccounts) PrepareLaunch(_ context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error) {
	id = domain.NormalizeClaudeAccountID(id)
	f.prepared = append(f.prepared, id)
	if f.err != nil {
		return domain.ClaudeAccount{}, f.err
	}
	account, ok := f.accounts[id]
	if !ok {
		return domain.ClaudeAccount{}, domain.ErrClaudeAccountNotFound
	}
	return account, nil
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

func TestRuntimeEnvPropagatesFolderUnavailable(t *testing.T) {
	accounts := newFakeClaudeAccounts()
	accounts.err = domain.ErrClaudeAccountFolderUnavailable
	m := New(Deps{ClaudeAccounts: accounts, Executable: func() (string, error) { return "/opt/opr/opr", nil }})
	_, err := m.runtimeEnv(context.Background(), domain.SessionRecord{ID: "proj-1"}, "personal", nil)
	if !errors.Is(err, domain.ErrClaudeAccountFolderUnavailable) {
		t.Fatalf("err = %v", err)
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
