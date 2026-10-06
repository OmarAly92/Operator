package ticket

import (
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestPlanningPromptFresh(t *testing.T) {
	tk := domain.Ticket{Slug: "editor", Title: "Editor", Brief: "Add a markdown editor."}
	got := planningPrompt(tk, "Keep it small.")
	for _, want := range []string{
		"ticket `editor`",
		".operator/tickets/editor/",
		"spec.md",
		"plans/01-<phase>.md",
		"plans/01-<phase>.kickoff.md",
		"title:",
		"Brief: Add a markdown editor.",
		"write `spec.md`",
		"Keep it small.",
		"commit",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
	if strings.Contains(got, "revise") {
		t.Errorf("fresh prompt must not say revise:\n%s", got)
	}
}

func TestPlanningPromptRevise(t *testing.T) {
	tk := domain.Ticket{Slug: "editor", Title: "Editor", Plans: []domain.Plan{{File: "plans/01-core.md", Title: "Core"}}}
	got := planningPrompt(tk, "")
	if !strings.Contains(got, "revise") || !strings.Contains(got, "plans/01-core.md") {
		t.Errorf("revise prompt wrong:\n%s", got)
	}
	if strings.HasSuffix(strings.TrimRight(got, "\n"), "instructions:") {
		t.Errorf("empty extra must not leave a dangling heading:\n%s", got)
	}
}

func TestImplementPrompt(t *testing.T) {
	tk := domain.Ticket{Slug: "editor", Title: "Editor", Brief: "Add it.", Plans: []domain.Plan{
		{File: "plans/01-daemon.md", Title: "Daemon", Status: domain.PlanStatusMerged},
		{File: "plans/02-ui.md", Title: "UI", Status: domain.PlanStatusWorking},
		{File: "plans/03-editor.md", Title: "Editor", Status: domain.PlanStatusTodo},
		{File: "plans/04-mobile.md", Title: "Mobile", Status: domain.PlanStatusTodo},
	}}
	got := implementPrompt(tk, tk.Plans[2], "", "Use TDD.")
	for _, want := range []string{
		"Editor",
		"Brief: Add it.",
		".operator/tickets/editor/spec.md",
		".operator/tickets/editor/plans/03-editor.md",
		"plans/01-daemon.md (merged)",
		"plans/02-ui.md (in progress)",
		"Implement only this phase",
		"pull request",
		"Use TDD.",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
	if strings.Contains(got, "04-mobile") {
		t.Errorf("later plans must not be listed:\n%s", got)
	}
	withKickoff := implementPrompt(tk, tk.Plans[2], "Execute plan 03 with subagents.\n", "Use TDD.")
	if !strings.Contains(withKickoff, "Execute plan 03 with subagents.") || strings.Contains(withKickoff, "Implement only this phase") {
		t.Errorf("kickoff body must replace the default body:\n%s", withKickoff)
	}
	if !strings.Contains(withKickoff, ".operator/tickets/editor/spec.md") || !strings.Contains(withKickoff, "Use TDD.") {
		t.Errorf("header and extra must survive with a kickoff:\n%s", withKickoff)
	}
}

func TestReviewAndMergePrompts(t *testing.T) {
	tk := domain.Ticket{Slug: "editor", Title: "Editor", Plans: []domain.Plan{{File: "plans/01-daemon.md", Title: "Daemon"}}}
	got := reviewPrompt(tk, tk.Plans[0], "opr/editor-01", "/data/worktrees/tk/tk-7", "Be strict.")
	for _, want := range []string{
		".operator/tickets/editor/spec.md",
		".operator/tickets/editor/plans/01-daemon.md",
		"opr/editor-01",
		"/data/worktrees/tk/tk-7",
		"Do not merge",
		"ticket_mark_merge_ready",
		"Be strict.",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
	m := mergeApprovedPrompt(tk, tk.Plans[0], "opr/editor-01", "development")
	if !strings.Contains(m, "Approved") || !strings.Contains(m, "opr/editor-01") || !strings.Contains(m, "development") {
		t.Errorf("merge prompt:\n%s", m)
	}
}
