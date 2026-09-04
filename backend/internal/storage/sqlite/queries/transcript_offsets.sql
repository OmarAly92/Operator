-- name: GetTranscriptOffset :one
SELECT * FROM transcript_offsets WHERE session_id = ?;

-- name: UpsertTranscriptOffset :exec
INSERT INTO transcript_offsets (session_id, path, byte_offset, updated_at)
VALUES (?, ?, ?, ?)
ON CONFLICT(session_id) DO UPDATE SET
    path = excluded.path,
    byte_offset = excluded.byte_offset,
    updated_at = excluded.updated_at;
