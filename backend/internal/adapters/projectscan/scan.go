// Package projectscan inspects local folders for importable Git repositories.
//
// It owns the desktop's import-folder scan that used to run in the Electron
// main process (frontend/src/main/import-folder-scan.ts): the daemon serves it
// behind LAN-blocked developer routes so every client resolves the same answer.
package projectscan

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	aoprocess "github.com/OmarAly92/operator/backend/internal/process"
)

// The desktop scan's bounded-resource decisions, kept verbatim.
const (
	scanConcurrency = 8
	maxScanEntries  = 200
	defaultGitBin   = "git"
	defaultTimeout  = 5 * time.Second
)

// Repository statuses reported per candidate.
const (
	StatusOK    = "ok"
	StatusError = "error"
)

// Mode selects single-repository or folder-of-candidates scanning.
type Mode string

// The scan modes.
const (
	ModeProject   Mode = "project"
	ModeWorkspace Mode = "workspace"
)

var skipDirs = map[string]bool{
	".git":         true,
	"node_modules": true,
	"dist":         true,
	"build":        true,
	".cache":       true,
	".turbo":       true,
	"target":       true,
	"coverage":     true,
	"tmp":          true,
	"temp":         true,
	"Library":      true,
}

// Repo is one candidate repository's validated summary.
type Repo struct {
	Name         string `json:"name"`
	Path         string `json:"path"`
	RelativePath string `json:"relativePath"`
	Branch       string `json:"branch"`
	Remote       string `json:"remote"`
	HasRemote    bool   `json:"hasRemote"`
	Status       string `json:"status" enum:"ok,error"`
	Reason       string `json:"reason,omitempty"`
}

// Result is a completed scan of one folder.
type Result struct {
	Path         string `json:"path"`
	Repos        []Repo `json:"repos"`
	SetupWarning string `json:"setupWarning,omitempty"`
}

// Options tune the scanner. Zero values resolve to the desktop defaults.
type Options struct {
	GitBin  string
	Timeout time.Duration
	HomeDir string
}

// Scanner runs bounded local folder scans.
type Scanner struct {
	opts   Options
	runner gitRunner
}

type gitRunner interface {
	gitOutput(ctx context.Context, dir string, args []string) (string, error)
}

// New builds a scanner that shells out to git.
func New(opts Options) *Scanner {
	if opts.GitBin == "" {
		opts.GitBin = defaultGitBin
	}
	if opts.Timeout <= 0 {
		opts.Timeout = defaultTimeout
	}
	return &Scanner{opts: opts, runner: execRunner{opts: opts}}
}

type execRunner struct{ opts Options }

func (e execRunner) gitOutput(ctx context.Context, dir string, args []string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, e.opts.Timeout)
	defer cancel()
	cmd := aoprocess.CommandContext(ctx, e.opts.GitBin, args...)
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		if ctxErr := ctx.Err(); ctxErr != nil {
			return "", ctxErr
		}
		return "", fmt.Errorf("git %s: %w", strings.Join(args, " "), err)
	}
	return strings.TrimSpace(string(out)), nil
}

func (s *Scanner) gitOutput(ctx context.Context, dir string, args []string) (string, error) {
	return s.runner.gitOutput(ctx, dir, args)
}

// ScanFolder scans rootPath for importable repositories. Project mode validates
// the folder itself as one repository; workspace mode validates each direct
// child directory. A nonexistent or unreadable root is an error; individual
// candidates that are not importable repositories are reported, not failed.
func (s *Scanner) ScanFolder(ctx context.Context, rootPath string, mode Mode) (Result, error) {
	if err := ctx.Err(); err != nil {
		return Result{}, err
	}
	switch mode {
	case ModeProject:
		return s.scanProject(ctx, rootPath)
	case ModeWorkspace:
		return s.scanWorkspace(ctx, rootPath)
	default:
		return Result{}, fmt.Errorf("unknown scan mode %q", mode)
	}
}

// AncestorRepository returns the desktop's setup warning when repoPath sits
// inside an enclosing Git repository, or "" when it does not. Any git failure
// means "no ancestor", matching the desktop reader it replaces.
func (s *Scanner) AncestorRepository(ctx context.Context, repoPath string) string {
	top, err := s.gitOutput(ctx, repoPath, []string{"rev-parse", "--show-toplevel"})
	if err != nil {
		return ""
	}
	top = normalizeReportedPath(repoPath, top)
	if top == "" || samePath(top, repoPath) {
		return ""
	}
	return fmt.Sprintf("Selected folder is inside an existing Git repository at %s. "+
		"Operator will initialize this folder as a separate repository.", top)
}

func (s *Scanner) scanProject(ctx context.Context, rootPath string) (Result, error) {
	if reason := s.projectSafetyReason(rootPath); reason != "" {
		return Result{
			Path: rootPath,
			Repos: []Repo{{
				Name:         filepath.Base(rootPath),
				Path:         rootPath,
				RelativePath: ".",
				Branch:       "HEAD",
				Status:       StatusError,
				Reason:       reason,
			}},
		}, nil
	}
	if repo := s.scanGitRepo(ctx, rootPath, rootPath); repo != nil {
		return Result{Path: rootPath, Repos: []Repo{*repo}}, nil
	}
	result := Result{Path: rootPath, Repos: []Repo{}}
	result.SetupWarning = s.AncestorRepository(ctx, rootPath)
	return result, nil
}

func (s *Scanner) scanWorkspace(ctx context.Context, rootPath string) (Result, error) {
	warning := s.AncestorRepository(ctx, rootPath)

	entries, err := os.ReadDir(rootPath)
	if err != nil {
		return Result{}, fmt.Errorf("read %s: %w", rootPath, err)
	}
	candidates := make([]string, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() || skipDirs[entry.Name()] {
			continue
		}
		candidates = append(candidates, filepath.Join(rootPath, entry.Name()))
	}
	if len(candidates) > maxScanEntries {
		candidates = candidates[:maxScanEntries]
	}

	scanned := make([]*Repo, len(candidates))
	err = mapLimited(ctx, candidates, scanConcurrency, func(ctx context.Context, dir string, index int) error {
		scanned[index] = s.scanGitRepo(ctx, dir, rootPath)
		return nil
	})
	if err != nil {
		return Result{}, err
	}

	repos := make([]Repo, 0, len(scanned))
	for _, repo := range scanned {
		if repo != nil {
			repos = append(repos, *repo)
		}
	}
	sort.Slice(repos, func(i, j int) bool { return repos[i].Name < repos[j].Name })

	return Result{Path: rootPath, Repos: repos, SetupWarning: warning}, nil
}

func (s *Scanner) scanGitRepo(ctx context.Context, repoPath, rootPath string) *Repo {
	relativePath := "."
	if repoPath != rootPath {
		rel, err := filepath.Rel(rootPath, repoPath)
		if err != nil {
			rel = repoPath
		}
		relativePath = rel
	}
	base := Repo{
		Name:         filepath.Base(repoPath),
		Path:         repoPath,
		RelativePath: relativePath,
		Branch:       "HEAD",
	}

	gitInfo, statErr := os.Stat(filepath.Join(repoPath, ".git"))
	if statErr != nil {
		out, bareErr := s.gitOutput(ctx, repoPath, []string{"rev-parse", "--is-bare-repository"})
		if bareErr == nil && out == "true" {
			base.Status = StatusError
			base.Reason = "Bare repositories cannot be imported."
			return &base
		}
		return nil
	}
	if !gitInfo.IsDir() {
		base.Status = StatusError
		base.Reason = "Linked worktree children cannot be imported."
		return &base
	}
	if !s.isGitRepo(ctx, repoPath) {
		return nil
	}

	var (
		wg      sync.WaitGroup
		branch  string
		remote  string
		hasRmt  bool
		isBare  bool
		hasHead bool
	)
	wg.Add(4)
	go func() {
		defer wg.Done()
		branch = s.resolveDefaultBranch(ctx, repoPath)
	}()
	go func() {
		defer wg.Done()
		out, err := s.gitOutput(ctx, repoPath, []string{"remote", "get-url", "origin"})
		remote = out
		hasRmt = err == nil && out != ""
	}()
	go func() {
		defer wg.Done()
		out, err := s.gitOutput(ctx, repoPath, []string{"rev-parse", "--is-bare-repository"})
		isBare = err == nil && out == "true"
	}()
	go func() {
		defer wg.Done()
		_, err := s.gitOutput(ctx, repoPath, []string{"rev-parse", "--verify", "HEAD"})
		hasHead = err == nil
	}()
	wg.Wait()

	base.Branch = branch
	base.Remote = remote
	base.HasRemote = hasRmt
	if reason := validationReason(base.Name, branch, hasRmt, isBare, hasHead); reason != "" {
		base.Status = StatusError
		base.Reason = reason
	} else {
		base.Status = StatusOK
	}
	return &base
}

func (s *Scanner) isGitRepo(ctx context.Context, repoPath string) bool {
	info, err := os.Stat(filepath.Join(repoPath, ".git"))
	if err != nil || !info.IsDir() {
		return false
	}
	_, err = s.gitOutput(ctx, repoPath, []string{"rev-parse", "--show-toplevel"})
	return err == nil
}

func (s *Scanner) resolveDefaultBranch(ctx context.Context, repoPath string) string {
	if ref, err := s.gitOutput(ctx, repoPath, []string{"symbolic-ref", "--short", "refs/remotes/origin/HEAD"}); err == nil && ref != "" {
		return strings.TrimPrefix(ref, "origin/")
	}
	if branch, err := s.gitOutput(ctx, repoPath, []string{"branch", "--show-current"}); err == nil && branch != "" {
		return branch
	}
	return "HEAD"
}

func validationReason(name, branch string, hasRemote, isBare, hasHead bool) string {
	switch {
	case name == "__root__":
		return "Repository name is reserved by Operator."
	case isBare:
		return "Bare repositories cannot be imported."
	case !hasHead:
		return "Repository must have at least one commit."
	case branch == "HEAD":
		return "Repository must have a checked-out branch."
	case !hasRemote:
		return "Origin remote is required."
	}
	return ""
}

func (s *Scanner) projectSafetyReason(repoPath string) string {
	home := strings.TrimSpace(s.opts.HomeDir)
	if home == "" {
		return ""
	}
	if isDescendantPath(repoPath, filepath.Join(home, ".operator")) {
		return "Selected folder is inside Operator's internal data directory. Select a project folder outside ~/.operator."
	}
	return ""
}

func normalizeReportedPath(cwd, value string) string {
	if value == "" {
		return ""
	}
	if !filepath.IsAbs(value) {
		value = filepath.Join(cwd, value)
	}
	return filepath.Clean(value)
}

func comparablePath(value string) string {
	resolved, err := filepath.Abs(value)
	if err != nil {
		resolved = filepath.Clean(value)
	}
	if evaluated, err := filepath.EvalSymlinks(resolved); err == nil {
		resolved = evaluated
	}
	if runtime.GOOS == "windows" {
		resolved = strings.ToLower(resolved)
	}
	return resolved
}

func samePath(a, b string) bool {
	return comparablePath(a) == comparablePath(b)
}

func isDescendantPath(child, parent string) bool {
	childKey := comparablePath(child)
	parentKey := comparablePath(parent)
	return childKey == parentKey || strings.HasPrefix(childKey, parentKey+string(os.PathSeparator))
}

func mapLimited[T any](ctx context.Context, items []T, limit int, fn func(context.Context, T, int) error) error {
	if limit <= 0 {
		limit = 1
	}
	if limit > len(items) {
		limit = len(items)
	}
	var (
		next     atomic.Int64
		wg       sync.WaitGroup
		firstErr = make(chan error, 1)
		report   = func(err error) {
			select {
			case firstErr <- err:
			default:
			}
		}
	)
	for worker := 0; worker < limit; worker++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				if err := ctx.Err(); err != nil {
					report(err)
					return
				}
				index := int(next.Add(1)) - 1
				if index >= len(items) {
					return
				}
				if err := fn(ctx, items[index], index); err != nil {
					report(err)
					return
				}
			}
		}()
	}
	wg.Wait()
	select {
	case err := <-firstErr:
		return err
	default:
		return nil
	}
}
