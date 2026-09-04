package sqlite

import (
	"database/sql"
	"path/filepath"
	"testing"
	"time"
)

func TestMigration0094ClearsEveryTableExceptAppSettings(t *testing.T) {
	db := openTestDB(t)
	upTo(t, db, 93)
	assertClearOrderRespectsForeignKeys(t, db)

	now := time.Now().UTC()
	mustExec(t, db, `INSERT INTO projects (id, path, display_name, registered_at) VALUES ('p1', '/tmp/p1', 'proj', ?)`, now)
	mustExec(t, db, `INSERT INTO sessions (id, project_id, num, kind, activity_state, activity_last_at, is_terminated, created_at, updated_at)
		VALUES ('opr-1', 'p1', 1, 'worker', 'idle', ?, 0, ?, ?)`, now, now, now)
	mustExec(t, db, `INSERT INTO conversations (id, scope, project_id, session_id, current_session_id, created_at, updated_at)
		VALUES ('c1', 'session', 'p1', 'opr-1', 'opr-1', ?, ?)`, now, now)
	mustExec(t, db, `INSERT INTO conversation_turns (id, conversation_id, handled_by_session_id, state, requested_at, branch_id)
		VALUES ('t1', 'c1', 'opr-1', 'completed', ?, 'b1')`, now)
	mustExec(t, db, `INSERT INTO conversation_branches (id, conversation_id, session_id, provider_conversation_id, created_at)
		VALUES ('b1', 'c1', 'opr-1', 'provider-1', ?)`, now)
	mustExec(t, db, `INSERT INTO conversation_branches (id, conversation_id, session_id, provider_conversation_id, parent_branch_id, fork_after_turn_id, created_at)
		VALUES ('b2', 'c1', 'opr-1', 'provider-2', 'b1', 't1', ?)`, now)
	mustExec(t, db, `UPDATE app_settings SET ui_locale = 'de' WHERE id = 1`)

	upTo(t, db, 94)

	assertPreReleaseTablesCleared(t, db)
	assertAppSettingsPreserved(t, db, "de")
	assertMigrationLedgerPreserved(t, db)
	assertChangeLogSequencePreserved(t, db)
}

func TestMigration0094ToleratesTablesMissingFromBurnedHistory(t *testing.T) {
	db, err := sql.Open("sqlite", "file:"+filepath.Join(t.TempDir(), "opr.db")+pragmas)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	db.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = db.Close() })

	upTo(t, db, 39)
	for version := 40; version <= 51; version++ {
		mustExec(t, db, `INSERT INTO goose_db_version (version_id, is_applied) VALUES (?, 1)`, version)
	}
	mustExec(t, db, `INSERT INTO projects (id, path, display_name, registered_at) VALUES ('p1', '/tmp/p1', 'proj', ?)`, time.Now().UTC())

	if err := migrate(db); err != nil {
		t.Fatalf("migrate burned history: %v", err)
	}

	assertPreReleaseTablesCleared(t, db)
	assertAppSettingsPreserved(t, db, "en")
	assertMigrationLedgerPreserved(t, db)
}

func assertPreReleaseTablesCleared(t *testing.T, db *sql.DB) {
	t.Helper()
	tables := applicationTableNames(t, db)
	for _, table := range tables {
		var rows int
		if err := db.QueryRow(`SELECT COUNT(*) FROM ` + table).Scan(&rows); err != nil {
			t.Fatalf("count %s: %v", table, err)
		}
		if rows != 0 {
			t.Errorf("%s still holds %d rows", table, rows)
		}
	}
}

func assertClearOrderRespectsForeignKeys(t *testing.T, db *sql.DB) {
	t.Helper()
	positions := make(map[string]int, len(preReleaseDataTables))
	for i, table := range preReleaseDataTables {
		positions[table.name] = i
	}
	for child, childPosition := range positions {
		for _, parent := range foreignKeyParents(t, db, child) {
			parentPosition, cleared := positions[parent]
			if cleared && parent != child && childPosition > parentPosition {
				t.Fatalf("clear order deletes parent %s before child %s", parent, child)
			}
		}
	}
}

func applicationTableNames(t *testing.T, db *sql.DB) []string {
	t.Helper()
	rows, err := db.Query(`SELECT name FROM sqlite_master
		WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT IN ('app_settings', 'goose_db_version')
		ORDER BY name`)
	if err != nil {
		t.Fatalf("list application tables: %v", err)
	}
	defer rows.Close()
	var tables []string
	for rows.Next() {
		var table string
		if err := rows.Scan(&table); err != nil {
			t.Fatalf("scan application table: %v", err)
		}
		tables = append(tables, table)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("list application tables: %v", err)
	}
	return tables
}

func foreignKeyParents(t *testing.T, db *sql.DB, table string) []string {
	t.Helper()
	rows, err := db.Query(`SELECT "table" FROM pragma_foreign_key_list(?)`, table)
	if err != nil {
		t.Fatalf("list foreign keys for %s: %v", table, err)
	}
	defer rows.Close()
	var parents []string
	for rows.Next() {
		var parent string
		if err := rows.Scan(&parent); err != nil {
			t.Fatalf("scan foreign key for %s: %v", table, err)
		}
		parents = append(parents, parent)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("list foreign keys for %s: %v", table, err)
	}
	return parents
}

func assertAppSettingsPreserved(t *testing.T, db *sql.DB, wantLocale string) {
	t.Helper()
	var rows int
	var locale string
	if err := db.QueryRow(`SELECT COUNT(*), MAX(ui_locale) FROM app_settings`).Scan(&rows, &locale); err != nil {
		t.Fatalf("read app_settings: %v", err)
	}
	if rows != 1 || locale != wantLocale {
		t.Errorf("app_settings = %d rows, locale %q; want one row with locale %q", rows, locale, wantLocale)
	}
}

func assertMigrationLedgerPreserved(t *testing.T, db *sql.DB) {
	t.Helper()
	var applied int
	if err := db.QueryRow(`SELECT COUNT(*) FROM goose_db_version WHERE version_id = 94 AND is_applied = 1`).Scan(&applied); err != nil {
		t.Fatalf("read migration ledger: %v", err)
	}
	if applied != 1 {
		t.Errorf("applied migration 94 rows = %d, want 1", applied)
	}
}

func assertChangeLogSequencePreserved(t *testing.T, db *sql.DB) {
	t.Helper()
	var sequence int64
	if err := db.QueryRow(`SELECT seq FROM sqlite_sequence WHERE name = 'change_log'`).Scan(&sequence); err != nil {
		t.Fatalf("read change_log sequence: %v", err)
	}
	if sequence == 0 {
		t.Error("change_log sequence reset to zero")
	}
}
