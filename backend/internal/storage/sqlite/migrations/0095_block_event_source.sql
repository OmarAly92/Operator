-- Migration 0095: record which channel produced a block event.
--
-- Hooks report status and the provider transcript reports body. The projection
-- applies precedence between the two, and a client needs to know which channel
-- a fact came from, so the channel is durable rather than inferred from kind.
-- Existing rows are hook rows: nothing else could have written them.

-- +goose Up
-- +goose StatementBegin
ALTER TABLE block_events ADD COLUMN source TEXT NOT NULL DEFAULT 'hook';
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE block_events DROP COLUMN source;
-- +goose StatementEnd
