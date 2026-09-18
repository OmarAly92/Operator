package ticket

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func initRepo(t *testing.T) string {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed")
	}
	dir := t.TempDir()
	run := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
		cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@x", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@x")
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	run("init", "-q", "-b", "main")
	run("config", "user.name", "t")
	run("config", "user.email", "t@x")
	if err := os.WriteFile(filepath.Join(dir, "README.md"), []byte("hi\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	run("add", "README.md")
	run("commit", "-q", "-m", "init")
	return dir
}

func TestGitHelpers(t *testing.T) {
	ctx := context.Background()
	repo := initRepo(t)
	branch, err := gitCurrentBranch(ctx, repo)
	if err != nil || branch != "main" {
		t.Fatalf("branch=%q err=%v", branch, err)
	}
	rel := ".operator/tickets/editor"
	dirty, err := gitPathDirty(ctx, repo, rel)
	if err != nil || dirty {
		t.Fatalf("empty path dirty=%v err=%v", dirty, err)
	}
	if err := os.MkdirAll(filepath.Join(repo, rel), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(repo, rel, "ticket.md"), []byte("---\ntitle: Editor\n---\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	dirty, err = gitPathDirty(ctx, repo, rel)
	if err != nil || !dirty {
		t.Fatalf("untracked should be dirty: dirty=%v err=%v", dirty, err)
	}
	if err := gitCommitPath(ctx, repo, rel, "ticket: add editor"); err != nil {
		t.Fatal(err)
	}
	dirty, err = gitPathDirty(ctx, repo, rel)
	if err != nil || dirty {
		t.Fatalf("after commit dirty=%v err=%v", dirty, err)
	}
	if err := gitCommitPath(ctx, repo, rel, "ticket: nothing"); err != nil {
		t.Fatalf("nothing to commit must not error: %v", err)
	}
	log, err := gitOutput(ctx, repo, "log", "--oneline")
	if err != nil || len(strings.Split(strings.TrimSpace(log), "\n")) != 2 {
		t.Fatalf("log=%q err=%v", log, err)
	}
	if _, err := gitCurrentBranch(ctx, t.TempDir()); err == nil {
		t.Fatal("non-repo must error")
	}
}
