package sqlite

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

var expectedUsageTableColumns = map[string][]string{
	"usage_bindings": {
		"id", "session_id", "harness", "native_root_id", "initial_model_id",
		"state", "last_error_code", "updated_at", "context_used", "context_window", "context_at",
	},
	"usage_sources": {
		"id", "binding_id", "kind", "native_session_id", "subagent_id", "artifact_path",
		"file_identity", "generation", "byte_offset", "parser_state_json", "state",
		"failure_count", "anomaly_count", "next_retry_at", "last_error_code", "updated_at",
	},
	"model_usage_events": {
		"id", "binding_id", "usage_source_id", "model_id", "input_tokens", "uncached_input_tokens",
		"cache_read_tokens", "cache_write_tokens", "output_tokens", "reasoning_tokens",
		"source_event_key", "occurred_at",
	},
}

func TestUsageTablesKeepOnlyDurableCollectionState(t *testing.T) {
	db := openMigratedTestDB(t)
	for table, wantColumns := range expectedUsageTableColumns {
		got := tableColumns(t, db, table)
		if !reflect.DeepEqual(got, wantColumns) {
			t.Errorf("%s columns = %v, want %v", table, got, wantColumns)
		}
	}
}

func TestMigration0098AddsUsageTimeAndContextSnapshot(t *testing.T) {
	db := openMigratedTestDB(t)

	rows, err := db.Query(`SELECT name, "notnull", dflt_value FROM pragma_table_info('usage_bindings') WHERE name IN ('context_used', 'context_window', 'context_at') ORDER BY name`)
	if err != nil {
		t.Fatalf("read context columns: %v", err)
	}
	defer func() { _ = rows.Close() }()
	wantDefaults := map[string]string{"context_used": "0", "context_window": "0", "context_at": ""}
	for rows.Next() {
		var name string
		var defaultValue sql.NullString
		var notNull int
		if err := rows.Scan(&name, &notNull, &defaultValue); err != nil {
			t.Fatalf("scan context column: %v", err)
		}
		if name == "context_at" {
			if notNull != 0 || defaultValue.Valid {
				t.Errorf("context_at metadata = notnull %d, default %q", notNull, defaultValue.String)
			}
			continue
		}
		if !defaultValue.Valid || notNull != 1 || defaultValue.String != wantDefaults[name] {
			t.Errorf("%s metadata = notnull %d, default %q", name, notNull, defaultValue.String)
		}
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate context columns: %v", err)
	}

	var indexCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_model_usage_events_occurred_at'`).Scan(&indexCount); err != nil {
		t.Fatalf("read occurred_at index: %v", err)
	}
	if indexCount != 1 {
		t.Fatalf("occurred_at index count = %d, want 1", indexCount)
	}
}

func TestUsageSchemaUpgradeClearsEarlierPRDataAtPreReleaseReset(t *testing.T) {
	db, err := sql.Open("sqlite", "file:"+filepath.Join(t.TempDir(), "opr.db")+"?_pragma=busy_timeout(5000)")
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	upTo(t, db, 43)

	// Reproduce the wider tables and burned migration history created by an
	// earlier checkout of this PR.
	if _, err := db.Exec(`
CREATE TABLE usage_bindings (
    id INTEGER PRIMARY KEY, session_id TEXT, harness TEXT, native_root_id TEXT,
    initial_model_id TEXT NOT NULL DEFAULT '', state TEXT,
    last_error_code TEXT NOT NULL DEFAULT '', first_seen_at TIMESTAMP,
    last_seen_at TIMESTAMP, updated_at TIMESTAMP
);
CREATE TABLE usage_sources (
    id INTEGER PRIMARY KEY, binding_id INTEGER, kind TEXT,
    native_session_id TEXT NOT NULL DEFAULT '', subagent_id TEXT NOT NULL DEFAULT '',
    artifact_path TEXT, file_identity TEXT NOT NULL DEFAULT '',
    generation INTEGER NOT NULL DEFAULT 0, byte_offset INTEGER NOT NULL DEFAULT 0,
    parser_state_json TEXT NOT NULL DEFAULT '{}', state TEXT,
    failure_count INTEGER NOT NULL DEFAULT 0, anomaly_count INTEGER NOT NULL DEFAULT 0,
    next_retry_at TIMESTAMP, last_error_code TEXT NOT NULL DEFAULT '',
    last_observed_at TIMESTAMP, created_at TIMESTAMP, updated_at TIMESTAMP
);
CREATE TABLE model_usage_events (
    id INTEGER PRIMARY KEY, binding_id INTEGER, usage_source_id INTEGER,
    project_id TEXT, session_id TEXT, harness TEXT, provider TEXT,
    model_id TEXT, observed_at TIMESTAMP, input_tokens INTEGER,
    uncached_input_tokens INTEGER, cache_read_tokens INTEGER,
    cache_write_tokens INTEGER, output_tokens INTEGER, reasoning_tokens INTEGER,
    source_event_key TEXT, created_at TIMESTAMP
);
INSERT INTO usage_bindings
    (id, session_id, harness, native_root_id, state, updated_at)
VALUES (1, 'session-1', 'codex', 'native-1', 'active', '2026-08-01T00:00:00Z');
INSERT INTO usage_sources
    (id, binding_id, kind, native_session_id, artifact_path, state, updated_at)
VALUES (1, 1, 'codex_rollout', 'native-1', '/tmp/rollout.jsonl', 'active', '2026-08-01T00:00:00Z');
INSERT INTO model_usage_events
    (id, binding_id, usage_source_id, model_id, input_tokens, uncached_input_tokens,
     cache_read_tokens, cache_write_tokens, output_tokens, source_event_key)
VALUES (1, 1, 1, 'gpt-test', 120, 100, 20, 0, 30, 'event-1');
`); err != nil {
		t.Fatalf("seed legacy usage: %v", err)
	}
	for version := 44; version <= 51; version++ {
		if _, err := db.Exec(
			`INSERT INTO goose_db_version (version_id, is_applied) VALUES (?, 1)`, version,
		); err != nil {
			t.Fatalf("seed migration %d: %v", version, err)
		}
	}

	if err := migrate(db); err != nil {
		t.Fatalf("migrate earlier usage schema: %v", err)
	}
	for table, wantColumns := range expectedUsageTableColumns {
		if got := tableColumns(t, db, table); !reflect.DeepEqual(got, wantColumns) {
			t.Errorf("%s columns = %v, want %v", table, got, wantColumns)
		}
	}
	var usageEvents int
	if err := db.QueryRow(`SELECT COUNT(*) FROM model_usage_events`).Scan(&usageEvents); err != nil {
		t.Fatalf("count usage events: %v", err)
	}
	if usageEvents != 0 {
		t.Fatalf("usage events after pre-release clear = %d, want 0", usageEvents)
	}
	var catalogTables int
	if err := db.QueryRow(
		`SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'agent_model_catalog'`,
	).Scan(&catalogTables); err != nil || catalogTables != 1 {
		t.Fatalf("agent_model_catalog table count = %d, err = %v", catalogTables, err)
	}
	var viewCount int
	if err := db.QueryRow(
		`SELECT COUNT(*) FROM sqlite_master WHERE type = 'view' AND name = 'usage_session_integrity'`,
	).Scan(&viewCount); err != nil || viewCount != 1 {
		t.Fatalf("usage_session_integrity view count = %d, err = %v", viewCount, err)
	}
	for _, table := range []string{"usage_sources", "model_usage_events"} {
		var staleReferences int
		if err := db.QueryRow(
			`SELECT COUNT(*) FROM pragma_foreign_key_list(?) WHERE "table" LIKE '%_next'`, table,
		).Scan(&staleReferences); err != nil || staleReferences != 0 {
			t.Fatalf("%s stale compatibility foreign keys = %d, err = %v", table, staleReferences, err)
		}
	}
}

func openMigratedTestDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite", "file:"+filepath.Join(t.TempDir(), "opr.db")+pragmas)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	db.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = db.Close() })
	if err := migrate(db); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func tableColumns(t *testing.T, db *sql.DB, table string) []string {
	t.Helper()
	rows, err := db.Query("PRAGMA table_info(" + table + ")")
	if err != nil {
		t.Fatalf("read %s columns: %v", table, err)
	}
	defer func() { _ = rows.Close() }()
	var columns []string
	for rows.Next() {
		var cid, notNull, primaryKey int
		var name, columnType string
		var defaultValue any
		if err := rows.Scan(&cid, &name, &columnType, &notNull, &defaultValue, &primaryKey); err != nil {
			t.Fatalf("scan %s columns: %v", table, err)
		}
		columns = append(columns, name)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate %s columns: %v", table, err)
	}
	return columns
}

// TestMigrateAllowsEveryShippedHarness guards against the collapsed-migration
// silent-no-op concern: a hand-written replace() that fails to widen the
// sessions.harness CHECK (because the target substring drifted) leaves the
// schema accepting only the original harnesses while migrate() still reports
// success. This test opens a fresh DB, runs the migrations, and asserts the
// live sessions schema admits every harness the domain ships, building the
// expected set from the domain constants so it can't silently drift.
func TestMigrateAllowsEveryShippedHarness(t *testing.T) {
	db := openMigratedTestDB(t)

	var schema string
	if err := db.QueryRow(
		"SELECT sql FROM sqlite_master WHERE type='table' AND name='sessions'",
	).Scan(&schema); err != nil {
		t.Fatalf("read sessions schema: %v", err)
	}
	harnesses := domain.AllHarnesses

	for _, h := range harnesses {
		if !strings.Contains(schema, "'"+string(h)+"'") {
			t.Errorf("sessions.harness CHECK is missing harness %q — the migration that widens it silently no-opped; schema:\n%s", h, schema)
		}
	}
}

func TestMigrateRepairsSkippedMuseHarnessConstraint(t *testing.T) {
	db, err := sql.Open("sqlite", "file:"+filepath.Join(t.TempDir(), "opr.db")+pragmas)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	db.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = db.Close() })
	upTo(t, db, 43)

	for version := 44; version <= 53; version++ {
		if _, err := db.Exec(
			`INSERT INTO goose_db_version (version_id, is_applied) VALUES (?, 1)`, version,
		); err != nil {
			t.Fatalf("seed migration %d: %v", version, err)
		}
	}

	if err := migrate(db); err != nil {
		t.Fatalf("migrate skipped muse harness schema: %v", err)
	}
	var schema string
	if err := db.QueryRow(
		"SELECT sql FROM sqlite_master WHERE type='table' AND name='sessions'",
	).Scan(&schema); err != nil {
		t.Fatalf("read sessions schema: %v", err)
	}
	if !strings.Contains(schema, "'muse'") {
		t.Fatalf("sessions.harness CHECK is missing muse after repair:\n%s", schema)
	}
	if _, err := db.Exec(`
INSERT INTO projects (id, path, registered_at, config)
VALUES ('operator', '/repo/operator', ?, '{}');
INSERT INTO sessions (id, project_id, num, harness, activity_last_at, created_at, updated_at)
VALUES ('operator-1', 'operator', 1, 'muse', ?, ?, ?);
`, time.Unix(100, 0).UTC(), time.Unix(101, 0).UTC(), time.Unix(101, 0).UTC(), time.Unix(101, 0).UTC()); err != nil {
		t.Fatalf("insert muse session after repair: %v", err)
	}
}

func TestMigrateRepairsSkippedMuseHarnessConstraintWithLegacyQM(t *testing.T) {
	db, err := sql.Open("sqlite", "file:"+filepath.Join(t.TempDir(), "opr.db")+pragmas)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	db.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = db.Close() })
	upTo(t, db, 43)

	if _, err := db.Exec(`PRAGMA writable_schema = ON`); err != nil {
		t.Fatalf("enable writable_schema: %v", err)
	}
	if _, err := db.Exec(
		`UPDATE sqlite_master
SET sql = replace(sql, ?, ?)
WHERE type = 'table' AND name = 'sessions'`,
		`CHECK (harness IN ('', 'claude-code', 'codex', 'aider', 'opencode', 'grok', 'droid', 'amp', 'agy', 'crush', 'cursor', 'qwen', 'copilot', 'goose', 'auggie', 'continue', 'devin', 'cline', 'kimi', 'kiro', 'kilocode', 'vibe', 'pi', 'autohand', 'fake'))`,
		`CHECK (harness IN ('', 'claude-code', 'codex', 'aider', 'opencode', 'grok', 'droid', 'amp', 'agy', 'crush', 'cursor', 'qwen', 'copilot', 'goose', 'auggie', 'continue', 'devin', 'cline', 'kimi', 'kiro', 'kilocode', 'vibe', 'pi', 'autohand', 'qm', 'fake'))`,
	); err != nil {
		t.Fatalf("seed legacy qm harness constraint: %v", err)
	}
	if _, err := db.Exec(`PRAGMA writable_schema = RESET`); err != nil {
		t.Fatalf("reparse legacy qm harness constraint: %v", err)
	}
	for version := 44; version <= 53; version++ {
		if _, err := db.Exec(
			`INSERT INTO goose_db_version (version_id, is_applied) VALUES (?, 1)`, version,
		); err != nil {
			t.Fatalf("seed migration %d: %v", version, err)
		}
	}

	if err := migrate(db); err != nil {
		t.Fatalf("migrate skipped muse harness schema with legacy qm: %v", err)
	}
	var schema string
	if err := db.QueryRow(
		"SELECT sql FROM sqlite_master WHERE type='table' AND name='sessions'",
	).Scan(&schema); err != nil {
		t.Fatalf("read sessions schema: %v", err)
	}
	for _, harness := range []string{"'muse'", "'qm'", "'kimchi'"} {
		if !strings.Contains(schema, harness) {
			t.Fatalf("sessions.harness CHECK is missing %s after repair:\n%s", harness, schema)
		}
	}
}

// TestMigration0054AddsKimchiToLegacyQMConstraint seeds a QM-variant constraint
// (the legacy constraint that includes 'qm' alongside 'muse') and runs only
// migration 0054, asserting that the QM replace pair inserted 'kimchi' into
// the constraint. Without the QM pair, the replace() source string omits 'qm'
// and no-ops, leaving Kimchi inserts to fail with a CHECK violation.
func TestMigration0054AddsKimchiToLegacyQMConstraint(t *testing.T) {
	db, err := sql.Open("sqlite", "file:"+filepath.Join(t.TempDir(), "opr.db")+pragmas)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	db.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = db.Close() })
	upTo(t, db, 53)

	// Simulate a legacy QM-variant database: swap the constraint from the
	// post-0053 state (muse, no qm) to the QM variant (muse, qm, no kimchi).
	if _, err := db.Exec(`PRAGMA writable_schema = ON`); err != nil {
		t.Fatalf("enable writable_schema: %v", err)
	}
	if _, err := db.Exec(
		`UPDATE sqlite_master
SET sql = replace(sql, ?, ?)
WHERE type = 'table' AND name = 'sessions'`,
		sessionsHarnessCheckWithMuse,
		sessionsHarnessCheckWithMuseQM,
	); err != nil {
		t.Fatalf("seed legacy qm harness constraint: %v", err)
	}
	if _, err := db.Exec(`PRAGMA writable_schema = RESET`); err != nil {
		t.Fatalf("reparse legacy qm harness constraint: %v", err)
	}

	// Run only migration 0054 (versions 1–53 are already applied).
	upTo(t, db, 54)

	var schema string
	if err := db.QueryRow(
		"SELECT sql FROM sqlite_master WHERE type='table' AND name='sessions'",
	).Scan(&schema); err != nil {
		t.Fatalf("read sessions schema: %v", err)
	}
	for _, harness := range []string{"'muse'", "'qm'", "'kimchi'"} {
		if !strings.Contains(schema, harness) {
			t.Fatalf("sessions.harness CHECK is missing %s after migration 0054:\n%s", harness, schema)
		}
	}
}

// TestMigrateRepairsKimchiConstraintBeforeClearingPrimeAgentSession reproduces
// the shared dev profile where the physical harness constraint drifted. Startup
// must repair the schema before the pre-release data reset runs.
func TestMigrateRepairsKimchiConstraintBeforeClearingPrimeAgentSession(t *testing.T) {
	db, err := sql.Open("sqlite", "file:"+filepath.Join(t.TempDir(), "opr.db")+pragmas)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	db.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = db.Close() })
	upTo(t, db, 80)

	const primeAgentQMConstraint = `CHECK (harness IN ('', 'claude-code', 'codex', 'aider', 'opencode', 'grok', 'droid', 'amp', 'agy', 'crush', 'cursor', 'qwen', 'copilot', 'goose', 'auggie', 'continue', 'devin', 'cline', 'kimi', 'muse', 'kiro', 'kilocode', 'vibe', 'pi', 'autohand', 'qm', 'prime-agent', 'fake'))`
	if _, err := db.Exec(`PRAGMA writable_schema = ON`); err != nil {
		t.Fatalf("enable writable_schema: %v", err)
	}
	if _, err := db.Exec(
		`UPDATE sqlite_master
SET sql = replace(sql, ?, ?)
WHERE type = 'table' AND name = 'sessions'`,
		sessionsHarnessCheckWithMuseKimchi,
		primeAgentQMConstraint,
	); err != nil {
		t.Fatalf("seed prime-agent qm harness constraint: %v", err)
	}
	if _, err := db.Exec(`PRAGMA writable_schema = RESET`); err != nil {
		t.Fatalf("reparse prime-agent qm harness constraint: %v", err)
	}

	if _, err := db.Exec(`
INSERT INTO projects (id, path, registered_at, config)
VALUES ('operator', '/repo/operator', ?, '{}');
INSERT INTO sessions (id, project_id, num, harness, activity_last_at, created_at, updated_at)
VALUES ('operator-1', 'operator', 1, 'prime-agent', ?, ?, ?);
`, time.Unix(100, 0).UTC(), time.Unix(101, 0).UTC(), time.Unix(101, 0).UTC(), time.Unix(101, 0).UTC()); err != nil {
		t.Fatalf("seed prime-agent session: %v", err)
	}
	for _, version := range []int{81, 82, 83} {
		if _, err := db.Exec(
			`INSERT INTO goose_db_version (version_id, is_applied) VALUES (?, 1)`, version,
		); err != nil {
			t.Fatalf("seed migration %d: %v", version, err)
		}
	}

	if err := migrate(db); err != nil {
		t.Fatalf("migrate prime-agent qm profile: %v", err)
	}
	var schema string
	if err := db.QueryRow(
		"SELECT sql FROM sqlite_master WHERE type='table' AND name='sessions'",
	).Scan(&schema); err != nil {
		t.Fatalf("read sessions schema: %v", err)
	}
	for _, harness := range []string{"'muse'", "'qm'", "'kimchi'", "'prime-agent'"} {
		if !strings.Contains(schema, harness) {
			t.Fatalf("sessions.harness CHECK is missing %s after repair:\n%s", harness, schema)
		}
	}
	var primeAgentSessions int
	if err := db.QueryRow(`SELECT COUNT(*) FROM sessions WHERE harness = 'prime-agent'`).Scan(&primeAgentSessions); err != nil {
		t.Fatalf("count prime-agent sessions: %v", err)
	}
	if primeAgentSessions != 0 {
		t.Fatalf("prime-agent sessions after pre-release clear = %d, want 0", primeAgentSessions)
	}
}

func TestOpenReadOnlyDoesNotCreateDatabase(t *testing.T) {
	dataDir := filepath.Join(t.TempDir(), "missing")
	if _, err := OpenReadOnly(context.Background(), dataDir); err == nil {
		t.Fatal("OpenReadOnly succeeded for missing database")
	}
	if _, err := os.Stat(dataDir); !os.IsNotExist(err) {
		t.Fatalf("data dir stat err = %v, want not exist", err)
	}
}

func TestOpenReadOnlyDoesNotMigrate(t *testing.T) {
	dataDir := t.TempDir()
	db, err := sql.Open("sqlite", "file:"+filepath.Join(dataDir, "opr.db")+pragmas)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	if _, err := db.Exec(`
CREATE TABLE projects (
    id TEXT PRIMARY KEY,
    path TEXT NOT NULL,
    repo_origin_url TEXT NOT NULL DEFAULT '',
    display_name TEXT NOT NULL DEFAULT '',
    registered_at TIMESTAMP NOT NULL,
    archived_at TIMESTAMP
);
INSERT INTO projects (id, path, registered_at) VALUES ('alpha', '/repos/alpha', ?);
`, time.Unix(100, 0).UTC()); err != nil {
		_ = db.Close()
		t.Fatalf("seed old schema: %v", err)
	}
	if err := db.Close(); err != nil {
		t.Fatalf("close seed db: %v", err)
	}

	store, err := OpenReadOnly(context.Background(), dataDir)
	if err != nil {
		t.Fatalf("OpenReadOnly: %v", err)
	}
	t.Cleanup(func() { _ = store.Close() })

	_, err = store.ListProjects(context.Background())
	if err == nil || !strings.Contains(err.Error(), "no such column") {
		t.Fatalf("ListProjects err = %v, want old-schema column failure", err)
	}

	checkDB, err := sql.Open("sqlite", "file:"+filepath.Join(dataDir, "opr.db")+pragmas)
	if err != nil {
		t.Fatalf("open check db: %v", err)
	}
	defer func() { _ = checkDB.Close() }()

	var schema string
	if err := checkDB.QueryRow(
		"SELECT sql FROM sqlite_master WHERE type='table' AND name='projects'",
	).Scan(&schema); err != nil {
		t.Fatalf("read projects schema: %v", err)
	}
	if strings.Contains(schema, "config") || strings.Contains(schema, "kind") {
		t.Fatalf("OpenReadOnly migrated projects schema:\n%s", schema)
	}
}
