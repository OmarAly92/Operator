-- +goose Up
ALTER TABLE claude_accounts ADD COLUMN is_preferred INTEGER NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX idx_claude_accounts_single_preferred ON claude_accounts (is_preferred) WHERE is_preferred = 1;

-- +goose Down
DROP INDEX idx_claude_accounts_single_preferred;
ALTER TABLE claude_accounts DROP COLUMN is_preferred;
