package project_test

import (
	"context"
	"os"
	"os/exec"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/workspace/gitworktree"
	"github.com/OmarAly92/operator/backend/internal/service/project"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/sqlitetest"
)

func newBranchManager(t *testing.T) *project.Service {
	t.Helper()
	t.Setenv("GIT_CEILING_DIRECTORIES", os.TempDir())
	store, err := sqlitetest.Open(t.TempDir())
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { _ = store.Close() })
	return project.NewWithDeps(project.Deps{Store: store, Branches: gitworktree.NewBranchLister("")})
}

func TestBranchesListsLocalBranchesOfASingleRepoProject(t *testing.T) {
	ctx := context.Background()
	m := newBranchManager(t)
	repo := gitRepo(t)
	if out, err := exec.Command("git", "-C", repo, "checkout", "-b", "logic/home").CombinedOutput(); err != nil {
		t.Fatalf("checkout: %v (%s)", err, out)
	}
	if _, err := m.Add(ctx, project.AddInput{Path: repo, ProjectID: ptr("opr")}); err != nil {
		t.Fatal(err)
	}

	got, err := m.Branches(ctx, "opr")
	if err != nil {
		t.Fatal(err)
	}
	if got.Current != "logic/home" {
		t.Fatalf("current = %q, want logic/home", got.Current)
	}
	found := map[string]project.Branch{}
	for _, b := range got.Branches {
		found[b.Name] = b
	}
	if len(found) != 2 {
		t.Fatalf("branches = %#v, want main and logic/home", got.Branches)
	}
	if home := found["logic/home"]; !home.IsMainCheckout || home.CheckedOutAt == "" {
		t.Fatalf("logic/home = %#v, want the main checkout", home)
	}
	if main := found["main"]; main.IsMainCheckout || main.CheckedOutAt != "" {
		t.Fatalf("main = %#v, want free", main)
	}
}

func TestBranchesRefusesAScratchProject(t *testing.T) {
	ctx := context.Background()
	m := newBranchManager(t)
	scratch, err := m.EnsureDefaultScratchProject(ctx, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	_, err = m.Branches(ctx, scratch.ID)
	wantCode(t, err, "BRANCHES_UNSUPPORTED_PROJECT_KIND")
}

func TestBranchesReportsAnUnknownProject(t *testing.T) {
	_, err := newBranchManager(t).Branches(context.Background(), "nope")
	wantCode(t, err, "PROJECT_NOT_FOUND")
}
