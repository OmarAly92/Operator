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
	SessionTicketRef(ctx context.Context, id domain.SessionID) (domain.SessionTicketRef, bool, error)
	GetPlanAssignment(ctx context.Context, id int64) (domain.PlanAssignmentRecord, bool, error)
	MarkPlanReviewRequested(ctx context.Context, id int64, reviewer domain.SessionID, at time.Time) error
	MarkPlanMergeReady(ctx context.Context, id int64, at time.Time, summary string) error
	MarkPlanMergeApproved(ctx context.Context, id int64, at time.Time) error
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
	p, rec, t, _, err := s.loadWithSessions(ctx, project, slug)
	return p, rec, t, err
}

func (s *Service) loadWithSessions(ctx context.Context, project domain.ProjectID, slug string) (domain.ProjectRecord, domain.TicketRecord, domain.Ticket, map[domain.SessionID]*domain.Session, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return p, domain.TicketRecord{}, domain.Ticket{}, nil, err
	}
	if !validSlug(slug) {
		return p, domain.TicketRecord{}, domain.Ticket{}, nil, apierr.NotFound("TICKET_NOT_FOUND", "Unknown ticket")
	}
	sc, ok := scanTicket(ticketsRoot(p), slug)
	if !ok {
		return p, domain.TicketRecord{}, domain.Ticket{}, nil, apierr.NotFound("TICKET_NOT_FOUND", "Unknown ticket")
	}
	rec, found, err := s.store.GetTicket(ctx, project, slug)
	if err != nil {
		return p, rec, domain.Ticket{}, nil, err
	}
	if !found {
		rec = domain.TicketRecord{ProjectID: project, Slug: slug}
	}
	sessions, err := s.sessionIndex(ctx, project)
	if err != nil {
		return p, rec, domain.Ticket{}, nil, err
	}
	t, err := s.build(ctx, rec, sc, sessions)
	return p, rec, t, sessions, err
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
	if info, err := os.Lstat(abs); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return "", errPathOutside
	}
	realDir, err := filepath.EvalSymlinks(dir)
	if err != nil {
		return "", apierr.NotFound("TICKET_NOT_FOUND", "Unknown ticket")
	}
	realRoot, err := filepath.EvalSymlinks(filepath.Dir(dir))
	if err != nil || realDir == realRoot || !withinRoot(realDir, realRoot) {
		return "", errPathOutside
	}
	if resolved, err := filepath.EvalSymlinks(abs); err == nil {
		if !withinRoot(resolved, realDir) {
			return "", errPathOutside
		}
	} else {
		anc := filepath.Dir(abs)
		for {
			resolved, err := filepath.EvalSymlinks(anc)
			if err == nil {
				if !withinRoot(resolved, realDir) {
					return "", errPathOutside
				}
				break
			}
			next := filepath.Dir(anc)
			if next == anc {
				break
			}
			anc = next
		}
	}
	return abs, nil
}

func withinRoot(resolved, realDir string) bool {
	return resolved == realDir || strings.HasPrefix(resolved, realDir+string(filepath.Separator))
}

func (s *Service) ReadFile(ctx context.Context, project domain.ProjectID, slug, rel string) (File, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return File{}, err
	}
	if !validSlug(slug) {
		return File{}, apierr.NotFound("TICKET_NOT_FOUND", "Unknown ticket")
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
	if !validSlug(slug) {
		return File{}, apierr.NotFound("TICKET_NOT_FOUND", "Unknown ticket")
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
	if err := os.MkdirAll(filepath.Dir(abs), 0o750); err != nil {
		return File{}, fmt.Errorf("create plans dir: %w", err)
	}
	if err := os.WriteFile(abs, []byte(content), 0o600); err != nil {
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
		if slug == "events" {
			continue
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
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return CreateResult{}, fmt.Errorf("create ticket dir: %w", err)
	}
	ticketMD := fmt.Sprintf("---\ntitle: %s\nbrief: %s\ncreated: %s\n---\n", yamlScalar(title), yamlScalar(brief), now.Format("2006-01-02"))
	if err := os.WriteFile(filepath.Join(dir, "ticket.md"), []byte(ticketMD), 0o600); err != nil {
		return CreateResult{}, fmt.Errorf("write ticket.md: %w", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "spec.md"), []byte("# "+title+"\n"), 0o600); err != nil {
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
	if err := os.MkdirAll(root, 0o750); err != nil {
		return "", fmt.Errorf("create tickets dir: %w", err)
	}
	return root, nil
}

func yamlScalar(s string) string {
	return fmt.Sprintf("%q", s)
}

func truncateRunes(s string) string {
	s = strings.TrimSpace(s)
	if utf8.RuneCountInString(s) <= maxDisplayName {
		return s
	}
	r := []rune(s)
	return strings.TrimSpace(string(r[:maxDisplayName]))
}

type SpawnInput struct {
	Harness         domain.AgentHarness
	Model           string
	ClaudeAccountID domain.ClaudeAccountID
	Extra           string
}

func (in SpawnInput) withDefaults(d domain.TicketRoleDefaults) SpawnInput {
	if in.Harness == "" {
		in.Harness = d.Harness
	}
	if strings.TrimSpace(in.Model) == "" {
		in.Model = d.Model
	}
	if in.ClaudeAccountID == "" {
		in.ClaudeAccountID = d.ClaudeAccountID
	}
	return in
}

type AssignInput struct {
	SpawnInput
	Force  bool
	DryRun bool
}

type AssignResult struct {
	Warnings []string
	Session  *domain.Session
}

func (s *Service) ensureRecord(ctx context.Context, rec domain.TicketRecord) error {
	if !rec.CreatedAt.IsZero() {
		return nil
	}
	rec.CreatedAt = s.now()
	if err := s.store.InsertTicket(ctx, rec); err != nil {
		return err
	}
	return nil
}

func planningLive(sessions map[domain.SessionID]*domain.Session, id domain.SessionID) bool {
	sess := sessions[id]
	if sess == nil {
		return false
	}
	switch sess.Status {
	case domain.StatusTerminated, domain.StatusMerged, domain.StatusExited:
		return false
	default:
		return true
	}
}

func (s *Service) Plan(ctx context.Context, project domain.ProjectID, slug string, in SpawnInput) (domain.Session, error) {
	p, rec, t, sessions, err := s.loadWithSessions(ctx, project, slug)
	if err != nil {
		return domain.Session{}, err
	}
	if planningLive(sessions, rec.PlanningSessionID) {
		return domain.Session{}, apierr.Conflict("TICKET_PLANNING_ACTIVE", "This ticket already has a running planning session", map[string]any{"sessionId": rec.PlanningSessionID})
	}
	if err := s.ensureRecord(ctx, rec); err != nil {
		return domain.Session{}, err
	}
	return s.spawnPlanner(ctx, p, t, in, planningPrompt(t, in.Extra))
}

func (s *Service) spawnPlanner(ctx context.Context, p domain.ProjectRecord, t domain.Ticket, in SpawnInput, prompt string) (domain.Session, error) {
	in = in.withDefaults(p.Config.Tickets.Planner)
	sess, _, _, err := s.sessions.Spawn(ctx, ports.SpawnConfig{
		ProjectID:       domain.ProjectID(p.ID),
		Kind:            domain.KindWorker,
		Harness:         in.Harness,
		WorkspaceMode:   domain.WorkspaceModeInPlace,
		Prompt:          prompt,
		AgentConfig:     ports.AgentConfig{Model: strings.TrimSpace(in.Model)},
		DisplayName:     truncateRunes(t.Title),
		ClaudeAccountID: in.ClaudeAccountID,
	})
	if err != nil {
		return domain.Session{}, err
	}
	if err := s.store.SetTicketPlanningSession(ctx, domain.ProjectID(p.ID), t.Slug, sess.ID); err != nil {
		return domain.Session{}, err
	}
	return s.refresh(ctx, sess), nil
}

func (s *Service) refresh(ctx context.Context, sess domain.Session) domain.Session {
	if fresh, err := s.sessions.Get(ctx, sess.ID); err == nil {
		return fresh
	}
	return sess
}

func findPlan(t domain.Ticket, planName string) (int, bool) {
	file := "plans/" + strings.TrimPrefix(strings.TrimSpace(planName), "plans/")
	for i, p := range t.Plans {
		if p.File == file {
			return i, true
		}
	}
	return 0, false
}

func planStem(plan domain.Plan) string {
	if !plan.Unordered {
		return fmt.Sprintf("%02d", plan.Order)
	}
	return strings.TrimSuffix(path.Base(plan.File), ".md")
}

func planBranch(slug string, plan domain.Plan, attempt int) string {
	b := "opr/" + slug + "-" + planStem(plan)
	if attempt > 1 {
		b += fmt.Sprintf("-%d", attempt)
	}
	return b
}

func (s *Service) assignWarnings(ctx context.Context, p domain.ProjectRecord, rec domain.TicketRecord, t domain.Ticket, idx int, sessions map[domain.SessionID]*domain.Session) []string {
	var w []string
	for _, earlier := range t.Plans[:idx] {
		if earlier.Status != domain.PlanStatusMerged && earlier.Status != domain.PlanStatusDone {
			w = append(w, "plan_order")
			break
		}
	}
	if dirty, err := gitPathDirty(ctx, p.Path, ticketFolder(t.Slug)); err == nil && dirty {
		w = append(w, "ticket_repo_dirty")
	}
	if branch, err := gitCurrentBranch(ctx, p.Path); err == nil && branch != p.Config.WithDefaults().DefaultBranch {
		w = append(w, "ticket_not_on_default_branch")
	}
	if planningLive(sessions, rec.PlanningSessionID) {
		w = append(w, "planning_active")
	}
	if planLive(t.Plans[idx].Status) {
		w = append(w, "plan_assigned")
	}
	return w
}

func (s *Service) Assign(ctx context.Context, project domain.ProjectID, slug, planName string, in AssignInput) (AssignResult, error) {
	p, rec, t, sessions, err := s.loadWithSessions(ctx, project, slug)
	if err != nil {
		return AssignResult{}, err
	}
	idx, ok := findPlan(t, planName)
	if !ok {
		return AssignResult{}, apierr.NotFound("TICKET_PLAN_NOT_FOUND", "No such plan in the ticket")
	}
	warnings := s.assignWarnings(ctx, p, rec, t, idx, sessions)
	if in.DryRun {
		return AssignResult{Warnings: warnings}, nil
	}
	if len(warnings) > 0 && !in.Force {
		return AssignResult{}, apierr.Conflict("TICKET_ASSIGN_BLOCKED", "Assignment needs confirmation", map[string]any{"warnings": warnings})
	}
	if err := s.ensureRecord(ctx, rec); err != nil {
		return AssignResult{}, err
	}
	rows, err := s.store.ListPlanAssignments(ctx, project, slug)
	if err != nil {
		return AssignResult{}, err
	}
	attempt := 1
	for _, r := range rows {
		if r.PlanFile == t.Plans[idx].File && r.SessionID != "" {
			attempt++
		}
	}
	plan := t.Plans[idx]
	kickoff := ""
	if plan.KickoffFile != "" {
		raw, err := os.ReadFile(filepath.Join(ticketsRoot(p), slug, filepath.FromSlash(plan.KickoffFile)))
		if err != nil {
			return AssignResult{}, fmt.Errorf("read kickoff %s: %w", plan.KickoffFile, err)
		}
		kickoff = string(raw)
	}
	role := in.withDefaults(p.Config.Tickets.Implementer)
	sess, _, _, err := s.sessions.Spawn(ctx, ports.SpawnConfig{
		ProjectID:       project,
		Kind:            domain.KindWorker,
		Harness:         role.Harness,
		WorkspaceMode:   domain.WorkspaceModeWorktree,
		Branch:          planBranch(slug, plan, attempt),
		Prompt:          implementPrompt(t, plan, kickoff, in.Extra),
		AgentConfig:     ports.AgentConfig{Model: strings.TrimSpace(role.Model)},
		DisplayName:     truncateRunes(fmt.Sprintf("%s · %s", slug, planStem(plan))),
		ClaudeAccountID: role.ClaudeAccountID,
	})
	if err != nil {
		return AssignResult{}, err
	}
	if err := s.store.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: project, Slug: slug, PlanFile: plan.File, SessionID: sess.ID, AssignedAt: s.now()}); err != nil {
		return AssignResult{}, err
	}
	sess = s.refresh(ctx, sess)
	return AssignResult{Warnings: warnings, Session: &sess}, nil
}

func (s *Service) MarkDone(ctx context.Context, project domain.ProjectID, slug, planName string) (domain.Ticket, error) {
	_, rec, t, err := s.load(ctx, project, slug)
	if err != nil {
		return domain.Ticket{}, err
	}
	idx, ok := findPlan(t, planName)
	if !ok {
		return domain.Ticket{}, apierr.NotFound("TICKET_PLAN_NOT_FOUND", "No such plan in the ticket")
	}
	if err := s.ensureRecord(ctx, rec); err != nil {
		return domain.Ticket{}, err
	}
	now := s.now()
	if err := s.store.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: project, Slug: slug, PlanFile: t.Plans[idx].File, AssignedAt: now, DoneAt: now}); err != nil {
		return domain.Ticket{}, err
	}
	return s.Get(ctx, project, slug)
}

func (s *Service) SetArchived(ctx context.Context, project domain.ProjectID, slug string, archived bool) (domain.Ticket, error) {
	_, rec, _, err := s.load(ctx, project, slug)
	if err != nil {
		return domain.Ticket{}, err
	}
	if err := s.ensureRecord(ctx, rec); err != nil {
		return domain.Ticket{}, err
	}
	at := time.Time{}
	if archived {
		at = s.now()
	}
	if err := s.store.SetTicketArchivedAt(ctx, project, slug, at); err != nil {
		return domain.Ticket{}, err
	}
	return s.Get(ctx, project, slug)
}

const (
	ReviewerPlanner = "planner"
	ReviewerNew     = "new"
)

type ReviewInput struct {
	SpawnInput
	Reviewer string
}

type ReviewResult struct {
	Session domain.Session
	Spawned bool
}

func (s *Service) currentAssignment(ctx context.Context, project domain.ProjectID, slug, planFile string) (domain.PlanAssignmentRecord, bool, error) {
	rows, err := s.store.ListPlanAssignments(ctx, project, slug)
	if err != nil {
		return domain.PlanAssignmentRecord{}, false, err
	}
	a, ok := currentAssignments(rows)[planFile]
	return a, ok, nil
}

func (s *Service) mergeReadyCurl(project domain.ProjectID, slug, planName string) string {
	return fmt.Sprintf(`curl -s -X POST %s/api/v1/projects/%s/tickets/%s/plans/%s/merge-ready -H 'content-type: application/json' -d '{"summary":"<one line: what you verified>"}'`, s.baseURL, project, slug, planName)
}

func (s *Service) sessionLive(sessions map[domain.SessionID]*domain.Session, id domain.SessionID) bool {
	return planningLive(sessions, id)
}

func (s *Service) Review(ctx context.Context, project domain.ProjectID, slug, planName string, in ReviewInput) (ReviewResult, error) {
	p, rec, t, sessions, err := s.loadWithSessions(ctx, project, slug)
	if err != nil {
		return ReviewResult{}, err
	}
	idx, ok := findPlan(t, planName)
	if !ok {
		return ReviewResult{}, apierr.NotFound("TICKET_PLAN_NOT_FOUND", "No such plan in the ticket")
	}
	plan := t.Plans[idx]
	a, ok, err := s.currentAssignment(ctx, project, slug, plan.File)
	if err != nil {
		return ReviewResult{}, err
	}
	if !ok || a.SessionID == "" {
		return ReviewResult{}, apierr.Conflict("TICKET_PLAN_UNASSIGNED", "Assign the plan to a session before reviewing it", nil)
	}
	mode := strings.TrimSpace(in.Reviewer)
	if mode == "" {
		mode = strings.TrimSpace(p.Config.Tickets.ReviewerMode)
	}
	if mode == "" {
		mode = ReviewerPlanner
	}
	if mode != ReviewerPlanner && mode != ReviewerNew {
		return ReviewResult{}, apierr.Invalid("TICKET_REVIEWER_INVALID", "reviewer must be planner or new", nil)
	}
	impl, err := s.sessions.Get(ctx, a.SessionID)
	if err != nil {
		return ReviewResult{}, err
	}
	prompt := reviewPrompt(t, plan, impl.Metadata.Branch, impl.Metadata.WorkspacePath, s.mergeReadyCurl(project, slug, path.Base(plan.File)), in.Extra)
	var reviewer domain.Session
	spawned := false
	switch {
	case mode == ReviewerPlanner && s.sessionLive(sessions, rec.PlanningSessionID):
		if err := s.sessions.Send(ctx, rec.PlanningSessionID, prompt, nil); err != nil {
			return ReviewResult{}, err
		}
		reviewer = *sessions[rec.PlanningSessionID]
	case mode == ReviewerPlanner:
		reviewer, err = s.spawnPlanner(ctx, p, t, in.SpawnInput, prompt)
		if err != nil {
			return ReviewResult{}, err
		}
		spawned = true
	default:
		defaults := p.Config.Tickets.Reviewer
		if defaults == (domain.TicketRoleDefaults{}) {
			defaults = p.Config.Tickets.Planner
		}
		role := in.withDefaults(defaults)
		reviewer, _, _, err = s.sessions.Spawn(ctx, ports.SpawnConfig{
			ProjectID:       project,
			Kind:            domain.KindWorker,
			Harness:         role.Harness,
			WorkspaceMode:   domain.WorkspaceModeInPlace,
			Prompt:          prompt,
			AgentConfig:     ports.AgentConfig{Model: strings.TrimSpace(role.Model)},
			DisplayName:     truncateRunes(slug + " review"),
			ClaudeAccountID: role.ClaudeAccountID,
		})
		if err != nil {
			return ReviewResult{}, err
		}
		spawned = true
	}
	if err := s.store.MarkPlanReviewRequested(ctx, a.ID, reviewer.ID, s.now()); err != nil {
		return ReviewResult{}, err
	}
	return ReviewResult{Session: s.refresh(ctx, reviewer), Spawned: spawned}, nil
}

func (s *Service) MergeReady(ctx context.Context, project domain.ProjectID, slug, planName, summary string) (domain.Ticket, error) {
	_, _, t, err := s.load(ctx, project, slug)
	if err != nil {
		return domain.Ticket{}, err
	}
	idx, ok := findPlan(t, planName)
	if !ok {
		return domain.Ticket{}, apierr.NotFound("TICKET_PLAN_NOT_FOUND", "No such plan in the ticket")
	}
	a, ok, err := s.currentAssignment(ctx, project, slug, t.Plans[idx].File)
	if err != nil {
		return domain.Ticket{}, err
	}
	if !ok || a.ReviewRequestedAt.IsZero() {
		return domain.Ticket{}, apierr.Conflict("TICKET_NOT_REVIEWING", "No review is in progress for this plan", nil)
	}
	if !a.MergeApprovedAt.IsZero() {
		return domain.Ticket{}, apierr.Conflict("TICKET_MERGE_APPROVED", "The user already approved this merge; finish merging instead", nil)
	}
	if err := s.store.MarkPlanMergeReady(ctx, a.ID, s.now(), strings.TrimSpace(summary)); err != nil {
		return domain.Ticket{}, err
	}
	return s.Get(ctx, project, slug)
}

func (s *Service) ApproveMerge(ctx context.Context, project domain.ProjectID, slug, planName string) (domain.Ticket, error) {
	p, _, t, sessions, err := s.loadWithSessions(ctx, project, slug)
	if err != nil {
		return domain.Ticket{}, err
	}
	idx, ok := findPlan(t, planName)
	if !ok {
		return domain.Ticket{}, apierr.NotFound("TICKET_PLAN_NOT_FOUND", "No such plan in the ticket")
	}
	plan := t.Plans[idx]
	a, ok, err := s.currentAssignment(ctx, project, slug, plan.File)
	if err != nil {
		return domain.Ticket{}, err
	}
	if !ok || a.MergeReadyAt.IsZero() || !a.MergeApprovedAt.IsZero() {
		return domain.Ticket{}, apierr.Conflict("TICKET_NOT_MERGE_READY", "The reviewer has not reported this plan as ready to merge", nil)
	}
	if a.SessionID == "" {
		return domain.Ticket{}, apierr.Conflict("TICKET_PLAN_UNASSIGNED", "The implementing session no longer exists", nil)
	}
	impl, err := s.sessions.Get(ctx, a.SessionID)
	if err != nil {
		return domain.Ticket{}, err
	}
	prompt := mergeApprovedPrompt(t, plan, impl.Metadata.Branch, p.Config.WithDefaults().DefaultBranch)
	if s.sessionLive(sessions, a.ReviewerSessionID) {
		if err := s.sessions.Send(ctx, a.ReviewerSessionID, prompt, nil); err != nil {
			return domain.Ticket{}, err
		}
	} else {
		defaults := p.Config.Tickets.Reviewer
		if defaults == (domain.TicketRoleDefaults{}) {
			defaults = p.Config.Tickets.Planner
		}
		role := SpawnInput{}.withDefaults(defaults)
		fresh, _, _, err := s.sessions.Spawn(ctx, ports.SpawnConfig{
			ProjectID:       project,
			Kind:            domain.KindWorker,
			Harness:         role.Harness,
			WorkspaceMode:   domain.WorkspaceModeInPlace,
			Prompt:          prompt,
			AgentConfig:     ports.AgentConfig{Model: strings.TrimSpace(role.Model)},
			DisplayName:     truncateRunes(slug + " merge"),
			ClaudeAccountID: role.ClaudeAccountID,
		})
		if err != nil {
			return domain.Ticket{}, err
		}
		if err := s.store.MarkPlanReviewRequested(ctx, a.ID, fresh.ID, a.ReviewRequestedAt); err != nil {
			return domain.Ticket{}, err
		}
	}
	if err := s.store.MarkPlanMergeApproved(ctx, a.ID, s.now()); err != nil {
		return domain.Ticket{}, err
	}
	return s.Get(ctx, project, slug)
}

func (s *Service) AutoReview(ctx context.Context, sessionID domain.SessionID) error {
	ref, ok, err := s.store.SessionTicketRef(ctx, sessionID)
	if err != nil || !ok || ref.Role != domain.TicketRoleImplementing {
		return err
	}
	impl, err := s.sessions.Get(ctx, sessionID)
	if err != nil {
		return err
	}
	p, err := s.project(ctx, impl.ProjectID)
	if err != nil {
		var apiErr *apierr.Error
		if errors.As(err, &apiErr) && (apiErr.Code == "TICKET_UNSUPPORTED_PROJECT" || apiErr.Code == "PROJECT_NOT_FOUND") {
			return nil
		}
		return err
	}
	if p.Config.Tickets.DisableAutoReview {
		return nil
	}
	a, ok, err := s.currentAssignment(ctx, impl.ProjectID, ref.Slug, ref.PlanFile)
	if err != nil {
		return err
	}
	if !ok || a.SessionID != sessionID || !a.ReviewRequestedAt.IsZero() {
		return nil
	}
	_, err = s.Review(ctx, impl.ProjectID, ref.Slug, path.Base(ref.PlanFile), ReviewInput{})
	return err
}
