-- name: UpsertTerminalBlock :exec
INSERT INTO terminal_blocks (
    terminal_id, source_id, session_id, command, cwd, git_branch, exit_code,
    raw_output, started_at, finished_at, shell_kind, shell_version,
    truncated_lines, truncated_bytes, capture_epoch, start_offset, end_offset, created_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (terminal_id, source_id) DO UPDATE SET
    session_id = excluded.session_id,
    command = excluded.command,
    cwd = excluded.cwd,
    git_branch = excluded.git_branch,
    exit_code = excluded.exit_code,
    raw_output = excluded.raw_output,
    started_at = excluded.started_at,
    finished_at = excluded.finished_at,
    shell_kind = excluded.shell_kind,
    shell_version = excluded.shell_version,
    truncated_lines = excluded.truncated_lines,
    truncated_bytes = excluded.truncated_bytes,
    capture_epoch = excluded.capture_epoch,
    start_offset = excluded.start_offset,
    end_offset = excluded.end_offset,
    created_at = excluded.created_at;

-- name: ListTerminalBlocks :many
SELECT terminal_id, source_id, session_id, command, cwd, git_branch, exit_code,
       raw_output, started_at, finished_at, shell_kind, shell_version,
       truncated_lines, truncated_bytes, capture_epoch, start_offset, end_offset, created_at
FROM (
    SELECT *
    FROM terminal_blocks
    WHERE terminal_id = ?
    ORDER BY finished_at DESC, source_id DESC
    LIMIT ?
)
ORDER BY finished_at ASC, source_id ASC;

-- name: TrimTerminalBlocks :exec
DELETE FROM terminal_blocks AS outer_tb
WHERE outer_tb.terminal_id = ?
  AND outer_tb.source_id NOT IN (
    SELECT keep_tb.source_id
    FROM terminal_blocks AS keep_tb
    WHERE keep_tb.terminal_id = ?
    ORDER BY keep_tb.finished_at DESC, keep_tb.source_id DESC
    LIMIT ?
  );

-- name: DeleteTerminalBlocks :exec
DELETE FROM terminal_blocks
WHERE terminal_id = ?;
