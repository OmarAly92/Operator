package terminalblock_test

import (
	"bytes"
	"context"
	"fmt"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/service/terminalblock"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/sqlitetest"
)

func newService(t *testing.T) (*terminalblock.Service, *sqlite.Store) {
	t.Helper()
	st := sqlitetest.MustOpen(t)
	return terminalblock.NewService(st), st
}

func sampleBlock(terminalID, sourceID string, finishedAt time.Time) domain.Block {
	code := 0
	return domain.Block{
		TerminalID:   terminalID,
		SourceID:     sourceID,
		SessionID:    "sess-1",
		Command:      "echo hi",
		Cwd:          "/repo",
		GitBranch:    "main",
		ExitCode:     &code,
		RawOutput:    []byte("hi\n"),
		StartedAt:    finishedAt.Add(-time.Second),
		FinishedAt:   finishedAt,
		ShellKind:    "bash",
		ShellVersion: "5.2",
		CaptureEpoch: "epoch-1",
		StartOffset:  10,
		EndOffset:    42,
		CreatedAt:    finishedAt,
	}
}

func TestRecordInsertAndHistory(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)

	in := sampleBlock("term-1", "1", time.Unix(1000, 0).UTC())
	if err := svc.Record(ctx, in); err != nil {
		t.Fatalf("record: %v", err)
	}

	got, err := svc.History(ctx, "term-1", 100)
	if err != nil {
		t.Fatalf("history: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("rows = %d, want 1", len(got))
	}
	b := got[0]
	if b.TerminalID != "term-1" || b.SourceID != "1" || b.SessionID != "sess-1" ||
		b.Command != "echo hi" || b.Cwd != "/repo" || b.GitBranch != "main" ||
		b.ShellKind != "bash" || b.ShellVersion != "5.2" || b.CaptureEpoch != "epoch-1" ||
		b.StartOffset != 10 || b.EndOffset != 42 {
		t.Fatalf("row = %+v, metadata did not round-trip", b)
	}
	if b.ExitCode == nil || *b.ExitCode != 0 {
		t.Fatalf("exit code = %v, want 0", b.ExitCode)
	}
	if !bytes.Equal(b.RawOutput, []byte("hi\n")) {
		t.Fatalf("raw output = %q, want %q", b.RawOutput, "hi\n")
	}
	if !b.FinishedAt.Equal(time.Unix(1000, 0).UTC()) {
		t.Fatalf("finished_at = %v", b.FinishedAt)
	}
	if !b.StartedAt.Equal(time.Unix(999, 0).UTC()) {
		t.Fatalf("started_at = %v", b.StartedAt)
	}
}

func TestRecordUpsertIsIdempotent(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)

	first := sampleBlock("term-1", "7", time.Unix(1000, 0).UTC())
	if err := svc.Record(ctx, first); err != nil {
		t.Fatalf("record first: %v", err)
	}

	second := sampleBlock("term-1", "7", time.Unix(2000, 0).UTC())
	second.Command = "ls -la"
	code := 3
	second.ExitCode = &code
	second.RawOutput = []byte("total 0\n")
	if err := svc.Record(ctx, second); err != nil {
		t.Fatalf("record replay: %v", err)
	}

	got, err := svc.History(ctx, "term-1", 100)
	if err != nil {
		t.Fatalf("history: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("rows = %d, want 1 after replay of same (terminal_id, source_id)", len(got))
	}
	b := got[0]
	if b.Command != "ls -la" || b.ExitCode == nil || *b.ExitCode != 3 ||
		!bytes.Equal(b.RawOutput, []byte("total 0\n")) || !b.FinishedAt.Equal(time.Unix(2000, 0).UTC()) {
		t.Fatalf("row = %+v, want the replay's fields", b)
	}
}

func TestRecordNullExitCodeRoundTrips(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)

	in := sampleBlock("term-1", "1", time.Unix(1000, 0).UTC())
	in.ExitCode = nil
	if err := svc.Record(ctx, in); err != nil {
		t.Fatalf("record: %v", err)
	}

	got, err := svc.History(ctx, "term-1", 100)
	if err != nil {
		t.Fatalf("history: %v", err)
	}
	if len(got) != 1 || got[0].ExitCode != nil {
		t.Fatalf("exit code = %v, want nil round-trip", got[0].ExitCode)
	}
}

func TestRecordPreservesNonUTF8Output(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)

	raw := []byte{0xff, 0xfe, 0x00, 0x01, 0x80, 0xc0, 'a', '\n'}
	in := sampleBlock("term-1", "1", time.Unix(1000, 0).UTC())
	in.RawOutput = raw
	if err := svc.Record(ctx, in); err != nil {
		t.Fatalf("record: %v", err)
	}

	got, err := svc.History(ctx, "term-1", 100)
	if err != nil {
		t.Fatalf("history: %v", err)
	}
	if len(got) != 1 || !bytes.Equal(got[0].RawOutput, raw) {
		t.Fatalf("raw output = %v, want the exact non-UTF-8 bytes %v", got[0].RawOutput, raw)
	}
}

func TestHistoryIsChronological(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)

	for _, sec := range []int64{3000, 1000, 2000} {
		in := sampleBlock("term-1", fmt.Sprintf("src-%d", sec), time.Unix(sec, 0).UTC())
		if err := svc.Record(ctx, in); err != nil {
			t.Fatalf("record %d: %v", sec, err)
		}
	}

	got, err := svc.History(ctx, "term-1", 100)
	if err != nil {
		t.Fatalf("history: %v", err)
	}
	if len(got) != 3 {
		t.Fatalf("rows = %d, want 3", len(got))
	}
	for i := 1; i < len(got); i++ {
		if got[i].FinishedAt.Before(got[i-1].FinishedAt) {
			t.Fatalf("history not chronological: %v then %v", got[i-1].FinishedAt, got[i].FinishedAt)
		}
	}
	if !got[0].FinishedAt.Equal(time.Unix(1000, 0).UTC()) || !got[2].FinishedAt.Equal(time.Unix(3000, 0).UTC()) {
		t.Fatalf("history order = %v..%v, want oldest first", got[0].FinishedAt, got[2].FinishedAt)
	}
}

func TestRecordPerTerminalIsolation(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)

	a := sampleBlock("term-A", "1", time.Unix(1000, 0).UTC())
	a.Command = "from A"
	b := sampleBlock("term-B", "1", time.Unix(1000, 0).UTC())
	b.Command = "from B"
	if err := svc.Record(ctx, a); err != nil {
		t.Fatalf("record A: %v", err)
	}
	if err := svc.Record(ctx, b); err != nil {
		t.Fatalf("record B: %v", err)
	}

	gotA, err := svc.History(ctx, "term-A", 100)
	if err != nil {
		t.Fatalf("history A: %v", err)
	}
	gotB, err := svc.History(ctx, "term-B", 100)
	if err != nil {
		t.Fatalf("history B: %v", err)
	}
	if len(gotA) != 1 || gotA[0].Command != "from A" {
		t.Fatalf("term-A history = %+v, want exactly its own row", gotA)
	}
	if len(gotB) != 1 || gotB[0].Command != "from B" {
		t.Fatalf("term-B history = %+v, want exactly its own row", gotB)
	}
}

func TestDeleteTerminalBlocks(t *testing.T) {
	ctx := context.Background()
	svc, st := newService(t)

	if err := svc.Record(ctx, sampleBlock("term-1", "1", time.Unix(1000, 0).UTC())); err != nil {
		t.Fatalf("record: %v", err)
	}
	if err := svc.Record(ctx, sampleBlock("term-2", "1", time.Unix(1000, 0).UTC())); err != nil {
		t.Fatalf("record other: %v", err)
	}

	if err := st.DeleteTerminalBlocks(ctx, "term-1"); err != nil {
		t.Fatalf("delete: %v", err)
	}

	got, err := svc.History(ctx, "term-1", 100)
	if err != nil {
		t.Fatalf("history: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("term-1 rows = %d, want 0 after delete", len(got))
	}
	other, err := svc.History(ctx, "term-2", 100)
	if err != nil {
		t.Fatalf("history other: %v", err)
	}
	if len(other) != 1 {
		t.Fatalf("term-2 rows = %d, want 1 (delete must be scoped)", len(other))
	}
}

func TestRecordTrimsToNewest100(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)

	for i := 0; i < 105; i++ {
		in := sampleBlock("term-1", fmt.Sprintf("src-%03d", i), time.Unix(int64(1000+i), 0).UTC())
		if err := svc.Record(ctx, in); err != nil {
			t.Fatalf("record %d: %v", i, err)
		}
	}

	got, err := svc.History(ctx, "term-1", 1000)
	if err != nil {
		t.Fatalf("history: %v", err)
	}
	if len(got) != 100 {
		t.Fatalf("rows = %d, want 100 after per-terminal retention", len(got))
	}
	if !got[0].FinishedAt.Equal(time.Unix(1005, 0).UTC()) {
		t.Fatalf("oldest retained = %v, want the 6th insert (newest 100 kept)", got[0].FinishedAt)
	}
	if !got[99].FinishedAt.Equal(time.Unix(1104, 0).UTC()) {
		t.Fatalf("newest retained = %v, want the last insert", got[99].FinishedAt)
	}
}

func TestRecordTruncatesTo5000Lines(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)

	var buf bytes.Buffer
	for i := 0; i < 6000; i++ {
		if i > 0 {
			buf.WriteByte('\n')
		}
		fmt.Fprintf(&buf, "line-%04d", i)
	}
	original := append([]byte(nil), buf.Bytes()...)

	in := sampleBlock("term-1", "1", time.Unix(1000, 0).UTC())
	in.RawOutput = original
	if err := svc.Record(ctx, in); err != nil {
		t.Fatalf("record: %v", err)
	}

	got, err := svc.History(ctx, "term-1", 100)
	if err != nil {
		t.Fatalf("history: %v", err)
	}
	b := got[0]
	if lines := bytes.Count(b.RawOutput, []byte{'\n'}) + 1; lines != 5000 {
		t.Fatalf("stored lines = %d, want 5000", lines)
	}
	if b.TruncatedLines != 1000 {
		t.Fatalf("truncated_lines = %d, want 1000", b.TruncatedLines)
	}
	if !bytes.HasPrefix(b.RawOutput, []byte("line-1000\n")) {
		t.Fatalf("stored output must retain the newest lines, starts %q", b.RawOutput[:20])
	}
	if !bytes.HasSuffix(original, b.RawOutput) {
		t.Fatalf("stored output must be a suffix of the original")
	}
	if b.TruncatedBytes != len(original)-len(b.RawOutput) {
		t.Fatalf("truncated_bytes = %d, want %d", b.TruncatedBytes, len(original)-len(b.RawOutput))
	}
}

func TestRecordTruncatesTo8MiBOnRuneBoundary(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)

	const cap8MiB = 8 << 20
	total := cap8MiB + 100
	original := make([]byte, 0, total)
	for i := 0; i < 99; i++ {
		original = append(original, 'a')
	}
	original = append(original, []byte("€")...)
	for len(original) < total {
		original = append(original, 'a')
	}

	in := sampleBlock("term-1", "1", time.Unix(1000, 0).UTC())
	in.RawOutput = append([]byte(nil), original...)
	if err := svc.Record(ctx, in); err != nil {
		t.Fatalf("record: %v", err)
	}

	got, err := svc.History(ctx, "term-1", 100)
	if err != nil {
		t.Fatalf("history: %v", err)
	}
	b := got[0]
	if len(b.RawOutput) > cap8MiB {
		t.Fatalf("stored %d bytes, want <= %d", len(b.RawOutput), cap8MiB)
	}
	if !utf8.Valid(b.RawOutput) {
		t.Fatalf("stored output split a UTF-8 rune")
	}
	if !bytes.HasSuffix(original, b.RawOutput) {
		t.Fatalf("stored output must be a suffix of the original (newest bytes retained)")
	}
	if b.TruncatedBytes != len(original)-len(b.RawOutput) {
		t.Fatalf("truncated_bytes = %d, want %d", b.TruncatedBytes, len(original)-len(b.RawOutput))
	}
	if b.TruncatedBytes != 102 {
		t.Fatalf("truncated_bytes = %d, want 102 (cut at index 100 advanced to the rune boundary at 102)", b.TruncatedBytes)
	}
}
