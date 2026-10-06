package integration

import (
	"context"
	"errors"
	"testing"
	"time"

	inplaceworkspace "github.com/OmarAly92/operator/backend/internal/adapters/workspace/inplace"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/lifecycle"
	sessionsvc "github.com/OmarAly92/operator/backend/internal/service/session"
	sessionmanager "github.com/OmarAly92/operator/backend/internal/session_manager"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/sqlitetest"
)

func newInPlaceBranchStack(t *testing.T, repo string) (*sessionsvc.Service, interface {
	ListSessions(context.Context, domain.ProjectID) ([]domain.SessionRecord, error)
}) {
	t.Helper()
	ctx := context.Background()
	store, err := sqlitetest.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close() })
	if err := store.UpsertProject(ctx, domain.ProjectRecord{
		ID: "br", Path: repo, Kind: domain.ProjectKindSingleRepo, RegisteredAt: time.Now(),
		Config: domain.ProjectConfig{DefaultBranch: "main", Harness: domain.HarnessClaudeCode},
	}); err != nil {
		t.Fatal(err)
	}
	ws, err := inplaceworkspace.New(inplaceworkspace.Deps{Projects: store})
	if err != nil {
		t.Fatal(err)
	}
	msg := &captureMessenger{}
	lcm := lifecycle.New(store, msg)
	mgr := sessionmanager.New(sessionmanager.Deps{Runtime: &stubRuntime{}, Agents: stubAgents{}, Workspace: ws, Store: store, Messenger: msg, Lifecycle: lcm, LookPath: func(string) (string, error) { return "/usr/bin/true", nil }})
	lcm.SetCompletionTerminator(mgr)
	return sessionsvc.New(mgr, store), store
}

func TestDelegateInPlaceRefusesABranchNotCheckedOutAndLeavesNoRow(t *testing.T) {
	ctx := context.Background()
	repo := gitRepo(t)
	svc, store := newInPlaceBranchStack(t, repo)

	_, err := svc.DelegateTask(ctx, sessionsvc.DelegateTaskInput{
		ProjectID:     "br",
		Brief:         "work on it",
		WorkspaceMode: domain.WorkspaceModeInPlace,
		Branch:        "logic/home",
	})
	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) || apiErr.Code != "BRANCH_NOT_CHECKED_OUT" {
		t.Fatalf("want BRANCH_NOT_CHECKED_OUT, got %v", err)
	}
	rows, err := store.ListSessions(ctx, "br")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 0 {
		t.Fatalf("want the seed row rolled back, got %d rows", len(rows))
	}
}

func TestDelegateInPlaceAcceptsTheCheckedOutBranch(t *testing.T) {
	ctx := context.Background()
	repo := gitRepo(t)
	svc, _ := newInPlaceBranchStack(t, repo)

	out, err := svc.DelegateTask(ctx, sessionsvc.DelegateTaskInput{
		ProjectID:     "br",
		Brief:         "work on it",
		WorkspaceMode: domain.WorkspaceModeInPlace,
		Branch:        "main",
	})
	if err != nil {
		t.Fatal(err)
	}
	got, err := svc.Get(ctx, out.WorkerID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Metadata.Branch != "main" || got.Metadata.WorkspaceMode != domain.WorkspaceModeInPlace {
		t.Fatalf("want an in-place session on main, got branch=%q mode=%q", got.Metadata.Branch, got.Metadata.WorkspaceMode)
	}
}
