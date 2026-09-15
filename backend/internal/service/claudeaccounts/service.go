package claudeaccounts

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode/claudesetup"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

const (
	maxLabelRunes = 32
	statusTTL     = 30 * time.Second
)

var slugInvalid = regexp.MustCompile(`[^a-z0-9]+`)

type Store interface {
	ListClaudeAccounts(ctx context.Context) ([]domain.ClaudeAccount, error)
	GetClaudeAccount(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error)
	InsertClaudeAccount(ctx context.Context, account domain.ClaudeAccount) error
	RenameClaudeAccount(ctx context.Context, id domain.ClaudeAccountID, label string) error
	DeleteClaudeAccount(ctx context.Context, id domain.ClaudeAccountID) error
}

type AccountView struct {
	Account     domain.ClaudeAccount
	ConfigDir   string
	Status      AuthStatus
	SharedSetup claudesetup.Report
}

type LoginLaunch struct {
	Account domain.ClaudeAccount
	Argv    []string
	Env     map[string]string
	Title   string
}

type Deps struct {
	Store         Store
	Prober        AuthProber
	Home          string
	Now           func() time.Time
	ResolveBinary func(context.Context) (string, error)
}

type Service struct {
	store         Store
	prober        AuthProber
	home          string
	now           func() time.Time
	resolveBinary func(context.Context) (string, error)

	createMu sync.Mutex
	mu       sync.Mutex
	cache    map[domain.ClaudeAccountID]AuthStatus
	added    []func(string)
}

func New(d Deps) *Service {
	now := d.Now
	if now == nil {
		now = func() time.Time { return time.Now().UTC() }
	}
	resolve := d.ResolveBinary
	if resolve == nil {
		resolve = claudecode.ResolveClaudeBinary
	}
	return &Service{
		store:         d.Store,
		prober:        d.Prober,
		home:          filepath.Clean(d.Home),
		now:           now,
		resolveBinary: resolve,
		cache:         map[domain.ClaudeAccountID]AuthStatus{},
	}
}

func Slug(label string) string {
	return strings.Trim(slugInvalid.ReplaceAllString(strings.ToLower(strings.TrimSpace(label)), "-"), "-")
}

func (s *Service) OnAccountAdded(fn func(configDir string)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.added = append(s.added, fn)
}

func (s *Service) defaultDir() string {
	return filepath.Join(s.home, ".claude")
}

func (s *Service) configDir(account domain.ClaudeAccount) string {
	if account.IsDefault {
		return s.defaultDir()
	}
	return account.ConfigDir
}

func (s *Service) Create(ctx context.Context, label string) (domain.ClaudeAccount, error) {
	label = strings.TrimSpace(label)
	slug := Slug(label)
	if slug == "" || utf8.RuneCountInString(label) > maxLabelRunes {
		return domain.ClaudeAccount{}, domain.ErrClaudeAccountLabelInvalid
	}
	s.createMu.Lock()
	defer s.createMu.Unlock()
	dir := filepath.Join(s.home, ".claude-"+slug)
	existing, err := s.store.ListClaudeAccounts(ctx)
	if err != nil {
		return domain.ClaudeAccount{}, err
	}
	for _, account := range existing {
		if strings.EqualFold(account.Label, label) || account.ID == domain.ClaudeAccountID(slug) || account.ConfigDir == dir {
			return domain.ClaudeAccount{}, domain.ErrClaudeAccountExists
		}
	}
	info, err := os.Stat(dir)
	switch {
	case errors.Is(err, os.ErrNotExist):
		if err := os.Mkdir(dir, 0o700); err != nil {
			return domain.ClaudeAccount{}, fmt.Errorf("%w: %w", domain.ErrClaudeAccountFolderUnavailable, err)
		}
	case err != nil:
		return domain.ClaudeAccount{}, fmt.Errorf("%w: %w", domain.ErrClaudeAccountFolderUnavailable, err)
	case !info.IsDir():
		return domain.ClaudeAccount{}, fmt.Errorf("%w: %s is not a directory", domain.ErrClaudeAccountFolderUnavailable, dir)
	}
	if _, err := claudesetup.Ensure(s.defaultDir(), dir); err != nil {
		return domain.ClaudeAccount{}, fmt.Errorf("%w: %w", domain.ErrClaudeAccountFolderUnavailable, err)
	}
	account := domain.ClaudeAccount{ID: domain.ClaudeAccountID(slug), Label: label, ConfigDir: dir, CreatedAt: s.now()}
	if err := s.store.InsertClaudeAccount(ctx, account); err != nil {
		return domain.ClaudeAccount{}, err
	}
	s.mu.Lock()
	hooks := append([]func(string){}, s.added...)
	s.mu.Unlock()
	for _, hook := range hooks {
		hook(claudecode.ProjectsDir(dir))
	}
	return account, nil
}

func (s *Service) Rename(ctx context.Context, id domain.ClaudeAccountID, label string) (domain.ClaudeAccount, error) {
	label = strings.TrimSpace(label)
	if Slug(label) == "" || utf8.RuneCountInString(label) > maxLabelRunes {
		return domain.ClaudeAccount{}, domain.ErrClaudeAccountLabelInvalid
	}
	existing, err := s.store.ListClaudeAccounts(ctx)
	if err != nil {
		return domain.ClaudeAccount{}, err
	}
	for _, account := range existing {
		if account.ID != id && strings.EqualFold(account.Label, label) {
			return domain.ClaudeAccount{}, domain.ErrClaudeAccountExists
		}
	}
	if err := s.store.RenameClaudeAccount(ctx, id, label); err != nil {
		return domain.ClaudeAccount{}, err
	}
	return s.store.GetClaudeAccount(ctx, id)
}

func (s *Service) Delete(ctx context.Context, id domain.ClaudeAccountID) error {
	if err := s.store.DeleteClaudeAccount(ctx, id); err != nil {
		return err
	}
	s.mu.Lock()
	delete(s.cache, id)
	s.mu.Unlock()
	return nil
}

func (s *Service) Relink(ctx context.Context, id domain.ClaudeAccountID) (claudesetup.Report, error) {
	account, err := s.store.GetClaudeAccount(ctx, id)
	if err != nil {
		return nil, err
	}
	if account.IsDefault {
		return claudesetup.Report{}, nil
	}
	report, err := claudesetup.Relink(s.defaultDir(), account.ConfigDir, s.now())
	if err != nil {
		return nil, fmt.Errorf("%w: %w", domain.ErrClaudeAccountFolderUnavailable, err)
	}
	return report, nil
}

func (s *Service) Get(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error) {
	return s.store.GetClaudeAccount(ctx, domain.NormalizeClaudeAccountID(id))
}

func (s *Service) PrepareLaunch(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error) {
	account, err := s.Get(ctx, id)
	if err != nil {
		return domain.ClaudeAccount{}, err
	}
	if account.IsDefault {
		return account, nil
	}
	info, err := os.Stat(account.ConfigDir)
	if err != nil || !info.IsDir() {
		return domain.ClaudeAccount{}, fmt.Errorf("%w: %s", domain.ErrClaudeAccountFolderUnavailable, account.ConfigDir)
	}
	if _, err := claudesetup.Ensure(s.defaultDir(), account.ConfigDir); err != nil {
		return domain.ClaudeAccount{}, fmt.Errorf("%w: %w", domain.ErrClaudeAccountFolderUnavailable, err)
	}
	if err := claudesetup.SyncMCP(filepath.Join(s.home, ".claude.json"), filepath.Join(account.ConfigDir, ".claude.json")); err != nil {
		return domain.ClaudeAccount{}, fmt.Errorf("%w: sync mcp servers: %w", domain.ErrClaudeAccountFolderUnavailable, err)
	}
	return account, nil
}

func (s *Service) Login(ctx context.Context, id domain.ClaudeAccountID) (LoginLaunch, error) {
	account, err := s.PrepareLaunch(ctx, id)
	if err != nil {
		return LoginLaunch{}, err
	}
	binary, err := s.resolveBinary(ctx)
	if err != nil {
		return LoginLaunch{}, err
	}
	env := map[string]string{}
	account.ApplyEnv(env)
	s.mu.Lock()
	delete(s.cache, account.ID)
	s.mu.Unlock()
	return LoginLaunch{Account: account, Argv: []string{binary}, Env: env, Title: "Claude login · " + account.Label}, nil
}

func (s *Service) EnvFor(ctx context.Context, id domain.ClaudeAccountID) (map[string]string, error) {
	account, err := s.Get(ctx, id)
	if err != nil {
		return nil, err
	}
	env := map[string]string{}
	account.ApplyEnv(env)
	return env, nil
}

func (s *Service) ConfigDirFor(ctx context.Context, id domain.ClaudeAccountID) (string, error) {
	account, err := s.Get(ctx, id)
	if err != nil {
		return "", err
	}
	return s.configDir(account), nil
}

func (s *Service) ProjectRootFor(ctx context.Context, id domain.ClaudeAccountID) (string, error) {
	dir, err := s.ConfigDirFor(ctx, id)
	if err != nil {
		return "", err
	}
	return claudecode.ProjectsDir(dir), nil
}

func (s *Service) ProjectRoots(ctx context.Context) ([]string, error) {
	dirs, err := s.ConfigDirs(ctx)
	if err != nil {
		return nil, err
	}
	roots := make([]string, len(dirs))
	for i, dir := range dirs {
		roots[i] = claudecode.ProjectsDir(dir)
	}
	return roots, nil
}

func (s *Service) ConfigDirs(ctx context.Context) ([]string, error) {
	accounts, err := s.store.ListClaudeAccounts(ctx)
	if err != nil {
		return nil, err
	}
	dirs := make([]string, 0, len(accounts))
	for _, account := range accounts {
		dirs = append(dirs, s.configDir(account))
	}
	return dirs, nil
}

func (s *Service) List(ctx context.Context, refresh bool) ([]AccountView, error) {
	accounts, err := s.store.ListClaudeAccounts(ctx)
	if err != nil {
		return nil, err
	}
	views := make([]AccountView, len(accounts))
	var wg sync.WaitGroup
	for i, account := range accounts {
		views[i] = AccountView{Account: account, ConfigDir: s.configDir(account), SharedSetup: claudesetup.Report{}}
		if !account.IsDefault {
			if report, err := claudesetup.Inspect(s.defaultDir(), account.ConfigDir); err == nil {
				views[i].SharedSetup = report
			}
		}
		wg.Add(1)
		go func(i int, account domain.ClaudeAccount) {
			defer wg.Done()
			views[i].Status = s.status(ctx, account, refresh)
		}(i, account)
	}
	wg.Wait()
	return views, nil
}

func (s *Service) status(ctx context.Context, account domain.ClaudeAccount, refresh bool) AuthStatus {
	s.mu.Lock()
	cached, ok := s.cache[account.ID]
	s.mu.Unlock()
	if ok && !refresh && s.now().Sub(cached.CheckedAt) < statusTTL {
		return cached
	}
	env := map[string]string{}
	account.ApplyEnv(env)
	status := AuthStatus{}
	if s.prober != nil {
		if probed, err := s.prober.Probe(ctx, env); err == nil {
			status = probed
		}
	}
	status.CheckedAt = s.now()
	s.mu.Lock()
	s.cache[account.ID] = status
	s.mu.Unlock()
	return status
}
