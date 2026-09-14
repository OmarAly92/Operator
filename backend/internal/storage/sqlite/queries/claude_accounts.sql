-- name: ListClaudeAccounts :many
SELECT id, label, config_dir, is_default, created_at
FROM claude_accounts
ORDER BY is_default DESC, created_at, id;

-- name: GetClaudeAccount :one
SELECT id, label, config_dir, is_default, created_at
FROM claude_accounts WHERE id = ?;

-- name: InsertClaudeAccount :exec
INSERT INTO claude_accounts (id, label, config_dir, is_default, created_at)
VALUES (?, ?, ?, 0, ?);

-- name: RenameClaudeAccount :execrows
UPDATE claude_accounts SET label = ? WHERE id = ?;

-- name: CountSessionsByClaudeAccount :one
SELECT COUNT(*) FROM sessions WHERE claude_account_id = ?;

-- name: DeleteClaudeAccount :execrows
DELETE FROM claude_accounts WHERE id = ? AND is_default = 0;
