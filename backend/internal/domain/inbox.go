package domain

import "time"

// OrchestratorInboxEventKind identifies the kind of event coalesced into the
// orchestrator inbox.
type OrchestratorInboxEventKind string

const (
	// InboxEventWorkerIdle means a worker session went idle.
	InboxEventWorkerIdle OrchestratorInboxEventKind = "worker_idle"
	// InboxEventCIFailed means CI failed for a worker's PR.
	InboxEventCIFailed OrchestratorInboxEventKind = "ci_failed"
	// InboxEventReviewChangesRequested means a reviewer requested changes.
	InboxEventReviewChangesRequested OrchestratorInboxEventKind = "review_changes_requested"
)

// OrchestratorInboxEventState is the lifecycle state of an inbox row.
type OrchestratorInboxEventState string

const (
	// InboxStatePending means the event has not yet been acknowledged.
	InboxStatePending OrchestratorInboxEventState = "pending"
	// InboxStateAcked means the event has been acknowledged.
	InboxStateAcked OrchestratorInboxEventState = "acked"
)

// OrchestratorInboxEvent is one coalesced pending-or-acked row in the
// orchestrator inbox: at most one pending row per (worker, kind) pair.
type OrchestratorInboxEvent struct {
	ID         string
	ProjectID  ProjectID
	WorkerID   SessionID
	Kind       OrchestratorInboxEventKind
	State      OrchestratorInboxEventState
	OccurredAt time.Time
	AckedAt    time.Time
	CreatedAt  time.Time
	UpdatedAt  time.Time
}
