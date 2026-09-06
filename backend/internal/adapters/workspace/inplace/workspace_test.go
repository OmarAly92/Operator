package inplace

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type stubProjects struct{ rec domain.ProjectRecord }

func (s stubProjects) GetProject(context.Context, string) (domain.ProjectRecord, bool, error) {
	return s.rec, true, nil
}

func newRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	for _, args := range [][]string{
		{"init"},
		{"-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "--allow-empty", "-m", "root"},
	} {
		cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "sentinel.txt"), []byte("keep me"), 0o600); err != nil {
		t.Fatal(err)
	}
	return dir
}

func newWorkspace(t *testing.T, repo string) *Workspace {
	t.Helper()
	w, err := New(Deps{Projects: stubProjects{rec: domain.ProjectRecord{ID: "p-1", Path: repo}}})
	if err != nil {
		t.Fatal(err)
	}
	return w
}

func TestCreateReturnsTheProjectPathAndCurrentBranch(t *testing.T) {
	repo := newRepo(t)
	w := newWorkspace(t, repo)
	info, err := w.Create(context.Background(), ports.WorkspaceConfig{ProjectID: "p-1", SessionID: "s-1"})
	if err != nil {
		t.Fatal(err)
	}
	if info.Path != repo || info.RepoPath != repo {
		t.Fatalf("want the project path, got path=%q repo=%q", info.Path, info.RepoPath)
	}
	if info.Branch == "" {
		t.Fatal("want the currently checked out branch recorded")
	}
}

func TestCreateRejectsABranchRequest(t *testing.T) {
	repo := newRepo(t)
	w := newWorkspace(t, repo)
	if _, err := w.Create(context.Background(), ports.WorkspaceConfig{
		ProjectID: "p-1", SessionID: "s-1", Branch: "feature/x",
	}); err == nil {
		t.Fatal("want an error: in-place cannot honour a requested branch")
	}
}

func TestCreateRejectsANonRepository(t *testing.T) {
	dir := t.TempDir()
	w, err := New(Deps{Projects: stubProjects{rec: domain.ProjectRecord{ID: "p-1", Path: dir}}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Create(context.Background(), ports.WorkspaceConfig{ProjectID: "p-1", SessionID: "s-1"}); err == nil {
		t.Fatal("want an error for a path that is not a git work tree")
	}
}

func TestDestroyNeverRemovesTheProjectDirectory(t *testing.T) {
	repo := newRepo(t)
	w := newWorkspace(t, repo)
	info := ports.WorkspaceInfo{Path: repo, RepoPath: repo, ProjectID: "p-1", SessionID: "s-1"}
	if err := w.Destroy(context.Background(), info); err != nil {
		t.Fatalf("Destroy must succeed as a no-op, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(repo, "sentinel.txt")); err != nil {
		t.Fatalf("Destroy deleted the project directory: %v", err)
	}
}

func TestForceDestroyNeverRemovesTheProjectDirectory(t *testing.T) {
	repo := newRepo(t)
	w := newWorkspace(t, repo)
	info := ports.WorkspaceInfo{Path: repo, RepoPath: repo, ProjectID: "p-1", SessionID: "s-1"}
	if err := w.ForceDestroy(context.Background(), info); err != nil {
		t.Fatalf("ForceDestroy must succeed as a no-op, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(repo, "sentinel.txt")); err != nil {
		t.Fatalf("ForceDestroy deleted the project directory: %v", err)
	}
	if _, err := os.Stat(filepath.Join(repo, ".git")); err != nil {
		t.Fatalf("ForceDestroy deleted the git directory: %v", err)
	}
}

func TestStashUncommittedNeverPreserves(t *testing.T) {
	repo := newRepo(t)
	w := newWorkspace(t, repo)
	ref, err := w.StashUncommitted(context.Background(), ports.WorkspaceInfo{
		Path: repo, RepoPath: repo, ProjectID: "p-1", SessionID: "s-1",
	})
	if err != nil || ref != "" {
		t.Fatalf("want (\"\", nil): the user owns this directory, got %q %v", ref, err)
	}
}

func TestObserveWorkspaceReportsRealGitState(t *testing.T) {
	repo := newRepo(t)
	w := newWorkspace(t, repo)
	obs, err := w.ObserveWorkspace(context.Background(), ports.WorkspaceInfo{
		Path: repo, RepoPath: repo, ProjectID: "p-1", SessionID: "s-1",
	})
	if err != nil {
		t.Fatal(err)
	}
	if obs.Branch == "" {
		t.Fatal("want the real branch reported, not a fabricated blank")
	}
}
