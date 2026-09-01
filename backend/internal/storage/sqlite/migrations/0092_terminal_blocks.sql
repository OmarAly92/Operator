-- Migration 0092: durable store for completed shell terminal command-blocks.
--
-- One idempotently-upserted row per submitted command, keyed by the terminal
-- and the capture source's own counter. Separate from block_events: that table
-- is an append-only agent hook log keyed by sequence, while a terminal block is
-- a completed artifact carrying raw output bytes, command/cwd/branch/exit
-- metadata, and its own per-terminal retention. Standalone shell terminals have
-- no project_id and terminal-block events are not in the change_log vocabulary,
-- so this table emits no CDC; the daemon publishes updates by terminal handle
-- after commit instead.

-- +goose Up
-- +goose StatementBegin
CREATE TABLE terminal_blocks (
    terminal_id     TEXT NOT NULL,
    source_id       TEXT NOT NULL,
    session_id      TEXT NOT NULL DEFAULT '',
    command         TEXT NOT NULL DEFAULT '',
    cwd             TEXT NOT NULL DEFAULT '',
    git_branch      TEXT NOT NULL DEFAULT '',
    exit_code       INTEGER,
    raw_output      BLOB NOT NULL,
    started_at      TIMESTAMP,
    finished_at     TIMESTAMP NOT NULL,
    shell_kind      TEXT NOT NULL DEFAULT '',
    shell_version   TEXT NOT NULL DEFAULT '',
    truncated_lines INTEGER NOT NULL DEFAULT 0,
    truncated_bytes INTEGER NOT NULL DEFAULT 0,
    capture_epoch   TEXT NOT NULL,
    start_offset    INTEGER NOT NULL,
    end_offset      INTEGER NOT NULL,
    created_at      TIMESTAMP NOT NULL,
    PRIMARY KEY (terminal_id, source_id)
);
-- +goose StatementEnd
-- +goose StatementBegin
CREATE INDEX terminal_blocks_terminal_finished
    ON terminal_blocks (terminal_id, finished_at DESC);
-- +goose StatementEnd
-- +goose StatementBegin
CREATE INDEX terminal_blocks_session
    ON terminal_blocks (session_id)
    WHERE session_id <> '';
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP INDEX IF EXISTS terminal_blocks_session;
-- +goose StatementEnd
-- +goose StatementBegin
DROP INDEX IF EXISTS terminal_blocks_terminal_finished;
-- +goose StatementEnd
-- +goose StatementBegin
DROP TABLE IF EXISTS terminal_blocks;
-- +goose StatementEnd
