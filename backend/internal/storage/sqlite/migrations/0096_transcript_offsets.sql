-- Migration 0096: one durable read cursor per session's native transcript.
--
-- The transcript tailer projects provider records into block events. Without a
-- durable cursor a daemon restart would re-emit every record it had already
-- projected. The path is stored beside the offset because a path change (agent
-- switch, provider rotation) means a different file, and an offset from the old
-- file would land mid-record in the new one.

-- +goose Up
-- +goose StatementBegin
CREATE TABLE transcript_offsets (
    session_id  TEXT PRIMARY KEY,
    path        TEXT NOT NULL,
    byte_offset INTEGER NOT NULL DEFAULT 0,
    updated_at  TIMESTAMP NOT NULL
);
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS transcript_offsets;
-- +goose StatementEnd
