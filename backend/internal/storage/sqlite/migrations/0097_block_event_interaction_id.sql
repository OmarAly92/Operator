-- Migration 0097: carry the daemon-minted pending-interaction id.
--
-- A phone client answers a permission/question dialog by posting back this
-- id. It is minted by the daemon, not lifted from the harness, so it must be
-- threaded onto the block event at write time rather than derived later.

-- +goose Up
-- +goose StatementBegin
ALTER TABLE block_events ADD COLUMN interaction_id TEXT NOT NULL DEFAULT '';
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE block_events DROP COLUMN interaction_id;
-- +goose StatementEnd
