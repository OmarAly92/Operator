-- +goose Up
-- +goose StatementBegin
ALTER TABLE terminal_blocks ADD COLUMN raw_output_cleared_at TIMESTAMP;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE terminal_blocks DROP COLUMN raw_output_cleared_at;
-- +goose StatementEnd
