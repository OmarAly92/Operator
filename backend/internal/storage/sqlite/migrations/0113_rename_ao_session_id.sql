-- +goose Up
-- +goose StatementBegin
ALTER TABLE agent_native_sessions RENAME COLUMN ao_session_id TO session_id;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE agent_native_sessions RENAME COLUMN session_id TO ao_session_id;
-- +goose StatementEnd
