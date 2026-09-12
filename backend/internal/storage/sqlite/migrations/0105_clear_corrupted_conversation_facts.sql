-- +goose Up
-- +goose StatementBegin
UPDATE sessions
SET latest_user_prompt = '', latest_assistant_update = ''
WHERE harness = 'claude-code'
  AND (latest_user_prompt <> '' OR latest_assistant_update <> '');
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
SELECT 1;
-- +goose StatementEnd
