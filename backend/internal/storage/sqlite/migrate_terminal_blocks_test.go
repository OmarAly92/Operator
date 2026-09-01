package sqlite

import (
	"bytes"
	"database/sql"
	"path/filepath"
	"reflect"
	"testing"
)

func TestMigration0092CreatesTerminalBlocksFrom0091(t *testing.T) {
	db, err := sql.Open("sqlite", "file:"+filepath.Join(t.TempDir(), "opr.db")+pragmas)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	db.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = db.Close() })

	upTo(t, db, 91)

	var terminalBlocksBefore int
	if err := db.QueryRow(
		`SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'terminal_blocks'`,
	).Scan(&terminalBlocksBefore); err != nil {
		t.Fatalf("probe table before: %v", err)
	}
	if terminalBlocksBefore != 0 {
		t.Fatalf("terminal_blocks exists before 0092")
	}

	upTo(t, db, 92)

	got := tableColumns(t, db, "terminal_blocks")
	want := []string{
		"terminal_id", "source_id", "session_id", "command", "cwd", "git_branch",
		"exit_code", "raw_output", "started_at", "finished_at", "shell_kind",
		"shell_version", "truncated_lines", "truncated_bytes", "capture_epoch",
		"start_offset", "end_offset", "created_at",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("terminal_blocks columns = %v, want %v", got, want)
	}

	pk := map[string]bool{}
	rows, err := db.Query(`SELECT name FROM pragma_table_info('terminal_blocks') WHERE pk > 0`)
	if err != nil {
		t.Fatalf("read pk: %v", err)
	}
	defer rows.Close()
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatalf("scan pk: %v", err)
		}
		pk[name] = true
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate pk: %v", err)
	}
	if len(pk) != 2 || !pk["terminal_id"] || !pk["source_id"] {
		t.Fatalf("primary key = %v, want {terminal_id, source_id}", pk)
	}

	indexes := map[string]bool{}
	idxRows, err := db.Query(`SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'terminal_blocks' AND name NOT LIKE 'sqlite_%'`)
	if err != nil {
		t.Fatalf("read indexes: %v", err)
	}
	defer idxRows.Close()
	for idxRows.Next() {
		var name string
		if err := idxRows.Scan(&name); err != nil {
			t.Fatalf("scan index: %v", err)
		}
		indexes[name] = true
	}
	if err := idxRows.Err(); err != nil {
		t.Fatalf("iterate indexes: %v", err)
	}
	if !indexes["terminal_blocks_terminal_finished"] || !indexes["terminal_blocks_session"] {
		t.Fatalf("indexes = %v, want the (terminal_id, finished_at DESC) and partial session_id indexes", indexes)
	}

	var partialIndexSQL string
	if err := db.QueryRow(
		`SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'terminal_blocks_session'`,
	).Scan(&partialIndexSQL); err != nil {
		t.Fatalf("read partial index sql: %v", err)
	}
	if !bytes.Contains([]byte(partialIndexSQL), []byte("WHERE session_id <> ''")) {
		t.Fatalf("terminal_blocks_session is not partial: %q", partialIndexSQL)
	}

	blob := []byte{0x00, 0xff, 0xfe, 0x80, 'a', '\n'}
	if _, err := db.Exec(`
INSERT INTO terminal_blocks (terminal_id, source_id, raw_output, finished_at, capture_epoch, start_offset, end_offset, created_at)
VALUES ('t1', 's1', ?, '2026-08-31T00:00:00Z', 'e1', 0, 10, '2026-08-31T00:00:00Z')`, blob); err != nil {
		t.Fatalf("insert row: %v", err)
	}
	if _, err := db.Exec(`
INSERT INTO terminal_blocks (terminal_id, source_id, raw_output, finished_at, capture_epoch, start_offset, end_offset, created_at)
VALUES ('t1', 's1', ?, '2026-08-31T01:00:00Z', 'e2', 0, 20, '2026-08-31T00:00:00Z')
ON CONFLICT (terminal_id, source_id) DO UPDATE SET raw_output = excluded.raw_output, end_offset = excluded.end_offset`, []byte("replaced")); err != nil {
		t.Fatalf("upsert row: %v", err)
	}

	var count, endOffset int
	var stored []byte
	if err := db.QueryRow(`SELECT COUNT(*), MAX(end_offset) FROM terminal_blocks WHERE terminal_id = 't1'`).Scan(&count, &endOffset); err != nil {
		t.Fatalf("count rows: %v", err)
	}
	if count != 1 || endOffset != 20 {
		t.Fatalf("after upsert: count = %d, end_offset = %d, want 1 and 20", count, endOffset)
	}
	if err := db.QueryRow(`SELECT raw_output FROM terminal_blocks WHERE terminal_id = 't1' AND source_id = 's1'`).Scan(&stored); err != nil {
		t.Fatalf("read raw_output: %v", err)
	}
	if !bytes.Equal(stored, []byte("replaced")) {
		t.Fatalf("raw_output = %q, want replaced", stored)
	}

	var nullExit sql.NullInt64
	if err := db.QueryRow(`SELECT exit_code FROM terminal_blocks WHERE terminal_id = 't1' AND source_id = 's1'`).Scan(&nullExit); err != nil {
		t.Fatalf("read exit_code: %v", err)
	}
	if nullExit.Valid {
		t.Fatalf("exit_code = %v, want NULL", nullExit)
	}
}
