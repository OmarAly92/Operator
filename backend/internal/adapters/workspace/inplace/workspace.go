package inplace

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type ProjectStore interface {
	GetProject(ctx context.Context, id string) (domain.ProjectRecord, bool, error)
}

type Deps struct {
	Projects ProjectStore
}

type Workspace struct {
	projects ProjectStore
}

var _ ports.Workspace = (*Workspace)(nil)
var _ ports.WorkspaceObserver = (*Workspace)(nil)

func New(deps Deps) (*Workspace, error) {
	if deps.Projects == nil {
		return nil, errors.New("inplace workspace: Projects is required")
	}
	return &Workspace{projects: deps.Projects}, nil
}

func (w *Workspace) Create(ctx context.Context, cfg ports.WorkspaceConfig) (ports.WorkspaceInfo, error) {
	if strings.TrimSpace(cfg.Branch) != "" {
		return ports.WorkspaceInfo{}, fmt.Errorf("inplace workspace: a branch cannot be requested: %q", cfg.Branch)
	}
	return w.resolve(ctx, cfg)
}

func (w *Workspace) Restore(ctx context.Context, cfg ports.WorkspaceConfig) (ports.WorkspaceInfo, error) {
	return w.resolve(ctx, ports.WorkspaceConfig{ProjectID: cfg.ProjectID, SessionID: cfg.SessionID, Kind: cfg.Kind})
}

func (w *Workspace) resolve(ctx context.Context, cfg ports.WorkspaceConfig) (ports.WorkspaceInfo, error) {
	project, ok, err := w.projects.GetProject(ctx, string(cfg.ProjectID))
	if err != nil {
		return ports.WorkspaceInfo{}, fmt.Errorf("inplace workspace: project %q: %w", cfg.ProjectID, err)
	}
	if !ok {
		return ports.WorkspaceInfo{}, fmt.Errorf("inplace workspace: project %q not found", cfg.ProjectID)
	}
	path := project.Path
	if info, err := os.Stat(path); err != nil || !info.IsDir() {
		return ports.WorkspaceInfo{}, fmt.Errorf("inplace workspace: project path %q is not a directory", path)
	}
	branch, err := w.currentBranch(ctx, path)
	if err != nil {
		return ports.WorkspaceInfo{}, err
	}
	return ports.WorkspaceInfo{
		Path:      path,
		RepoPath:  path,
		Branch:    branch,
		SessionID: cfg.SessionID,
		ProjectID: cfg.ProjectID,
	}, nil
}

func (w *Workspace) currentBranch(ctx context.Context, path string) (string, error) {
	out, err := exec.CommandContext(ctx, "git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD").Output()
	if err != nil {
		return "", fmt.Errorf("inplace workspace: %q is not a git work tree: %w", path, err)
	}
	branch := strings.TrimSpace(string(out))
	if branch == "" {
		return "", fmt.Errorf("inplace workspace: could not resolve the branch at %q", path)
	}
	return branch, nil
}

func (w *Workspace) Destroy(context.Context, ports.WorkspaceInfo) error { return nil }

func (w *Workspace) ForceDestroy(context.Context, ports.WorkspaceInfo) error { return nil }

func (w *Workspace) StashUncommitted(context.Context, ports.WorkspaceInfo) (string, error) {
	return "", nil
}

func (w *Workspace) ApplyPreserved(context.Context, ports.WorkspaceInfo, string) error { return nil }

func (w *Workspace) AddExclude(ctx context.Context, info ports.WorkspaceInfo, patterns ...string) error {
	return addExclude(ctx, info.Path, patterns...)
}

func addExclude(ctx context.Context, path string, patterns ...string) error {
	if len(patterns) == 0 {
		return nil
	}
	out, err := exec.CommandContext(ctx, "git", "-C", path, "rev-parse", "--git-dir").Output()
	if err != nil {
		return fmt.Errorf("inplace workspace: AddExclude resolve git dir: %w", err)
	}
	gitDir := strings.TrimSpace(string(out))
	if !filepath.IsAbs(gitDir) {
		gitDir = filepath.Join(path, gitDir)
	}
	infoDir := filepath.Join(gitDir, "info")
	if err := os.MkdirAll(infoDir, 0o750); err != nil {
		return fmt.Errorf("inplace workspace: AddExclude create info dir: %w", err)
	}
	excludePath := filepath.Join(infoDir, "exclude")
	existing, _ := os.ReadFile(excludePath)
	var toAdd []string
	for _, p := range patterns {
		if !strings.Contains(string(existing), p) {
			toAdd = append(toAdd, p)
		}
	}
	if len(toAdd) == 0 {
		return nil
	}
	f, err := os.OpenFile(excludePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return fmt.Errorf("inplace workspace: AddExclude open exclude: %w", err)
	}
	defer func() { _ = f.Close() }()
	prefix := ""
	if len(existing) > 0 && !strings.HasSuffix(string(existing), "\n") {
		prefix = "\n"
	}
	if _, err := f.WriteString(prefix + strings.Join(toAdd, "\n") + "\n"); err != nil {
		return fmt.Errorf("inplace workspace: AddExclude write exclude: %w", err)
	}
	return nil
}

const (
	maxObservedWorkspaceChanges = 500
	maxObservedWorkspaceCommits = 20
)

func (w *Workspace) ObserveWorkspace(ctx context.Context, info ports.WorkspaceInfo) (ports.WorkspaceObservation, error) {
	path := strings.TrimSpace(info.Path)
	if path == "" {
		return ports.WorkspaceObservation{}, errors.New("inplace workspace: observe workspace path is required")
	}

	head, err := exec.CommandContext(ctx, "git", "-C", path, "rev-parse", "--verify", "HEAD").Output()
	if err != nil {
		return ports.WorkspaceObservation{}, fmt.Errorf("inplace workspace: observe HEAD: %w", err)
	}
	branch := strings.TrimSpace(info.Branch)
	if out, branchErr := exec.CommandContext(ctx, "git", "-C", path, "branch", "--show-current").Output(); branchErr == nil {
		if current := strings.TrimSpace(string(out)); current != "" {
			branch = current
		}
	}
	statusOut, err := exec.CommandContext(ctx, "git", "-C", path, "status", "--porcelain=v1", "--untracked-files=all").Output()
	if err != nil {
		return ports.WorkspaceObservation{}, fmt.Errorf("inplace workspace: observe status: %w", err)
	}
	changes, staged, untracked := parseObservedWorkspaceChanges(string(statusOut), maxObservedWorkspaceChanges)

	logFormat := "%H%x1f%s%x1f%aI%x1e"
	logOut, err := exec.CommandContext(ctx, "git", "-C", path, "log", "-n", fmt.Sprintf("%d", maxObservedWorkspaceCommits), "--pretty=format:"+logFormat).Output()
	if err != nil {
		return ports.WorkspaceObservation{}, fmt.Errorf("inplace workspace: observe log: %w", err)
	}
	return ports.WorkspaceObservation{
		Path:      path,
		Branch:    branch,
		HeadSHA:   strings.TrimSpace(string(head)),
		Dirty:     len(changes) > 0,
		Staged:    staged,
		Untracked: untracked,
		Changes:   changes,
		Commits:   parseObservedWorkspaceCommits(string(logOut)),
	}, nil
}

func parseObservedWorkspaceChanges(output string, limit int) ([]ports.WorkspaceChange, bool, bool) {
	lines := strings.Split(strings.ReplaceAll(output, "\r\n", "\n"), "\n")
	changes := make([]ports.WorkspaceChange, 0, min(len(lines), limit))
	var staged, untracked bool
	for _, line := range lines {
		if len(line) < 3 {
			continue
		}
		status := line[:2]
		path := strings.TrimSpace(line[3:])
		if path == "" {
			continue
		}
		if status == "??" {
			untracked = true
		} else if status[0] != ' ' && status[0] != '?' {
			staged = true
		}
		if len(changes) < limit {
			changes = append(changes, ports.WorkspaceChange{Path: path, Status: status})
		}
	}
	return changes, staged, untracked
}

func parseObservedWorkspaceCommits(output string) []ports.WorkspaceCommit {
	records := strings.Split(output, "\x1e")
	commits := make([]ports.WorkspaceCommit, 0, len(records))
	for _, record := range records {
		record = strings.TrimSpace(record)
		if record == "" {
			continue
		}
		fields := strings.SplitN(record, "\x1f", 3)
		if len(fields) != 3 {
			continue
		}
		commits = append(commits, ports.WorkspaceCommit{
			SHA:        strings.TrimSpace(fields[0]),
			Subject:    strings.TrimSpace(fields[1]),
			AuthoredAt: strings.TrimSpace(fields[2]),
		})
	}
	return commits
}
