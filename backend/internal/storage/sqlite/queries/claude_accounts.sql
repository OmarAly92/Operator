-- name: ListClaudeAccounts :many
SELECT * FROM claude_accounts
ORDER BY is_default DESC, created_at, id;

-- name: GetClaudeAccount :one
SELECT * FROM claude_accounts WHERE id = ?;

-- name: GetPreferredClaudeAccount :one
SELECT * FROM claude_accounts WHERE is_preferred = 1;

-- name: InsertClaudeAccount :exec
INSERT INTO claude_accounts (id, label, config_dir, is_default, is_preferred, created_at)
VALUES (?, ?, ?, 0, 0, ?);

-- name: RenameClaudeAccount :execrows
UPDATE claude_accounts SET label = ? WHERE id = ?;

-- name: ClearPreferredClaudeAccount :exec
UPDATE claude_accounts SET is_preferred = 0 WHERE is_preferred = 1;

-- name: MarkPreferredClaudeAccount :execrows
UPDATE claude_accounts SET is_preferred = 1 WHERE id = ?;

-- name: CountSessionsByClaudeAccount :one
SELECT COUNT(*) FROM sessions WHERE claude_account_id = ?;

-- name: DeleteClaudeAccount :execrows
DELETE FROM claude_accounts WHERE id = ? AND is_default = 0;
