-- +goose Up
-- +goose StatementBegin
ALTER TABLE usage_bindings ADD COLUMN context_model_id TEXT NOT NULL DEFAULT '';
UPDATE usage_bindings
SET context_model_id = initial_model_id
WHERE context_at IS NOT NULL;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE usage_bindings DROP COLUMN context_model_id;
-- +goose StatementEnd
