package sqlite

import (
	"database/sql"
	"path/filepath"
	"strings"
	"testing"
)

func openMigrationDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite", "file:"+filepath.Join(t.TempDir(), "opr.db")+"?_pragma=foreign_keys(1)")
	if err != nil {
		t.Fatal(err)
	}
	db.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = db.Close() })
	return db
}

func seedProjectAndSessions(t *testing.T, db *sql.DB) {
	t.Helper()
	if _, err := db.Exec(`INSERT INTO projects (id, path, registered_at) VALUES ('p', '/tmp/p', datetime('now'))`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO sessions (id, project_id, num, kind, activity_last_at, created_at, updated_at, workspace_mode)
		VALUES ('w1', 'p', 1, 'worker', datetime('now'), datetime('now'), datetime('now'), 'worktree')`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO sessions (id, project_id, num, kind, activity_last_at, created_at, updated_at, workspace_mode)
		VALUES ('o1', 'p', 2, 'orchestrator', datetime('now'), datetime('now'), datetime('now'), 'worktree')`); err != nil {
		t.Fatal(err)
	}
}

func TestMigrate0116DropsOrchestratorColumnsAndRows(t *testing.T) {
	db := openMigrationDB(t)
	upTo(t, db, 115)
	seedProjectAndSessions(t, db)
	upTo(t, db, 116)

	for _, col := range []string{"kind", "spawned_by"} {
		var n int
		if err := db.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('sessions') WHERE name = ?`, col).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 0 {
			t.Fatalf("sessions.%s still exists", col)
		}
	}

	var ids string
	if err := db.QueryRow(`SELECT group_concat(id) FROM sessions`).Scan(&ids); err != nil {
		t.Fatal(err)
	}
	if ids != "w1" {
		t.Fatalf("sessions after migrate = %q, want \"w1\" (orchestrator row must be deleted)", ids)
	}

	var n int
	if err := db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'orchestrator_inbox'`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatal("orchestrator_inbox table must be dropped")
	}

	var integrity string
	if err := db.QueryRow(`PRAGMA integrity_check`).Scan(&integrity); err != nil {
		t.Fatal(err)
	}
	if integrity != "ok" {
		t.Fatalf("integrity_check = %s", integrity)
	}
}

func TestMigrate0116PreservesSessionCDCTriggers(t *testing.T) {
	db := openMigrationDB(t)
	upTo(t, db, 115)
	seedProjectAndSessions(t, db)
	upTo(t, db, 116)

	for _, name := range []string{"sessions_cdc_insert", "sessions_cdc_update", "sessions_cdc_delete"} {
		var n int
		if err := db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND name = ?`, name).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 1 {
			t.Fatalf("trigger %s missing after migrate", name)
		}
	}

	if _, err := db.Exec(`DELETE FROM change_log`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE sessions SET activity_state = 'waiting_input' WHERE id = 'w1'`); err != nil {
		t.Fatal(err)
	}
	var eventType, payload string
	if err := db.QueryRow(`SELECT event_type, payload FROM change_log ORDER BY seq DESC LIMIT 1`).Scan(&eventType, &payload); err != nil {
		t.Fatal("no change_log row after activity update; mobile and Kanban liveness is broken: " + err.Error())
	}
	if eventType != "session_updated" {
		t.Fatalf("event_type = %s, want session_updated", eventType)
	}
	if !strings.Contains(payload, `"activity":"waiting_input"`) || !strings.Contains(payload, `"isTerminated"`) {
		t.Fatalf("payload missing activity/isTerminated: %s", payload)
	}

	if _, err := db.Exec(`DELETE FROM change_log`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE sessions SET is_terminated = 1 WHERE id = 'w1'`); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT event_type FROM change_log ORDER BY seq DESC LIMIT 1`).Scan(&eventType); err != nil {
		t.Fatal(err)
	}
	if eventType != "session_updated" {
		t.Fatalf("termination event_type = %s, want session_updated", eventType)
	}

	// sessions_cdc_insert: inserting a new session row fires session_created
	// with the id/activity/isTerminated payload the board and mobile expect.
	if _, err := db.Exec(`DELETE FROM change_log`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO sessions (id, project_id, num, activity_last_at, created_at, updated_at, workspace_mode)
		VALUES ('w2', 'p', 3, datetime('now'), datetime('now'), datetime('now'), 'worktree')`); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT event_type, payload FROM change_log ORDER BY seq DESC LIMIT 1`).Scan(&eventType, &payload); err != nil {
		t.Fatal("no change_log row after insert; sessions_cdc_insert is broken: " + err.Error())
	}
	if eventType != "session_created" {
		t.Fatalf("insert event_type = %s, want session_created", eventType)
	}
	if !strings.Contains(payload, `"id":"w2"`) || !strings.Contains(payload, `"isTerminated"`) {
		t.Fatalf("insert payload missing id/isTerminated: %s", payload)
	}

	// sessions_cdc_delete: deleting a session row fires session_deleted with
	// the deleted id, so subscribers can drop it from their in-memory state.
	if _, err := db.Exec(`DELETE FROM change_log`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`DELETE FROM sessions WHERE id = 'w2'`); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT event_type, payload FROM change_log ORDER BY seq DESC LIMIT 1`).Scan(&eventType, &payload); err != nil {
		t.Fatal("no change_log row after delete; sessions_cdc_delete is broken: " + err.Error())
	}
	if eventType != "session_deleted" {
		t.Fatalf("delete event_type = %s, want session_deleted", eventType)
	}
	if !strings.Contains(payload, `"id":"w2"`) {
		t.Fatalf("delete payload missing id: %s", payload)
	}
}
