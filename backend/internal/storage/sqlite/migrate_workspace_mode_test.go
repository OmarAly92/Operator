package sqlite

import (
	"context"
	"strings"
	"testing"
)

func TestMigration0103AddsWorkspaceModeWithoutDefault(t *testing.T) {
	db := openMigratedTestDB(t)
	var ddl string
	if err := db.QueryRowContext(context.Background(),
		`SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'sessions'`).Scan(&ddl); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(ddl, "workspace_mode") {
		t.Fatalf("sessions is missing workspace_mode:\n%s", ddl)
	}
	if !strings.Contains(ddl, "CHECK") || !strings.Contains(ddl, "in_place") {
		t.Fatalf("workspace_mode must be CHECK-constrained to the two modes:\n%s", ddl)
	}
	if strings.Contains(ddl, "workspace_mode TEXT NOT NULL DEFAULT") {
		t.Fatalf("workspace_mode must have no DEFAULT: %s", ddl)
	}
}

func TestMigration0103RejectsAnUnknownMode(t *testing.T) {
	db := openMigratedTestDB(t)
	_, err := db.ExecContext(context.Background(),
		`INSERT INTO sessions (id, project_id, workspace_mode) VALUES ('s-1', 'p-1', 'nonsense')`)
	if err == nil {
		t.Fatal("want the CHECK constraint to reject an unknown workspace_mode")
	}
}

func TestMigration0102ClearsSessions(t *testing.T) {
	db := openMigratedTestDB(t)
	var count int
	if err := db.QueryRowContext(context.Background(), `SELECT COUNT(*) FROM sessions`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Fatalf("want a cleared sessions table, got %d rows", count)
	}
}
