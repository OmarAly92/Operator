package sqlite

import (
	"database/sql"
	"path/filepath"
	"testing"
)

func TestBoardCDCMigrationPreservesHistoryAndSequence(t *testing.T) {
	db, err := sql.Open("sqlite", "file:"+filepath.Join(t.TempDir(), "opr.db")+"?_pragma=foreign_keys(1)")
	if err != nil {
		t.Fatal(err)
	}
	db.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = db.Close() })
	upTo(t, db, 107)
	if _, err := db.Exec(`INSERT INTO projects (id, path, registered_at) VALUES ('p', '/tmp/p', datetime('now'))`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO change_log (seq, project_id, event_type, payload) VALUES (42, 'p', 'session_updated', '{"existing":true}')`); err != nil {
		t.Fatal(err)
	}
	upTo(t, db, 108)
	var payload string
	if err := db.QueryRow(`SELECT payload FROM change_log WHERE seq = 42`).Scan(&payload); err != nil {
		t.Fatal(err)
	}
	if payload != `{"existing":true}` {
		t.Fatalf("history changed: %s", payload)
	}
	if _, err := db.Exec(`UPDATE projects SET display_name = 'Renamed' WHERE id = 'p'`); err != nil {
		t.Fatal(err)
	}
	var seq int64
	var eventType string
	if err := db.QueryRow(`SELECT seq, event_type FROM change_log ORDER BY seq DESC LIMIT 1`).Scan(&seq, &eventType); err != nil {
		t.Fatal(err)
	}
	if seq != 43 || eventType != "project_updated" {
		t.Fatalf("new event = %d, %s", seq, eventType)
	}
	if _, err := db.Exec(`INSERT INTO change_log (project_id, event_type, payload) VALUES ('p', 'unknown', '{}')`); err == nil {
		t.Fatal("unknown event type must remain invalid")
	}
	var integrity string
	if err := db.QueryRow(`PRAGMA integrity_check`).Scan(&integrity); err != nil {
		t.Fatal(err)
	}
	if integrity != "ok" {
		t.Fatalf("integrity: %s", integrity)
	}
}
