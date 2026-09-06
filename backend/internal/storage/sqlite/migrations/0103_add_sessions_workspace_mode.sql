-- +goose Up
ALTER TABLE sessions ADD COLUMN workspace_mode TEXT NOT NULL CHECK (workspace_mode IN ('worktree', 'in_place'));

-- +goose Down
ALTER TABLE sessions DROP COLUMN workspace_mode;
