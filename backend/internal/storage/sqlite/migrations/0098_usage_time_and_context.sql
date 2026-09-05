-- +goose Up
-- +goose StatementBegin
ALTER TABLE model_usage_events ADD COLUMN occurred_at TIMESTAMP;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE INDEX idx_model_usage_events_occurred_at
    ON model_usage_events (occurred_at);
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE usage_bindings ADD COLUMN context_used INTEGER NOT NULL DEFAULT 0
    CHECK (context_used >= 0);
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE usage_bindings ADD COLUMN context_window INTEGER NOT NULL DEFAULT 0
    CHECK (context_window >= 0);
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE usage_bindings ADD COLUMN context_at TIMESTAMP;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP INDEX IF EXISTS idx_model_usage_events_occurred_at;
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE usage_bindings DROP COLUMN context_at;
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE usage_bindings DROP COLUMN context_window;
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE usage_bindings DROP COLUMN context_used;
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE model_usage_events DROP COLUMN occurred_at;
-- +goose StatementEnd
