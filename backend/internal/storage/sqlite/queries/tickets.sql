-- name: ListTickets :many
SELECT * FROM tickets WHERE project_id = ? ORDER BY created_at, slug;

-- name: GetTicket :one
SELECT * FROM tickets WHERE project_id = ? AND slug = ?;

-- name: InsertTicket :exec
INSERT INTO tickets (project_id, slug, planning_session_id, archived_at, created_at)
VALUES (?, ?, ?, ?, ?);

-- name: SetTicketPlanningSession :execrows
UPDATE tickets SET planning_session_id = ? WHERE project_id = ? AND slug = ?;

-- name: SetTicketArchivedAt :execrows
UPDATE tickets SET archived_at = ? WHERE project_id = ? AND slug = ?;

-- name: TicketByPlanningSession :one
SELECT * FROM tickets WHERE planning_session_id = ?;

-- name: ListPlanAssignments :many
SELECT * FROM plan_assignments WHERE project_id = ? AND slug = ? ORDER BY id DESC;

-- name: InsertPlanAssignment :exec
INSERT INTO plan_assignments (project_id, slug, plan_file, session_id, assigned_at, done_at)
VALUES (?, ?, ?, ?, ?, ?);

-- name: PlanAssignmentBySession :one
SELECT * FROM plan_assignments WHERE session_id = ? ORDER BY id DESC LIMIT 1;

-- name: GetPlanAssignment :one
SELECT * FROM plan_assignments WHERE id = ?;

-- name: PlanAssignmentByReviewer :one
SELECT * FROM plan_assignments WHERE reviewer_session_id = ? ORDER BY id DESC LIMIT 1;

-- name: SetPlanAssignmentReviewRequested :execrows
UPDATE plan_assignments SET reviewer_session_id = ?, review_requested_at = ? WHERE id = ?;

-- name: SetPlanAssignmentMergeReady :execrows
UPDATE plan_assignments SET merge_ready_at = ?, merge_summary = ? WHERE id = ?;

-- name: SetPlanAssignmentMergeApproved :execrows
UPDATE plan_assignments SET merge_approved_at = ? WHERE id = ?;
