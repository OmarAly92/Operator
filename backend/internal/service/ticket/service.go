package ticket

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/ports"
	sessionsvc "github.com/OmarAly92/operator/backend/internal/service/session"
)

type Store interface {
	GetProject(ctx context.Context, id string) (domain.ProjectRecord, bool, error)
	ListTickets(ctx context.Context, project domain.ProjectID) ([]domain.TicketRecord, error)
	GetTicket(ctx context.Context, project domain.ProjectID, slug string) (domain.TicketRecord, bool, error)
	InsertTicket(ctx context.Context, rec domain.TicketRecord) error
	SetTicketPlanningSession(ctx context.Context, project domain.ProjectID, slug string, session domain.SessionID) error
	SetTicketArchivedAt(ctx context.Context, project domain.ProjectID, slug string, at time.Time) error
	ListPlanAssignments(ctx context.Context, project domain.ProjectID, slug string) ([]domain.PlanAssignmentRecord, error)
	InsertPlanAssignment(ctx context.Context, rec domain.PlanAssignmentRecord) error
}

type Sessions interface {
	List(ctx context.Context, filter sessionsvc.ListFilter) ([]domain.Session, error)
	Get(ctx context.Context, id domain.SessionID) (domain.Session, error)
	Spawn(ctx context.Context, cfg ports.SpawnConfig) (domain.Session, int, int, error)
	Send(ctx context.Context, id domain.SessionID, message string, attachment *ports.SpawnAttachment) error
}

type Deps struct {
	Store    Store
	Sessions Sessions
	Now      func() time.Time
	BaseURL  string
}

type Service struct {
	store    Store
	sessions Sessions
	now      func() time.Time
	baseURL  string
}

func New(d Deps) *Service {
	now := d.Now
	if now == nil {
		now = func() time.Time { return time.Now().UTC() }
	}
	base := strings.TrimRight(d.BaseURL, "/")
	if base == "" {
		base = "http://127.0.0.1:3001"
	}
	return &Service{store: d.Store, sessions: d.Sessions, now: now, baseURL: base}
}

type File struct {
	Path       string
	Content    string
	ModifiedAt time.Time
}

type CreateInput struct {
	Title string
	Brief string
}

type CreateResult struct {
	Ticket   domain.Ticket
	Warnings []string
}

const maxDisplayName = 20

var errPathOutside = apierr.Invalid("TICKET_PATH_OUTSIDE", "Path must be a markdown file inside the ticket folder", nil)

func (s *Service) project(ctx context.Context, id domain.ProjectID) (domain.ProjectRecord, error) {
	row, ok, err := s.store.GetProject(ctx, string(id))
	if err != nil {
		return domain.ProjectRecord{}, apierr.Internal("PROJECT_LOAD_FAILED", "Failed to load project")
	}
	if !ok || !row.ArchivedAt.IsZero() {
		return domain.ProjectRecord{}, apierr.NotFound("PROJECT_NOT_FOUND", "Unknown project")
	}
	if row.Kind.WithDefault() != domain.ProjectKindSingleRepo {
		return domain.ProjectRecord{}, apierr.Invalid("TICKET_UNSUPPORTED_PROJECT", "Tickets need a single-repository project", nil)
	}
	return row, nil
}

func ticketsRoot(p domain.ProjectRecord) string {
	return filepath.Join(p.Path, filepath.FromSlash(domain.TicketsDir))
}

func (s *Service) sessionIndex(ctx context.Context, project domain.ProjectID) (map[domain.SessionID]*domain.Session, error) {
	list, err := s.sessions.List(ctx, sessionsvc.ListFilter{ProjectID: project})
	if err != nil {
		return nil, fmt.Errorf("list sessions: %w", err)
	}
	out := make(map[domain.SessionID]*domain.Session, len(list))
	for i := range list {
		out[list[i].ID] = &list[i]
	}
	return out, nil
}

func (s *Service) build(ctx context.Context, rec domain.TicketRecord, sc scannedTicket, sessions map[domain.SessionID]*domain.Session) (domain.Ticket, error) {
	rows, err := s.store.ListPlanAssignments(ctx, rec.ProjectID, rec.Slug)
	if err != nil {
		return domain.Ticket{}, err
	}
	current := currentAssignments(rows)
	t := domain.Ticket{
		ProjectID:         rec.ProjectID,
		Slug:              rec.Slug,
		Title:             sc.Title,
		Brief:             sc.Brief,
		PlanningSessionID: rec.PlanningSessionID,
		Files:             sc.Files,
		Warning:           sc.Warning,
		CreatedAt:         rec.CreatedAt,
		ArchivedAt:        rec.ArchivedAt,
		Plans:             make([]domain.Plan, 0, len(sc.Plans)),
	}
	for _, sp := range sc.Plans {
		a, ok := current[sp.File]
		p := domain.Plan{File: sp.File, Order: sp.Order, Title: sp.Title, KickoffFile: sp.Kickoff, Unordered: sp.Unordered, Warning: sp.Warning}
		if ok {
			p.SessionID = a.SessionID
			p.AssignmentID = a.ID
			p.ReviewerID = a.ReviewerSessionID
			p.MergeSummary = a.MergeSummary
		}
		p.Status = planStatus(a, ok, sessions[a.SessionID])
		t.Plans = append(t.Plans, p)
	}
	t.Status = ticketStatus(rec, t.Plans, sessions[rec.PlanningSessionID])
	return t, nil
}

func (s *Service) List(ctx context.Context, project domain.ProjectID) ([]domain.Ticket, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return nil, err
	}
	scanned, err := scanTickets(ticketsRoot(p))
	if err != nil {
		return nil, err
	}
	records, err := s.store.ListTickets(ctx, project)
	if err != nil {
		return nil, err
	}
	byslug := make(map[string]domain.TicketRecord, len(records))
	for _, r := range records {
		byslug[r.Slug] = r
	}
	sessions, err := s.sessionIndex(ctx, project)
	if err != nil {
		return nil, err
	}
	out := make([]domain.Ticket, 0, len(scanned))
	for _, sc := range scanned {
		rec, ok := byslug[sc.Slug]
		if !ok {
			rec = domain.TicketRecord{ProjectID: project, Slug: sc.Slug}
		}
		t, err := s.build(ctx, rec, sc, sessions)
		if err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, nil
}

func (s *Service) load(ctx context.Context, project domain.ProjectID, slug string) (domain.ProjectRecord, domain.TicketRecord, domain.Ticket, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return p, domain.TicketRecord{}, domain.Ticket{}, err
	}
	sc, ok, err := scanTicket(ticketsRoot(p), slug)
	if err != nil {
		return p, domain.TicketRecord{}, domain.Ticket{}, err
	}
	if !ok {
		return p, domain.TicketRecord{}, domain.Ticket{}, apierr.NotFound("TICKET_NOT_FOUND", "Unknown ticket")
	}
	rec, found, err := s.store.GetTicket(ctx, project, slug)
	if err != nil {
		return p, rec, domain.Ticket{}, err
	}
	if !found {
		rec = domain.TicketRecord{ProjectID: project, Slug: slug}
	}
	sessions, err := s.sessionIndex(ctx, project)
	if err != nil {
		return p, rec, domain.Ticket{}, err
	}
	t, err := s.build(ctx, rec, sc, sessions)
	return p, rec, t, err
}

func (s *Service) Get(ctx context.Context, project domain.ProjectID, slug string) (domain.Ticket, error) {
	_, _, t, err := s.load(ctx, project, slug)
	return t, err
}

func resolveTicketPath(dir, rel string) (string, error) {
	rel = strings.TrimSpace(filepath.ToSlash(rel))
	if rel == "" || strings.HasPrefix(rel, "/") || filepath.IsAbs(rel) {
		return "", errPathOutside
	}
	clean := path.Clean(rel)
	if clean == "." || clean == ".." || strings.HasPrefix(clean, "../") || !strings.HasSuffix(clean, ".md") {
		return "", errPathOutside
	}
	parent := path.Dir(clean)
	if parent != "." && parent != "plans" {
		return "", errPathOutside
	}
	abs := filepath.Join(dir, filepath.FromSlash(clean))
	realDir, err := filepath.EvalSymlinks(dir)
	if err != nil {
		return "", apierr.NotFound("TICKET_NOT_FOUND", "Unknown ticket")
	}
	if real, err := filepath.EvalSymlinks(abs); err == nil {
		if real != realDir && !strings.HasPrefix(real, realDir+string(filepath.Separator)) {
			return "", errPathOutside
		}
	}
	return abs, nil
}

func (s *Service) ReadFile(ctx context.Context, project domain.ProjectID, slug, rel string) (File, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return File{}, err
	}
	abs, err := resolveTicketPath(filepath.Join(ticketsRoot(p), slug), rel)
	if err != nil {
		return File{}, err
	}
	raw, err := os.ReadFile(abs)
	if errors.Is(err, os.ErrNotExist) {
		return File{}, apierr.NotFound("TICKET_FILE_NOT_FOUND", "No such file in the ticket")
	}
	if err != nil {
		return File{}, fmt.Errorf("read ticket file: %w", err)
	}
	info, err := os.Stat(abs)
	if err != nil {
		return File{}, fmt.Errorf("stat ticket file: %w", err)
	}
	return File{Path: path.Clean(filepath.ToSlash(rel)), Content: string(raw), ModifiedAt: info.ModTime().UTC()}, nil
}

func (s *Service) WriteFile(ctx context.Context, project domain.ProjectID, slug, rel, content string, ifUnmodifiedSince time.Time) (File, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return File{}, err
	}
	abs, err := resolveTicketPath(filepath.Join(ticketsRoot(p), slug), rel)
	if err != nil {
		return File{}, err
	}
	if info, err := os.Stat(abs); err == nil && !ifUnmodifiedSince.IsZero() {
		if info.ModTime().Truncate(time.Second).After(ifUnmodifiedSince.Truncate(time.Second)) {
			return File{}, apierr.Conflict("TICKET_FILE_STALE", "The file changed on disk since it was loaded", map[string]any{"modifiedAt": info.ModTime().UTC()})
		}
	}
	if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
		return File{}, fmt.Errorf("create plans dir: %w", err)
	}
	if err := os.WriteFile(abs, []byte(content), 0o644); err != nil {
		return File{}, fmt.Errorf("write ticket file: %w", err)
	}
	return s.ReadFile(ctx, project, slug, rel)
}

func (s *Service) uniqueSlug(ctx context.Context, project domain.ProjectID, root, base string) (string, error) {
	for i := 1; ; i++ {
		slug := base
		if i > 1 {
			slug = fmt.Sprintf("%s-%d", base, i)
		}
		if _, err := os.Stat(filepath.Join(root, slug)); err == nil {
			continue
		}
		if _, found, err := s.store.GetTicket(ctx, project, slug); err != nil {
			return "", err
		} else if found {
			continue
		}
		return slug, nil
	}
}

func (s *Service) Create(ctx context.Context, project domain.ProjectID, in CreateInput) (CreateResult, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return CreateResult{}, err
	}
	title := strings.TrimSpace(in.Title)
	if title == "" {
		return CreateResult{}, apierr.Invalid("TICKET_TITLE_REQUIRED", "A ticket needs a title", nil)
	}
	brief := strings.TrimSpace(in.Brief)
	root := ticketsRoot(p)
	slug, err := s.uniqueSlug(ctx, project, root, slugify(title))
	if err != nil {
		return CreateResult{}, err
	}
	now := s.now()
	dir := filepath.Join(root, slug)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return CreateResult{}, fmt.Errorf("create ticket dir: %w", err)
	}
	ticketMD := fmt.Sprintf("---\ntitle: %s\nbrief: %s\ncreated: %s\n---\n", yamlScalar(title), yamlScalar(brief), now.Format("2006-01-02"))
	if err := os.WriteFile(filepath.Join(dir, "ticket.md"), []byte(ticketMD), 0o644); err != nil {
		return CreateResult{}, fmt.Errorf("write ticket.md: %w", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "spec.md"), []byte("# "+title+"\n"), 0o644); err != nil {
		return CreateResult{}, fmt.Errorf("write spec.md: %w", err)
	}
	if err := s.store.InsertTicket(ctx, domain.TicketRecord{ProjectID: project, Slug: slug, CreatedAt: now}); err != nil {
		return CreateResult{}, err
	}
	var warnings []string
	if branch, err := gitCurrentBranch(ctx, p.Path); err == nil && branch != p.Config.WithDefaults().DefaultBranch {
		warnings = append(warnings, "not_on_default_branch")
	}
	if err := gitCommitPath(ctx, p.Path, ticketFolder(slug), "ticket: add "+slug); err != nil {
		warnings = append(warnings, "commit_failed")
	}
	t, err := s.Get(ctx, project, slug)
	if err != nil {
		return CreateResult{}, err
	}
	return CreateResult{Ticket: t, Warnings: warnings}, nil
}

func (s *Service) WatchRoot(ctx context.Context, project domain.ProjectID) (string, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return "", err
	}
	root := ticketsRoot(p)
	if err := os.MkdirAll(root, 0o755); err != nil {
		return "", fmt.Errorf("create tickets dir: %w", err)
	}
	return root, nil
}

func yamlScalar(s string) string {
	if s == "" {
		return `""`
	}
	if strings.ContainsAny(s, ":#\"'\n[]{}&*!|>%@`") || strings.TrimSpace(s) != s {
		return fmt.Sprintf("%q", s)
	}
	return s
}

func truncateRunes(s string, n int) string {
	s = strings.TrimSpace(s)
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	r := []rune(s)
	return strings.TrimSpace(string(r[:n]))
}
