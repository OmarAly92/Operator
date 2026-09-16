-- +goose Up
-- +goose StatementBegin
ALTER TABLE app_settings DROP COLUMN migration_json;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE app_settings ADD COLUMN migration_json TEXT NOT NULL DEFAULT '{}';
-- +goose StatementEnd
