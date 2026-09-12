-- +goose Up
ALTER TABLE sessions ADD COLUMN spawned_by TEXT NOT NULL DEFAULT '';

-- +goose Down
ALTER TABLE sessions DROP COLUMN spawned_by;
