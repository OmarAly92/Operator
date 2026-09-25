-- name: InsertBlockEvent :one
INSERT INTO block_events (
    session_id, source_id, kind, raw_event, harness, tool_name, tool_use_id,
    tool_input, text, redacted_spans, error_type, hook_version, truncated_lines,
    source, interaction_id, agent_id, detail, created_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
RETURNING *;

-- name: SelectBlockEventsBySession :many
SELECT *
FROM block_events
WHERE session_id = ? AND agent_id = ? AND seq > ?
ORDER BY seq
LIMIT ?;

-- name: SelectBlockEventsBeforeSeq :many
SELECT * FROM (
  SELECT seq, session_id, source_id, kind, raw_event, harness, tool_name, tool_use_id,
         text, redacted_spans, tool_input, error_type, hook_version, truncated_lines,
         source, interaction_id, agent_id, detail, created_at
  FROM block_events
  WHERE session_id = ? AND agent_id = ? AND seq < ?
  ORDER BY seq DESC
  LIMIT ?
) ORDER BY seq ASC;

-- name: TrimBlockEventsForSession :execrows
DELETE FROM block_events AS outer_be
WHERE outer_be.session_id = ?
  AND outer_be.agent_id = ?
  AND outer_be.kind <> 'task_update'
  AND outer_be.seq < (
    SELECT be.seq FROM block_events AS be
    WHERE be.session_id = ?
      AND be.agent_id = ?
      AND be.kind <> 'task_update'
    ORDER BY be.seq DESC
    LIMIT 1 OFFSET ?
  );

-- name: TrimTaskUpdatesForSession :execrows
DELETE FROM block_events AS outer_be
WHERE outer_be.session_id = ?
  AND outer_be.agent_id = ?
  AND outer_be.kind = 'task_update'
  AND outer_be.seq < (
    SELECT be.seq FROM block_events AS be
    WHERE be.session_id = ?
      AND be.agent_id = ?
      AND be.kind = 'task_update'
    ORDER BY be.seq DESC
    LIMIT 1 OFFSET ?
  );

-- name: SelectTaskUpdatesBySession :many
SELECT *
FROM block_events
WHERE session_id = ? AND agent_id = '' AND kind = 'task_update'
ORDER BY seq;

-- name: SelectLatestTurnModels :many
SELECT session_id, text
FROM block_events
WHERE kind = 'turn_model'
  AND agent_id = ''
  AND seq IN (
    SELECT MAX(seq) FROM block_events WHERE kind = 'turn_model' AND agent_id = '' GROUP BY session_id
  );
