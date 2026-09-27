package blockretention_test

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/observe/blockretention"
	"github.com/OmarAly92/operator/backend/internal/service/shellterm"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/sqlitetest"
)

func newTestStore(t *testing.T) *sqlite.Store {
	t.Helper()
	return sqlitetest.MustOpen(t)
}

func insertBlock(t *testing.T, store *sqlite.Store, terminalID, sourceID, command string, rawOutput []byte, finishedAt time.Time) {
	t.Helper()
	code := 0
	b := domain.Block{
		TerminalID:   terminalID,
		SourceID:     sourceID,
		SessionID:    "sess-1",
		Command:      command,
		Cwd:          "/repo",
		GitBranch:    "main",
		ExitCode:     &code,
		RawOutput:    rawOutput,
		StartedAt:    finishedAt.Add(-time.Second),
		FinishedAt:   finishedAt,
		ShellKind:    "bash",
		ShellVersion: "5.2",
		CaptureEpoch: "epoch-1",
		StartOffset:  0,
		EndOffset:    int64(len(rawOutput)),
		CreatedAt:    finishedAt,
	}
	if err := store.UpsertTerminalBlock(context.Background(), b); err != nil {
		t.Fatalf("insert block %s/%s: %v", terminalID, sourceID, err)
	}
}

func insertShellTerminal(t *testing.T, store *sqlite.Store, handleID string, createdAt time.Time) {
	t.Helper()
	rec := shellterm.ShellTerminalRecord{
		HandleID:   handleID,
		WorkingDir: "/repo",
		Title:      "shell",
		AppRunID:   "app-run-1",
		CreatedAt:  createdAt,
	}
	if err := store.InsertShellTerminal(context.Background(), rec); err != nil {
		t.Fatalf("insert shell terminal %s: %v", handleID, err)
	}
}

func listCommandRuns(t *testing.T, store *sqlite.Store) ([]string, error) {
	t.Helper()
	runs, err := store.ListRecentTerminalCommands(context.Background(), 100)
	if err != nil {
		return nil, err
	}
	out := make([]string, 0, len(runs))
	for _, run := range runs {
		out = append(out, run.Command)
	}
	return out, nil
}

func TestTickReclaimsRawOutputThenTheRowOnceTheDeleteGraceAlsoPasses(t *testing.T) {
	ctx := context.Background()
	store := newTestStore(t)
	now := time.Date(2026, 9, 27, 12, 0, 0, 0, time.UTC)
	insertBlock(t, store, "closed-term", "1", "make build", []byte("a lot of output"), now.Add(-40*24*time.Hour))

	clock := now
	r := blockretention.New(store, blockretention.Config{Clock: func() time.Time { return clock }})
	cleared, deleted, err := r.Tick(ctx)
	if err != nil {
		t.Fatalf("tick 1: %v", err)
	}
	if cleared != 1 || deleted != 0 {
		t.Fatalf("tick 1 cleared=%d deleted=%d, want 1,0 (raw_output_cleared_at is set to now, so the delete grace has not started yet)", cleared, deleted)
	}
	if runs, err := listCommandRuns(t, store); err != nil || len(runs) != 1 || runs[0] != "make build" {
		t.Fatalf("history right after clearing = %v, err %v, want [make build] (the row survives, only raw_output is gone)", runs, err)
	}

	clock = now.Add(31 * 24 * time.Hour)
	cleared, deleted, err = r.Tick(ctx)
	if err != nil {
		t.Fatalf("tick 2: %v", err)
	}
	if cleared != 0 || deleted != 1 {
		t.Fatalf("tick 2 cleared=%d deleted=%d, want 0,1 (31 days past the clear, past the row-delete grace)", cleared, deleted)
	}
	runs, err := listCommandRuns(t, store)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(runs) != 0 {
		t.Fatalf("history after full retention = %v, want empty (row deleted)", runs)
	}
}

func TestTickKeepsCommandHistoryOfARecentlyClearedTerminal(t *testing.T) {
	ctx := context.Background()
	store := newTestStore(t)
	now := time.Date(2026, 9, 27, 12, 0, 0, 0, time.UTC)
	insertBlock(t, store, "closed-term", "1", "make build", []byte("output"), now.Add(-8*24*time.Hour))

	r := blockretention.New(store, blockretention.Config{Clock: func() time.Time { return now }})
	cleared, deleted, err := r.Tick(ctx)
	if err != nil {
		t.Fatalf("tick: %v", err)
	}
	if cleared != 1 || deleted != 0 {
		t.Fatalf("cleared=%d deleted=%d, want 1,0", cleared, deleted)
	}
	runs, err := listCommandRuns(t, store)
	if err != nil || len(runs) != 1 || runs[0] != "make build" {
		t.Fatalf("history = %v, err %v, want [make build]", runs, err)
	}
}

func TestTickNeverTouchesARestorableTerminal(t *testing.T) {
	ctx := context.Background()
	store := newTestStore(t)
	now := time.Date(2026, 9, 27, 12, 0, 0, 0, time.UTC)
	insertShellTerminal(t, store, "open-term", now.Add(-90*24*time.Hour))
	insertBlock(t, store, "open-term", "1", "make build", []byte("output"), now.Add(-90*24*time.Hour))

	r := blockretention.New(store, blockretention.Config{Clock: func() time.Time { return now }})
	cleared, deleted, err := r.Tick(ctx)
	if err != nil {
		t.Fatalf("tick: %v", err)
	}
	if cleared != 0 || deleted != 0 {
		t.Fatalf("cleared=%d deleted=%d, want 0,0 (the terminal still has a shell_terminals row)", cleared, deleted)
	}
}
