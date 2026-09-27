-- +goose Up
-- +goose StatementBegin
CREATE INDEX terminal_blocks_finished
    ON terminal_blocks (finished_at DESC, terminal_id DESC, source_id DESC);
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP INDEX IF EXISTS terminal_blocks_finished;
-- +goose StatementEnd
