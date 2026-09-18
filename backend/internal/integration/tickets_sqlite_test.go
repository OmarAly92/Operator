package integration

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	sessionsvc "github.com/OmarAly92/operator/backend/internal/service/session"
	ticketsvc "github.com/OmarAly92/operator/backend/internal/service/ticket"
)

func gitRepo(t *testing.T) string {
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

func TestTicketCreatePlanAssignRoundTrip(t *testing.T) {
	ctx := context.Background()
	st := newStack(t)
	repo := gitRepo(t)
	if err := st.store.UpsertProject(ctx, domain.ProjectRecord{
		ID: "tk", Path: repo, Kind: domain.ProjectKindSingleRepo, RegisteredAt: time.Now(),
		Config: domain.ProjectConfig{DefaultBranch: "main", Worker: domain.RoleOverride{Harness: domain.HarnessClaudeCode}},
	}); err != nil {
		t.Fatal(err)
	}
	svc := ticketsvc.New(ticketsvc.Deps{Store: st.store, Sessions: st.sm})

	created, err := svc.Create(ctx, "tk", ticketsvc.CreateInput{Title: "Editor", Brief: "Add an editor"})
	if err != nil {
		t.Fatal(err)
	}
	if created.Ticket.Slug != "editor" || created.Ticket.Status != domain.TicketStatusDraft || len(created.Warnings) != 0 {
		t.Fatalf("created = %+v", created)
	}

	planning, err := svc.Plan(ctx, "tk", "editor", ticketsvc.SpawnInput{Harness: domain.HarnessClaudeCode})
	if err != nil {
		t.Fatal(err)
	}
	got, err := st.sm.Get(ctx, planning.ID)
	if err != nil || got.Ticket == nil || got.Ticket.Role != domain.TicketRolePlanning || got.Ticket.Slug != "editor" {
		t.Fatalf("planning session = %+v err=%v", got.Ticket, err)
	}
	if got.Metadata.WorkspaceMode != domain.WorkspaceModeInPlace {
		t.Fatalf("planning workspace mode = %q", got.Metadata.WorkspaceMode)
	}
	if !strings.Contains(got.Metadata.Prompt, ".operator/tickets/editor/") {
		t.Fatalf("planning prompt = %q", got.Metadata.Prompt)
	}
	tk, err := svc.Get(ctx, "tk", "editor")
	if err != nil || tk.Status != domain.TicketStatusPlanning {
		t.Fatalf("ticket = %+v err=%v", tk, err)
	}
	if _, err := st.sm.Kill(ctx, planning.ID); err != nil {
		t.Fatal(err)
	}

	planDir := filepath.Join(repo, ".operator", "tickets", "editor", "plans")
	if err := os.MkdirAll(planDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(planDir, "01-daemon.md"), []byte("---\ntitle: Daemon\n---\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("git", "-C", repo, "add", "-A")
	cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@x", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@x")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git add: %v %s", err, out)
	}
	cmd = exec.Command("git", "-C", repo, "commit", "-q", "-m", "plan")
	cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@x", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@x")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git commit: %v %s", err, out)
	}

	tk, _ = svc.Get(ctx, "tk", "editor")
	if tk.Status != domain.TicketStatusReady || len(tk.Plans) != 1 || tk.Plans[0].Status != domain.PlanStatusTodo {
		t.Fatalf("ticket after plan file = %+v", tk)
	}

	dry, err := svc.Assign(ctx, "tk", "editor", "01-daemon.md", ticketsvc.AssignInput{DryRun: true})
	if err != nil || len(dry.Warnings) != 0 || dry.Session != nil {
		t.Fatalf("dry = %+v err=%v", dry, err)
	}
	res, err := svc.Assign(ctx, "tk", "editor", "01-daemon.md", ticketsvc.AssignInput{SpawnInput: ticketsvc.SpawnInput{Harness: domain.HarnessClaudeCode, Extra: "Use TDD."}})
	if err != nil || res.Session == nil {
		t.Fatalf("assign = %+v err=%v", res, err)
	}
	impl, err := st.sm.Get(ctx, res.Session.ID)
	if err != nil {
		t.Fatal(err)
	}
	if impl.Metadata.Branch != "opr/editor-01" || impl.Metadata.WorkspaceMode != domain.WorkspaceModeWorktree {
		t.Fatalf("impl metadata = %+v", impl.Metadata)
	}
	if impl.Ticket == nil || impl.Ticket.Role != domain.TicketRoleImplementing || impl.Ticket.PlanFile != "plans/01-daemon.md" {
		t.Fatalf("impl ticket = %+v", impl.Ticket)
	}
	if !strings.Contains(impl.Metadata.Prompt, "plans/01-daemon.md") || !strings.Contains(impl.Metadata.Prompt, "Use TDD.") {
		t.Fatalf("impl prompt = %q", impl.Metadata.Prompt)
	}
	list, err := st.sm.List(ctx, sessionsvc.ListFilter{ProjectID: "tk"})
	if err != nil || len(list) != 2 {
		t.Fatalf("list = %+v err=%v", list, err)
	}
	tk, _ = svc.Get(ctx, "tk", "editor")
	if tk.Status != domain.TicketStatusInProgress || tk.Plans[0].Status != domain.PlanStatusIdle || tk.Plans[0].SessionID != res.Session.ID {
		t.Fatalf("ticket in progress = %+v", tk)
	}

	if _, err := st.sm.Kill(ctx, res.Session.ID); err != nil {
		t.Fatal(err)
	}
	tk, _ = svc.Get(ctx, "tk", "editor")
	if tk.Plans[0].Status != domain.PlanStatusTerminated || tk.Status != domain.TicketStatusReady {
		t.Fatalf("ticket after kill = %+v", tk)
	}

	res2, err := svc.Assign(ctx, "tk", "editor", "01-daemon.md", ticketsvc.AssignInput{Force: true, SpawnInput: ticketsvc.SpawnInput{Harness: domain.HarnessClaudeCode}})
	if err != nil || res2.Session == nil {
		t.Fatalf("second assign = %+v err=%v", res2, err)
	}
	review, err := svc.Review(ctx, "tk", "editor", "01-daemon.md", ticketsvc.ReviewInput{SpawnInput: ticketsvc.SpawnInput{Harness: domain.HarnessClaudeCode}})
	if err != nil || !review.Spawned {
		t.Fatalf("review = %+v err=%v", review, err)
	}
	reviewer, err := st.sm.Get(ctx, review.Session.ID)
	if err != nil || reviewer.Ticket == nil || reviewer.Ticket.Role != domain.TicketRolePlanning || reviewer.Metadata.WorkspaceMode != domain.WorkspaceModeInPlace {
		t.Fatalf("reviewer = %+v err=%v", reviewer.Ticket, err)
	}
	tk, _ = svc.Get(ctx, "tk", "editor")
	if tk.Plans[0].Status != domain.PlanStatusReviewing || tk.Plans[0].ReviewerID != review.Session.ID {
		t.Fatalf("reviewing = %+v", tk.Plans[0])
	}
	tk, err = svc.MergeReady(ctx, "tk", "editor", "01-daemon.md", "verified")
	if err != nil || tk.Plans[0].Status != domain.PlanStatusAwaitMerge || tk.Status != domain.TicketStatusAwaitMerge {
		t.Fatalf("merge ready = %+v err=%v", tk, err)
	}
	tk, err = svc.ApproveMerge(ctx, "tk", "editor", "01-daemon.md")
	if err != nil || tk.Plans[0].Status != domain.PlanStatusReviewing {
		t.Fatalf("approve = %+v err=%v", tk, err)
	}
	fresh, err := svc.Review(ctx, "tk", "editor", "01-daemon.md", ticketsvc.ReviewInput{Reviewer: ticketsvc.ReviewerNew, SpawnInput: ticketsvc.SpawnInput{Harness: domain.HarnessClaudeCode}})
	if err != nil || !fresh.Spawned || fresh.Session.ID == review.Session.ID {
		t.Fatalf("fresh review = %+v err=%v", fresh, err)
	}
	if got, _ := st.sm.Get(ctx, fresh.Session.ID); got.Ticket == nil || got.Ticket.Role != domain.TicketRoleReviewing {
		t.Fatalf("fresh reviewer ref = %+v", got.Ticket)
	}
	if _, err := st.sm.Kill(ctx, res2.Session.ID); err != nil {
		t.Fatal(err)
	}

	tk, err = svc.MarkDone(ctx, "tk", "editor", "01-daemon.md")
	if err != nil || tk.Status != domain.TicketStatusDone {
		t.Fatalf("done = %+v err=%v", tk, err)
	}
	head, _ := st.store.LatestSeq(ctx)
	events, err := st.store.EventsAfter(ctx, 0, int(head)+1)
	if err != nil {
		t.Fatal(err)
	}
	ticketEvents := 0
	for _, e := range events {
		if string(e.Type) == "ticket_updated" {
			ticketEvents++
		}
	}
	if ticketEvents < 8 {
		t.Fatalf("want ticket_updated for create, plan link, assigns, review, merge-ready, approve and done; got %d in %+v", ticketEvents, events)
	}
}
