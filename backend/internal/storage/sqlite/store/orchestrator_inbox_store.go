package store

import (
	"context"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

// UpdateSessionFromActivitySignalAndEnqueueInboxEvent projects an
// activity-derived session update and enqueues the coalesced inbox event in a
// single transaction, so a crash between the two writes cannot persist the
// activity transition while losing the event. A second enqueue for the same
// (worker, kind) while one is still pending is silently coalesced by the
// underlying insert's ON CONFLICT DO NOTHING.
func (s *Store) UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx context.Context, rec domain.SessionRecord, event domain.OrchestratorInboxEvent) (bool, error) {
	activity := normalActivity(rec.Activity, rec.UpdatedAt)
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	tx, err := s.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return false, fmt.Errorf("begin enqueue inbox event for %s: %w", rec.ID, err)
	}
	defer func() { _ = tx.Rollback() }()
	q := s.qw.WithTx(tx)

	rows, err := q.UpdateSessionFromActivitySignal(ctx, gen.UpdateSessionFromActivitySignalParams{
		ActivityState:           activity.State,
		ActivityLastAt:          activity.LastActivityAt,
		FirstSignalAt:           timeToNullTime(rec.FirstSignalAt),
		AgentSessionID:          rec.Metadata.AgentSessionID,
		LatestUserPrompt:        rec.Metadata.LatestUserPrompt,
		LatestAssistantUpdate:   rec.Metadata.LatestAssistantUpdate,
		NativeTranscriptPath:    rec.Metadata.NativeTranscriptPath,
		UpdatedAt:               rec.UpdatedAt,
		ID:                      rec.ID,
		ExpectedHarness:         rec.Harness,
		ExpectedRuntimeLaunchID: rec.Metadata.RuntimeLaunchID,
	})
	if err != nil {
		return false, fmt.Errorf("update session %s from activity signal: %w", rec.ID, err)
	}
	if rows == 0 {
		return false, nil
	}

	now := time.Now().UTC()
	if err := q.EnqueueOrchestratorInboxEvent(ctx, gen.EnqueueOrchestratorInboxEventParams{
		ID:         event.ID,
		ProjectID:  event.ProjectID,
		WorkerID:   event.WorkerID,
		Kind:       event.Kind,
		OccurredAt: event.OccurredAt,
		CreatedAt:  now,
		UpdatedAt:  now,
	}); err != nil {
		return false, fmt.Errorf("enqueue inbox event for %s: %w", rec.ID, err)
	}

	if err := tx.Commit(); err != nil {
		return false, fmt.Errorf("commit enqueue inbox event for %s: %w", rec.ID, err)
	}
	return true, nil
}

// CountPendingInboxEvents returns the number of not-yet-acknowledged inbox
// events for a project.
func (s *Store) CountPendingInboxEvents(ctx context.Context, project domain.ProjectID) (int, error) {
	n, err := s.qr.CountPendingInboxEvents(ctx, project)
	if err != nil {
		return 0, fmt.Errorf("count pending inbox events for %s: %w", project, err)
	}
	return int(n), nil
}

// ListPendingInboxEvents returns every pending inbox event for a project,
// oldest first.
func (s *Store) ListPendingInboxEvents(ctx context.Context, project domain.ProjectID) ([]domain.OrchestratorInboxEvent, error) {
	rows, err := s.qr.ListPendingInboxEventsByProject(ctx, project)
	if err != nil {
		return nil, fmt.Errorf("list pending inbox events for %s: %w", project, err)
	}
	out := make([]domain.OrchestratorInboxEvent, 0, len(rows))
	for _, r := range rows {
		out = append(out, inboxEventFromGen(r))
	}
	return out, nil
}

// ListProjectsWithPendingInboxEvents returns the distinct set of projects
// that currently have at least one pending inbox event.
func (s *Store) ListProjectsWithPendingInboxEvents(ctx context.Context) ([]domain.ProjectID, error) {
	rows, err := s.qr.ListProjectsWithPendingInboxEvents(ctx)
	if err != nil {
		return nil, fmt.Errorf("list projects with pending inbox events: %w", err)
	}
	return rows, nil
}

// AckInboxEvents acknowledges the given inbox event ids for a project and
// prunes acked rows past the retention window. An id that does not exist, or
// that names an already-acked row, is a no-op rather than an error.
func (s *Store) AckInboxEvents(ctx context.Context, project domain.ProjectID, ids []string) (int, error) {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	now := time.Now().UTC()
	acked := 0
	for _, id := range ids {
		n, err := s.qw.AckInboxEvent(ctx, gen.AckInboxEventParams{
			AckedAt:   timeToNullTime(now),
			UpdatedAt: now,
			ID:        id,
			ProjectID: project,
		})
		if err != nil {
			return acked, fmt.Errorf("ack inbox event %s: %w", id, err)
		}
		acked += int(n)
	}
	if acked > 0 {
		cutoff := now.AddDate(0, 0, -7)
		if _, err := s.qw.DeleteAckedInboxEventsOlderThan(ctx, gen.DeleteAckedInboxEventsOlderThanParams{
			ProjectID: project,
			AckedAt:   timeToNullTime(cutoff),
		}); err != nil {
			return acked, fmt.Errorf("prune acked inbox events for %s: %w", project, err)
		}
	}
	return acked, nil
}

func inboxEventFromGen(row gen.OrchestratorInbox) domain.OrchestratorInboxEvent {
	return domain.OrchestratorInboxEvent{
		ID:         row.ID,
		ProjectID:  row.ProjectID,
		WorkerID:   row.WorkerID,
		Kind:       row.Kind,
		State:      row.State,
		OccurredAt: row.OccurredAt,
		AckedAt:    nullTimeToTime(row.AckedAt),
		CreatedAt:  row.CreatedAt,
		UpdatedAt:  row.UpdatedAt,
	}
}
