package sqlite

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/pressly/goose/v3"
)

var preReleaseDataTables = []struct {
	name      string
	deleteSQL string
}{
	{"change_log", `DELETE FROM change_log`},
	{"block_events", `DELETE FROM block_events`},
	{"terminal_blocks", `DELETE FROM terminal_blocks`},
	{"shell_terminals", `DELETE FROM shell_terminals`},
	{"conversation_branches", `DELETE FROM conversation_branches`},
	{"conversation_provider_events", `DELETE FROM conversation_provider_events`},
	{"conversation_activities", `DELETE FROM conversation_activities`},
	{"conversation_messages", `DELETE FROM conversation_messages`},
	{"conversation_turns", `DELETE FROM conversation_turns`},
	{"conversations", `DELETE FROM conversations`},
	{"session_interface_transition_messages", `DELETE FROM session_interface_transition_messages`},
	{"session_interface_transitions", `DELETE FROM session_interface_transitions`},
	{"agent_switches", `DELETE FROM agent_switches`},
	{"agent_native_sessions", `DELETE FROM agent_native_sessions`},
	{"agent_model_catalog", `DELETE FROM agent_model_catalog`},
	{"pr_review_threads", `DELETE FROM pr_review_threads`},
	{"pr_reviews", `DELETE FROM pr_reviews`},
	{"pr_comment", `DELETE FROM pr_comment`},
	{"pr_checks", `DELETE FROM pr_checks`},
	{"pr", `DELETE FROM pr`},
	{"review_run", `DELETE FROM review_run`},
	{"review", `DELETE FROM review`},
	{"session_cleanup_facts", `DELETE FROM session_cleanup_facts`},
	{"session_worktrees", `DELETE FROM session_worktrees`},
	{"notifications", `DELETE FROM notifications`},
	{"telemetry_event", `DELETE FROM telemetry_event`},
	{"model_usage_events", `DELETE FROM model_usage_events`},
	{"usage_sources", `DELETE FROM usage_sources`},
	{"usage_bindings", `DELETE FROM usage_bindings`},
	{"sessions", `DELETE FROM sessions`},
	{"workspace_repos", `DELETE FROM workspace_repos`},
	{"projects", `DELETE FROM projects`},
}

func init() {
	goose.AddMigrationContext(clearPreReleaseData, nil)
}

func clearPreReleaseData(ctx context.Context, tx *sql.Tx) error {
	if _, err := tx.ExecContext(ctx, `PRAGMA defer_foreign_keys = ON`); err != nil {
		return fmt.Errorf("defer foreign keys: %w", err)
	}
	for _, table := range preReleaseDataTables {
		exists, err := migrationTableExists(ctx, tx, table.name)
		if err != nil {
			return fmt.Errorf("find table %s: %w", table.name, err)
		}
		if !exists {
			continue
		}
		if _, err := tx.ExecContext(ctx, table.deleteSQL); err != nil {
			return fmt.Errorf("clear table %s: %w", table.name, err)
		}
	}
	return nil
}

func migrationTableExists(ctx context.Context, tx *sql.Tx, table string) (bool, error) {
	var count int
	err := tx.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?`, table,
	).Scan(&count)
	return count > 0, err
}
