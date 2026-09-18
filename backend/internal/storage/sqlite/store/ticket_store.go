package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

var errTicketNotFound = errors.New("ticket not found")

func ticketFromGen(row gen.Ticket) domain.TicketRecord {
	rec := domain.TicketRecord{ProjectID: row.ProjectID, Slug: row.Slug, CreatedAt: row.CreatedAt}
	if row.PlanningSessionID != nil {
		rec.PlanningSessionID = *row.PlanningSessionID
	}
	if row.ArchivedAt.Valid {
		rec.ArchivedAt = row.ArchivedAt.Time
	}
	return rec
}

func planAssignmentFromGen(row gen.PlanAssignment) domain.PlanAssignmentRecord {
	rec := domain.PlanAssignmentRecord{ID: row.ID, ProjectID: row.ProjectID, Slug: row.Slug, PlanFile: row.PlanFile, AssignedAt: row.AssignedAt}
	if row.SessionID != nil {
		rec.SessionID = *row.SessionID
	}
	if row.DoneAt.Valid {
		rec.DoneAt = row.DoneAt.Time
	}
	if row.ReviewerSessionID != nil {
		rec.ReviewerSessionID = *row.ReviewerSessionID
	}
	if row.ReviewRequestedAt.Valid {
		rec.ReviewRequestedAt = row.ReviewRequestedAt.Time
	}
	if row.MergeReadyAt.Valid {
		rec.MergeReadyAt = row.MergeReadyAt.Time
	}
	rec.MergeSummary = row.MergeSummary
	if row.MergeApprovedAt.Valid {
		rec.MergeApprovedAt = row.MergeApprovedAt.Time
	}
	return rec
}

func optionalTime(t time.Time) sql.NullTime {
	if t.IsZero() {
		return sql.NullTime{}
	}
	return sql.NullTime{Time: t, Valid: true}
}

func (s *Store) ListTickets(ctx context.Context, project domain.ProjectID) ([]domain.TicketRecord, error) {
	rows, err := s.qr.ListTickets(ctx, project)
	if err != nil {
		return nil, fmt.Errorf("list tickets %s: %w", project, err)
	}
	out := make([]domain.TicketRecord, 0, len(rows))
	for _, row := range rows {
		out = append(out, ticketFromGen(row))
	}
	return out, nil
}

func (s *Store) GetTicket(ctx context.Context, project domain.ProjectID, slug string) (domain.TicketRecord, bool, error) {
	row, err := s.qr.GetTicket(ctx, gen.GetTicketParams{ProjectID: project, Slug: slug})
	if errors.Is(err, sql.ErrNoRows) {
		return domain.TicketRecord{}, false, nil
	}
	if err != nil {
		return domain.TicketRecord{}, false, fmt.Errorf("get ticket %s/%s: %w", project, slug, err)
	}
	return ticketFromGen(row), true, nil
}

func (s *Store) InsertTicket(ctx context.Context, rec domain.TicketRecord) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	err := s.qw.InsertTicket(ctx, gen.InsertTicketParams{
		ProjectID:         rec.ProjectID,
		Slug:              rec.Slug,
		PlanningSessionID: optionalSessionID(rec.PlanningSessionID),
		ArchivedAt:        optionalTime(rec.ArchivedAt),
		CreatedAt:         rec.CreatedAt,
	})
	if err != nil {
		return fmt.Errorf("insert ticket %s/%s: %w", rec.ProjectID, rec.Slug, err)
	}
	return nil
}

func (s *Store) SetTicketPlanningSession(ctx context.Context, project domain.ProjectID, slug string, session domain.SessionID) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.SetTicketPlanningSession(ctx, gen.SetTicketPlanningSessionParams{PlanningSessionID: optionalSessionID(session), ProjectID: project, Slug: slug})
	if err != nil {
		return fmt.Errorf("set ticket planning session %s/%s: %w", project, slug, err)
	}
	if n == 0 {
		return errTicketNotFound
	}
	return nil
}

func (s *Store) SetTicketArchivedAt(ctx context.Context, project domain.ProjectID, slug string, at time.Time) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.SetTicketArchivedAt(ctx, gen.SetTicketArchivedAtParams{ArchivedAt: optionalTime(at), ProjectID: project, Slug: slug})
	if err != nil {
		return fmt.Errorf("set ticket archived %s/%s: %w", project, slug, err)
	}
	if n == 0 {
		return errTicketNotFound
	}
	return nil
}

func (s *Store) ListPlanAssignments(ctx context.Context, project domain.ProjectID, slug string) ([]domain.PlanAssignmentRecord, error) {
	rows, err := s.qr.ListPlanAssignments(ctx, gen.ListPlanAssignmentsParams{ProjectID: project, Slug: slug})
	if err != nil {
		return nil, fmt.Errorf("list plan assignments %s/%s: %w", project, slug, err)
	}
	out := make([]domain.PlanAssignmentRecord, 0, len(rows))
	for _, row := range rows {
		out = append(out, planAssignmentFromGen(row))
	}
	return out, nil
}

func (s *Store) InsertPlanAssignment(ctx context.Context, rec domain.PlanAssignmentRecord) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	err := s.qw.InsertPlanAssignment(ctx, gen.InsertPlanAssignmentParams{
		ProjectID:  rec.ProjectID,
		Slug:       rec.Slug,
		PlanFile:   rec.PlanFile,
		SessionID:  optionalSessionID(rec.SessionID),
		AssignedAt: rec.AssignedAt,
		DoneAt:     optionalTime(rec.DoneAt),
	})
	if err != nil {
		return fmt.Errorf("insert plan assignment %s/%s %s: %w", rec.ProjectID, rec.Slug, rec.PlanFile, err)
	}
	return nil
}

func (s *Store) SessionTicketRef(ctx context.Context, id domain.SessionID) (domain.SessionTicketRef, bool, error) {
	if id == "" {
		return domain.SessionTicketRef{}, false, nil
	}
	ticket, err := s.qr.TicketByPlanningSession(ctx, &id)
	if err == nil {
		return domain.SessionTicketRef{Slug: ticket.Slug, Role: domain.TicketRolePlanning}, true, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return domain.SessionTicketRef{}, false, fmt.Errorf("ticket by planning session %s: %w", id, err)
	}
	assignment, err := s.qr.PlanAssignmentBySession(ctx, &id)
	if err == nil {
		return domain.SessionTicketRef{Slug: assignment.Slug, PlanFile: assignment.PlanFile, Role: domain.TicketRoleImplementing}, true, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return domain.SessionTicketRef{}, false, fmt.Errorf("plan assignment by session %s: %w", id, err)
	}
	review, err := s.qr.PlanAssignmentByReviewer(ctx, &id)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.SessionTicketRef{}, false, nil
	}
	if err != nil {
		return domain.SessionTicketRef{}, false, fmt.Errorf("plan assignment by reviewer %s: %w", id, err)
	}
	return domain.SessionTicketRef{Slug: review.Slug, PlanFile: review.PlanFile, Role: domain.TicketRoleReviewing}, true, nil
}

func (s *Store) GetPlanAssignment(ctx context.Context, id int64) (domain.PlanAssignmentRecord, bool, error) {
	row, err := s.qr.GetPlanAssignment(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.PlanAssignmentRecord{}, false, nil
	}
	if err != nil {
		return domain.PlanAssignmentRecord{}, false, fmt.Errorf("get plan assignment %d: %w", id, err)
	}
	return planAssignmentFromGen(row), true, nil
}

var errPlanAssignmentNotFound = errors.New("plan assignment not found")

func (s *Store) MarkPlanReviewRequested(ctx context.Context, id int64, reviewer domain.SessionID, at time.Time) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.SetPlanAssignmentReviewRequested(ctx, gen.SetPlanAssignmentReviewRequestedParams{ReviewerSessionID: optionalSessionID(reviewer), ReviewRequestedAt: optionalTime(at), ID: id})
	if err != nil {
		return fmt.Errorf("mark plan review requested %d: %w", id, err)
	}
	if n == 0 {
		return errPlanAssignmentNotFound
	}
	return nil
}

func (s *Store) MarkPlanMergeReady(ctx context.Context, id int64, at time.Time, summary string) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.SetPlanAssignmentMergeReady(ctx, gen.SetPlanAssignmentMergeReadyParams{MergeReadyAt: optionalTime(at), MergeSummary: summary, ID: id})
	if err != nil {
		return fmt.Errorf("mark plan merge ready %d: %w", id, err)
	}
	if n == 0 {
		return errPlanAssignmentNotFound
	}
	return nil
}

func (s *Store) MarkPlanMergeApproved(ctx context.Context, id int64, at time.Time) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.SetPlanAssignmentMergeApproved(ctx, gen.SetPlanAssignmentMergeApprovedParams{MergeApprovedAt: optionalTime(at), ID: id})
	if err != nil {
		return fmt.Errorf("mark plan merge approved %d: %w", id, err)
	}
	if n == 0 {
		return errPlanAssignmentNotFound
	}
	return nil
}
