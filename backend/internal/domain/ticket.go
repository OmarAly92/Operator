package domain

import "time"

const TicketsDir = ".operator/tickets"

type TicketStatus string

const (
	TicketStatusDraft      TicketStatus = "draft"
	TicketStatusPlanning   TicketStatus = "planning"
	TicketStatusReady      TicketStatus = "ready"
	TicketStatusInProgress TicketStatus = "in_progress"
	TicketStatusAwaitMerge TicketStatus = "awaiting_merge"
	TicketStatusDone       TicketStatus = "done"
	TicketStatusArchived   TicketStatus = "archived"
)

type PlanStatus string

const (
	PlanStatusTodo       PlanStatus = "todo"
	PlanStatusIdle       PlanStatus = "idle"
	PlanStatusWorking    PlanStatus = "working"
	PlanStatusNeedsYou   PlanStatus = "needs_you"
	PlanStatusInReview   PlanStatus = "in_review"
	PlanStatusReviewing  PlanStatus = "reviewing"
	PlanStatusAwaitMerge PlanStatus = "awaiting_merge"
	PlanStatusMerged     PlanStatus = "merged"
	PlanStatusDone       PlanStatus = "done"
	PlanStatusTerminated PlanStatus = "terminated"
)

type TicketRole string

const (
	TicketRolePlanning     TicketRole = "planning"
	TicketRoleImplementing TicketRole = "implementing"
	TicketRoleReviewing    TicketRole = "reviewing"
)

type TicketRecord struct {
	ProjectID         ProjectID
	Slug              string
	PlanningSessionID SessionID
	ArchivedAt        time.Time
	CreatedAt         time.Time
}

type PlanAssignmentRecord struct {
	ID                int64
	ProjectID         ProjectID
	Slug              string
	PlanFile          string
	SessionID         SessionID
	AssignedAt        time.Time
	DoneAt            time.Time
	ReviewerSessionID SessionID
	ReviewRequestedAt time.Time
	MergeReadyAt      time.Time
	MergeSummary      string
	MergeApprovedAt   time.Time
}

type SessionTicketRef struct {
	Slug     string     `json:"slug"`
	PlanFile string     `json:"planFile,omitempty"`
	Role     TicketRole `json:"role" enum:"planning,implementing,reviewing"`
}

type Plan struct {
	File         string
	Order        int
	Title        string
	Status       PlanStatus
	SessionID    SessionID
	AssignmentID int64
	ReviewerID   SessionID
	MergeSummary string
	KickoffFile  string
	Unordered    bool
	Warning      string
}

type Ticket struct {
	ProjectID         ProjectID
	Slug              string
	Title             string
	Brief             string
	Status            TicketStatus
	PlanningSessionID SessionID
	Plans             []Plan
	Files             []string
	Warning           string
	CreatedAt         time.Time
	ArchivedAt        time.Time
}
