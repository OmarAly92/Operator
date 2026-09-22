package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestClaudeAccountsMigrationSeedsDefault(t *testing.T) {
	s := newTestStore(t)
	accounts, err := s.ListClaudeAccounts(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(accounts) != 1 {
		t.Fatalf("accounts = %+v, want only default", accounts)
	}
	got := accounts[0]
	if got.ID != domain.DefaultClaudeAccountID || !got.IsDefault || got.ConfigDir != "" || got.Label != "Default" {
		t.Fatalf("default = %+v", got)
	}
}

func TestClaudeAccountsInsertRenameGet(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	created := domain.ClaudeAccount{ID: "personal", Label: "Personal", ConfigDir: "/Users/u/.claude-personal", CreatedAt: time.Now().UTC()}
	if err := s.InsertClaudeAccount(ctx, created); err != nil {
		t.Fatal(err)
	}
	if err := s.RenameClaudeAccount(ctx, "personal", "Home"); err != nil {
		t.Fatal(err)
	}
	got, err := s.GetClaudeAccount(ctx, "personal")
	if err != nil {
		t.Fatal(err)
	}
	if got.Label != "Home" || got.ConfigDir != "/Users/u/.claude-personal" || got.IsDefault {
		t.Fatalf("got %+v", got)
	}
	accounts, err := s.ListClaudeAccounts(ctx)
	if err != nil || len(accounts) != 2 || accounts[0].ID != domain.DefaultClaudeAccountID {
		t.Fatalf("list = %+v err=%v, want default first", accounts, err)
	}
	if _, err := s.GetClaudeAccount(ctx, "missing"); !errors.Is(err, domain.ErrClaudeAccountNotFound) {
		t.Fatalf("missing err = %v", err)
	}
}

func TestPreferredClaudeAccount(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	got, err := s.PreferredClaudeAccount(ctx)
	if err != nil || got.ID != domain.DefaultClaudeAccountID {
		t.Fatalf("unset preferred = %+v err=%v, want default", got, err)
	}
	for _, id := range []domain.ClaudeAccountID{"personal", "work"} {
		if err := s.InsertClaudeAccount(ctx, domain.ClaudeAccount{ID: id, Label: string(id), ConfigDir: "/Users/u/.claude-" + string(id), CreatedAt: time.Now().UTC()}); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.SetPreferredClaudeAccount(ctx, "personal"); err != nil {
		t.Fatal(err)
	}
	if err := s.SetPreferredClaudeAccount(ctx, "work"); err != nil {
		t.Fatal(err)
	}
	accounts, err := s.ListClaudeAccounts(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, a := range accounts {
		if a.IsPreferred != (a.ID == "work") {
			t.Fatalf("preferred flag on %s = %v", a.ID, a.IsPreferred)
		}
	}
	if err := s.SetPreferredClaudeAccount(ctx, "missing"); !errors.Is(err, domain.ErrClaudeAccountNotFound) {
		t.Fatalf("missing err = %v", err)
	}
	if got, err := s.PreferredClaudeAccount(ctx); err != nil || got.ID != "work" {
		t.Fatalf("preferred after failed set = %+v err=%v", got, err)
	}
	if err := s.DeleteClaudeAccount(ctx, "work"); err != nil {
		t.Fatal(err)
	}
	if got, err := s.PreferredClaudeAccount(ctx); err != nil || got.ID != domain.DefaultClaudeAccountID {
		t.Fatalf("preferred after delete = %+v err=%v, want default", got, err)
	}
}

func TestClaudeAccountsInsertRejectsEmptyFolder(t *testing.T) {
	s := newTestStore(t)
	err := s.InsertClaudeAccount(context.Background(), domain.ClaudeAccount{ID: "x", Label: "X", CreatedAt: time.Now().UTC()})
	if !errors.Is(err, domain.ErrClaudeAccountFolderUnavailable) {
		t.Fatalf("err = %v", err)
	}
}

func TestDeleteClaudeAccountRules(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "proj-1")
	now := time.Now().UTC()
	for _, a := range []domain.ClaudeAccount{
		{ID: "personal", Label: "Personal", ConfigDir: "/Users/u/.claude-personal", CreatedAt: now},
		{ID: "spare", Label: "Spare", ConfigDir: "/Users/u/.claude-spare", CreatedAt: now},
	} {
		if err := s.InsertClaudeAccount(ctx, a); err != nil {
			t.Fatal(err)
		}
	}
	rec := minimalSessionRecord("proj-1", now)
	rec.ClaudeAccountID = "personal"
	created, err := s.CreateSession(ctx, rec)
	if err != nil {
		t.Fatal(err)
	}
	stored, ok, err := s.GetSession(ctx, created.ID)
	if err != nil || !ok || stored.ClaudeAccountID != "personal" {
		t.Fatalf("stored account = %q ok=%v err=%v", stored.ClaudeAccountID, ok, err)
	}
	if err := s.DeleteClaudeAccount(ctx, domain.DefaultClaudeAccountID); !errors.Is(err, domain.ErrClaudeAccountDefaultImmutable) {
		t.Fatalf("delete default err = %v", err)
	}
	if err := s.DeleteClaudeAccount(ctx, "personal"); !errors.Is(err, domain.ErrClaudeAccountInUse) {
		t.Fatalf("delete in-use err = %v", err)
	}
	if err := s.DeleteClaudeAccount(ctx, "missing"); !errors.Is(err, domain.ErrClaudeAccountNotFound) {
		t.Fatalf("delete missing err = %v", err)
	}
	if err := s.DeleteClaudeAccount(ctx, "spare"); err != nil {
		t.Fatalf("delete spare err = %v", err)
	}
}

func TestSessionWithoutAccountDefaults(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "proj-1")
	created, err := s.CreateSession(ctx, minimalSessionRecord("proj-1", time.Now().UTC()))
	if err != nil {
		t.Fatal(err)
	}
	stored, _, err := s.GetSession(ctx, created.ID)
	if err != nil || stored.ClaudeAccountID != domain.DefaultClaudeAccountID {
		t.Fatalf("account = %q err=%v", stored.ClaudeAccountID, err)
	}
}
