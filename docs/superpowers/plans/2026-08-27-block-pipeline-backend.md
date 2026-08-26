# Block Pipeline (Backend) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture the rich agent hook payloads the daemon currently discards, redact secrets from them, persist them as a bounded per-session log, and stream them to clients over the existing mux socket.

**Architecture:** Hook callbacks already reach `POST /api/v1/sessions/{id}/activity` and are collapsed into a single `ActivityState` string. A new service becomes a third consumer of the same decoded `ports.ActivitySignal`, alongside `c.Activity` and `c.Usage`. It normalizes the harness-native event name into a shared vocabulary, redacts secrets, appends to a bounded sqlite log, and publishes to a new `blocks` channel on `/mux`. No UI changes and no existing behaviour changes.

**Tech Stack:** Go, sqlc + goose migrations, chi router, the existing `/mux` WebSocket manager.

**Spec:** `docs/superpowers/specs/2026-08-27-session-blocks-design.md`

## Global Constraints

- No comments in new code unless the surrounding file already comments heavily; this repo's Go files do document exported types, so match the local density.
- `npm run lint` (backend `go test ./...` + golangci-lint v2.12.2) must pass. From `backend/`: `go build ./...` and `go test ./...`.
- Regenerate sqlc with `npm run sqlc` from the repo root after touching `queries/` or `migrations/`. Never hand-edit `backend/internal/storage/sqlite/gen/`.
- Migrations are goose-numbered; the next free number is **0090**.
- API contract changes go through `npm run api`. This plan adds no REST surface, so that is not needed.
- Redaction happens **daemon-side, before persistence or transmission**. No task may persist or publish unredacted text.
- Every event retains an unknown variant rather than being dropped. A harness update must degrade to less detail, never to a gap.
- Block ids are minted at the source and never invented by a consumer.

---

### Task 1: Normalized block-event vocabulary

**Files:**
- Create: `backend/internal/domain/blockevent.go`
- Test: `backend/internal/domain/blockevent_test.go`

**Interfaces:**
- Consumes: nothing.
- Produces: `domain.BlockEventKind` (string type), the nine constants below, `domain.BlockEventUnknown`, and `func ParseBlockEventKind(s string) (BlockEventKind, bool)`.

- [ ] **Step 1: Write the failing test**

```go
package domain

import "testing"

func TestParseBlockEventKind(t *testing.T) {
	tests := []struct {
		in   string
		want BlockEventKind
		ok   bool
	}{
		{"session_start", BlockEventSessionStart, true},
		{"prompt_submit", BlockEventPromptSubmit, true},
		{"tool_complete", BlockEventToolComplete, true},
		{"stop", BlockEventStop, true},
		{"stop_failure", BlockEventStopFailure, true},
		{"permission_request", BlockEventPermissionRequest, true},
		{"permission_replied", BlockEventPermissionReplied, true},
		{"question_asked", BlockEventQuestionAsked, true},
		{"idle_prompt", BlockEventIdlePrompt, true},
		{"something_new", BlockEventUnknown, false},
		{"", BlockEventUnknown, false},
	}
	for _, tt := range tests {
		got, ok := ParseBlockEventKind(tt.in)
		if got != tt.want || ok != tt.ok {
			t.Fatalf("ParseBlockEventKind(%q) = %q,%v want %q,%v", tt.in, got, ok, tt.want, tt.ok)
		}
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/domain/ -run TestParseBlockEventKind -v`
Expected: FAIL — `undefined: BlockEventKind`

- [ ] **Step 3: Write minimal implementation**

```go
package domain

// BlockEventKind is the harness-independent vocabulary a block event is
// normalized into. Harness-native names are mapped onto it by per-harness
// mappers; an unrecognized name becomes BlockEventUnknown and keeps its raw
// name alongside, so a harness update degrades to less detail rather than a gap.
type BlockEventKind string

const (
	BlockEventSessionStart      BlockEventKind = "session_start"
	BlockEventPromptSubmit      BlockEventKind = "prompt_submit"
	BlockEventToolComplete      BlockEventKind = "tool_complete"
	BlockEventStop              BlockEventKind = "stop"
	BlockEventStopFailure       BlockEventKind = "stop_failure"
	BlockEventPermissionRequest BlockEventKind = "permission_request"
	BlockEventPermissionReplied BlockEventKind = "permission_replied"
	BlockEventQuestionAsked     BlockEventKind = "question_asked"
	BlockEventIdlePrompt        BlockEventKind = "idle_prompt"
	BlockEventUnknown           BlockEventKind = "unknown"
)

// ParseBlockEventKind resolves a normalized name. ok=false means the caller
// must keep the raw name on the event and emit BlockEventUnknown.
func ParseBlockEventKind(s string) (BlockEventKind, bool) {
	switch BlockEventKind(s) {
	case BlockEventSessionStart, BlockEventPromptSubmit, BlockEventToolComplete,
		BlockEventStop, BlockEventStopFailure, BlockEventPermissionRequest,
		BlockEventPermissionReplied, BlockEventQuestionAsked, BlockEventIdlePrompt:
		return BlockEventKind(s), true
	default:
		return BlockEventUnknown, false
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/domain/ -run TestParseBlockEventKind -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/domain/blockevent.go backend/internal/domain/blockevent_test.go
git commit -m "feat(backend): add normalized block-event vocabulary"
```

---

### Task 2: Per-harness event mappers

**Files:**
- Create: `backend/internal/adapters/agent/blockdispatch/dispatch.go`
- Test: `backend/internal/adapters/agent/blockdispatch/dispatch_test.go`

**Interfaces:**
- Consumes: `domain.BlockEventKind`, `domain.ParseBlockEventKind` from Task 1.
- Produces: `blockdispatch.MapFunc`, `blockdispatch.Mappers` (a `map[string]MapFunc`), and `func Map(harness, event string) (domain.BlockEventKind, bool)`.

Mirror `adapters/agent/activitydispatch/dispatch.go` in shape: a package-level registry keyed by the agent token used in `opr hooks <agent> <event>`. Claude Code's hook names come from `claudecode/hooks.go`; Codex's from `codex/hooks.go`.

- [ ] **Step 1: Write the failing test**

```go
package blockdispatch

import (
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestMap(t *testing.T) {
	tests := []struct {
		harness string
		event   string
		want    domain.BlockEventKind
		ok      bool
	}{
		{"claude-code", "user-prompt-submit", domain.BlockEventPromptSubmit, true},
		{"claude-code", "post-tool-use", domain.BlockEventToolComplete, true},
		{"claude-code", "permission-request", domain.BlockEventPermissionRequest, true},
		{"claude-code", "stop", domain.BlockEventStop, true},
		{"claude-code", "session-start", domain.BlockEventSessionStart, true},
		{"claude-code", "brand-new-hook", domain.BlockEventUnknown, false},
		{"codex", "user-prompt-submit", domain.BlockEventPromptSubmit, true},
		{"codex", "permission-request", domain.BlockEventPermissionRequest, true},
		{"unregistered-harness", "stop", domain.BlockEventUnknown, false},
	}
	for _, tt := range tests {
		got, ok := Map(tt.harness, tt.event)
		if got != tt.want || ok != tt.ok {
			t.Fatalf("Map(%q,%q) = %q,%v want %q,%v", tt.harness, tt.event, got, ok, tt.want, tt.ok)
		}
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/adapters/agent/blockdispatch/ -v`
Expected: FAIL — package does not exist

- [ ] **Step 3: Write minimal implementation**

```go
// Package blockdispatch maps the agent token and event name in
// `opr hooks <agent> <event>` onto the normalized block-event vocabulary.
// It deliberately mirrors activitydispatch: an adapter that installs hooks
// without registering a mapper here still reports activity, it simply
// contributes no blocks.
package blockdispatch

import "github.com/OmarAly92/operator/backend/internal/domain"

// MapFunc resolves one harness's native hook name. ok=false means the event is
// unknown to this harness's mapper and must be carried through as
// domain.BlockEventUnknown with its raw name preserved.
type MapFunc func(event string) (domain.BlockEventKind, bool)

func fromTable(table map[string]domain.BlockEventKind) MapFunc {
	return func(event string) (domain.BlockEventKind, bool) {
		kind, found := table[event]
		if !found {
			return domain.BlockEventUnknown, false
		}
		return kind, true
	}
}

var claudeCodeEvents = map[string]domain.BlockEventKind{
	"session-start":         domain.BlockEventSessionStart,
	"user-prompt-submit":    domain.BlockEventPromptSubmit,
	"post-tool-use":         domain.BlockEventToolComplete,
	"post-tool-use-failure": domain.BlockEventToolComplete,
	"permission-request":    domain.BlockEventPermissionRequest,
	"stop":                  domain.BlockEventStop,
	"notification":          domain.BlockEventQuestionAsked,
}

var codexEvents = map[string]domain.BlockEventKind{
	"session-start":      domain.BlockEventSessionStart,
	"user-prompt-submit": domain.BlockEventPromptSubmit,
	"permission-request": domain.BlockEventPermissionRequest,
	"stop":               domain.BlockEventStop,
}

// Mappers is keyed by the agent token in `opr hooks <agent> <event>`.
var Mappers = map[string]MapFunc{
	"claude-code": fromTable(claudeCodeEvents),
	"grok":        fromTable(claudeCodeEvents),
	"codex":       fromTable(codexEvents),
}

// Map resolves harness and event. An unregistered harness yields
// BlockEventUnknown so the caller can record the event without inventing a kind.
func Map(harness, event string) (domain.BlockEventKind, bool) {
	mapper, found := Mappers[harness]
	if !found {
		return domain.BlockEventUnknown, false
	}
	return mapper(event)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/adapters/agent/blockdispatch/ -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/adapters/agent/blockdispatch/
git commit -m "feat(backend): map harness hook names onto the block vocabulary"
```

---

### Task 3: Secret redaction

**Files:**
- Create: `backend/internal/redact/redact.go`
- Test: `backend/internal/redact/redact_test.go`

**Interfaces:**
- Consumes: nothing.
- Produces: `redact.Span{Start, End int}`, `redact.Result{Text string, Spans []Span}`, and `func Text(s string) Result`.

Spans are marked and the matched run is replaced with a fixed-width mask, so the UI can show that something was removed rather than silently altering output. Offsets in `Spans` index the **returned** `Text`.

- [ ] **Step 1: Write the failing test**

```go
package redact

import "testing"

func TestTextRedactsKnownSecretShapes(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{"aws access key", "key=AKIAIOSFODNN7EXAMPLE done", "key=[redacted] done"},
		{"github token", "ghp_0123456789abcdefghijklmnopqrstuvwxyz", "[redacted]"},
		{"bearer header", "Authorization: Bearer abc.def.ghijklmnop", "Authorization: Bearer [redacted]"},
		{"url password", "https://user:hunter2@example.com/x", "https://user:[redacted]@example.com/x"},
		{"nothing to do", "ls -la /tmp", "ls -la /tmp"},
	}
	for _, tt := range tests {
		got := Text(tt.in)
		if got.Text != tt.want {
			t.Fatalf("%s: Text(%q).Text = %q want %q", tt.name, tt.in, got.Text, tt.want)
		}
	}
}

func TestTextReportsSpansIntoReturnedText(t *testing.T) {
	got := Text("key=AKIAIOSFODNN7EXAMPLE done")
	if len(got.Spans) != 1 {
		t.Fatalf("Spans = %v, want exactly one", got.Spans)
	}
	if got.Text[got.Spans[0].Start:got.Spans[0].End] != mask {
		t.Fatalf("span %v does not cover the mask in %q", got.Spans[0], got.Text)
	}
}

func TestTextLeavesEmptyInputAlone(t *testing.T) {
	got := Text("")
	if got.Text != "" || len(got.Spans) != 0 {
		t.Fatalf("Text(\"\") = %+v, want empty", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/redact/ -v`
Expected: FAIL — package does not exist

- [ ] **Step 3: Write minimal implementation**

```go
// Package redact removes secret-shaped runs from text before it is persisted
// or transmitted. Operator's blocks leave the machine that produced them —
// they cross a WebSocket to a phone and land in sqlite — so redaction must
// happen here, daemon-side, and never in a client.
//
// Matches are replaced with a fixed mask rather than deleted, so the UI can
// show that something was removed. An invisible redaction is its own bug when
// someone is reading output to debug.
package redact

import (
	"regexp"
	"sort"
)

const mask = "[redacted]"

// Span marks a redacted run. Offsets index the returned Result.Text.
type Span struct {
	Start int `json:"start"`
	End   int `json:"end"`
}

// Result is redacted text plus where the removals landed.
type Result struct {
	Text  string `json:"text"`
	Spans []Span `json:"spans,omitempty"`
}

// patterns errs toward redacting too much. A false positive costs a reader one
// masked token; a false negative ships a live credential to a phone.
var patterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)\bAKIA[0-9A-Z]{16}\b`),
	regexp.MustCompile(`\bgh[pousr]_[A-Za-z0-9]{20,}\b`),
	regexp.MustCompile(`\bsk-[A-Za-z0-9_\-]{20,}\b`),
	regexp.MustCompile(`(?i)(bearer\s+)[A-Za-z0-9._\-]{16,}`),
	regexp.MustCompile(`(?i)((?:api[_\-]?key|secret|token|password)\s*[:=]\s*)[^\s"']{8,}`),
	regexp.MustCompile(`([a-z][a-z0-9+.\-]*://[^\s:/@]+:)[^\s@]+(@)`),
}

// Text redacts s. Patterns with a leading capture group keep that group and
// mask only the tail, so "Bearer <token>" stays readable as "Bearer [redacted]".
func Text(s string) Result {
	if s == "" {
		return Result{}
	}
	type hit struct{ start, end int }
	var hits []hit
	for _, re := range patterns {
		for _, m := range re.FindAllStringSubmatchIndex(s, -1) {
			start, end := m[0], m[1]
			if len(m) >= 4 && m[2] == m[0] && m[3] > m[2] {
				start = m[3]
			}
			if len(m) >= 6 && m[4] >= 0 && m[5] == m[1] {
				end = m[4]
			}
			if end > start {
				hits = append(hits, hit{start, end})
			}
		}
	}
	if len(hits) == 0 {
		return Result{Text: s}
	}
	sort.Slice(hits, func(i, j int) bool { return hits[i].start < hits[j].start })

	var out []byte
	var spans []Span
	cursor, lastEnd := 0, -1
	for _, h := range hits {
		if h.start < lastEnd {
			continue
		}
		out = append(out, s[cursor:h.start]...)
		spans = append(spans, Span{Start: len(out), End: len(out) + len(mask)})
		out = append(out, mask...)
		cursor, lastEnd = h.end, h.end
	}
	out = append(out, s[cursor:]...)
	return Result{Text: string(out), Spans: spans}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/redact/ -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/redact/
git commit -m "feat(backend): redact secret-shaped runs before persistence"
```

---

### Task 4: Persist a bounded per-session event log

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0090_block_events.sql`
- Create: `backend/internal/storage/sqlite/queries/block_events.sql`
- Create: `backend/internal/storage/sqlite/store/block_event_store.go`
- Test: `backend/internal/storage/sqlite/store/block_event_store_test.go`

**Interfaces:**
- Consumes: `domain.BlockEventKind` from Task 1.
- Produces: `store.InsertBlockEvent(ctx, rec blockeventsvc.Record) (int64, error)` returning the assigned sequence, `store.SelectBlockEventsBySession(ctx, sessionID string, afterSeq int64, limit int) ([]blockeventsvc.Record, error)`, and `store.TrimBlockEvents(ctx, sessionID string, keep int) (int64, error)`.
- **Do Task 5 Step 1 before this task.** The store references `blockeventsvc.Record`
  and `blockeventsvc.Store`, both declared in `backend/internal/service/blockevent/types.go`.
  Write that one file first (it has no dependencies of its own beyond `domain` and
  `redact`), then return here. Nothing else from Task 5 is needed.

- [ ] **Step 1: Write the migration and queries**

`backend/internal/storage/sqlite/migrations/0090_block_events.sql`:

```sql
-- Migration 0090: bounded per-session log of normalized agent block events.
--
-- Separate from activity: activity is one current state per session, this is an
-- append-only history a client can replay after a reconnect. Rows are trimmed
-- per session rather than globally so one busy session cannot evict another's.

-- +goose Up
-- +goose StatementBegin
CREATE TABLE block_events (
    seq              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id       TEXT NOT NULL,
    source_id        TEXT NOT NULL DEFAULT '',
    kind             TEXT NOT NULL,
    raw_event        TEXT NOT NULL DEFAULT '',
    harness          TEXT NOT NULL DEFAULT '',
    tool_name        TEXT NOT NULL DEFAULT '',
    tool_use_id      TEXT NOT NULL DEFAULT '',
    text             TEXT NOT NULL DEFAULT '',
    redacted_spans   TEXT NOT NULL DEFAULT '',
    error_type       TEXT NOT NULL DEFAULT '',
    hook_version     TEXT NOT NULL DEFAULT '',
    truncated_lines  INTEGER NOT NULL DEFAULT 0,
    created_at       TIMESTAMP NOT NULL
);
-- +goose StatementEnd
-- +goose StatementBegin
CREATE INDEX block_events_session_seq ON block_events (session_id, seq);
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP INDEX IF EXISTS block_events_session_seq;
-- +goose StatementEnd
-- +goose StatementBegin
DROP TABLE IF EXISTS block_events;
-- +goose StatementEnd
```

`backend/internal/storage/sqlite/queries/block_events.sql`:

```sql
-- name: InsertBlockEvent :one
INSERT INTO block_events (
    session_id, source_id, kind, raw_event, harness, tool_name, tool_use_id,
    text, redacted_spans, error_type, hook_version, truncated_lines, created_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
RETURNING *;

-- name: SelectBlockEventsBySession :many
SELECT *
FROM block_events
WHERE session_id = ? AND seq > ?
ORDER BY seq
LIMIT ?;

-- name: TrimBlockEventsForSession :execrows
DELETE FROM block_events
WHERE session_id = ?
  AND seq <= (
    SELECT seq FROM block_events
    WHERE session_id = ?
    ORDER BY seq DESC
    LIMIT 1 OFFSET ?
  );
```

- [ ] **Step 2: Regenerate and confirm the build breaks only where expected**

Run: `npm run sqlc && cd backend && go build ./...`
Expected: sqlc writes `gen/block_events.sql.go`; the build succeeds because nothing calls it yet.

- [ ] **Step 3: Write the failing store test**

```go
package store_test

import (
	"context"
	"testing"
	"time"

	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestBlockEventRoundTripAndTrim(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)

	for i := range 5 {
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: "s-1",
			SourceID:  "tool-" + string(rune('a'+i)),
			Kind:      domain.BlockEventToolComplete,
			ToolName:  "Bash",
			Text:      "ok",
			CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert %d: %v", i, err)
		}
	}

	got, err := s.SelectBlockEventsBySession(ctx, "s-1", 0, 100)
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	if len(got) != 5 {
		t.Fatalf("len = %d, want 5", len(got))
	}
	if got[0].Seq >= got[1].Seq {
		t.Fatalf("sequence not ascending: %d then %d", got[0].Seq, got[1].Seq)
	}

	afterFirst, err := s.SelectBlockEventsBySession(ctx, "s-1", got[0].Seq, 100)
	if err != nil {
		t.Fatalf("select after: %v", err)
	}
	if len(afterFirst) != 4 {
		t.Fatalf("resume len = %d, want 4", len(afterFirst))
	}

	if _, err := s.TrimBlockEvents(ctx, "s-1", 2); err != nil {
		t.Fatalf("trim: %v", err)
	}
	kept, err := s.SelectBlockEventsBySession(ctx, "s-1", 0, 100)
	if err != nil {
		t.Fatalf("select after trim: %v", err)
	}
	if len(kept) != 2 {
		t.Fatalf("kept = %d, want 2", len(kept))
	}
}

func TestBlockEventTrimIsPerSession(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)
	for _, id := range []string{"s-1", "s-1", "s-1", "s-2"} {
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: id, Kind: domain.BlockEventStop, CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert: %v", err)
		}
	}
	if _, err := s.TrimBlockEvents(ctx, "s-1", 1); err != nil {
		t.Fatalf("trim: %v", err)
	}
	other, err := s.SelectBlockEventsBySession(ctx, "s-2", 0, 100)
	if err != nil {
		t.Fatalf("select s-2: %v", err)
	}
	if len(other) != 1 {
		t.Fatalf("s-2 lost rows to s-1's trim: %d", len(other))
	}
}
```

`newTestStore` already exists at `backend/internal/storage/sqlite/store/store_test.go:18`:

```go
func newTestStore(t *testing.T) *sqlite.Store {
	t.Helper()
	return sqlitetest.MustOpen(t)
}
```

Use it as-is. Do not add a second helper. It returns a fully migrated, isolated
store whose cleanup is already registered with `t`.

- [ ] **Step 4: Run test to verify it fails**

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run TestBlockEvent -v`
Expected: FAIL — `s.InsertBlockEvent undefined`

- [ ] **Step 5: Write the store**

```go
package store

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/redact"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

var _ blockeventsvc.Store = (*Store)(nil)

// InsertBlockEvent appends one event and returns its assigned sequence.
func (s *Store) InsertBlockEvent(ctx context.Context, rec blockeventsvc.Record) (int64, error) {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	spans := ""
	if len(rec.RedactedSpans) > 0 {
		encoded, err := json.Marshal(rec.RedactedSpans)
		if err != nil {
			return 0, fmt.Errorf("encode redacted spans: %w", err)
		}
		spans = string(encoded)
	}
	row, err := s.qw.InsertBlockEvent(ctx, gen.InsertBlockEventParams{
		SessionID:      rec.SessionID,
		SourceID:       rec.SourceID,
		Kind:           string(rec.Kind),
		RawEvent:       rec.RawEvent,
		Harness:        rec.Harness,
		ToolName:       rec.ToolName,
		ToolUseID:      rec.ToolUseID,
		Text:           rec.Text,
		RedactedSpans:  spans,
		ErrorType:      rec.ErrorType,
		HookVersion:    rec.HookVersion,
		TruncatedLines: int64(rec.TruncatedLines),
		CreatedAt:      rec.CreatedAt,
	})
	if err != nil {
		return 0, fmt.Errorf("insert block event for %s: %w", rec.SessionID, err)
	}
	return row.Seq, nil
}

// SelectBlockEventsBySession returns events after afterSeq in ascending order.
func (s *Store) SelectBlockEventsBySession(ctx context.Context, sessionID string, afterSeq int64, limit int) ([]blockeventsvc.Record, error) {
	rows, err := s.qr.SelectBlockEventsBySession(ctx, gen.SelectBlockEventsBySessionParams{
		SessionID: sessionID,
		Seq:       afterSeq,
		Limit:     int64(limit),
	})
	if err != nil {
		return nil, fmt.Errorf("select block events for %s: %w", sessionID, err)
	}
	out := make([]blockeventsvc.Record, 0, len(rows))
	for _, row := range rows {
		rec := blockeventsvc.Record{
			Seq:            row.Seq,
			SessionID:      row.SessionID,
			SourceID:       row.SourceID,
			Kind:           domain.BlockEventKind(row.Kind),
			RawEvent:       row.RawEvent,
			Harness:        row.Harness,
			ToolName:       row.ToolName,
			ToolUseID:      row.ToolUseID,
			Text:           row.Text,
			ErrorType:      row.ErrorType,
			HookVersion:    row.HookVersion,
			TruncatedLines: int(row.TruncatedLines),
			CreatedAt:      row.CreatedAt,
		}
		if row.RedactedSpans != "" {
			var spans []redact.Span
			if err := json.Unmarshal([]byte(row.RedactedSpans), &spans); err == nil {
				rec.RedactedSpans = spans
			}
		}
		out = append(out, rec)
	}
	return out, nil
}

// TrimBlockEvents drops all but the newest keep rows for one session. Trimming
// is per session so a busy session cannot evict a quiet one's history.
func (s *Store) TrimBlockEvents(ctx context.Context, sessionID string, keep int) (int64, error) {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.TrimBlockEventsForSession(ctx, gen.TrimBlockEventsForSessionParams{
		SessionID:   sessionID,
		SessionID_2: sessionID,
		Offset:      int64(keep - 1),
	})
	if err != nil {
		return 0, fmt.Errorf("trim block events for %s: %w", sessionID, err)
	}
	return n, nil
}
```

sqlc derives param field names from the query's placeholder order. After
`npm run sqlc`, open `backend/internal/storage/sqlite/gen/block_events.sql.go`
and read the three generated `...Params` structs, then make the field names above
match exactly. Two are likely to differ from the guesses here:

- `SelectBlockEventsBySessionParams` — the `seq > ?` placeholder may be named
  `Seq` or `Seq_2`.
- `TrimBlockEventsForSessionParams` — the query uses `session_id` twice, so the
  second is generated as `SessionID_2`, and the `OFFSET ?` placeholder is
  generated as `Offset`.

Match the generated names. Never edit files under `gen/`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd backend && go test ./internal/storage/sqlite/... -run TestBlockEvent -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add backend/internal/storage/sqlite/
git commit -m "feat(backend): persist a bounded per-session block event log"
```

---

### Task 5: The block event service

**Files:**
- Create: `backend/internal/service/blockevent/types.go`
- Create: `backend/internal/service/blockevent/service.go`
- Test: `backend/internal/service/blockevent/service_test.go`

**Interfaces:**
- Consumes: `domain.BlockEventKind`, `blockdispatch.Map`, `redact.Text`, and the store methods from Task 4.
- Produces:
  - `blockevent.Record` — the struct Task 4 persists.
  - `blockevent.Store` interface — `InsertBlockEvent`, `SelectBlockEventsBySession`, `TrimBlockEvents`.
  - `blockevent.Publisher` interface — `PublishBlockEvent(sessionID string, rec Record)`.
  - `blockevent.NewService(store Store, pub Publisher, retain int) *Service`.
  - `(*Service).Record(ctx context.Context, sessionID domain.SessionID, harness string, sig ports.ActivitySignal) error`.
  - `(*Service).History(ctx context.Context, sessionID domain.SessionID, afterSeq int64, limit int) ([]Record, error)`.

- [ ] **Step 1: Write types.go**

```go
package blockevent

import (
	"context"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/redact"
)

// Record is one normalized, redacted block event. Seq is assigned by the store
// and is the resume cursor a reconnecting client sends back.
//
// SourceID is minted by whatever produced the event — a hook's tool_use_id
// today, a shell mark's counter later. It is never invented here: a consumer
// that invents ids cannot deduplicate on reconnect and cannot correlate a
// tool completion with the prompt that caused it.
type Record struct {
	Seq            int64                `json:"seq"`
	SessionID      string               `json:"sessionId"`
	SourceID       string               `json:"sourceId,omitempty"`
	Kind           domain.BlockEventKind `json:"kind"`
	RawEvent       string               `json:"rawEvent,omitempty"`
	Harness        string               `json:"harness,omitempty"`
	ToolName       string               `json:"toolName,omitempty"`
	ToolUseID      string               `json:"toolUseId,omitempty"`
	Text           string               `json:"text,omitempty"`
	RedactedSpans  []redact.Span        `json:"redactedSpans,omitempty"`
	ErrorType      string               `json:"errorType,omitempty"`
	HookVersion    string               `json:"hookVersion,omitempty"`
	TruncatedLines int                  `json:"truncatedLines,omitempty"`
	CreatedAt      time.Time            `json:"createdAt"`
}

// Store is the persistence slice the service needs.
type Store interface {
	InsertBlockEvent(ctx context.Context, rec Record) (int64, error)
	SelectBlockEventsBySession(ctx context.Context, sessionID string, afterSeq int64, limit int) ([]Record, error)
	TrimBlockEvents(ctx context.Context, sessionID string, keep int) (int64, error)
}

// Publisher fans a recorded event out to live clients.
type Publisher interface {
	PublishBlockEvent(sessionID string, rec Record)
}
```

- [ ] **Step 2: Write the failing service test**

```go
package blockevent

import (
	"context"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeStore struct {
	inserted []Record
	trimmed  []string
	nextSeq  int64
}

func (f *fakeStore) InsertBlockEvent(_ context.Context, rec Record) (int64, error) {
	f.nextSeq++
	rec.Seq = f.nextSeq
	f.inserted = append(f.inserted, rec)
	return rec.Seq, nil
}

func (f *fakeStore) SelectBlockEventsBySession(context.Context, string, int64, int) ([]Record, error) {
	return f.inserted, nil
}

func (f *fakeStore) TrimBlockEvents(_ context.Context, sessionID string, _ int) (int64, error) {
	f.trimmed = append(f.trimmed, sessionID)
	return 0, nil
}

type fakePublisher struct{ published []Record }

func (f *fakePublisher) PublishBlockEvent(_ string, rec Record) {
	f.published = append(f.published, rec)
}

func TestRecordNormalizesAndPublishes(t *testing.T) {
	store, pub := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, pub, 500)

	err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{
		Event:     "post-tool-use",
		ToolName:  "Bash",
		ToolUseID: "tu-1",
	})
	if err != nil {
		t.Fatalf("Record: %v", err)
	}
	if len(store.inserted) != 1 {
		t.Fatalf("inserted %d, want 1", len(store.inserted))
	}
	got := store.inserted[0]
	if got.Kind != domain.BlockEventToolComplete {
		t.Fatalf("Kind = %q, want tool_complete", got.Kind)
	}
	if got.SourceID != "tu-1" {
		t.Fatalf("SourceID = %q, want the hook's tool use id", got.SourceID)
	}
	if len(pub.published) != 1 || pub.published[0].Seq != 1 {
		t.Fatalf("published = %+v, want one record carrying its assigned seq", pub.published)
	}
}

func TestRecordKeepsUnknownEventsWithTheirRawName(t *testing.T) {
	store, pub := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, pub, 500)

	if err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{
		Event: "brand-new-hook",
	}); err != nil {
		t.Fatalf("Record: %v", err)
	}
	got := store.inserted[0]
	if got.Kind != domain.BlockEventUnknown {
		t.Fatalf("Kind = %q, want unknown", got.Kind)
	}
	if got.RawEvent != "brand-new-hook" {
		t.Fatalf("RawEvent = %q, want the raw name preserved", got.RawEvent)
	}
}

func TestRecordRedactsBeforeStoringOrPublishing(t *testing.T) {
	store, pub := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, pub, 500)

	if err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{
		Event:            "user-prompt-submit",
		LatestUserPrompt: "deploy with AKIAIOSFODNN7EXAMPLE now",
	}); err != nil {
		t.Fatalf("Record: %v", err)
	}
	if strings.Contains(store.inserted[0].Text, "AKIAIOSFODNN7EXAMPLE") {
		t.Fatal("secret reached the store")
	}
	if strings.Contains(pub.published[0].Text, "AKIAIOSFODNN7EXAMPLE") {
		t.Fatal("secret reached a client")
	}
	if len(store.inserted[0].RedactedSpans) == 0 {
		t.Fatal("redaction was not reported to the UI")
	}
}

func TestRecordIgnoresSignalsWithNoEvent(t *testing.T) {
	store, pub := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, pub, 500)

	if err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{}); err != nil {
		t.Fatalf("Record: %v", err)
	}
	if len(store.inserted) != 0 || len(pub.published) != 0 {
		t.Fatal("an eventless signal produced a block event")
	}
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd backend && go test ./internal/service/blockevent/ -v`
Expected: FAIL — `undefined: NewService`

- [ ] **Step 4: Write the service**

```go
package blockevent

import (
	"context"
	"strings"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/blockdispatch"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/redact"
)

// maxTextBytes caps one event's text. A single tool result can be enormous and
// this log is replayed to a phone over Tailscale, so the tail is dropped and
// the drop is counted rather than hidden.
const maxTextBytes = 16 << 10

// trimEvery bounds how often a session's log is trimmed. Trimming on every
// insert would put a delete in the path of every hook callback.
const trimEvery = 64

// Service turns hook signals into normalized, redacted, persisted block events.
type Service struct {
	store  Store
	pub    Publisher
	retain int
	writes int
}

// NewService builds the service. retain is how many events one session keeps.
func NewService(store Store, pub Publisher, retain int) *Service {
	if retain <= 0 {
		retain = 500
	}
	return &Service{store: store, pub: pub, retain: retain}
}

// Record normalizes one activity signal into a block event. A signal carrying
// no event name is not a block event and is ignored: activity and usage still
// consume it independently.
func (s *Service) Record(ctx context.Context, sessionID domain.SessionID, harness string, sig ports.ActivitySignal) error {
	if strings.TrimSpace(sig.Event) == "" {
		return nil
	}
	kind, known := blockdispatch.Map(harness, sig.Event)

	text := sig.LatestAssistantUpdate
	if text == "" {
		text = sig.LatestUserPrompt
	}
	truncated := 0
	if len(text) > maxTextBytes {
		truncated = strings.Count(text[maxTextBytes:], "\n") + 1
		text = text[:maxTextBytes]
	}
	redacted := redact.Text(text)

	sourceID := sig.ToolUseID
	if sourceID == "" {
		sourceID = sig.AgentSessionID
	}

	rec := Record{
		SessionID:      string(sessionID),
		SourceID:       sourceID,
		Kind:           kind,
		Harness:        harness,
		ToolName:       sig.ToolName,
		ToolUseID:      sig.ToolUseID,
		Text:           redacted.Text,
		RedactedSpans:  redacted.Spans,
		TruncatedLines: truncated,
		CreatedAt:      time.Now().UTC(),
	}
	if !known {
		rec.RawEvent = sig.Event
	}

	seq, err := s.store.InsertBlockEvent(ctx, rec)
	if err != nil {
		return err
	}
	rec.Seq = seq

	s.writes++
	if s.writes%trimEvery == 0 {
			_, _ = s.store.TrimBlockEvents(ctx, string(sessionID), s.retain)
	}

	if s.pub != nil {
		s.pub.PublishBlockEvent(sessionID, rec)
	}
	return nil
}

// History returns persisted events after afterSeq so a reconnecting client can
// replay what it missed instead of only seeing what arrives next.
func (s *Service) History(ctx context.Context, sessionID domain.SessionID, afterSeq int64, limit int) ([]Record, error) {
	if limit <= 0 || limit > s.retain {
		limit = s.retain
	}
	return s.store.SelectBlockEventsBySession(ctx, string(sessionID), afterSeq, limit)
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && go test ./internal/service/blockevent/ -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add backend/internal/service/blockevent/
git commit -m "feat(backend): normalize, redact and persist agent block events"
```

---

### Task 6: Wire the service into the activity endpoint

**Files:**
- Modify: `backend/internal/httpd/controllers/sessions.go` — add the interface beside `ActivityRecorder` (declared near line 111), add a field to `SessionsController`, and add the call inside `activity` (the handler begins at line 1269; the insertion point is immediately after the `if c.Activity != nil { ... }` block and before `if c.Usage != nil {`)
- Modify: `backend/internal/httpd/api.go:28` (add to `APIDeps`) and `:94` (pass into `controllers.SessionsController{...}`)
- Modify: `backend/internal/daemon/daemon.go` — construct the service after `termMgr` (line 141) and add it to the `httpd.APIDeps{...}` literal (line 393)
- Test: `backend/internal/httpd/controllers/sessions_block_events_test.go`

**Interfaces:**
- Consumes: `blockevent.Service` and `blockevent.Record` from Task 5.
- Produces: `controllers.BlockEventRecorder` with the single method
  `Record(ctx context.Context, sessionID domain.SessionID, harness string, sig ports.ActivitySignal) error`,
  and a `BlockEvents` field on both `SessionsController` and `httpd.APIDeps`.

**Session id type.** The controller passes `sessionID(r)`, which returns
`domain.SessionID`. Task 5's `Service.Record` already takes `domain.SessionID`
and converts internally, matching every other recorder in this handler. No
conversion is needed at the call site.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/httpd/controllers/sessions_block_events_test.go`:

```go
package controllers_test

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeBlockEventRecorder struct {
	gotID      domain.SessionID
	gotHarness string
	gotSignal  ports.ActivitySignal
	calls      int
	err        error
}

func (f *fakeBlockEventRecorder) Record(_ context.Context, id domain.SessionID, harness string, sig ports.ActivitySignal) error {
	f.calls++
	f.gotID = id
	f.gotHarness = harness
	f.gotSignal = sig
	return f.err
}

func newBlockEventsTestServer(t *testing.T, rec *fakeBlockEventRecorder) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{}
	if rec != nil {
		deps.BlockEvents = rec
	}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestSessionsAPI_ActivityRecordsBlockEvent(t *testing.T) {
	rec := &fakeBlockEventRecorder{}
	srv := newBlockEventsTestServer(t, rec)

	body, status, _ := doRequest(t, srv, "POST", "/api/v1/sessions/opr-1/activity", `{
		"state":"active",
		"event":"post-tool-use",
		"toolName":"Bash",
		"toolUseId":"tu-1",
		"usage":{"harness":"claude-code"}
	}`)
	if status != http.StatusOK {
		t.Fatalf("activity = %d, want 200; body=%s", status, body)
	}
	if rec.calls != 1 {
		t.Fatalf("block recorder calls = %d, want 1", rec.calls)
	}
	if rec.gotID != "opr-1" {
		t.Fatalf("session id = %q, want opr-1", rec.gotID)
	}
	if rec.gotHarness != "claude-code" {
		t.Fatalf("harness = %q, want claude-code", rec.gotHarness)
	}
	if rec.gotSignal.ToolUseID != "tu-1" {
		t.Fatalf("ToolUseID = %q, want tu-1", rec.gotSignal.ToolUseID)
	}
}

func TestSessionsAPI_ActivitySkipsBlockEventWithoutAnEventName(t *testing.T) {
	rec := &fakeBlockEventRecorder{}
	srv := newBlockEventsTestServer(t, rec)

	_, status, _ := doRequest(t, srv, "POST", "/api/v1/sessions/opr-1/activity", `{"state":"active"}`)
	if status != http.StatusOK {
		t.Fatalf("activity = %d, want 200", status)
	}
	if rec.calls != 0 {
		t.Fatalf("block recorder calls = %d, want 0 for an eventless signal", rec.calls)
	}
}

func TestSessionsAPI_ActivitySurvivesBlockRecorderFailure(t *testing.T) {
	rec := &fakeBlockEventRecorder{err: context.DeadlineExceeded}
	srv := newBlockEventsTestServer(t, rec)

	body, status, _ := doRequest(t, srv, "POST", "/api/v1/sessions/opr-1/activity", `{"state":"active","event":"stop"}`)
	if status != http.StatusOK {
		t.Fatalf("activity = %d, want 200 despite a failing block recorder; body=%s", status, body)
	}
}

func TestSessionsAPI_ActivityWorksWithNoBlockRecorder(t *testing.T) {
	srv := newBlockEventsTestServer(t, nil)

	_, status, _ := doRequest(t, srv, "POST", "/api/v1/sessions/opr-1/activity", `{"state":"active","event":"stop"}`)
	if status != http.StatusOK {
		t.Fatalf("activity = %d, want 200 with a nil recorder", status)
	}
}
```

`doRequest` already exists at `backend/internal/httpd/controllers/projects_test.go:522` with
signature `doRequest(t *testing.T, srv *httptest.Server, method, path, body string) ([]byte, int, http.Header)`.
It is in the same `controllers_test` package, so call it directly. Do not write another one.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && go test ./internal/httpd/controllers/ -run TestSessionsAPI_Activity -v`
Expected: FAIL — `deps.BlockEvents undefined (type httpd.APIDeps has no field or method BlockEvents)`

- [ ] **Step 3: Declare the interface and the controller field**

In `backend/internal/httpd/controllers/sessions.go`, directly below the existing
`ActivityRecorder` interface declaration (near line 111):

```go
// BlockEventRecorder retains the rich hook payload as a block event. It is
// optional: a nil recorder leaves activity and usage behaviour untouched, so an
// older daemon build and a newer one differ only in whether blocks appear.
type BlockEventRecorder interface {
	Record(ctx context.Context, sessionID domain.SessionID, harness string, sig ports.ActivitySignal) error
}
```

Add the field to `SessionsController` beside `Activity` and `Usage`:

```go
	BlockEvents BlockEventRecorder
```

- [ ] **Step 4: Call it from the activity handler**

In the same file, inside `func (c *SessionsController) activity`, insert this
between the `if c.Activity != nil && (sig.Valid || sig.AgentSessionID != "") { ... }`
block and the `if c.Usage != nil {` block:

```go
	if c.BlockEvents != nil && sig.Event != "" {
		harness := ""
		if in.Usage != nil {
			harness = capActivityMeta(domain.SanitizeControlChars(strings.TrimSpace(string(in.Usage.Harness))))
		}
		if err := c.BlockEvents.Record(r.Context(), sessionID(r), harness, sig); err != nil {
			slog.Default().Warn(
				"block event recording failed",
				"session", sessionID(r),
				"event", sig.Event,
				"err", err,
			)
		}
	}
```

A recording failure warns and continues, matching how a `c.Usage.RecordHook`
failure is handled a few lines below: a lost block is a degraded view, never a
reason to fail the agent's hook callback and stall its turn.

- [ ] **Step 5: Add it to APIDeps and the controller construction**

In `backend/internal/httpd/api.go`, add to the `APIDeps` struct (line 28) beside
`UsageHooks`:

```go
	// BlockEvents retains rich hook payloads as block events. Nil leaves the
	// activity endpoint's existing behaviour untouched.
	BlockEvents controllers.BlockEventRecorder
```

and in the `controllers.SessionsController{...}` literal at line 94, beside
`Usage: deps.UsageHooks,`:

```go
			BlockEvents:   deps.BlockEvents,
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd backend && go test ./internal/httpd/... -run TestSessionsAPI_Activity -v`
Expected: PASS — all four tests.

- [ ] **Step 7: Wire the real service in the daemon**

In `backend/internal/daemon/daemon.go`, after `termMgr` is created (line 141) and
before the `httpd.NewWithDeps` call (line 393), add:

```go
	blockEvents := blockevent.NewService(store, nil, 500)
```

The publisher is `nil` until Task 7 makes `termMgr` satisfy `blockevent.Publisher`.
Task 7 Step 6 replaces this line.

Add the import:

```go
	blockevent "github.com/OmarAly92/operator/backend/internal/service/blockevent"
```

and add to the `httpd.APIDeps{...}` literal beside `UsageHooks: usageCollector,`:

```go
		BlockEvents:        blockEvents,
```

- [ ] **Step 8: Verify the whole backend still builds and passes**

Run: `cd backend && go build ./... && go test ./internal/httpd/... ./internal/daemon/... ./internal/service/blockevent/...`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add backend/internal/httpd/ backend/internal/daemon/daemon.go backend/internal/service/blockevent/
git commit -m "feat(backend): record block events from the activity endpoint"
```

---

### Task 7: The `blocks` mux channel

**Files:**
- Modify: `backend/internal/terminal/protocol.go` — channel constants (lines 15-18), message-type constants, and `serverMsg` (lines 71-83)
- Modify: `backend/internal/terminal/manager.go` — `Manager` struct (line 44), `Serve` (line 333), `connState` struct (around line 360), `handle` dispatch (line 374), `cleanup` (line 573)
- Test: `backend/internal/terminal/blocks_test.go`

**Interfaces:**
- Consumes: `blockevent.Record` from Task 5.
- Produces: `(*Manager).PublishBlockEvent(sessionID string, rec blockevent.Record)` — this satisfies `blockevent.Publisher`; `chBlocks = "blocks"`; `msgBlock = "block"`; and `Block *blockevent.Record` on `serverMsg`.

Wire protocol: a client subscribes with `{"ch":"blocks","type":"subscribe","id":"<sessionId>"}`
and then receives `{"ch":"blocks","type":"block","id":"<sessionId>","block":{...}}`.

**Important: `Manager` has no connection registry today.** It tracks
`attachments map[*attachment]struct{}` only — attachments are per-terminal PTY
attaches, not connections. A `connState` is created in `Serve` and is never
registered anywhere. This task adds that registry; without it there is no way to
reach subscribed connections.

**Existing test helpers in this package** (`manager_test.go`), use them as-is:

- `newFakeConn() *fakeConn` — takes no arguments, is an in-memory `wsConn`
  with buffered `in chan clientMsg` and `out chan serverMsg`.
- `recv(t *testing.T, c *fakeConn, ch, typ string, d time.Duration) serverMsg` —
  waits for a frame matching channel and type, draining others.
- Drive a connection by `go m.Serve(ctx, conn)` then `conn.in <- clientMsg{...}`.
- Read `manager_test.go:70` (`TestServeOpenStreamsAndWritesTerminal`) for the
  exact setup shape before writing the test below.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/terminal/blocks_test.go`:

```go
package terminal

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
)

func TestPublishBlockEventReachesSubscribedConnection(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	conn := newFakeConn()
	go m.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chBlocks, Type: msgSubscribe, ID: "s-1"}

	waitForBlockSubscriber(t, m, "s-1")

	m.PublishBlockEvent("s-1", blockeventsvc.Record{
		Seq:       7,
		SessionID: "s-1",
		Kind:      domain.BlockEventToolComplete,
		ToolName:  "Bash",
		CreatedAt: time.Now().UTC(),
	})

	msg := recv(t, conn, chBlocks, msgBlock, 2*time.Second)
	if msg.ID != "s-1" {
		t.Fatalf("frame id = %q, want s-1", msg.ID)
	}
	if msg.Block == nil {
		t.Fatal("frame carried no block payload")
	}
	if msg.Block.Seq != 7 || msg.Block.ToolName != "Bash" {
		t.Fatalf("block = %+v, want seq 7 / Bash", msg.Block)
	}
}

func TestPublishBlockEventIgnoresOtherSessions(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	conn := newFakeConn()
	go m.Serve(ctx, conn)
	conn.in <- clientMsg{Ch: chBlocks, Type: msgSubscribe, ID: "s-1"}
	waitForBlockSubscriber(t, m, "s-1")

	m.PublishBlockEvent("s-2", blockeventsvc.Record{Seq: 1, SessionID: "s-2"})

	select {
	case got := <-conn.out:
		if got.Ch == chBlocks {
			t.Fatalf("received a block frame for an unsubscribed session: %+v", got)
		}
	case <-time.After(200 * time.Millisecond):
	}
}

func TestPublishBlockEventIgnoresUnsubscribedConnection(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	conn := newFakeConn()
	go m.Serve(ctx, conn)

	m.PublishBlockEvent("s-1", blockeventsvc.Record{Seq: 1, SessionID: "s-1"})

	select {
	case got := <-conn.out:
		if got.Ch == chBlocks {
			t.Fatalf("a connection that never subscribed received %+v", got)
		}
	case <-time.After(200 * time.Millisecond):
	}
}

// waitForBlockSubscriber blocks until the manager has registered a subscriber
// for id. Serve reads the subscribe frame on its own goroutine, so publishing
// immediately after sending it would race.
func waitForBlockSubscriber(t *testing.T, m *Manager, id string) {
	t.Helper()
	deadline := time.After(2 * time.Second)
	for {
		if m.blockSubscriberCount(id) > 0 {
			return
		}
		select {
		case <-deadline:
			t.Fatalf("no block subscriber for %q appeared", id)
		case <-time.After(5 * time.Millisecond):
		}
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && go test ./internal/terminal/ -run TestPublishBlockEvent -v`
Expected: FAIL — `undefined: chBlocks`

- [ ] **Step 3: Extend the protocol**

In `backend/internal/terminal/protocol.go`, add to the channel constant block
(currently lines 15-18, holding `chTerminal`, `chSubscribe`, `chSessions`,
`chSystem`):

```go
	chBlocks = "blocks"
```

Add to the message-type constant block in the same file, beside `msgSnapshot`:

```go
	msgBlock = "block"
```

Add to `serverMsg` (line 71), after the `Session *sessionUpdate` field:

```go
	// Block is the ch "blocks" payload: one normalized agent block event.
	Block *blockeventsvc.Record `json:"block,omitempty"`
```

and add the import:

```go
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
```

- [ ] **Step 4: Add the connection registry**

In `backend/internal/terminal/manager.go`, add to the `Manager` struct (line 44),
inside the section guarded by `mu` beside `attachments`:

```go
	conns map[*connState]struct{}
```

Initialize it in `NewManager`, which builds the struct literal at
`manager.go:126-137`. Add one line beside `attachments`:

```go
	m := &Manager{
		src:          src,
		events:       events,
		log:          log,
		heartbeat:    defaultHeartbeat,
		ctx:          ctx,
		cancel:       cancel,
		attachments:  map[*attachment]struct{}{},
		conns:        map[*connState]struct{}{},
		shared:       map[string]*sharedTerm{},
		inputBlocked: map[string]int{},
		lastInputAt:  map[string]time.Time{},
	}
```

Add to the `connState` struct (around line 360), inside the section guarded by
its `mu` beside `terms`:

```go
	blockSubs map[string]struct{} // session id -> subscribed
```

In `Serve` (line 333), register the connection right after `c` is constructed and
before `defer c.cleanup()`:

```go
	m.mu.Lock()
	if m.conns == nil {
		m.conns = map[*connState]struct{}{}
	}
	m.conns[c] = struct{}{}
	m.mu.Unlock()
```

In `cleanup` (line 573), unregister it. Add this immediately after the
`c.mu.Unlock()` that follows the `closed` guard, so a torn-down connection is
never published to:

```go
	c.mgr.mu.Lock()
	delete(c.mgr.conns, c)
	c.mgr.mu.Unlock()
```

- [ ] **Step 5: Handle subscribe and publish**

In `manager.go`, add a case to `func (c *connState) handle(msg clientMsg)`
(line 374), beside `case chSubscribe:`:

```go
	case chBlocks:
		c.handleBlockSubscribe(msg)
```

Add the handler next to `handleSubscribe`:

```go
// handleBlockSubscribe registers this connection for one session's block
// events. Subscription is per session rather than global so an idle client
// pays nothing for a busy session it is not looking at.
func (c *connState) handleBlockSubscribe(msg clientMsg) {
	if msg.Type != msgSubscribe || msg.ID == "" {
		return
	}
	c.mu.Lock()
	if c.blockSubs == nil {
		c.blockSubs = map[string]struct{}{}
	}
	c.blockSubs[msg.ID] = struct{}{}
	c.mu.Unlock()
}
```

Add the publisher on `Manager`:

```go
// PublishBlockEvent fans one recorded block event out to every connection
// subscribed to that session. It satisfies blockevent.Publisher.
func (m *Manager) PublishBlockEvent(sessionID string, rec blockeventsvc.Record) {
	m.mu.Lock()
	conns := make([]*connState, 0, len(m.conns))
	for conn := range m.conns {
		conns = append(conns, conn)
	}
	m.mu.Unlock()

	for _, conn := range conns {
		conn.mu.Lock()
		_, subscribed := conn.blockSubs[sessionID]
		conn.mu.Unlock()
		if !subscribed {
			continue
		}
		payload := rec
		conn.enqueue(serverMsg{Ch: chBlocks, ID: sessionID, Type: msgBlock, Block: &payload})
	}
}

// blockSubscriberCount reports how many connections are subscribed to one
// session. It exists for tests, which must not publish before Serve's reader
// goroutine has processed the subscribe frame.
func (m *Manager) blockSubscriberCount(sessionID string) int {
	m.mu.Lock()
	conns := make([]*connState, 0, len(m.conns))
	for conn := range m.conns {
		conns = append(conns, conn)
	}
	m.mu.Unlock()

	n := 0
	for _, conn := range conns {
		conn.mu.Lock()
		if _, ok := conn.blockSubs[sessionID]; ok {
			n++
		}
		conn.mu.Unlock()
	}
	return n
}
```

The local `payload := rec` copy is deliberate: every subscriber must get its own
pointer target rather than sharing one that a later loop iteration could reuse.

Do **not** hold `m.mu` while calling `conn.enqueue`. `enqueue` can tear down a
slow connection, which takes connection-side locks; holding the manager lock
across that risks a lock-order inversion with `Serve` and `cleanup`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd backend && go test ./internal/terminal/ -race -v`
Expected: PASS, including the pre-existing tests. The `-race` flag matters here:
this task adds cross-goroutine shared state.

- [ ] **Step 7: Replace the nil publisher from Task 6**

In `backend/internal/daemon/daemon.go`, change the line added in Task 6 Step 7:

```go
	blockEvents := blockevent.NewService(store, termMgr, 500)
```

`termMgr` now satisfies `blockevent.Publisher`. A compile error here means
`Manager.PublishBlockEvent` does not match
`PublishBlockEvent(sessionID string, rec blockevent.Record)` exactly. Fix the
method's signature to match the interface; do not widen the interface to match
the method.

- [ ] **Step 8: Run the full backend gate**

Run: `cd backend && go build ./... && go test ./... && cd .. && npm run lint`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add backend/internal/terminal/ backend/internal/daemon/daemon.go
git commit -m "feat(backend): stream block events over a blocks mux channel"
```

---

### Task 8: Shared cross-client fixtures

**Files:**
- Create: `testdata/blocks/hook_stream_basic.json`
- Create: `testdata/blocks/hook_stream_unknown_event.json`
- Create: `testdata/blocks/hook_stream_secrets.json`
- Create: `backend/internal/service/blockevent/fixtures_test.go`

**Interfaces:**
- Consumes: `blockevent.Service` from Task 5.
- Produces: a fixture corpus at repo root `testdata/blocks/` that the mobile and desktop plans assert against, so block assembly cannot drift between Dart and TypeScript.

Each fixture is `{"harness": "...", "signals": [...], "expected": [...]}` where `signals` are activity-endpoint bodies and `expected` are the resulting `Record` values with `seq` and `createdAt` omitted.

- [ ] **Step 1: Write the fixtures**

`testdata/blocks/hook_stream_basic.json`:

```json
{
  "harness": "claude-code",
  "signals": [
    { "event": "user-prompt-submit", "latestUserPrompt": "run the tests" },
    { "event": "post-tool-use", "toolName": "Bash", "toolUseId": "tu-1" },
    { "event": "stop", "latestAssistantUpdate": "all green" }
  ],
  "expected": [
    { "kind": "prompt_submit", "text": "run the tests" },
    { "kind": "tool_complete", "toolName": "Bash", "toolUseId": "tu-1", "sourceId": "tu-1" },
    { "kind": "stop", "text": "all green" }
  ]
}
```

`testdata/blocks/hook_stream_unknown_event.json`:

```json
{
  "harness": "claude-code",
  "signals": [
    { "event": "brand-new-hook", "latestAssistantUpdate": "who knows" }
  ],
  "expected": [
    { "kind": "unknown", "rawEvent": "brand-new-hook", "text": "who knows" }
  ]
}
```

`testdata/blocks/hook_stream_secrets.json`:

```json
{
  "harness": "claude-code",
  "signals": [
    { "event": "user-prompt-submit", "latestUserPrompt": "deploy with AKIAIOSFODNN7EXAMPLE now" }
  ],
  "expected": [
    { "kind": "prompt_submit", "text": "deploy with [redacted] now", "redactedSpansCount": 1 }
  ]
}
```

- [ ] **Step 2: Write the failing fixture test**

```go
package blockevent

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fixtureFile struct {
	Harness string `json:"harness"`
	Signals []struct {
		Event                 string `json:"event"`
		ToolName              string `json:"toolName"`
		ToolUseID             string `json:"toolUseId"`
		LatestUserPrompt      string `json:"latestUserPrompt"`
		LatestAssistantUpdate string `json:"latestAssistantUpdate"`
	} `json:"signals"`
	Expected []struct {
		Kind               string `json:"kind"`
		RawEvent           string `json:"rawEvent"`
		ToolName           string `json:"toolName"`
		ToolUseID          string `json:"toolUseId"`
		SourceID           string `json:"sourceId"`
		Text               string `json:"text"`
		RedactedSpansCount int    `json:"redactedSpansCount"`
	} `json:"expected"`
}

func TestSharedFixtures(t *testing.T) {
	dir := filepath.Join("..", "..", "..", "..", "testdata", "blocks")
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read fixtures: %v", err)
	}
	if len(entries) == 0 {
		t.Fatal("no fixtures found; the clients have nothing to agree with")
	}
	for _, entry := range entries {
		t.Run(entry.Name(), func(t *testing.T) {
			raw, err := os.ReadFile(filepath.Join(dir, entry.Name()))
			if err != nil {
				t.Fatalf("read: %v", err)
			}
			var fixture fixtureFile
			if err := json.Unmarshal(raw, &fixture); err != nil {
				t.Fatalf("decode: %v", err)
			}

			store := &fakeStore{}
			svc := NewService(store, nil, 500)
			for _, sig := range fixture.Signals {
				err := svc.Record(context.Background(), "s-1", fixture.Harness, ports.ActivitySignal{
					Event:                 sig.Event,
					ToolName:              sig.ToolName,
					ToolUseID:             sig.ToolUseID,
					LatestUserPrompt:      sig.LatestUserPrompt,
					LatestAssistantUpdate: sig.LatestAssistantUpdate,
				})
				if err != nil {
					t.Fatalf("Record: %v", err)
				}
			}
			if len(store.inserted) != len(fixture.Expected) {
				t.Fatalf("produced %d records, fixture expects %d", len(store.inserted), len(fixture.Expected))
			}
			for i, want := range fixture.Expected {
				got := store.inserted[i]
				if string(got.Kind) != want.Kind {
					t.Errorf("record %d Kind = %q, want %q", i, got.Kind, want.Kind)
				}
				if got.RawEvent != want.RawEvent {
					t.Errorf("record %d RawEvent = %q, want %q", i, got.RawEvent, want.RawEvent)
				}
				if got.Text != want.Text {
					t.Errorf("record %d Text = %q, want %q", i, got.Text, want.Text)
				}
				if want.SourceID != "" && got.SourceID != want.SourceID {
					t.Errorf("record %d SourceID = %q, want %q", i, got.SourceID, want.SourceID)
				}
				if len(got.RedactedSpans) != want.RedactedSpansCount {
					t.Errorf("record %d spans = %d, want %d", i, len(got.RedactedSpans), want.RedactedSpansCount)
				}
			}
		})
	}
}
```

- [ ] **Step 3: Run tests to verify they fail, then pass**

Run: `cd backend && go test ./internal/service/blockevent/ -run TestSharedFixtures -v`
The path `filepath.Join("..", "..", "..", "..", "testdata", "blocks")` is correct
from `backend/internal/service/blockevent/`: four levels up is the repo root
(`blockevent` → `service` → `internal` → `backend` → root). Do not change it.

Expected: PASS. If a fixture fails, **do not edit the fixture to match the code.**
A mismatch means either the implementation is wrong or the vocabulary needs a
deliberate change — and the clients in later plans assert against these same
files, so quietly relaxing one here breaks a contract two other plans depend on.

- [ ] **Step 4: Run the full gate**

Run: `npm run lint`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add testdata/blocks/ backend/internal/service/blockevent/fixtures_test.go
git commit -m "test(backend): pin block assembly with cross-client fixtures"
```

---

## What this plan deliberately does not do

- No REST endpoint for block history. The mux channel plus `Service.History` is enough for the client plans; a REST surface would need `npm run api` and an OpenAPI change, and no consumer needs it yet.
- No transcript reading. Hook events alone produce usable blocks; enrichment is its own plan.
- No shell marks. Shell blocks are their own plan.
- No stuck-state resolution. The rule that no block stays `running` once its session's process is gone belongs with the client-side block assembly that owns block status, and lands in the mobile plan.
- No UI. Nothing in this plan changes what either client renders.
