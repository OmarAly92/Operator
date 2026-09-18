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
