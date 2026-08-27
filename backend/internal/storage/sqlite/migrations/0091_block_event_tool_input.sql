-- Migration 0091: bounded preview of the native tool input.
--
-- 0090 recorded which tool ran but not what it was asked to do, which is the
-- half a permission block needs to be worth reading.

-- +goose Up
-- +goose StatementBegin
ALTER TABLE block_events ADD COLUMN tool_input TEXT NOT NULL DEFAULT '';
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE block_events DROP COLUMN tool_input;
-- +goose StatementEnd
