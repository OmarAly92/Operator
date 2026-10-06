-- +goose Up
ALTER TABLE sessions ADD COLUMN launch_permission_mode TEXT NOT NULL DEFAULT ''
    CHECK (launch_permission_mode IN ('', 'default', 'accept-edits', 'plan', 'auto', 'bypass-permissions'));

-- +goose Down
SELECT 1;
