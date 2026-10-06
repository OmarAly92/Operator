package gitworktree

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func commitAt(t *testing.T, git, dir, message, date string) {
	t.Helper()
	cmd := exec.Command(git, "-C", dir, "commit", "--allow-empty", "-m", message)
	cmd.Env = append(os.Environ(), "GIT_COMMITTER_DATE="+date, "GIT_AUTHOR_DATE="+date)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("commit %s: %v\n%s", message, err, out)
	}
}

func TestBranchListerOrdersByCommitDateAndMarksCheckouts(t *testing.T) {
	git := requireGit(t)
	tmp := t.TempDir()
	repo := setupOriginClone(t, git, tmp)

	runGit(t, git, repo, "checkout", "-b", "old")
	commitAt(t, git, repo, "old", "2031-01-01T00:00:00Z")
	runGit(t, git, repo, "checkout", "-b", "newest")
	commitAt(t, git, repo, "newest", "2033-01-01T00:00:00Z")
	runGit(t, git, repo, "checkout", "-b", "logic/home", "old")
	commitAt(t, git, repo, "home", "2032-01-01T00:00:00Z")
	linked := filepath.Join(tmp, "linked")
	runGit(t, git, repo, "worktree", "add", linked, "newest")

	listing, err := NewBranchLister(git).ListBranches(context.Background(), repo)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if listing.Current != "logic/home" {
		t.Fatalf("current = %q, want logic/home", listing.Current)
	}
	var names []string
	byName := map[string]ports.BranchInfo{}
	for _, b := range listing.Branches {
		names = append(names, b.Name)
		byName[b.Name] = b
	}
	want := []string{"newest", "logic/home", "old", "main"}
	if len(names) != len(want) {
		t.Fatalf("branches = %v, want %v", names, want)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Fatalf("branches = %v, want %v", names, want)
		}
	}
	home := byName["logic/home"]
	if !home.IsMainCheckout || home.CheckedOutAt == "" {
		t.Fatalf("logic/home = %#v, want main checkout", home)
	}
	newest := byName["newest"]
	if newest.IsMainCheckout || filepath.Base(newest.CheckedOutAt) != "linked" {
		t.Fatalf("newest = %#v, want checked out at linked worktree", newest)
	}
	if old := byName["old"]; old.CheckedOutAt != "" || old.IsMainCheckout {
		t.Fatalf("old = %#v, want free", old)
	}
}

func TestBranchListerReportsDetachedMainCheckout(t *testing.T) {
	git := requireGit(t)
	tmp := t.TempDir()
	repo := setupOriginClone(t, git, tmp)
	runGit(t, git, repo, "checkout", "--detach", "HEAD")

	listing, err := NewBranchLister(git).ListBranches(context.Background(), repo)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if listing.Current != "" {
		t.Fatalf("current = %q, want empty on detached HEAD", listing.Current)
	}
	if len(listing.Branches) != 1 || listing.Branches[0].Name != "main" || listing.Branches[0].CheckedOutAt != "" {
		t.Fatalf("branches = %#v, want free main", listing.Branches)
	}
}

func TestBranchListerFailsOutsideARepo(t *testing.T) {
	git := requireGit(t)
	if _, err := NewBranchLister(git).ListBranches(context.Background(), t.TempDir()); err == nil {
		t.Fatal("want an error for a folder that is not a git repo")
	}
}
