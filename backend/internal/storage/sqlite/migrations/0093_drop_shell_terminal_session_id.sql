-- +goose Up
-- +goose StatementBegin
ALTER TABLE shell_terminals DROP COLUMN session_id;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE shell_terminals
    ADD COLUMN session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE;
-- +goose StatementEnd
