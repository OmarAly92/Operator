package sqlite

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/pressly/goose/v3"
)

var workspaceModeClearedTables = []string{
	"change_log",
	"block_events",
	"terminal_blocks",
	"shell_terminals",
	"agent_switches",
	"agent_native_sessions",
	"pr_review_threads",
	"pr_reviews",
	"pr_comment",
	"pr_checks",
	"pr",
	"review_run",
	"review",
	"session_cleanup_facts",
	"session_worktrees",
	"notifications",
	"sessions",
}

func init() {
	goose.AddMigrationContext(addSessionWorkspaceMode, nil)
}

func addSessionWorkspaceMode(ctx context.Context, tx *sql.Tx) error {
	if _, err := tx.ExecContext(ctx, `PRAGMA defer_foreign_keys = ON`); err != nil {
		return fmt.Errorf("defer foreign keys: %w", err)
	}
	for _, table := range workspaceModeClearedTables {
		exists, err := migrationTableExists(ctx, tx, table)
		if err != nil {
			return fmt.Errorf("find table %s: %w", table, err)
		}
		if !exists {
			continue
		}
		if _, err := tx.ExecContext(ctx, fmt.Sprintf(`DELETE FROM %s`, table)); err != nil {
			return fmt.Errorf("clear table %s: %w", table, err)
		}
	}
	if _, err := tx.ExecContext(ctx,
		`ALTER TABLE sessions ADD COLUMN workspace_mode TEXT NOT NULL CHECK (workspace_mode IN ('worktree', 'in_place'))`,
	); err != nil {
		return fmt.Errorf("add sessions.workspace_mode: %w", err)
	}
	return nil
}
