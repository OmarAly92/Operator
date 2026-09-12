-- name: EnqueueOrchestratorInboxEvent :exec
INSERT INTO orchestrator_inbox (
    id, project_id, worker_id, kind, occurred_at, state, created_at, updated_at
) VALUES (
    ?, ?, ?, ?, ?, 'pending', ?, ?
)
ON CONFLICT (worker_id, kind) WHERE state = 'pending' DO NOTHING;

-- name: CountPendingInboxEvents :one
SELECT COUNT(*) FROM orchestrator_inbox WHERE project_id = ? AND state = 'pending';

-- name: ListPendingInboxEventsByProject :many
SELECT * FROM orchestrator_inbox WHERE project_id = ? AND state = 'pending' ORDER BY occurred_at ASC;

-- name: ListProjectsWithPendingInboxEvents :many
SELECT DISTINCT project_id FROM orchestrator_inbox WHERE state = 'pending';

-- name: AckInboxEvent :execrows
UPDATE orchestrator_inbox SET state = 'acked', acked_at = ?, updated_at = ?
WHERE id = ? AND project_id = ? AND state = 'pending';

-- name: DeleteAckedInboxEventsOlderThan :execrows
DELETE FROM orchestrator_inbox WHERE project_id = ? AND state = 'acked' AND acked_at < ?;
