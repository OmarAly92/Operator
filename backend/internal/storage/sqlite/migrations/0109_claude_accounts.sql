-- +goose Up
CREATE TABLE claude_accounts (
    id         TEXT PRIMARY KEY,
    label      TEXT NOT NULL UNIQUE,
    config_dir TEXT UNIQUE,
    is_default INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL,
    CHECK ((is_default = 1 AND config_dir IS NULL) OR (is_default = 0 AND config_dir IS NOT NULL))
);
CREATE UNIQUE INDEX idx_claude_accounts_single_default ON claude_accounts (is_default) WHERE is_default = 1;
INSERT INTO claude_accounts (id, label, config_dir, is_default, created_at)
VALUES ('default', 'Default', NULL, 1, CURRENT_TIMESTAMP);
ALTER TABLE sessions ADD COLUMN claude_account_id TEXT NOT NULL DEFAULT 'default';
CREATE INDEX idx_sessions_claude_account ON sessions (claude_account_id);
ALTER TABLE agent_switches ADD COLUMN from_claude_account_id TEXT NOT NULL DEFAULT '';
ALTER TABLE agent_switches ADD COLUMN target_claude_account_id TEXT NOT NULL DEFAULT '';

-- +goose Down
ALTER TABLE agent_switches DROP COLUMN target_claude_account_id;
ALTER TABLE agent_switches DROP COLUMN from_claude_account_id;
DROP INDEX idx_sessions_claude_account;
ALTER TABLE sessions DROP COLUMN claude_account_id;
DROP INDEX idx_claude_accounts_single_default;
DROP TABLE claude_accounts;
