package usage

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestAllowedRootsUseAccountRootsWhenProvided(t *testing.T) {
	a := filepath.Join(t.TempDir(), "projects")
	b := filepath.Join(t.TempDir(), "projects")
	c := NewCollector(nil, SourceRoots{
		ClaudeProjects:     "/ignored",
		ClaudeProjectRoots: func(context.Context) []string { return []string{a, b} },
	}, nil)
	got := c.allowedRoots(context.Background(), domain.HarnessClaudeCode)
	if len(got) != 2 || got[0] != a || got[1] != b {
		t.Fatalf("roots = %v", got)
	}
	legacy := NewCollector(nil, SourceRoots{ClaudeProjects: a}, nil)
	if got := legacy.allowedRoots(context.Background(), domain.HarnessClaudeCode); len(got) != 1 || got[0] != a {
		t.Fatalf("legacy roots = %v", got)
	}
}

func TestClaudeProjectsRootForSession(t *testing.T) {
	c := NewCollector(nil, SourceRoots{
		ClaudeProjects: "/default/projects",
		ClaudeProjectsFor: func(_ context.Context, id domain.SessionID) (string, error) {
			if id == "proj-9" {
				return "/acct/projects", nil
			}
			return "", domain.ErrClaudeAccountNotFound
		},
	}, nil)
	if got := c.claudeProjectsRoot(context.Background(), "proj-9"); got != "/acct/projects" {
		t.Fatalf("root = %q", got)
	}
	if got := c.claudeProjectsRoot(context.Background(), "proj-x"); got != "" {
		t.Fatalf("unknown session root = %q, want empty", got)
	}
}
