package sqlite

import (
	"database/sql"
	"path/filepath"
	"testing"

	"github.com/pressly/goose/v3"
)

func downTo(t *testing.T, db *sql.DB, version int64) {
	t.Helper()
	gooseMu.Lock()
	defer gooseMu.Unlock()
	goose.SetBaseFS(migrationsFS)
	goose.SetLogger(goose.NopLogger())
	if err := goose.SetDialect("sqlite3"); err != nil {
		t.Fatalf("set dialect: %v", err)
	}
	if err := goose.DownTo(db, "migrations", version); err != nil {
		t.Fatalf("migrate down to %d: %v", version, err)
	}
}

func TestMigration0117DownSucceedsWhenAResolvedUnreadRowCoexistsWithANewerOpenRow(t *testing.T) {
	db, err := sql.Open("sqlite", "file:"+filepath.Join(t.TempDir(), "opr.db")+"?_pragma=busy_timeout(5000)")
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })

	upTo(t, db, 117)

	if _, err := db.Exec(
		`INSERT INTO projects (id, path, registered_at) VALUES ('proj-1', '/proj', '2026-09-01T00:00:00Z')`,
	); err != nil {
		t.Fatalf("seed project: %v", err)
	}
	if _, err := db.Exec(
		`INSERT INTO sessions (id, project_id, num, activity_last_at, workspace_mode, created_at, updated_at)
		 VALUES ('sess-1', 'proj-1', 1, '2026-09-01T00:00:00Z', 'worktree', '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z')`,
	); err != nil {
		t.Fatalf("seed session: %v", err)
	}
	if _, err := db.Exec(`
INSERT INTO notifications (id, session_id, project_id, pr_url, type, title, body, status, created_at, resolved_at, quiet)
VALUES
	('ntf-resolved-unread', 'sess-1', 'proj-1', '', 'needs_input', 'old', '', 'unread', '2026-09-01T00:00:00Z', '2026-09-01T01:00:00Z', 0),
	('ntf-open', 'sess-1', 'proj-1', '', 'needs_input', 'new', '', 'unread', '2026-09-01T02:00:00Z', NULL, 0)`,
	); err != nil {
		t.Fatalf("seed notifications: %v", err)
	}

	downTo(t, db, 116)

	var status string
	if err := db.QueryRow(`SELECT status FROM notifications WHERE id = 'ntf-resolved-unread'`).Scan(&status); err != nil {
		t.Fatalf("query resolved row status: %v", err)
	}
	if status != "read" {
		t.Fatalf("resolved-but-unread row status = %q, want read", status)
	}
	var openStatus string
	if err := db.QueryRow(`SELECT status FROM notifications WHERE id = 'ntf-open'`).Scan(&openStatus); err != nil {
		t.Fatalf("query open row status: %v", err)
	}
	if openStatus != "unread" {
		t.Fatalf("open row status = %q, want unread", openStatus)
	}

	if _, err := db.Exec(
		`INSERT INTO notifications (id, session_id, project_id, pr_url, type, title, body, status, created_at)
		 VALUES ('ntf-dup', 'sess-1', 'proj-1', '', 'needs_input', 'dup', '', 'unread', '2026-09-01T03:00:00Z')`,
	); err == nil {
		t.Fatal("expected the restored open-dedupe unique index to reject a duplicate open needs_input row")
	}
}
