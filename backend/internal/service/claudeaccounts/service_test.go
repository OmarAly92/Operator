package claudeaccounts

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type memStore struct {
	mu       sync.Mutex
	accounts map[domain.ClaudeAccountID]domain.ClaudeAccount
	inUse    map[domain.ClaudeAccountID]bool
}

func newMemStore() *memStore {
	return &memStore{
		accounts: map[domain.ClaudeAccountID]domain.ClaudeAccount{
			domain.DefaultClaudeAccountID: {ID: domain.DefaultClaudeAccountID, Label: "Default", IsDefault: true},
		},
		inUse: map[domain.ClaudeAccountID]bool{},
	}
}

func (m *memStore) ListClaudeAccounts(context.Context) ([]domain.ClaudeAccount, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]domain.ClaudeAccount, 0, len(m.accounts))
	for _, a := range m.accounts {
		out = append(out, a)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].IsDefault != out[j].IsDefault {
			return out[i].IsDefault
		}
		return out[i].ID < out[j].ID
	})
	return out, nil
}

func (m *memStore) GetClaudeAccount(_ context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	a, ok := m.accounts[id]
	if !ok {
		return domain.ClaudeAccount{}, domain.ErrClaudeAccountNotFound
	}
	return a, nil
}

func (m *memStore) InsertClaudeAccount(_ context.Context, a domain.ClaudeAccount) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.accounts[a.ID] = a
	return nil
}

func (m *memStore) RenameClaudeAccount(_ context.Context, id domain.ClaudeAccountID, label string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	a, ok := m.accounts[id]
	if !ok {
		return domain.ErrClaudeAccountNotFound
	}
	a.Label = label
	m.accounts[id] = a
	return nil
}

func (m *memStore) PreferredClaudeAccount(ctx context.Context) (domain.ClaudeAccount, error) {
	m.mu.Lock()
	for _, a := range m.accounts {
		if a.IsPreferred {
			m.mu.Unlock()
			return a, nil
		}
	}
	m.mu.Unlock()
	return m.GetClaudeAccount(ctx, domain.DefaultClaudeAccountID)
}

func (m *memStore) SetPreferredClaudeAccount(_ context.Context, id domain.ClaudeAccountID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.accounts[id]; !ok {
		return domain.ErrClaudeAccountNotFound
	}
	for key, a := range m.accounts {
		a.IsPreferred = key == id
		m.accounts[key] = a
	}
	return nil
}

func (m *memStore) DeleteClaudeAccount(_ context.Context, id domain.ClaudeAccountID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	a, ok := m.accounts[id]
	switch {
	case !ok:
		return domain.ErrClaudeAccountNotFound
	case a.IsDefault:
		return domain.ErrClaudeAccountDefaultImmutable
	case m.inUse[id]:
		return domain.ErrClaudeAccountInUse
	}
	delete(m.accounts, id)
	return nil
}

type fakeProber struct {
	mu    sync.Mutex
	calls int
	envs  []map[string]string
}

func (f *fakeProber) Probe(_ context.Context, env map[string]string) (AuthStatus, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.envs = append(f.envs, env)
	yes := true
	return AuthStatus{LoggedIn: &yes, SubscriptionType: "pro"}, nil
}

func newTestService(t *testing.T) (*Service, *memStore, *fakeProber, string) {
	t.Helper()
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, ".claude", "skills"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, ".claude", "CLAUDE.md"), []byte("rules"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, ".claude.json"), []byte(`{"mcpServers":{"pencil":{}}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	store := newMemStore()
	prober := &fakeProber{}
	svc := New(Deps{
		Store:  store,
		Prober: prober,
		Home:   home,
		Now:    func() time.Time { return time.Unix(1789400000, 0).UTC() },
		ResolveBinary: func(context.Context) (string, error) {
			return "/usr/local/bin/claude", nil
		},
	})
	return svc, store, prober, home
}

func TestSlug(t *testing.T) {
	cases := map[string]string{
		"Personal":        "personal",
		"  Work Account ": "work-account",
		"Omar's #2":       "omar-s-2",
		"---":             "",
	}
	for in, want := range cases {
		if got := Slug(in); got != want {
			t.Errorf("Slug(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestCreateMakesFolderLinksAndNotifies(t *testing.T) {
	svc, _, _, home := newTestService(t)
	var added []string
	svc.OnAccountAdded(func(dir string) { added = append(added, dir) })

	account, err := svc.Create(context.Background(), " Personal ")
	if err != nil {
		t.Fatal(err)
	}
	wantDir := filepath.Join(home, ".claude-personal")
	if account.ID != "personal" || account.Label != "Personal" || account.ConfigDir != wantDir {
		t.Fatalf("account = %+v", account)
	}
	info, err := os.Stat(wantDir)
	if err != nil || !info.IsDir() || info.Mode().Perm() != 0o700 {
		t.Fatalf("folder info = %v err=%v", info, err)
	}
	if target, err := os.Readlink(filepath.Join(wantDir, "CLAUDE.md")); err != nil || target != filepath.Join(home, ".claude", "CLAUDE.md") {
		t.Fatalf("CLAUDE.md link = %q err=%v", target, err)
	}
	if len(added) != 1 || added[0] != filepath.Join(wantDir, "projects") {
		t.Fatalf("added = %v", added)
	}
}

func TestCreateAdoptsExistingFolder(t *testing.T) {
	svc, _, _, home := newTestService(t)
	dir := filepath.Join(home, ".claude-personal")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".claude.json"), []byte(`{"userID":"keep"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Create(context.Background(), "Personal"); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(filepath.Join(dir, ".claude.json"))
	if string(data) != `{"userID":"keep"}` {
		t.Fatalf("existing config changed: %s", data)
	}
}

func TestCreateRejectsInvalidAndDuplicate(t *testing.T) {
	svc, _, _, home := newTestService(t)
	ctx := context.Background()
	for _, label := range []string{"", "   ", "---", "this label is far longer than thirty-two runes"} {
		if _, err := svc.Create(ctx, label); !errors.Is(err, domain.ErrClaudeAccountLabelInvalid) {
			t.Errorf("Create(%q) err = %v", label, err)
		}
	}
	if _, err := svc.Create(ctx, "Default"); !errors.Is(err, domain.ErrClaudeAccountExists) {
		t.Errorf("Default err = %v", err)
	}
	if _, err := svc.Create(ctx, "Personal"); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Create(ctx, "personal"); !errors.Is(err, domain.ErrClaudeAccountExists) {
		t.Errorf("duplicate err = %v", err)
	}
	if err := os.WriteFile(filepath.Join(home, ".claude-file"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Create(ctx, "File"); !errors.Is(err, domain.ErrClaudeAccountFolderUnavailable) {
		t.Errorf("file path err = %v", err)
	}
}

func TestRenameKeepsFolder(t *testing.T) {
	svc, _, _, _ := newTestService(t)
	ctx := context.Background()
	created, err := svc.Create(ctx, "Personal")
	if err != nil {
		t.Fatal(err)
	}
	renamed, err := svc.Rename(ctx, "personal", "Home")
	if err != nil {
		t.Fatal(err)
	}
	if renamed.Label != "Home" || renamed.ConfigDir != created.ConfigDir || renamed.ID != "personal" {
		t.Fatalf("renamed = %+v", renamed)
	}
}

func TestPrepareLaunch(t *testing.T) {
	svc, _, _, home := newTestService(t)
	ctx := context.Background()
	def, err := svc.PrepareLaunch(ctx, "")
	if err != nil || !def.IsDefault {
		t.Fatalf("default = %+v err=%v", def, err)
	}
	created, err := svc.Create(ctx, "Personal")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(created.ConfigDir, "CLAUDE.md")); err != nil {
		t.Fatal(err)
	}
	got, err := svc.PrepareLaunch(ctx, "personal")
	if err != nil || got.ConfigDir != created.ConfigDir {
		t.Fatalf("prepare = %+v err=%v", got, err)
	}
	if _, err := os.Readlink(filepath.Join(created.ConfigDir, "CLAUDE.md")); err != nil {
		t.Fatalf("link not repaired: %v", err)
	}
	data, err := os.ReadFile(filepath.Join(created.ConfigDir, ".claude.json"))
	if err != nil || string(data) == "" {
		t.Fatalf("mcp not synced: %s err=%v", data, err)
	}
	if err := os.RemoveAll(created.ConfigDir); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.PrepareLaunch(ctx, "personal"); !errors.Is(err, domain.ErrClaudeAccountFolderUnavailable) {
		t.Fatalf("missing folder err = %v", err)
	}
	if _, err := svc.PrepareLaunch(ctx, "missing"); !errors.Is(err, domain.ErrClaudeAccountNotFound) {
		t.Fatalf("unknown err = %v", err)
	}
	_ = home
}

func TestEnvForAndConfigDirs(t *testing.T) {
	svc, _, _, home := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Create(ctx, "Personal"); err != nil {
		t.Fatal(err)
	}
	env, err := svc.EnvFor(ctx, domain.DefaultClaudeAccountID)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := env[domain.ClaudeConfigDirEnv]; ok {
		t.Fatalf("default env = %v", env)
	}
	env, err = svc.EnvFor(ctx, "personal")
	if err != nil || env[domain.ClaudeConfigDirEnv] != filepath.Join(home, ".claude-personal") {
		t.Fatalf("personal env = %v err=%v", env, err)
	}
	dirs, err := svc.ConfigDirs(ctx)
	want := []string{filepath.Join(home, ".claude"), filepath.Join(home, ".claude-personal")}
	if err != nil || len(dirs) != 2 || dirs[0] != want[0] || dirs[1] != want[1] {
		t.Fatalf("dirs = %v err=%v", dirs, err)
	}
}

func TestListCachesStatusAndRefreshBypasses(t *testing.T) {
	svc, _, prober, _ := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Create(ctx, "Personal"); err != nil {
		t.Fatal(err)
	}
	views, err := svc.List(ctx, false)
	if err != nil || len(views) != 2 || prober.calls != 2 {
		t.Fatalf("views=%d calls=%d err=%v", len(views), prober.calls, err)
	}
	if views[0].ConfigDir == "" || views[1].SharedSetup["CLAUDE.md"] != "linked" {
		t.Fatalf("views = %+v", views)
	}
	if _, err := svc.List(ctx, false); err != nil || prober.calls != 2 {
		t.Fatalf("cached list probed again: calls=%d", prober.calls)
	}
	if _, err := svc.List(ctx, true); err != nil || prober.calls != 4 {
		t.Fatalf("refresh did not probe: calls=%d", prober.calls)
	}
}

func TestLoginBuildsLaunch(t *testing.T) {
	svc, _, _, home := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Create(ctx, "Personal"); err != nil {
		t.Fatal(err)
	}
	launch, err := svc.Login(ctx, "personal")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(launch.Argv, " ") != "/usr/local/bin/claude auth login" {
		t.Fatalf("argv = %v", launch.Argv)
	}
	if launch.Env[domain.ClaudeConfigDirEnv] != filepath.Join(home, ".claude-personal") || launch.Title != "Claude login · Personal" {
		t.Fatalf("launch = %+v", launch)
	}
}

func TestDeletePassesStoreErrors(t *testing.T) {
	svc, store, _, _ := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Create(ctx, "Personal"); err != nil {
		t.Fatal(err)
	}
	store.inUse["personal"] = true
	if err := svc.Delete(ctx, "personal"); !errors.Is(err, domain.ErrClaudeAccountInUse) {
		t.Fatalf("err = %v", err)
	}
}
