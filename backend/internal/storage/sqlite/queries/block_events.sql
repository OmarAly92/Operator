-- name: InsertBlockEvent :one
INSERT INTO block_events (
    session_id, source_id, kind, raw_event, harness, tool_name, tool_use_id,
    tool_input, text, redacted_spans, error_type, hook_version, truncated_lines, created_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
RETURNING *;

-- name: SelectBlockEventsBySession :many
SELECT *
FROM block_events
WHERE session_id = ? AND seq > ?
ORDER BY seq
LIMIT ?;

-- name: TrimBlockEventsForSession :execrows
DELETE FROM block_events AS outer_be
WHERE outer_be.session_id = ?
  AND outer_be.seq < (
    SELECT be.seq FROM block_events AS be
    WHERE be.session_id = ?
    ORDER BY be.seq DESC
    LIMIT 1 OFFSET ?
  );
