package ticket

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/ports"
	sessionsvc "github.com/OmarAly92/operator/backend/internal/service/session"
)

type fakeStore struct {
	projects    map[string]domain.ProjectRecord
	tickets     map[string]domain.TicketRecord
	assignments []domain.PlanAssignmentRecord
	nextID      int64
}

func newFakeStore(p domain.ProjectRecord) *fakeStore {
	return &fakeStore{projects: map[string]domain.ProjectRecord{string(p.ID): p}, tickets: map[string]domain.TicketRecord{}}
}

func key(p domain.ProjectID, slug string) string { return string(p) + "/" + slug }

func (f *fakeStore) GetProject(_ context.Context, id string) (domain.ProjectRecord, bool, error) {
	p, ok := f.projects[id]
	return p, ok, nil
}
func (f *fakeStore) ListTickets(_ context.Context, p domain.ProjectID) ([]domain.TicketRecord, error) {
	var out []domain.TicketRecord
	for _, t := range f.tickets {
		if t.ProjectID == p {
			out = append(out, t)
		}
	}
	return out, nil
}
func (f *fakeStore) GetTicket(_ context.Context, p domain.ProjectID, slug string) (domain.TicketRecord, bool, error) {
	t, ok := f.tickets[key(p, slug)]
	return t, ok, nil
}
func (f *fakeStore) InsertTicket(_ context.Context, rec domain.TicketRecord) error {
	if _, dup := f.tickets[key(rec.ProjectID, rec.Slug)]; dup {
		return errors.New("duplicate")
	}
	f.tickets[key(rec.ProjectID, rec.Slug)] = rec
	return nil
}
func (f *fakeStore) SetTicketPlanningSession(_ context.Context, p domain.ProjectID, slug string, s domain.SessionID) error {
	t, ok := f.tickets[key(p, slug)]
	if !ok {
		return errors.New("missing")
	}
	t.PlanningSessionID = s
	f.tickets[key(p, slug)] = t
	return nil
}
func (f *fakeStore) SetTicketArchivedAt(_ context.Context, p domain.ProjectID, slug string, at time.Time) error {
	t, ok := f.tickets[key(p, slug)]
	if !ok {
		return errors.New("missing")
	}
	t.ArchivedAt = at
	f.tickets[key(p, slug)] = t
	return nil
}
func (f *fakeStore) ListPlanAssignments(_ context.Context, p domain.ProjectID, slug string) ([]domain.PlanAssignmentRecord, error) {
	var out []domain.PlanAssignmentRecord
	for i := len(f.assignments) - 1; i >= 0; i-- {
		a := f.assignments[i]
		if a.ProjectID == p && a.Slug == slug {
			out = append(out, a)
		}
	}
	return out, nil
}
func (f *fakeStore) InsertPlanAssignment(_ context.Context, rec domain.PlanAssignmentRecord) error {
	f.nextID++
	rec.ID = f.nextID
	f.assignments = append(f.assignments, rec)
	return nil
}

type fakeSessions struct {
	sessions []domain.Session
	spawned  []ports.SpawnConfig
	sent     []sentMessage
	spawnErr error
	nextNum  int
}

func (f *fakeSessions) List(_ context.Context, filter sessionsvc.ListFilter) ([]domain.Session, error) {
	var out []domain.Session
	for _, s := range f.sessions {
		if filter.ProjectID == "" || s.ProjectID == filter.ProjectID {
			out = append(out, s)
		}
	}
	return out, nil
}
func (f *fakeSessions) Spawn(_ context.Context, cfg ports.SpawnConfig) (domain.Session, int, int, error) {
	if f.spawnErr != nil {
		return domain.Session{}, 0, 0, f.spawnErr
	}
	f.spawned = append(f.spawned, cfg)
	f.nextNum++
	s := domain.Session{SessionRecord: domain.SessionRecord{ID: domain.SessionID("tk-" + strings.Repeat("x", f.nextNum)), ProjectID: cfg.ProjectID}, Status: domain.StatusIdle}
	f.sessions = append(f.sessions, s)
	return s, 0, 0, nil
}
func (f *fakeSessions) Get(_ context.Context, id domain.SessionID) (domain.Session, error) {
	for _, s := range f.sessions {
		if s.ID == id {
			return s, nil
		}
	}
	return domain.Session{}, apierr.NotFound("SESSION_NOT_FOUND", "no session")
}

type sentMessage struct {
	id  domain.SessionID
	msg string
}

func (f *fakeSessions) Send(_ context.Context, id domain.SessionID, msg string, _ *ports.SpawnAttachment) error {
	f.sent = append(f.sent, sentMessage{id: id, msg: msg})
	return nil
}
func (f *fakeSessions) set(id domain.SessionID, status domain.SessionStatus) {
	for i := range f.sessions {
		if f.sessions[i].ID == id {
			f.sessions[i].Status = status
		}
	}
}

type harness struct {
	svc      *Service
	store    *fakeStore
	sessions *fakeSessions
	repo     string
	root     string
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	repo := initRepo(t)
	p := domain.ProjectRecord{ID: "tk", Path: repo, Kind: domain.ProjectKindSingleRepo, Config: domain.ProjectConfig{DefaultBranch: "main"}}
	st := newFakeStore(p)
	ss := &fakeSessions{}
	now := time.Date(2026, 9, 18, 12, 0, 0, 0, time.UTC)
	svc := New(Deps{Store: st, Sessions: ss, Now: func() time.Time { return now }})
	return &harness{svc: svc, store: st, sessions: ss, repo: repo, root: filepath.Join(repo, ".operator", "tickets")}
}

func (h *harness) ticketFile(slug, rel, content string) {
	writeFile(nil, filepath.Join(h.root, slug, filepath.FromSlash(rel)), content)
}

func codeOf(err error) string {
	var e *apierr.Error
	if errors.As(err, &e) {
		return e.Code
	}
	return ""
}

func TestListMergesFoldersAndRecords(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\nbrief: b\n---\n")
	h.ticketFile("editor", "plans/01-core.md", "---\ntitle: Core\n---\n")
	h.ticketFile("hand", "ticket.md", "# Hand written\n")
	_ = h.store.InsertTicket(ctx, domain.TicketRecord{ProjectID: "tk", Slug: "editor", CreatedAt: time.Now()})
	_ = h.store.InsertTicket(ctx, domain.TicketRecord{ProjectID: "tk", Slug: "deleted-folder", CreatedAt: time.Now()})

	got, err := h.svc.List(ctx, "tk")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].Slug != "editor" || got[1].Slug != "hand" {
		t.Fatalf("got %+v", got)
	}
	if got[0].Status != domain.TicketStatusReady || len(got[0].Plans) != 1 || got[0].Plans[0].Status != domain.PlanStatusTodo {
		t.Fatalf("editor = %+v", got[0])
	}
	if got[1].Status != domain.TicketStatusDraft || got[1].Title != "Hand written" {
		t.Fatalf("hand = %+v", got[1])
	}
}

func TestGetErrors(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	if _, err := h.svc.Get(ctx, "tk", "nope"); codeOf(err) != "TICKET_NOT_FOUND" {
		t.Fatalf("err = %v", err)
	}
	if _, err := h.svc.Get(ctx, "other", "nope"); codeOf(err) != "PROJECT_NOT_FOUND" {
		t.Fatalf("err = %v", err)
	}
	h.store.projects["ws"] = domain.ProjectRecord{ID: "ws", Path: h.repo, Kind: domain.ProjectKindWorkspace}
	if _, err := h.svc.List(ctx, "ws"); codeOf(err) != "TICKET_UNSUPPORTED_PROJECT" {
		t.Fatalf("err = %v", err)
	}
}

func TestReadWriteFileAndTraversal(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "spec.md", "# Spec\n")
	f, err := h.svc.ReadFile(ctx, "tk", "editor", "spec.md")
	if err != nil || f.Content != "# Spec\n" || f.ModifiedAt.IsZero() || f.Path != "spec.md" {
		t.Fatalf("f=%+v err=%v", f, err)
	}
	for _, bad := range []string{"", "../ticket.md", "../../README.md", "/etc/passwd", "plans/../../x.md", "spec.txt", "plans/sub/x.md"} {
		if _, err := h.svc.ReadFile(ctx, "tk", "editor", bad); codeOf(err) != "TICKET_PATH_OUTSIDE" {
			t.Errorf("%q: err = %v", bad, err)
		}
	}
	if _, err := h.svc.ReadFile(ctx, "tk", "editor", "plans/09-missing.md"); codeOf(err) != "TICKET_FILE_NOT_FOUND" {
		t.Fatalf("err = %v", err)
	}
	if err := os.Symlink(filepath.Join(h.repo, "README.md"), filepath.Join(h.root, "editor", "link.md")); err == nil {
		if _, err := h.svc.ReadFile(ctx, "tk", "editor", "link.md"); codeOf(err) != "TICKET_PATH_OUTSIDE" {
			t.Fatalf("symlink escape err = %v", err)
		}
	}
	h.ticketFile("boundary", "ticket.md", "---\ntitle: Boundary\n---\n")
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(h.root, "boundary", "plans")); err == nil {
		if _, err := h.svc.WriteFile(ctx, "tk", "boundary", "plans/new-file.md", "leak\n", time.Time{}); codeOf(err) != "TICKET_PATH_OUTSIDE" {
			t.Fatalf("symlinked plans dir escape err = %v", err)
		}
		if _, err := os.Stat(filepath.Join(outside, "new-file.md")); err == nil {
			t.Fatal("write escaped the ticket folder via symlinked plans dir")
		}
	}
	h.ticketFile("leafsym", "ticket.md", "---\ntitle: Leaf Symlink\n---\n")
	leafOutside := filepath.Join(t.TempDir(), "outside.md")
	if err := os.MkdirAll(filepath.Join(h.root, "leafsym", "plans"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(leafOutside, filepath.Join(h.root, "leafsym", "plans", "leak.md")); err == nil {
		if _, err := h.svc.WriteFile(ctx, "tk", "leafsym", "plans/leak.md", "pwned", time.Time{}); codeOf(err) != "TICKET_PATH_OUTSIDE" {
			t.Fatalf("dangling leaf symlink escape err = %v", err)
		}
		if _, err := os.Lstat(leafOutside); err == nil {
			t.Fatal("write created the file at the dangling symlink's external target")
		}
		if _, err := h.svc.WriteFile(ctx, "tk", "leafsym", "plans/ok.md", "fine\n", time.Time{}); err != nil {
			t.Fatalf("normal new-file write regressed: %v", err)
		}
	}
	w, err := h.svc.WriteFile(ctx, "tk", "editor", "plans/02-ui.md", "---\ntitle: UI\n---\n", time.Time{})
	if err != nil || w.ModifiedAt.IsZero() {
		t.Fatalf("w=%+v err=%v", w, err)
	}
	if got, _ := os.ReadFile(filepath.Join(h.root, "editor", "plans", "02-ui.md")); string(got) != "---\ntitle: UI\n---\n" {
		t.Fatalf("written = %q", got)
	}
	tk, _ := h.svc.Get(ctx, "tk", "editor")
	if len(tk.Plans) != 1 || tk.Plans[0].File != "plans/02-ui.md" {
		t.Fatalf("plans = %+v", tk.Plans)
	}
}

func TestWriteFileStale(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "spec.md", "v1\n")
	f, _ := h.svc.ReadFile(ctx, "tk", "editor", "spec.md")
	stale := f.ModifiedAt.Add(-2 * time.Second)
	_, err := h.svc.WriteFile(ctx, "tk", "editor", "spec.md", "v2\n", stale)
	if codeOf(err) != "TICKET_FILE_STALE" {
		t.Fatalf("err = %v", err)
	}
	if _, err := h.svc.WriteFile(ctx, "tk", "editor", "spec.md", "v2\n", f.ModifiedAt); err != nil {
		t.Fatalf("fresh write: %v", err)
	}
	if _, err := h.svc.WriteFile(ctx, "tk", "editor", "spec.md", "v3\n", time.Time{}); err != nil {
		t.Fatalf("unconditional write: %v", err)
	}
}

func TestCreateWritesFolderRecordAndCommit(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	res, err := h.svc.Create(ctx, "tk", CreateInput{Title: "Markdown Editor", Brief: "Edit docs in app"})
	if err != nil {
		t.Fatal(err)
	}
	if res.Ticket.Slug != "markdown-editor" || res.Ticket.Status != domain.TicketStatusDraft || len(res.Warnings) != 0 {
		t.Fatalf("res = %+v", res)
	}
	raw, err := os.ReadFile(filepath.Join(h.root, "markdown-editor", "ticket.md"))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"---\n", "title: Markdown Editor\n", "brief: Edit docs in app\n", "created: 2026-09-18\n"} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("ticket.md missing %q:\n%s", want, raw)
		}
	}
	if spec, _ := os.ReadFile(filepath.Join(h.root, "markdown-editor", "spec.md")); string(spec) != "# Markdown Editor\n" {
		t.Fatalf("spec = %q", spec)
	}
	if _, ok := h.store.tickets[key("tk", "markdown-editor")]; !ok {
		t.Fatal("record not inserted")
	}
	if dirty, _ := gitPathDirty(ctx, h.repo, ".operator/tickets/markdown-editor"); dirty {
		t.Fatal("create must commit the folder")
	}
	res2, err := h.svc.Create(ctx, "tk", CreateInput{Title: "Markdown Editor"})
	if err != nil || res2.Ticket.Slug != "markdown-editor-2" {
		t.Fatalf("collision: %+v %v", res2, err)
	}
	if _, err := h.svc.Create(ctx, "tk", CreateInput{Title: "   "}); codeOf(err) != "TICKET_TITLE_REQUIRED" {
		t.Fatalf("err = %v", err)
	}
	if _, err := gitOutput(ctx, h.repo, "checkout", "-q", "-b", "feature"); err != nil {
		t.Fatal(err)
	}
	res3, err := h.svc.Create(ctx, "tk", CreateInput{Title: "On feature"})
	if err != nil || len(res3.Warnings) != 1 || res3.Warnings[0] != "not_on_default_branch" {
		t.Fatalf("res3 = %+v err=%v", res3, err)
	}
}

func TestPlanSpawnsInPlaceAndRefusesWhileActive(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Markdown Editor For Everyone\nbrief: b\n---\n")
	sess, err := h.svc.Plan(ctx, "tk", "editor", SpawnInput{Harness: domain.HarnessClaudeCode, ClaudeAccountID: "personal", Extra: "Be brief."})
	if err != nil {
		t.Fatal(err)
	}
	if len(h.sessions.spawned) != 1 {
		t.Fatalf("spawned = %+v", h.sessions.spawned)
	}
	cfg := h.sessions.spawned[0]
	if cfg.ProjectID != "tk" || cfg.Kind != domain.KindWorker || cfg.WorkspaceMode != domain.WorkspaceModeInPlace || cfg.Branch != "" ||
		cfg.Harness != domain.HarnessClaudeCode || cfg.ClaudeAccountID != "personal" || cfg.DisplayName != "Markdown Editor For" {
		t.Fatalf("cfg = %+v", cfg)
	}
	if !strings.Contains(cfg.Prompt, "Be brief.") || !strings.Contains(cfg.Prompt, "ticket `editor`") {
		t.Fatalf("prompt = %q", cfg.Prompt)
	}
	rec := h.store.tickets[key("tk", "editor")]
	if rec.PlanningSessionID != sess.ID {
		t.Fatalf("record = %+v", rec)
	}
	tk, _ := h.svc.Get(ctx, "tk", "editor")
	if tk.Status != domain.TicketStatusPlanning {
		t.Fatalf("status = %s", tk.Status)
	}
	if _, err := h.svc.Plan(ctx, "tk", "editor", SpawnInput{}); codeOf(err) != "TICKET_PLANNING_ACTIVE" {
		t.Fatalf("err = %v", err)
	}
	h.sessions.set(sess.ID, domain.StatusTerminated)
	if _, err := h.svc.Plan(ctx, "tk", "editor", SpawnInput{}); err != nil {
		t.Fatalf("replan after termination: %v", err)
	}
	if len(h.sessions.spawned) != 2 || !strings.Contains(h.sessions.spawned[1].Prompt, "Brainstorm") {
		t.Fatalf("second spawn = %+v", h.sessions.spawned)
	}
}

func TestAssignWarningsDryRunForceAndBranch(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "spec.md", "# s\n")
	h.ticketFile("editor", "plans/01-daemon.md", "---\ntitle: Daemon\n---\n")
	h.ticketFile("editor", "plans/02-ui.md", "---\ntitle: UI\n---\n")
	if err := gitCommitPath(ctx, h.repo, ".operator/tickets/editor", "ticket: add editor"); err != nil {
		t.Fatal(err)
	}

	res, err := h.svc.Assign(ctx, "tk", "editor", "02-ui.md", AssignInput{DryRun: true})
	if err != nil || res.Session != nil {
		t.Fatalf("dry run: %+v %v", res, err)
	}
	if len(res.Warnings) != 1 || res.Warnings[0] != "plan_order" {
		t.Fatalf("warnings = %v", res.Warnings)
	}
	if _, err := h.svc.Assign(ctx, "tk", "editor", "02-ui.md", AssignInput{}); codeOf(err) != "TICKET_ASSIGN_BLOCKED" {
		t.Fatalf("blocked err = %v", err)
	}
	if len(h.sessions.spawned) != 0 {
		t.Fatal("blocked assign must not spawn")
	}

	res, err = h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{SpawnInput: SpawnInput{Harness: domain.HarnessCodex, Model: "gpt-5-mini", Extra: "Use TDD."}})
	if err != nil || res.Session == nil || len(res.Warnings) != 0 {
		t.Fatalf("assign: %+v %v", res, err)
	}
	cfg := h.sessions.spawned[0]
	if cfg.WorkspaceMode != domain.WorkspaceModeWorktree || cfg.Branch != "opr/editor-01" || cfg.Harness != domain.HarnessCodex || cfg.AgentConfig.Model != "gpt-5-mini" ||
		cfg.DisplayName != "editor · 01" || !strings.Contains(cfg.Prompt, "plans/01-daemon.md") || !strings.Contains(cfg.Prompt, "Use TDD.") {
		t.Fatalf("cfg = %+v", cfg)
	}
	tk, _ := h.svc.Get(ctx, "tk", "editor")
	if tk.Status != domain.TicketStatusInProgress || tk.Plans[0].Status != domain.PlanStatusIdle || tk.Plans[0].SessionID != res.Session.ID {
		t.Fatalf("ticket = %+v", tk)
	}

	res, err = h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{DryRun: true})
	if err != nil || len(res.Warnings) != 1 || res.Warnings[0] != "plan_assigned" {
		t.Fatalf("reassign dry run = %+v %v", res, err)
	}
	h.sessions.set(res.Session.ID, domain.StatusTerminated)
	res, err = h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{})
	if err != nil || h.sessions.spawned[1].Branch != "opr/editor-01-2" {
		t.Fatalf("second attempt = %+v err=%v", h.sessions.spawned, err)
	}

	h.sessions.set(res.Session.ID, domain.StatusMerged)
	h.ticketFile("editor", "spec.md", "# edited\n")
	res, err = h.svc.Assign(ctx, "tk", "editor", "02-ui.md", AssignInput{DryRun: true})
	if err != nil || len(res.Warnings) != 1 || res.Warnings[0] != "ticket_repo_dirty" {
		t.Fatalf("dirty warnings = %v err=%v", res.Warnings, err)
	}
	res, err = h.svc.Assign(ctx, "tk", "editor", "02-ui.md", AssignInput{Force: true})
	if err != nil || res.Session == nil || len(res.Warnings) != 1 {
		t.Fatalf("forced = %+v err=%v", res, err)
	}
	if !strings.Contains(h.sessions.spawned[2].Prompt, "plans/01-daemon.md (merged)") {
		t.Fatalf("prompt = %q", h.sessions.spawned[2].Prompt)
	}
	if _, err := h.svc.Assign(ctx, "tk", "editor", "99-nope.md", AssignInput{}); codeOf(err) != "TICKET_PLAN_NOT_FOUND" {
		t.Fatalf("err = %v", err)
	}
}

func TestAssignUsesKickoffFileAndProjectDefaults(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	p := h.store.projects["tk"]
	p.Config.Tickets = domain.TicketDefaults{
		Planner:     domain.TicketRoleDefaults{Harness: domain.HarnessClaudeCode, Model: "opus", ClaudeAccountID: "personal"},
		Implementer: domain.TicketRoleDefaults{Harness: domain.HarnessClaudeCode, Model: "sonnet"},
	}
	h.store.projects["tk"] = p
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "plans/01-daemon.md", "---\ntitle: Daemon\n---\n")
	h.ticketFile("editor", "plans/01-daemon.kickoff.md", "Execute plan 01 with subagents.\n")
	_ = gitCommitPath(ctx, h.repo, ".operator/tickets/editor", "ticket: add editor")
	if _, err := h.svc.Plan(ctx, "tk", "editor", SpawnInput{}); err != nil {
		t.Fatal(err)
	}
	planner := h.sessions.spawned[0]
	if planner.AgentConfig.Model != "opus" || planner.ClaudeAccountID != "personal" || planner.Harness != domain.HarnessClaudeCode {
		t.Fatalf("planner cfg = %+v", planner)
	}
	if !strings.Contains(planner.Prompt, "kickoff.md") {
		t.Fatalf("planning prompt must ask for kickoff files:\n%s", planner.Prompt)
	}
	res, err := h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{Force: true})
	if err != nil || res.Session == nil {
		t.Fatalf("assign = %+v err=%v", res, err)
	}
	impl := h.sessions.spawned[1]
	if impl.AgentConfig.Model != "sonnet" || impl.ClaudeAccountID != "" {
		t.Fatalf("implementer cfg = %+v", impl)
	}
	if !strings.Contains(impl.Prompt, "Execute plan 01 with subagents.") || strings.Contains(impl.Prompt, "Implement only this phase") {
		t.Fatalf("kickoff body not used:\n%s", impl.Prompt)
	}
	res, err = h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{Force: true, SpawnInput: SpawnInput{Model: "haiku"}})
	if err != nil || h.sessions.spawned[2].AgentConfig.Model != "haiku" {
		t.Fatalf("override = %+v err=%v", h.sessions.spawned[2], err)
	}
}

func TestAssignSpawnFailureLeavesNoAssignment(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "plans/01-daemon.md", "---\ntitle: Daemon\n---\n")
	_ = gitCommitPath(ctx, h.repo, ".operator/tickets/editor", "ticket: add editor")
	h.sessions.spawnErr = errors.New("boom")
	if _, err := h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{}); err == nil {
		t.Fatal("want spawn error")
	}
	if len(h.store.assignments) != 0 {
		t.Fatalf("assignments = %+v", h.store.assignments)
	}
}

func TestMarkDoneAndArchive(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "plans/01-daemon.md", "---\ntitle: Daemon\n---\n")
	tk, err := h.svc.MarkDone(ctx, "tk", "editor", "01-daemon.md")
	if err != nil || tk.Plans[0].Status != domain.PlanStatusDone || tk.Status != domain.TicketStatusDone {
		t.Fatalf("tk = %+v err=%v", tk, err)
	}
	if _, ok := h.store.tickets[key("tk", "editor")]; !ok {
		t.Fatal("mark done must create the record for a hand-written ticket")
	}
	tk, err = h.svc.SetArchived(ctx, "tk", "editor", true)
	if err != nil || tk.Status != domain.TicketStatusArchived || tk.ArchivedAt.IsZero() {
		t.Fatalf("tk = %+v err=%v", tk, err)
	}
	tk, err = h.svc.SetArchived(ctx, "tk", "editor", false)
	if err != nil || tk.Status != domain.TicketStatusDone {
		t.Fatalf("tk = %+v err=%v", tk, err)
	}
	if _, err := h.svc.MarkDone(ctx, "tk", "editor", "nope.md"); codeOf(err) != "TICKET_PLAN_NOT_FOUND" {
		t.Fatalf("err = %v", err)
	}
}

func TestPlanBranch(t *testing.T) {
	cases := []struct {
		plan    domain.Plan
		attempt int
		want    string
	}{
		{domain.Plan{File: "plans/01-daemon.md", Order: 1}, 1, "opr/editor-01"},
		{domain.Plan{File: "plans/10-ui.md", Order: 10}, 3, "opr/editor-10-3"},
		{domain.Plan{File: "plans/notes.md", Unordered: true}, 1, "opr/editor-notes"},
	}
	for _, tc := range cases {
		if got := planBranch("editor", tc.plan, tc.attempt); got != tc.want {
			t.Errorf("%+v attempt %d = %q want %q", tc.plan, tc.attempt, got, tc.want)
		}
	}
}
