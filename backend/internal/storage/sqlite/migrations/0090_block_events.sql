-- Migration 0090: bounded per-session log of normalized agent block events.
--
-- Separate from activity: activity is one current state per session, this is an
-- append-only history a client can replay after a reconnect. Rows are trimmed
-- per session rather than globally so one busy session cannot evict another's.

-- +goose Up
-- +goose StatementBegin
CREATE TABLE block_events (
    seq              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id       TEXT NOT NULL,
    source_id        TEXT NOT NULL DEFAULT '',
    kind             TEXT NOT NULL,
    raw_event        TEXT NOT NULL DEFAULT '',
    harness          TEXT NOT NULL DEFAULT '',
    tool_name        TEXT NOT NULL DEFAULT '',
    tool_use_id      TEXT NOT NULL DEFAULT '',
    text             TEXT NOT NULL DEFAULT '',
    redacted_spans   TEXT NOT NULL DEFAULT '',
    error_type       TEXT NOT NULL DEFAULT '',
    hook_version     TEXT NOT NULL DEFAULT '',
    truncated_lines  INTEGER NOT NULL DEFAULT 0,
    created_at       TIMESTAMP NOT NULL
);
-- +goose StatementEnd
-- +goose StatementBegin
CREATE INDEX block_events_session_seq ON block_events (session_id, seq);
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP INDEX IF EXISTS block_events_session_seq;
-- +goose StatementEnd
-- +goose StatementBegin
DROP TABLE IF EXISTS block_events;
-- +goose StatementEnd
