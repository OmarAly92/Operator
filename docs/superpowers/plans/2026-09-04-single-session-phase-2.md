# Single Session Kind, Phase 2 — Transcript Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tail the native transcript of every live Claude Code and Codex session, map each record onto normalized block events, and project them on the phone so the blocks view shows assistant text, reasoning, full tool input, tool results, todos, the turn's model, compaction, and answerable-shaped questions — at the fidelity chat mode had.

**Architecture:** Hooks stay the *status* channel and gain a sibling *body* channel. A per-session tailer in a new `backend/internal/observe/transcript` package reads new complete JSONL lines from a persisted byte offset, hands each line to a per-harness mapper that lives in that harness's adapter package, and records the results through the existing `blockevent.Service` — same redaction, same caps, same store, same mux publish as a hook event, with a new `source` field marking which channel produced it. The mobile assembler (`block_assembly.dart`) grows the new kinds and one precedence rule: transcript wins on body, hook wins on status. Nothing about the desktop changes; it has no blocks view.

**Tech Stack:** Go 1.25.7 (chi, goose, sqlc, modernc sqlite, fsnotify), Flutter 3.44.5 (flutter_bloc, mocktail, equatable). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-04-single-session-interface-design.md`, section "Phase 2 — transcript enrichment: the phone sees everything". Read it before Task 1; the tables in "What the phone sees, after Phase 2", "Claude Code", "Codex" and "Projection" are the acceptance criteria this plan implements.

**Predecessor:** Phase 1 is merged on `master` (`docs/superpowers/plans/2026-09-04-single-session-phase-1-report.md`). Every session is a TUI in a pty; mobile opens covered harnesses in blocks view.

---

## Global Constraints

- Work on a fresh branch from `master` in its own worktree (superpowers:using-git-worktrees). Branch name: `feat/single-session-phase-2`.
- **Do not add code comments.** This repo's user instruction forbids them. Existing comments you do not touch stay; delete comments attached to code you delete. Package-level doc comments on **new** Go packages and exported Go identifiers are the one exception — Go tooling and `golangci-lint` require them, and every existing package in this repo has them.
- Keep every change surgical. No drive-by cleanup outside the files a task names, except deleting an import your change made unused.
- **Never edit `backend/internal/storage/sqlite/gen/*` and never edit an already-merged migration.** Add a new migration; after changing `queries/*.sql` or `migrations/*.sql` run `npm run sqlc` from the repo root and commit the regenerated `gen/` with the change.
- After changing `backend/internal/httpd/controllers/dto.go` or `backend/internal/httpd/apispec/specgen/build.go`, run `npm run api` from the repo root and commit `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts` with the Go change.
- Backend gate per task: `cd backend && go build ./... && go test ./<touched packages>/...`, then `go vet ./...`. Run `go test ./...` before the last commit of each Part.
- Mobile gate per task: `cd packages/mobile && flutter analyze` must print `No issues found!`, then `flutter test test/<touched files>`, then the full `flutter test` before the last commit of Part D.
- Mobile conventions (these override the generic Flutter skill, per `CLAUDE.md`): **Cubit only**, never `Bloc`. **No `freezed`, no `json_serializable`, no `build_runner`** in first-party code. Models are hand-written, **all fields nullable**, `fromJson` does the wire→domain mapping. Static-only classes are `sealed class`. Feature code never imports `flutter_screenutil`; spacing/padding/radii take raw ints. User-facing copy is **inline English** — there is no `LocaleKeys` catalogue. Colors come from `context.skin` (`AppSkin`), type from `AppTextStyle.style<Size><Weight>` / `mono<Size><Weight>`. Navigation is `Navigator.of(context)` with `RoutesStrings`. Parameterized paths get static methods on `EndPoints`.
- Mobile widgets: one widget class per file under `ui/widgets/`; never extract a widget as a method. Every `BlocBuilder` declares `buildWhen`.
- Error envelopes keep `{error, code, message, requestId}`.
- Fixtures under `testdata/` are shared by the Go and Dart suites. **Never fix a failing fixture by editing the fixture.**
- Conventional commit messages (`feat:`, `fix:`, `test:`, `docs:`, `chore:`). End every commit with the two attribution trailers your own session's guidance gives you (a `Co-Authored-By:` line naming your model and a `Claude-Session:` URL). Do not copy Phase 1's trailers.

## Vocabulary this plan introduces

Memorise these names; later tasks use them without redefining them.

| name | where | what |
|---|---|---|
| `domain.BlockEventAssistantText` … `BlockEventCompaction` | `backend/internal/domain/blockevent.go` | seven new normalized kinds |
| `domain.BlockEventSource` (`"hook"` / `"transcript"`) | same file | which channel produced a record |
| `domain.BlockTranscriptEvent` | same file | one mapper output; the neutral struct that keeps adapter packages and `service/blockevent` free of an import cycle |
| `blockevent.Record.Source` | `backend/internal/service/blockevent/types.go` | persisted + wire field |
| `blockevent.Service.RecordTranscript` | `backend/internal/service/blockevent/service.go` | the transcript-side sibling of `Record` |
| `claudecode.MapTranscriptRecord` / `codex.MapTranscriptRecord` | adapter packages | `func([]byte) ([]domain.BlockTranscriptEvent, bool)` |
| `blocktranscript.Map` | `backend/internal/adapters/agent/blocktranscript/` | harness → mapper registry, mirroring `blockdispatch` |
| `transcript.Supervisor` | `backend/internal/observe/transcript/` | the tailer: reconcile live sessions, watch files, pump lines |
| `SessionBlock.result` / `SessionBlock.model` | `packages/mobile/.../logic/session_block.dart` | tool result section; the turn's model |
| `QuestionBlockDetail` | same file | the parsed `AskUserQuestion` input |

## File map

**Backend (create):**
- `backend/internal/storage/sqlite/migrations/0095_block_event_source.sql`
- `backend/internal/storage/sqlite/migrations/0096_transcript_offsets.sql`
- `backend/internal/storage/sqlite/queries/transcript_offsets.sql`
- `backend/internal/storage/sqlite/store/transcript_offset_store.go` + `_test.go`
- `backend/internal/adapters/agent/claudecode/transcript.go` + `transcript_test.go`
- `backend/internal/adapters/agent/codex/transcript.go` + `transcript_test.go`
- `backend/internal/adapters/agent/blocktranscript/dispatch.go` + `dispatch_test.go`
- `backend/internal/observe/transcript/resolve.go` + `resolve_test.go`
- `backend/internal/observe/transcript/tail.go` + `tail_test.go`
- `backend/internal/observe/transcript/supervisor.go` + `supervisor_test.go`
- `testdata/transcripts/claude_code_turn.jsonl` + `claude_code_turn.expected.json`
- `testdata/transcripts/claude_code_edge.jsonl` + `claude_code_edge.expected.json`
- `testdata/transcripts/codex_turn.jsonl` + `codex_turn.expected.json`
- `testdata/transcripts/codex_edge.jsonl` + `codex_edge.expected.json`

**Backend (modify):** `backend/internal/domain/blockevent.go` + `_test.go`, `backend/internal/service/blockevent/types.go`, `service.go` + `service_test.go`, `backend/internal/storage/sqlite/queries/block_events.sql`, `backend/internal/storage/sqlite/store/block_event_store.go`, `backend/internal/httpd/controllers/dto.go`, `backend/internal/daemon/daemon.go`.

**Mobile (create):**
- `packages/mobile/lib/feature/blocks/logic/block_question.dart`
- `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_result_section.dart`
- `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_question_options.dart`
- `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_todo_list.dart`
- `packages/mobile/test/feature/blocks/logic/block_assembly_transcript_test.dart`
- `packages/mobile/test/feature/blocks/presentation/blocks_screen/transcript_rendering_test.dart`
- `testdata/blocks/assembly_transcript_turn.json`
- `testdata/blocks/assembly_transcript_tool_merge.json`
- `testdata/blocks/assembly_transcript_codex.json`
- `testdata/blocks/assembly_transcript_question.json`

**Mobile (modify):** `lib/feature/blocks/data/model/block_event_model.dart`, `lib/feature/blocks/logic/session_block.dart`, `block_assembly.dart`, `turn_grouping.dart`, `lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart`, `ui/widgets/block_card.dart`, `blocks_body.dart`, `block_list.dart`, `turn_group_status.dart`, and the tests each task names.

**Docs (modify):** `docs/superpowers/specs/2026-09-04-single-session-interface-design.md` (status line), `docs/STATUS.md`, `docs/architecture.md`, `todo_without_tmux.md`.

---

## Part A — Vocabulary, storage, and the record path

### Task 1: New block-event kinds and the `source` channel marker

Adds the seven transcript kinds to the normalized vocabulary, adds `Source` to the block-event record end to end (domain → store → service → wire), and raises per-session retention because transcript enrichment multiplies events per turn.

**Files:**
- Modify: `backend/internal/domain/blockevent.go`
- Modify: `backend/internal/domain/blockevent_test.go`
- Create: `backend/internal/storage/sqlite/migrations/0095_block_event_source.sql`
- Modify: `backend/internal/storage/sqlite/queries/block_events.sql`
- Modify: `backend/internal/storage/sqlite/store/block_event_store.go`
- Modify: `backend/internal/storage/sqlite/store/block_event_store_test.go`
- Modify: `backend/internal/service/blockevent/types.go`
- Modify: `backend/internal/service/blockevent/service.go:88` (the `Record` literal) and `:151` (`NewService` default)
- Modify: `backend/internal/httpd/controllers/dto.go` (`BlockEventView`, `blockEventViews`)
- Modify: `backend/internal/daemon/daemon.go:151`

**Interfaces:**
- Produces: `domain.BlockEventAssistantText`, `BlockEventReasoning`, `BlockEventToolStart`, `BlockEventToolResult`, `BlockEventTodo`, `BlockEventTurnModel`, `BlockEventCompaction`; `domain.BlockEventSource` with `BlockEventSourceHook` and `BlockEventSourceTranscript`; `domain.BlockTranscriptEvent`; `blockevent.Record.Source`. Task 3 fills `Source`; Tasks 4–6 return `[]domain.BlockTranscriptEvent`; Task 10 reads `source` off the wire.

- [ ] **Step 1: Write the failing domain test**

Append to `backend/internal/domain/blockevent_test.go`:

```go
func TestParseBlockEventKindAcceptsTranscriptKinds(t *testing.T) {
	for _, name := range []string{
		"assistant_text", "reasoning", "tool_start", "tool_result",
		"todo", "turn_model", "compaction",
	} {
		got, ok := ParseBlockEventKind(name)
		if !ok || string(got) != name {
			t.Fatalf("ParseBlockEventKind(%q) = %q,%v want %q,true", name, got, ok, name)
		}
	}
}

func TestBlockEventSourceValues(t *testing.T) {
	if BlockEventSourceHook != "hook" || BlockEventSourceTranscript != "transcript" {
		t.Fatalf("source constants = %q,%q", BlockEventSourceHook, BlockEventSourceTranscript)
	}
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `cd backend && go test ./internal/domain/ -run 'BlockEvent'`
Expected: FAIL — undefined `BlockEventSourceHook`, and `ParseBlockEventKind("assistant_text")` returns `unknown,false`.

- [ ] **Step 3: Add the kinds, the source type, and the mapper event struct**

In `backend/internal/domain/blockevent.go`, extend the const block (keep the existing ten entries above these):

```go
	BlockEventAssistantText     BlockEventKind = "assistant_text"
	BlockEventReasoning         BlockEventKind = "reasoning"
	BlockEventToolStart         BlockEventKind = "tool_start"
	BlockEventToolResult        BlockEventKind = "tool_result"
	BlockEventTodo              BlockEventKind = "todo"
	BlockEventTurnModel         BlockEventKind = "turn_model"
	BlockEventCompaction        BlockEventKind = "compaction"
```

Extend the `ParseBlockEventKind` switch to list them alongside the existing nine recognized names. Update the doc comment above the const block: it says "The first nine are the recognized names"; make it read "The recognized names are everything above BlockEventUnknown, which carries an unrecognized event through with its raw name preserved."

Append to the same file:

```go
// BlockEventSource names the channel a block event came from. Hooks are the
// status source and the native transcript is the body source; the projection
// applies precedence between them, so a client must be able to tell them apart.
type BlockEventSource string

// BlockEventSource values.
const (
	BlockEventSourceHook       BlockEventSource = "hook"
	BlockEventSourceTranscript BlockEventSource = "transcript"
)

// BlockTranscriptEvent is one per-harness transcript mapper's output. It lives
// in domain so an adapter package can produce it and the block-event service can
// consume it without either importing the other.
type BlockTranscriptEvent struct {
	Kind      BlockEventKind
	SourceID  string
	ToolName  string
	ToolUseID string
	ToolInput string
	Text      string
	ErrorType string
	RawEvent  string
}
```

- [ ] **Step 4: Run the domain test to verify it passes**

Run: `cd backend && go test ./internal/domain/ -run 'BlockEvent'`
Expected: PASS

- [ ] **Step 5: Add migration 0095**

Create `backend/internal/storage/sqlite/migrations/0095_block_event_source.sql`:

```sql
-- Migration 0095: record which channel produced a block event.
--
-- Hooks report status and the provider transcript reports body. The projection
-- applies precedence between the two, and a client needs to know which channel
-- a fact came from, so the channel is durable rather than inferred from kind.
-- Existing rows are hook rows: nothing else could have written them.

-- +goose Up
-- +goose StatementBegin
ALTER TABLE block_events ADD COLUMN source TEXT NOT NULL DEFAULT 'hook';
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE block_events DROP COLUMN source;
-- +goose StatementEnd
```

- [ ] **Step 6: Add `source` to the queries and regenerate sqlc**

In `backend/internal/storage/sqlite/queries/block_events.sql`, change the insert to carry the column:

```sql
-- name: InsertBlockEvent :one
INSERT INTO block_events (
    session_id, source_id, kind, raw_event, harness, tool_name, tool_use_id,
    tool_input, text, redacted_spans, error_type, hook_version, truncated_lines,
    source, created_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
RETURNING *;
```

In the same file, `SelectBlockEventsBeforeSeq` lists its columns explicitly. Add `source` to that list, after `truncated_lines`:

```sql
  SELECT seq, session_id, source_id, kind, raw_event, harness, tool_name, tool_use_id,
         text, redacted_spans, tool_input, error_type, hook_version, truncated_lines,
         source, created_at
```

Then, from the repo root:

```bash
npm run sqlc
```

Expected: `backend/internal/storage/sqlite/gen/block_events.sql.go` and `models.go` now carry a `Source string` field. Do not hand-edit them.

- [ ] **Step 7: Write the failing store test**

In `backend/internal/storage/sqlite/store/block_event_store_test.go`, add:

```go
func TestBlockEventStoreRoundTripsSource(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)
	if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
		SessionID: "s-1",
		Kind:      domain.BlockEventAssistantText,
		Source:    domain.BlockEventSourceTranscript,
		Text:      "done",
		CreatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("insert: %v", err)
	}
	recs, err := s.SelectBlockEventsBySession(ctx, "s-1", 0, 10)
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	if len(recs) != 1 || recs[0].Source != domain.BlockEventSourceTranscript {
		t.Fatalf("source = %+v", recs)
	}
}
```

Use whatever helper the neighbouring tests in that file already use to build a store; if it is not called `newTestStore`, copy the exact construction from the test directly above yours.

- [ ] **Step 8: Run it to verify it fails**

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run BlockEventStoreRoundTripsSource`
Expected: FAIL — `Record` has no field `Source`.

- [ ] **Step 9: Thread `Source` through the record and the store**

In `backend/internal/service/blockevent/types.go`, add the field to `Record`, immediately after `Kind`:

```go
	Source         domain.BlockEventSource `json:"source,omitempty"`
```

In `backend/internal/storage/sqlite/store/block_event_store.go`:
- `InsertBlockEvent`: add `Source: string(rec.Source),` to the `gen.InsertBlockEventParams` literal.
- Both `SelectBlockEventsBySession` and `SelectBlockEventsBeforeSeq`: add `Source: domain.BlockEventSource(row.Source),` to the `blockeventsvc.Record` literal.

In `backend/internal/service/blockevent/service.go`, in `Record`, add `Source: domain.BlockEventSourceHook,` to the `rec := Record{...}` literal.

- [ ] **Step 10: Run the store test to verify it passes**

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run BlockEventStoreRoundTripsSource`
Expected: PASS

- [ ] **Step 11: Put `source` on the wire and regenerate the API**

In `backend/internal/httpd/controllers/dto.go`, add to `BlockEventView` immediately after `Kind`:

```go
	Source         string                  `json:"source,omitempty"`
```

and in `blockEventViews`, add `Source: string(rec.Source),` to the `BlockEventView` literal.

Then, from the repo root:

```bash
npm run api
```

Expected: `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts` both gain the field.

- [ ] **Step 12: Raise per-session retention**

In `backend/internal/daemon/daemon.go:151`, change the retention argument:

```go
	blockEvents := blockevent.NewService(store, termMgr, 2000)
```

In `backend/internal/service/blockevent/service.go`, `NewService`'s zero-value default stays `500`; only the daemon's figure changes. Leave `maxBlockEventPage` in `backend/internal/httpd/controllers/sessions.go` at 500: a client pages backwards with `beforeSeq`, so a larger retention is reachable without widening one response.

Update the comment above `maxBlockEventPage` — it claims the page cap "matches the daemon's per-session retention (blockevent.NewService(store, termMgr, 500) in daemon.go)", which is no longer true. Replace that sentence with: "It bounds one response; a client reaches older events with beforeSeq."

- [ ] **Step 13: Run the gates**

```bash
cd backend
go build ./...
go test ./internal/domain/... ./internal/storage/sqlite/... ./internal/service/blockevent/... ./internal/httpd/...
go vet ./...
```

Expected: all pass. If `internal/httpd` reports spec drift, you missed `npm run api`.

- [ ] **Step 14: Commit**

```bash
git add backend/internal/domain backend/internal/storage/sqlite backend/internal/service/blockevent \
        backend/internal/httpd backend/internal/daemon/daemon.go frontend/src/api/schema.ts
git commit -m "feat(blocks): add the transcript block-event kinds and the source channel marker"
```

---

### Task 2: Durable transcript offsets

A per-session cursor so a daemon restart resumes the tail instead of re-emitting the whole transcript, and a path change resets it.

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0096_transcript_offsets.sql`
- Create: `backend/internal/storage/sqlite/queries/transcript_offsets.sql`
- Create: `backend/internal/storage/sqlite/store/transcript_offset_store.go`
- Create: `backend/internal/storage/sqlite/store/transcript_offset_store_test.go`

**Interfaces:**
- Produces:
  ```go
  func (s *Store) GetTranscriptOffset(ctx context.Context, sessionID string) (path string, offset int64, found bool, err error)
  func (s *Store) UpsertTranscriptOffset(ctx context.Context, sessionID, path string, offset int64, at time.Time) error
  ```
  Task 8 consumes exactly these two through its own `OffsetStore` interface. There is deliberately no delete: a terminated session that is later restored resumes the same native transcript, and dropping its cursor would re-emit the whole file as duplicate blocks. One row per session is a smaller cost than that.

- [ ] **Step 1: Add migration 0096**

Create `backend/internal/storage/sqlite/migrations/0096_transcript_offsets.sql`:

```sql
-- Migration 0096: one durable read cursor per session's native transcript.
--
-- The transcript tailer projects provider records into block events. Without a
-- durable cursor a daemon restart would re-emit every record it had already
-- projected. The path is stored beside the offset because a path change (agent
-- switch, provider rotation) means a different file, and an offset from the old
-- file would land mid-record in the new one.

-- +goose Up
-- +goose StatementBegin
CREATE TABLE transcript_offsets (
    session_id  TEXT PRIMARY KEY,
    path        TEXT NOT NULL,
    byte_offset INTEGER NOT NULL DEFAULT 0,
    updated_at  TIMESTAMP NOT NULL
);
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS transcript_offsets;
-- +goose StatementEnd
```

- [ ] **Step 2: Add the queries and regenerate sqlc**

Create `backend/internal/storage/sqlite/queries/transcript_offsets.sql`:

```sql
-- name: GetTranscriptOffset :one
SELECT * FROM transcript_offsets WHERE session_id = ?;

-- name: UpsertTranscriptOffset :exec
INSERT INTO transcript_offsets (session_id, path, byte_offset, updated_at)
VALUES (?, ?, ?, ?)
ON CONFLICT(session_id) DO UPDATE SET
    path = excluded.path,
    byte_offset = excluded.byte_offset,
    updated_at = excluded.updated_at;
```

Then, from the repo root: `npm run sqlc`

- [ ] **Step 3: Write the failing store test**

Create `backend/internal/storage/sqlite/store/transcript_offset_store_test.go`. Build the store exactly the way `block_event_store_test.go` does.

```go
package store

import (
	"context"
	"testing"
	"time"
)

func TestTranscriptOffsetUpsertGetDelete(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)
	now := time.Now().UTC()

	if _, _, found, err := s.GetTranscriptOffset(ctx, "s-1"); err != nil || found {
		t.Fatalf("empty get = found %v err %v", found, err)
	}

	if err := s.UpsertTranscriptOffset(ctx, "s-1", "/tmp/a.jsonl", 128, now); err != nil {
		t.Fatalf("upsert: %v", err)
	}
	path, offset, found, err := s.GetTranscriptOffset(ctx, "s-1")
	if err != nil || !found || path != "/tmp/a.jsonl" || offset != 128 {
		t.Fatalf("get = %q,%d,%v,%v", path, offset, found, err)
	}

	if err := s.UpsertTranscriptOffset(ctx, "s-1", "/tmp/b.jsonl", 4, now); err != nil {
		t.Fatalf("re-upsert: %v", err)
	}
	path, offset, _, _ = s.GetTranscriptOffset(ctx, "s-1")
	if path != "/tmp/b.jsonl" || offset != 4 {
		t.Fatalf("after re-upsert = %q,%d", path, offset)
	}
}
```

- [ ] **Step 4: Run it to verify it fails**

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run TranscriptOffset`
Expected: FAIL — undefined methods on `*Store`.

- [ ] **Step 5: Write the store methods**

Create `backend/internal/storage/sqlite/store/transcript_offset_store.go`:

```go
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

// GetTranscriptOffset returns the durable read cursor for one session's native
// transcript. found=false means the session has never been tailed.
func (s *Store) GetTranscriptOffset(ctx context.Context, sessionID string) (string, int64, bool, error) {
	row, err := s.qr.GetTranscriptOffset(ctx, sessionID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", 0, false, nil
	}
	if err != nil {
		return "", 0, false, fmt.Errorf("get transcript offset for %s: %w", sessionID, err)
	}
	return row.Path, row.ByteOffset, true, nil
}

// UpsertTranscriptOffset advances the cursor. A different path replaces the row
// wholesale: an offset from another file cannot be resumed against this one.
func (s *Store) UpsertTranscriptOffset(ctx context.Context, sessionID, path string, offset int64, at time.Time) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	if err := s.qw.UpsertTranscriptOffset(ctx, gen.UpsertTranscriptOffsetParams{
		SessionID:  sessionID,
		Path:       path,
		ByteOffset: offset,
		UpdatedAt:  at,
	}); err != nil {
		return fmt.Errorf("upsert transcript offset for %s: %w", sessionID, err)
	}
	return nil
}
```

If the generated param struct or field names differ from the above, use the generated names — do not rename the generated code.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run TranscriptOffset`
Expected: PASS

- [ ] **Step 7: Run the migration suite**

Run: `cd backend && go test ./internal/storage/sqlite/...`
Expected: PASS. The migration ledger test discovers both SQL and registered Go migrations, so the two new SQL files need no registration.

- [ ] **Step 8: Commit**

```bash
git add backend/internal/storage/sqlite
git commit -m "feat(storage): persist a per-session transcript read cursor"
```

---

### Task 3: `blockevent.Service.RecordTranscript`

The transcript-side sibling of `Record`: same redaction, same store, same trim, same mux publish, a larger text budget, and `Source = transcript`.

**Files:**
- Modify: `backend/internal/service/blockevent/service.go`
- Modify: `backend/internal/service/blockevent/service_test.go`

**Interfaces:**
- Consumes: `domain.BlockTranscriptEvent`, `blockevent.Record.Source` (Task 1).
- Produces: `func (s *Service) RecordTranscript(ctx context.Context, sessionID domain.SessionID, harness string, ev domain.BlockTranscriptEvent) error`. Task 8's `Sink` interface is exactly this signature.

- [ ] **Step 1: Write the failing service test**

Append to `backend/internal/service/blockevent/service_test.go`:

```go
func TestRecordTranscriptMarksSourceAndRedacts(t *testing.T) {
	store, pub := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, pub, 500)

	err := svc.RecordTranscript(context.Background(), "s-1", "claude-code", domain.BlockTranscriptEvent{
		Kind:      domain.BlockEventToolResult,
		SourceID:  "toolu_1",
		ToolUseID: "toolu_1",
		Text:      "token ghp_abcdefghijklmnopqrstuvwxyz0123 leaked",
	})
	if err != nil {
		t.Fatalf("RecordTranscript: %v", err)
	}
	if len(store.inserted) != 1 {
		t.Fatalf("inserted %d", len(store.inserted))
	}
	rec := store.inserted[0]
	if rec.Source != domain.BlockEventSourceTranscript {
		t.Fatalf("source = %q", rec.Source)
	}
	if rec.Kind != domain.BlockEventToolResult || rec.SourceID != "toolu_1" {
		t.Fatalf("record = %+v", rec)
	}
	if strings.Contains(rec.Text, "ghp_abcdefghijklmnopqrstuvwxyz0123") {
		t.Fatal("secret survived redaction")
	}
	if len(rec.RedactedSpans) == 0 {
		t.Fatal("redacted spans were not reported")
	}
	if len(pub.published) != 1 || pub.published[0].Seq != 1 {
		t.Fatalf("published %+v", pub.published)
	}
}

func TestRecordTranscriptCapsAndMarksTruncation(t *testing.T) {
	store := &fakeStore{}
	svc := NewService(store, nil, 500)

	body := strings.Repeat("line\n", 40000)
	if err := svc.RecordTranscript(context.Background(), "s-1", "codex", domain.BlockTranscriptEvent{
		Kind: domain.BlockEventAssistantText,
		Text: body,
	}); err != nil {
		t.Fatalf("RecordTranscript: %v", err)
	}
	rec := store.inserted[0]
	if len(rec.Text) > maxTranscriptTextBytes {
		t.Fatalf("text len = %d", len(rec.Text))
	}
	if rec.TruncatedLines == 0 {
		t.Fatal("a capped body must be marked")
	}
	if !utf8.ValidString(rec.Text) {
		t.Fatal("cap split a rune")
	}
}

func TestRecordTranscriptIgnoresEmptyKind(t *testing.T) {
	store := &fakeStore{}
	svc := NewService(store, nil, 500)
	if err := svc.RecordTranscript(context.Background(), "s-1", "codex", domain.BlockTranscriptEvent{}); err != nil {
		t.Fatalf("RecordTranscript: %v", err)
	}
	if len(store.inserted) != 0 {
		t.Fatal("an event with no kind is not a block event")
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/service/blockevent/ -run RecordTranscript`
Expected: FAIL — `svc.RecordTranscript` undefined, `maxTranscriptTextBytes` undefined.

- [ ] **Step 3: Extract the shared truncation and persistence, then add `RecordTranscript`**

In `backend/internal/service/blockevent/service.go`, add the new budgets beside `maxTextBytes`:

```go
// maxTranscriptTextBytes is the transcript channel's body budget. A tool result
// is the largest thing the phone ever sees and truncating it to the hook budget
// would hide most of it, so the transcript gets four times the room; the cut is
// still counted rather than hidden.
const maxTranscriptTextBytes = 64 << 10

// maxTranscriptToolInputBytes caps a tool's full input separately from its
// result: an input that big is a generated file, not something a phone renders.
const maxTranscriptToolInputBytes = 16 << 10
```

Add the two helpers at the bottom of the file:

```go
func capText(s string, limit int) (string, int) {
	if len(s) <= limit {
		return s, 0
	}
	cut := limit
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	return s[:cut], strings.Count(s[cut:], "\n") + 1
}

func (s *Service) persist(ctx context.Context, rec Record) error {
	seq, err := s.store.InsertBlockEvent(ctx, rec)
	if err != nil {
		return err
	}
	rec.Seq = seq

	if s.writes.Add(1)%trimEvery == 0 {
		_, _ = s.store.TrimBlockEvents(ctx, rec.SessionID, s.retain)
	}

	if s.pub != nil {
		s.pub.PublishBlockEvent(rec.SessionID, rec)
	}
	return nil
}
```

Rewrite the tail of `Record` to use them. Replace the inline truncation block

```go
	truncated := 0
	if len(text) > maxTextBytes {
		cut := maxTextBytes
		for cut > 0 && !utf8.RuneStart(text[cut]) {
			cut--
		}
		truncated = strings.Count(text[cut:], "\n") + 1
		text = text[:cut]
	}
```

with

```go
	text, truncated := capText(text, maxTextBytes)
```

and replace everything from `seq, err := s.store.InsertBlockEvent(ctx, rec)` to the end of `Record` with

```go
	return s.persist(ctx, rec)
```

Then add:

```go
// RecordTranscript normalizes one provider-transcript record into a block
// event. It is the body channel's entry point: same redaction, caps, store,
// trim and publish as a hook event, marked so the projection can apply
// precedence between the two channels.
func (s *Service) RecordTranscript(
	ctx context.Context,
	sessionID domain.SessionID,
	harness string,
	ev domain.BlockTranscriptEvent,
) error {
	if ev.Kind == "" {
		return nil
	}
	text, textTruncated := capText(ev.Text, maxTranscriptTextBytes)
	input, inputTruncated := capText(ev.ToolInput, maxTranscriptToolInputBytes)
	redacted := redact.Text(text)
	redactedInput := redact.Text(input)

	return s.persist(ctx, Record{
		SessionID:      string(sessionID),
		SourceID:       ev.SourceID,
		Kind:           ev.Kind,
		Source:         domain.BlockEventSourceTranscript,
		RawEvent:       ev.RawEvent,
		Harness:        harness,
		ToolName:       ev.ToolName,
		ToolUseID:      ev.ToolUseID,
		ToolInput:      redactedInput.Text,
		Text:           redacted.Text,
		RedactedSpans:  redacted.Spans,
		ErrorType:      ev.ErrorType,
		TruncatedLines: textTruncated + inputTruncated,
		CreatedAt:      time.Now().UTC(),
	})
}
```

- [ ] **Step 4: Run the whole package to verify nothing regressed**

Run: `cd backend && go test ./internal/service/blockevent/`
Expected: PASS, including the pre-existing `TestRecordNormalizesAndPublishes` and the shared-fixture test — the `Record` refactor must not change hook behaviour.

- [ ] **Step 5: Run the gates and commit**

```bash
cd backend && go build ./... && go test ./... && go vet ./...
git add backend/internal/service/blockevent
git commit -m "feat(blocks): record provider transcript events through the block-event service"
```

---

## Part B — Per-harness transcript mappers

A mapper is a pure function over one JSONL line. It never reads a file, never
holds state, and never fails: an unrecognised record type returns
`(nil, false)` so the tailer can count it, and a record it recognises but has
nothing to show for returns `(nil, true)`.

Fixture contract, shared by Tasks 4 and 5:

- `testdata/transcripts/<name>.jsonl` — one provider record per line, captured
  from a real session on this machine with the content replaced.
- `testdata/transcripts/<name>.expected.json` — `{"harness": ..., "lines": [...]}`
  with **one entry per line of the `.jsonl`, in order**:
  `{"known": true|false, "events": [{"kind","sourceId","toolName","toolUseId","toolInput","text","errorType","rawEvent"}]}`.
  Absent event fields mean empty string. A `sourceId` of `"*"` means "must be
  non-empty, exact value not asserted" — it is how a line-hash id is expressed.

### Task 4: The Claude Code transcript mapper

**Files:**
- Create: `backend/internal/adapters/agent/claudecode/transcript.go`
- Create: `backend/internal/adapters/agent/claudecode/transcript_test.go`
- Create: `testdata/transcripts/claude_code_turn.jsonl`
- Create: `testdata/transcripts/claude_code_turn.expected.json`
- Create: `testdata/transcripts/claude_code_edge.jsonl`
- Create: `testdata/transcripts/claude_code_edge.expected.json`

**Interfaces:**
- Consumes: `domain.BlockTranscriptEvent` and the seven kinds from Task 1.
- Produces: `func MapTranscriptRecord(line []byte) ([]domain.BlockTranscriptEvent, bool)` in package `claudecode`. Task 6 registers it.

- [ ] **Step 1: Write the two fixtures**

Create `testdata/transcripts/claude_code_turn.jsonl` (six lines, no trailing blank line beyond the final newline):

```
{"type":"assistant","uuid":"u-1","parentUuid":null,"isSidechain":false,"message":{"id":"msg_1","model":"claude-sonnet-5","role":"assistant","content":[{"type":"thinking","thinking":"The tests live under backend.","signature":"sig"}]}}
{"type":"assistant","uuid":"u-2","parentUuid":"u-1","isSidechain":false,"message":{"id":"msg_2","model":"claude-sonnet-5","role":"assistant","content":[{"type":"text","text":"Running the backend suite."},{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"go test ./..."}}]}}
{"type":"user","uuid":"u-3","parentUuid":"u-2","isSidechain":false,"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","is_error":false,"content":"ok  operator/backend 1.2s"}]}}
{"type":"assistant","uuid":"u-4","parentUuid":"u-3","isSidechain":false,"message":{"id":"msg_3","model":"claude-sonnet-5","role":"assistant","content":[{"type":"tool_use","id":"toolu_2","name":"Read","input":{"file_path":"/repo/main.go"}}]}}
{"type":"user","uuid":"u-5","parentUuid":"u-4","isSidechain":false,"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_2","is_error":true,"content":[{"type":"text","text":"File does not exist."}]}]}}
{"type":"assistant","uuid":"u-6","parentUuid":"u-5","isSidechain":false,"message":{"id":"msg_4","model":"claude-sonnet-5","role":"assistant","content":[{"type":"text","text":"Everything passes."}]}}
```

Create `testdata/transcripts/claude_code_turn.expected.json`:

```json
{
  "harness": "claude-code",
  "lines": [
    { "known": true, "events": [
      { "kind": "turn_model", "sourceId": "u-1", "text": "claude-sonnet-5" },
      { "kind": "reasoning", "sourceId": "u-1", "text": "The tests live under backend." }
    ] },
    { "known": true, "events": [
      { "kind": "turn_model", "sourceId": "u-2", "text": "claude-sonnet-5" },
      { "kind": "assistant_text", "sourceId": "u-2", "text": "Running the backend suite." },
      { "kind": "tool_start", "sourceId": "toolu_1", "toolUseId": "toolu_1", "toolName": "Bash", "toolInput": "{\"command\":\"go test ./...\"}" }
    ] },
    { "known": true, "events": [
      { "kind": "tool_result", "sourceId": "toolu_1", "toolUseId": "toolu_1", "text": "ok  operator/backend 1.2s" }
    ] },
    { "known": true, "events": [
      { "kind": "turn_model", "sourceId": "u-4", "text": "claude-sonnet-5" },
      { "kind": "tool_start", "sourceId": "toolu_2", "toolUseId": "toolu_2", "toolName": "Read", "toolInput": "{\"file_path\":\"/repo/main.go\"}" }
    ] },
    { "known": true, "events": [
      { "kind": "tool_result", "sourceId": "toolu_2", "toolUseId": "toolu_2", "text": "File does not exist.", "errorType": "tool_failed" }
    ] },
    { "known": true, "events": [
      { "kind": "turn_model", "sourceId": "u-6", "text": "claude-sonnet-5" },
      { "kind": "assistant_text", "sourceId": "u-6", "text": "Everything passes." }
    ] }
  ]
}
```

Create `testdata/transcripts/claude_code_edge.jsonl` (eight lines; the last one is deliberately not JSON):

```
{"type":"assistant","uuid":"u-10","isSidechain":true,"message":{"model":"claude-sonnet-5","content":[{"type":"text","text":"subagent chatter"}]}}
{"type":"queue-operation","operation":"enqueue","sessionId":"s-1","timestamp":"2026-09-04T00:00:00.000Z"}
{"type":"assistant","uuid":"u-11","isSidechain":false,"message":{"model":"claude-sonnet-5","content":[{"type":"text","text":"first"},{"type":"text","text":"second"}]}}
{"type":"assistant","uuid":"u-12","isSidechain":false,"message":{"model":"claude-sonnet-5","content":[{"type":"tool_use","id":"toolu_9","name":"AskUserQuestion","input":{"questions":[{"question":"Which branch?","header":"Branch","multiSelect":false,"options":[{"label":"main","description":"the default branch"},{"label":"develop","description":"the integration branch"}]}]}}]}}
{"type":"system","subtype":"compact_boundary","uuid":"u-13","isSidechain":false,"content":"Conversation compacted","compactMetadata":{"trigger":"manual","preTokens":278168}}
{"type":"system","subtype":"stop_hook_summary","uuid":"u-14","isSidechain":false,"content":"hook ran"}
{"type":"future-record-kind","uuid":"u-15"}
not json at all
```

Create `testdata/transcripts/claude_code_edge.expected.json`:

```json
{
  "harness": "claude-code",
  "lines": [
    { "known": true, "events": [] },
    { "known": true, "events": [] },
    { "known": true, "events": [
      { "kind": "turn_model", "sourceId": "u-11", "text": "claude-sonnet-5" },
      { "kind": "assistant_text", "sourceId": "u-11", "text": "first" },
      { "kind": "assistant_text", "sourceId": "u-11#1", "text": "second" }
    ] },
    { "known": true, "events": [
      { "kind": "turn_model", "sourceId": "u-12", "text": "claude-sonnet-5" },
      { "kind": "question_asked", "sourceId": "toolu_9", "toolUseId": "toolu_9", "toolName": "AskUserQuestion", "toolInput": "{\"questions\":[{\"question\":\"Which branch?\",\"header\":\"Branch\",\"multiSelect\":false,\"options\":[{\"label\":\"main\",\"description\":\"the default branch\"},{\"label\":\"develop\",\"description\":\"the integration branch\"}]}]}" }
    ] },
    { "known": true, "events": [
      { "kind": "compaction", "sourceId": "u-13", "text": "Conversation compacted (manual)" }
    ] },
    { "known": true, "events": [] },
    { "known": false, "events": [] },
    { "known": false, "events": [] }
  ]
}
```

- [ ] **Step 2: Write the failing mapper test**

Create `backend/internal/adapters/agent/claudecode/transcript_test.go`:

```go
package claudecode

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type transcriptFixture struct {
	Harness string `json:"harness"`
	Lines   []struct {
		Known  bool `json:"known"`
		Events []struct {
			Kind      string `json:"kind"`
			SourceID  string `json:"sourceId"`
			ToolName  string `json:"toolName"`
			ToolUseID string `json:"toolUseId"`
			ToolInput string `json:"toolInput"`
			Text      string `json:"text"`
			ErrorType string `json:"errorType"`
			RawEvent  string `json:"rawEvent"`
		} `json:"events"`
	} `json:"lines"`
}

func TestMapTranscriptRecordFixtures(t *testing.T) {
	dir := filepath.Join("..", "..", "..", "..", "..", "testdata", "transcripts")
	for _, name := range []string{"claude_code_turn", "claude_code_edge"} {
		t.Run(name, func(t *testing.T) {
			raw, err := os.ReadFile(filepath.Join(dir, name+".expected.json"))
			if err != nil {
				t.Fatalf("read expectations: %v", err)
			}
			var fixture transcriptFixture
			if err := json.Unmarshal(raw, &fixture); err != nil {
				t.Fatalf("decode expectations: %v", err)
			}
			file, err := os.Open(filepath.Join(dir, name+".jsonl"))
			if err != nil {
				t.Fatalf("open transcript: %v", err)
			}
			defer func() { _ = file.Close() }()

			scanner := bufio.NewScanner(file)
			scanner.Buffer(make([]byte, 0, 1<<20), 1<<20)
			index := 0
			for scanner.Scan() {
				if index >= len(fixture.Lines) {
					t.Fatalf("transcript has more lines than expectations (%d)", len(fixture.Lines))
				}
				want := fixture.Lines[index]
				got, known := MapTranscriptRecord(scanner.Bytes())
				if known != want.Known {
					t.Fatalf("line %d known = %v want %v", index+1, known, want.Known)
				}
				if len(got) != len(want.Events) {
					t.Fatalf("line %d produced %d events, want %d: %+v", index+1, len(got), len(want.Events), got)
				}
				for i, expected := range want.Events {
					actual := got[i]
					if string(actual.Kind) != expected.Kind ||
						actual.ToolName != expected.ToolName ||
						actual.ToolUseID != expected.ToolUseID ||
						actual.ToolInput != expected.ToolInput ||
						actual.Text != expected.Text ||
						actual.ErrorType != expected.ErrorType ||
						actual.RawEvent != expected.RawEvent {
						t.Fatalf("line %d event %d = %+v want %+v", index+1, i, actual, expected)
					}
					if expected.SourceID == "*" {
						if actual.SourceID == "" {
							t.Fatalf("line %d event %d has an empty source id", index+1, i)
						}
					} else if actual.SourceID != expected.SourceID {
						t.Fatalf("line %d event %d source id = %q want %q", index+1, i, actual.SourceID, expected.SourceID)
					}
				}
				index++
			}
			if err := scanner.Err(); err != nil {
				t.Fatalf("scan transcript: %v", err)
			}
			if index != len(fixture.Lines) {
				t.Fatalf("consumed %d lines, expectations cover %d", index, len(fixture.Lines))
			}
		})
	}
	_ = domain.BlockEventAssistantText
}
```

Delete the trailing `_ = domain.BlockEventAssistantText` line once the file compiles with the `domain` import actually used; if it is not used, drop the import instead.

- [ ] **Step 3: Run it to verify it fails**

Run: `cd backend && go test ./internal/adapters/agent/claudecode/ -run MapTranscriptRecord`
Expected: FAIL — `MapTranscriptRecord` undefined.

- [ ] **Step 4: Write the mapper**

Create `backend/internal/adapters/agent/claudecode/transcript.go`:

```go
package claudecode

import (
	"encoding/json"
	"strconv"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type claudeTranscriptRecord struct {
	Type            string          `json:"type"`
	Subtype         string          `json:"subtype"`
	UUID            string          `json:"uuid"`
	IsSidechain     bool            `json:"isSidechain"`
	Content         json.RawMessage `json:"content"`
	CompactMetadata struct {
		Trigger string `json:"trigger"`
	} `json:"compactMetadata"`
	Message struct {
		Model   string          `json:"model"`
		Content json.RawMessage `json:"content"`
	} `json:"message"`
}

type claudeContentBlock struct {
	Type      string          `json:"type"`
	Text      string          `json:"text"`
	Thinking  string          `json:"thinking"`
	ID        string          `json:"id"`
	Name      string          `json:"name"`
	Input     json.RawMessage `json:"input"`
	ToolUseID string          `json:"tool_use_id"`
	Content   json.RawMessage `json:"content"`
	IsError   bool            `json:"is_error"`
}

// claudeIgnoredRecordTypes are bookkeeping records that carry no user-facing
// content. They are listed rather than defaulted so a record type Claude Code
// adds in a future release is reported as unrecognised instead of silently
// dropped.
var claudeIgnoredRecordTypes = map[string]struct{}{
	"attachment":            {},
	"last-prompt":           {},
	"queue-operation":       {},
	"mode":                  {},
	"summary":               {},
	"file-history-snapshot": {},
}

// MapTranscriptRecord maps one line of Claude Code's native JSONL transcript
// onto zero or more block transcript events. ok=false means the record type was
// not recognised; the caller counts those so a harness upgrade degrades to
// fewer blocks rather than to a crash.
func MapTranscriptRecord(line []byte) ([]domain.BlockTranscriptEvent, bool) {
	var rec claudeTranscriptRecord
	if err := json.Unmarshal(line, &rec); err != nil {
		return nil, false
	}
	if rec.IsSidechain {
		return nil, true
	}
	switch rec.Type {
	case "assistant":
		return claudeAssistantEvents(rec), true
	case "user":
		return claudeUserEvents(rec), true
	case "system":
		if rec.Subtype != "compact_boundary" {
			return nil, true
		}
		return []domain.BlockTranscriptEvent{{
			Kind:     domain.BlockEventCompaction,
			SourceID: rec.UUID,
			Text:     claudeCompactionText(rec),
		}}, true
	default:
		if _, ignored := claudeIgnoredRecordTypes[rec.Type]; ignored {
			return nil, true
		}
		return nil, false
	}
}

func claudeAssistantEvents(rec claudeTranscriptRecord) []domain.BlockTranscriptEvent {
	events := make([]domain.BlockTranscriptEvent, 0, 4)
	if model := strings.TrimSpace(rec.Message.Model); model != "" {
		events = append(events, domain.BlockTranscriptEvent{
			Kind:     domain.BlockEventTurnModel,
			SourceID: rec.UUID,
			Text:     model,
		})
	}
	counts := map[domain.BlockEventKind]int{}
	for _, block := range claudeContentBlocks(rec.Message.Content) {
		switch block.Type {
		case "text":
			if strings.TrimSpace(block.Text) == "" {
				continue
			}
			events = append(events, domain.BlockTranscriptEvent{
				Kind:     domain.BlockEventAssistantText,
				SourceID: claudeContentSourceID(rec.UUID, domain.BlockEventAssistantText, counts),
				Text:     block.Text,
			})
		case "thinking":
			if strings.TrimSpace(block.Thinking) == "" {
				continue
			}
			events = append(events, domain.BlockTranscriptEvent{
				Kind:     domain.BlockEventReasoning,
				SourceID: claudeContentSourceID(rec.UUID, domain.BlockEventReasoning, counts),
				Text:     block.Thinking,
			})
		case "tool_use":
			events = append(events, claudeToolUseEvent(block))
		}
	}
	return events
}

func claudeContentSourceID(uuid string, kind domain.BlockEventKind, counts map[domain.BlockEventKind]int) string {
	index := counts[kind]
	counts[kind] = index + 1
	if index == 0 {
		return uuid
	}
	return uuid + "#" + strconv.Itoa(index)
}

func claudeToolUseEvent(block claudeContentBlock) domain.BlockTranscriptEvent {
	input := strings.TrimSpace(string(block.Input))
	switch block.Name {
	case "TodoWrite":
		return domain.BlockTranscriptEvent{
			Kind:      domain.BlockEventTodo,
			SourceID:  block.ID,
			ToolUseID: block.ID,
			ToolName:  block.Name,
			ToolInput: input,
			Text:      input,
		}
	case "AskUserQuestion":
		return domain.BlockTranscriptEvent{
			Kind:      domain.BlockEventQuestionAsked,
			SourceID:  block.ID,
			ToolUseID: block.ID,
			ToolName:  block.Name,
			ToolInput: input,
		}
	default:
		return domain.BlockTranscriptEvent{
			Kind:      domain.BlockEventToolStart,
			SourceID:  block.ID,
			ToolUseID: block.ID,
			ToolName:  block.Name,
			ToolInput: input,
		}
	}
}

func claudeUserEvents(rec claudeTranscriptRecord) []domain.BlockTranscriptEvent {
	events := make([]domain.BlockTranscriptEvent, 0, 2)
	for _, block := range claudeContentBlocks(rec.Message.Content) {
		if block.Type != "tool_result" || block.ToolUseID == "" {
			continue
		}
		event := domain.BlockTranscriptEvent{
			Kind:      domain.BlockEventToolResult,
			SourceID:  block.ToolUseID,
			ToolUseID: block.ToolUseID,
			Text:      claudeFlattenText(block.Content),
		}
		if block.IsError {
			event.ErrorType = "tool_failed"
		}
		events = append(events, event)
	}
	return events
}

func claudeContentBlocks(raw json.RawMessage) []claudeContentBlock {
	if len(raw) == 0 {
		return nil
	}
	var blocks []claudeContentBlock
	if err := json.Unmarshal(raw, &blocks); err != nil {
		return nil
	}
	return blocks
}

func claudeFlattenText(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return text
	}
	blocks := claudeContentBlocks(raw)
	if blocks == nil {
		return strings.TrimSpace(string(raw))
	}
	parts := make([]string, 0, len(blocks))
	for _, block := range blocks {
		if block.Type == "text" && block.Text != "" {
			parts = append(parts, block.Text)
		}
	}
	return strings.Join(parts, "\n")
}

func claudeCompactionText(rec claudeTranscriptRecord) string {
	text := strings.TrimSpace(claudeFlattenText(rec.Content))
	if text == "" {
		text = "Conversation compacted"
	}
	if trigger := strings.TrimSpace(rec.CompactMetadata.Trigger); trigger != "" {
		text += " (" + trigger + ")"
	}
	return text
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd backend && go test ./internal/adapters/agent/claudecode/`
Expected: PASS, including the pre-existing tests in that package.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/adapters/agent/claudecode testdata/transcripts
git commit -m "feat(claude-code): map native transcript records onto block events"
```

---

### Task 5: The Codex transcript mapper

Codex needs this more than Claude Code does: its hook table maps only
`session-start`, `user-prompt-submit`, `permission-request` and `stop`, so
without the transcript a Codex session on the phone has no tool blocks at all.

**Files:**
- Create: `backend/internal/adapters/agent/codex/transcript.go`
- Create: `backend/internal/adapters/agent/codex/transcript_test.go`
- Create: `testdata/transcripts/codex_turn.jsonl`
- Create: `testdata/transcripts/codex_turn.expected.json`
- Create: `testdata/transcripts/codex_edge.jsonl`
- Create: `testdata/transcripts/codex_edge.expected.json`

**Interfaces:**
- Produces: `func MapTranscriptRecord(line []byte) ([]domain.BlockTranscriptEvent, bool)` in package `codex`, the same signature as Task 4's.

- [ ] **Step 1: Write the two fixtures**

Create `testdata/transcripts/codex_turn.jsonl` (twelve lines):

```
{"timestamp":"2026-09-04T10:00:00.000Z","type":"session_meta","payload":{"id":"019d7309-c80b-7ca1-8824-e4122d0faa67","cwd":"/repo","originator":"codex_cli_rs"}}
{"timestamp":"2026-09-04T10:00:01.000Z","type":"turn_context","payload":{"turn_id":"t-1","cwd":"/repo","model":"gpt-5.4","approval_policy":"on-request"}}
{"timestamp":"2026-09-04T10:00:02.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"run the tests"}]}}
{"timestamp":"2026-09-04T10:00:03.000Z","type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"**Planning the run**"}],"encrypted_content":"xxx","content":[]}}
{"timestamp":"2026-09-04T10:00:04.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"commentary","content":[{"type":"output_text","text":"Running the suite now."}]}}
{"timestamp":"2026-09-04T10:00:05.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"go test ./...\"}","call_id":"call_1"}}
{"timestamp":"2026-09-04T10:00:06.000Z","type":"event_msg","payload":{"type":"exec_command_end","call_id":"call_1"}}
{"timestamp":"2026-09-04T10:00:07.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call_1","output":"ok  operator/backend 1.2s"}}
{"timestamp":"2026-09-04T10:00:08.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","call_id":"call_2","status":"completed","input":"*** Begin Patch"}}
{"timestamp":"2026-09-04T10:00:09.000Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call_2","output":"{\"output\":\"Success.\"}"}}
{"timestamp":"2026-09-04T10:00:10.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"All green."}]}}
{"timestamp":"2026-09-04T10:00:11.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10}}}}
```

Create `testdata/transcripts/codex_turn.expected.json`:

```json
{
  "harness": "codex",
  "lines": [
    { "known": true, "events": [] },
    { "known": true, "events": [ { "kind": "turn_model", "sourceId": "*", "text": "gpt-5.4" } ] },
    { "known": true, "events": [] },
    { "known": true, "events": [ { "kind": "reasoning", "sourceId": "*", "text": "**Planning the run**" } ] },
    { "known": true, "events": [ { "kind": "assistant_text", "sourceId": "*", "text": "Running the suite now.", "rawEvent": "commentary" } ] },
    { "known": true, "events": [ { "kind": "tool_start", "sourceId": "call_1", "toolUseId": "call_1", "toolName": "exec_command", "toolInput": "{\"cmd\":\"go test ./...\"}" } ] },
    { "known": true, "events": [] },
    { "known": true, "events": [ { "kind": "tool_result", "sourceId": "call_1", "toolUseId": "call_1", "text": "ok  operator/backend 1.2s" } ] },
    { "known": true, "events": [ { "kind": "tool_start", "sourceId": "call_2", "toolUseId": "call_2", "toolName": "apply_patch", "toolInput": "*** Begin Patch" } ] },
    { "known": true, "events": [ { "kind": "tool_result", "sourceId": "call_2", "toolUseId": "call_2", "text": "{\"output\":\"Success.\"}" } ] },
    { "known": true, "events": [ { "kind": "assistant_text", "sourceId": "*", "text": "All green.", "rawEvent": "final_answer" } ] },
    { "known": true, "events": [] }
  ]
}
```

Create `testdata/transcripts/codex_edge.jsonl` (seven lines):

```
{"timestamp":"2026-09-04T11:00:00.074Z","type":"compacted","payload":{"message":"","replacement_history":[]}}
{"timestamp":"2026-09-04T11:00:00.082Z","type":"event_msg","payload":{"type":"context_compacted"}}
{"timestamp":"2026-09-04T11:00:01.000Z","type":"response_item","payload":{"type":"reasoning","summary":[],"encrypted_content":"xxx","content":[]}}
{"timestamp":"2026-09-04T11:00:02.000Z","type":"event_msg","payload":{"type":"sub_agent_activity","agent":"child"}}
{"timestamp":"2026-09-04T11:00:03.000Z","type":"event_msg","payload":{"type":"future_event_kind"}}
{"timestamp":"2026-09-04T11:00:04.000Z","type":"response_item","payload":{"type":"future_item_kind"}}
{"timestamp":"2026-09-04T11:00:05.000Z","type":"future_record_kind","payload":{}}
```

Create `testdata/transcripts/codex_edge.expected.json`. The first two lines
deliberately share a source id: Codex writes `compacted` and its `event_msg`
twin milliseconds apart, and one compaction must project to one block.

```json
{
  "harness": "codex",
  "lines": [
    { "known": true, "events": [ { "kind": "compaction", "sourceId": "compaction:2026-09-04T11:00:00", "text": "Conversation compacted" } ] },
    { "known": true, "events": [ { "kind": "compaction", "sourceId": "compaction:2026-09-04T11:00:00", "text": "Conversation compacted" } ] },
    { "known": true, "events": [] },
    { "known": true, "events": [] },
    { "known": false, "events": [] },
    { "known": false, "events": [] },
    { "known": false, "events": [] }
  ]
}
```

- [ ] **Step 2: Write the failing mapper test**

Create `backend/internal/adapters/agent/codex/transcript_test.go` with the **same body as Task 4 Step 2**, changed in exactly three places: `package codex`, the fixture name list `{"codex_turn", "codex_edge"}`, and no `domain` import (this file does not reference it). Repeating it is deliberate: the two adapters are independent packages and a shared test helper package would couple them.

```go
package codex

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

type transcriptFixture struct {
	Harness string `json:"harness"`
	Lines   []struct {
		Known  bool `json:"known"`
		Events []struct {
			Kind      string `json:"kind"`
			SourceID  string `json:"sourceId"`
			ToolName  string `json:"toolName"`
			ToolUseID string `json:"toolUseId"`
			ToolInput string `json:"toolInput"`
			Text      string `json:"text"`
			ErrorType string `json:"errorType"`
			RawEvent  string `json:"rawEvent"`
		} `json:"events"`
	} `json:"lines"`
}

func TestMapTranscriptRecordFixtures(t *testing.T) {
	dir := filepath.Join("..", "..", "..", "..", "..", "testdata", "transcripts")
	for _, name := range []string{"codex_turn", "codex_edge"} {
		t.Run(name, func(t *testing.T) {
			raw, err := os.ReadFile(filepath.Join(dir, name+".expected.json"))
			if err != nil {
				t.Fatalf("read expectations: %v", err)
			}
			var fixture transcriptFixture
			if err := json.Unmarshal(raw, &fixture); err != nil {
				t.Fatalf("decode expectations: %v", err)
			}
			file, err := os.Open(filepath.Join(dir, name+".jsonl"))
			if err != nil {
				t.Fatalf("open rollout: %v", err)
			}
			defer func() { _ = file.Close() }()

			scanner := bufio.NewScanner(file)
			scanner.Buffer(make([]byte, 0, 1<<20), 1<<20)
			index := 0
			for scanner.Scan() {
				if index >= len(fixture.Lines) {
					t.Fatalf("rollout has more lines than expectations (%d)", len(fixture.Lines))
				}
				want := fixture.Lines[index]
				got, known := MapTranscriptRecord(scanner.Bytes())
				if known != want.Known {
					t.Fatalf("line %d known = %v want %v", index+1, known, want.Known)
				}
				if len(got) != len(want.Events) {
					t.Fatalf("line %d produced %d events, want %d: %+v", index+1, len(got), len(want.Events), got)
				}
				for i, expected := range want.Events {
					actual := got[i]
					if string(actual.Kind) != expected.Kind ||
						actual.ToolName != expected.ToolName ||
						actual.ToolUseID != expected.ToolUseID ||
						actual.ToolInput != expected.ToolInput ||
						actual.Text != expected.Text ||
						actual.ErrorType != expected.ErrorType ||
						actual.RawEvent != expected.RawEvent {
						t.Fatalf("line %d event %d = %+v want %+v", index+1, i, actual, expected)
					}
					if expected.SourceID == "*" {
						if actual.SourceID == "" {
							t.Fatalf("line %d event %d has an empty source id", index+1, i)
						}
					} else if actual.SourceID != expected.SourceID {
						t.Fatalf("line %d event %d source id = %q want %q", index+1, i, actual.SourceID, expected.SourceID)
					}
				}
				index++
			}
			if err := scanner.Err(); err != nil {
				t.Fatalf("scan rollout: %v", err)
			}
			if index != len(fixture.Lines) {
				t.Fatalf("consumed %d lines, expectations cover %d", index, len(fixture.Lines))
			}
		})
	}
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd backend && go test ./internal/adapters/agent/codex/ -run MapTranscriptRecord`
Expected: FAIL — `MapTranscriptRecord` undefined.

- [ ] **Step 4: Write the mapper**

Create `backend/internal/adapters/agent/codex/transcript.go`:

```go
package codex

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type codexRolloutRecord struct {
	Timestamp string          `json:"timestamp"`
	Type      string          `json:"type"`
	Payload   json.RawMessage `json:"payload"`
}

type codexRolloutPayload struct {
	Type      string          `json:"type"`
	ID        string          `json:"id"`
	Role      string          `json:"role"`
	Phase     string          `json:"phase"`
	Content   []codexTextPart `json:"content"`
	Summary   []codexTextPart `json:"summary"`
	Name      string          `json:"name"`
	CallID    string          `json:"call_id"`
	Arguments string          `json:"arguments"`
	Input     string          `json:"input"`
	Output    json.RawMessage `json:"output"`
	Model     string          `json:"model"`
}

type codexTextPart struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

// codexIgnoredEventMsgTypes are UI events that duplicate a response_item or a
// hook. token_count is the usage observer's business and sub_agent_activity is
// deferred with Claude's sidechain records.
var codexIgnoredEventMsgTypes = map[string]struct{}{
	"task_started":            {},
	"task_complete":           {},
	"user_message":            {},
	"agent_message":           {},
	"agent_reasoning":         {},
	"exec_command_end":        {},
	"patch_apply_end":         {},
	"token_count":             {},
	"sub_agent_activity":      {},
	"turn_aborted":            {},
	"item_completed":          {},
	"web_search_end":          {},
	"thread_settings_applied": {},
	"thread_rolled_back":      {},
	"error":                   {},
}

var codexIgnoredRecordTypes = map[string]struct{}{
	"session_meta":                       {},
	"token_usage_record":                 {},
	"world_state":                        {},
	"inter_agent_communication_metadata": {},
}

// MapTranscriptRecord maps one line of Codex's rollout JSONL onto zero or more
// block transcript events. ok=false means the record or event type was not
// recognised; the caller counts those.
func MapTranscriptRecord(line []byte) ([]domain.BlockTranscriptEvent, bool) {
	var rec codexRolloutRecord
	if err := json.Unmarshal(line, &rec); err != nil {
		return nil, false
	}
	switch rec.Type {
	case "response_item":
		return codexResponseItemEvents(rec, line)
	case "turn_context":
		var payload codexRolloutPayload
		if err := json.Unmarshal(rec.Payload, &payload); err != nil {
			return nil, false
		}
		if strings.TrimSpace(payload.Model) == "" {
			return nil, true
		}
		return []domain.BlockTranscriptEvent{{
			Kind:     domain.BlockEventTurnModel,
			SourceID: codexLineID(line),
			Text:     payload.Model,
		}}, true
	case "compacted":
		return []domain.BlockTranscriptEvent{codexCompactionEvent(rec)}, true
	case "event_msg":
		var payload codexRolloutPayload
		if err := json.Unmarshal(rec.Payload, &payload); err != nil {
			return nil, false
		}
		if payload.Type == "context_compacted" {
			return []domain.BlockTranscriptEvent{codexCompactionEvent(rec)}, true
		}
		if _, ignored := codexIgnoredEventMsgTypes[payload.Type]; ignored {
			return nil, true
		}
		return nil, false
	default:
		if _, ignored := codexIgnoredRecordTypes[rec.Type]; ignored {
			return nil, true
		}
		return nil, false
	}
}

func codexResponseItemEvents(rec codexRolloutRecord, line []byte) ([]domain.BlockTranscriptEvent, bool) {
	var payload codexRolloutPayload
	if err := json.Unmarshal(rec.Payload, &payload); err != nil {
		return nil, false
	}
	id := strings.TrimSpace(payload.ID)
	if id == "" {
		id = codexLineID(line)
	}
	switch payload.Type {
	case "message":
		if payload.Role != "assistant" {
			return nil, true
		}
		text := codexJoinText(payload.Content)
		if strings.TrimSpace(text) == "" {
			return nil, true
		}
		return []domain.BlockTranscriptEvent{{
			Kind:     domain.BlockEventAssistantText,
			SourceID: id,
			Text:     text,
			RawEvent: payload.Phase,
		}}, true
	case "reasoning":
		text := codexJoinText(payload.Summary)
		if strings.TrimSpace(text) == "" {
			return nil, true
		}
		return []domain.BlockTranscriptEvent{{
			Kind:     domain.BlockEventReasoning,
			SourceID: id,
			Text:     text,
		}}, true
	case "function_call", "custom_tool_call":
		input := payload.Arguments
		if input == "" {
			input = payload.Input
		}
		return []domain.BlockTranscriptEvent{{
			Kind:      domain.BlockEventToolStart,
			SourceID:  payload.CallID,
			ToolUseID: payload.CallID,
			ToolName:  payload.Name,
			ToolInput: input,
		}}, true
	case "function_call_output", "custom_tool_call_output":
		return []domain.BlockTranscriptEvent{{
			Kind:      domain.BlockEventToolResult,
			SourceID:  payload.CallID,
			ToolUseID: payload.CallID,
			Text:      codexOutputText(payload.Output),
		}}, true
	default:
		return nil, false
	}
}

// codexCompactionEvent keys both halves of one compaction — the `compacted`
// history record and its `context_compacted` UI event, written milliseconds
// apart — on the same second, so the projection collapses them into one block.
func codexCompactionEvent(rec codexRolloutRecord) domain.BlockTranscriptEvent {
	timestamp := rec.Timestamp
	if len(timestamp) >= 19 {
		timestamp = timestamp[:19]
	}
	return domain.BlockTranscriptEvent{
		Kind:     domain.BlockEventCompaction,
		SourceID: "compaction:" + timestamp,
		Text:     "Conversation compacted",
	}
}

func codexJoinText(parts []codexTextPart) string {
	texts := make([]string, 0, len(parts))
	for _, part := range parts {
		if part.Text != "" {
			texts = append(texts, part.Text)
		}
	}
	return strings.Join(texts, "\n")
}

func codexOutputText(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return text
	}
	return string(raw)
}

func codexLineID(line []byte) string {
	sum := sha256.Sum256(line)
	return hex.EncodeToString(sum[:8])
}
```

`encrypted_content` is never read. That is deliberate and must stay true.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd backend && go test ./internal/adapters/agent/codex/`
Expected: PASS, including the pre-existing tests in that package.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/adapters/agent/codex testdata/transcripts
git commit -m "feat(codex): map rollout records onto block events"
```

---

### Task 6: The harness → mapper registry

Mirrors `blockdispatch`: an adapter with no registered mapper contributes hook
blocks and nothing else, rather than breaking.

**Files:**
- Create: `backend/internal/adapters/agent/blocktranscript/dispatch.go`
- Create: `backend/internal/adapters/agent/blocktranscript/dispatch_test.go`

**Interfaces:**
- Consumes: `claudecode.MapTranscriptRecord`, `codex.MapTranscriptRecord`.
- Produces: `blocktranscript.Supports(harness string) bool` and `blocktranscript.Map(harness string, line []byte) ([]domain.BlockTranscriptEvent, bool)`. Task 8 calls both.

- [ ] **Step 1: Write the failing registry test**

Create `backend/internal/adapters/agent/blocktranscript/dispatch_test.go`:

```go
package blocktranscript

import "testing"

func TestSupportsOnlyMappedHarnesses(t *testing.T) {
	for _, harness := range []string{"claude-code", "codex"} {
		if !Supports(harness) {
			t.Fatalf("%s must have a transcript mapper", harness)
		}
	}
	for _, harness := range []string{"grok", "opencode", "", "unknown"} {
		if Supports(harness) {
			t.Fatalf("%s must not have a transcript mapper", harness)
		}
	}
}

func TestMapUnregisteredHarnessIsUnknown(t *testing.T) {
	events, known := Map("grok", []byte(`{"type":"assistant"}`))
	if known || len(events) != 0 {
		t.Fatalf("Map(grok) = %+v,%v", events, known)
	}
}

func TestMapRoutesToTheHarnessMapper(t *testing.T) {
	events, known := Map("claude-code", []byte(`{"type":"assistant","uuid":"u-1","message":{"model":"m","content":[]}}`))
	if !known || len(events) != 1 || events[0].Text != "m" {
		t.Fatalf("Map(claude-code) = %+v,%v", events, known)
	}
	events, known = Map("codex", []byte(`{"timestamp":"2026-09-04T10:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}`))
	if !known || len(events) != 1 || events[0].Text != "gpt-5.4" {
		t.Fatalf("Map(codex) = %+v,%v", events, known)
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/adapters/agent/blocktranscript/`
Expected: FAIL — the package does not exist.

- [ ] **Step 3: Write the registry**

Create `backend/internal/adapters/agent/blocktranscript/dispatch.go`:

```go
// Package blocktranscript maps a harness token onto the function that projects
// that harness's native transcript records into block events. It deliberately
// mirrors blockdispatch, which does the same job for hook events: a harness
// with no mapper registered here still contributes hook blocks, it simply adds
// nothing from its transcript.
package blocktranscript

import (
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/codex"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

// MapFunc projects one raw transcript line. ok=false means the record type was
// not recognised.
type MapFunc func(line []byte) ([]domain.BlockTranscriptEvent, bool)

// Mappers is keyed by the harness token, which is the same string as the agent
// token in `opr hooks <agent> <event>`. grok is deliberately absent: it reuses
// Claude Code's hook table but its transcript shape is unverified — see
// todo_without_tmux.md section 15.1.
var Mappers = map[string]MapFunc{
	"claude-code": claudecode.MapTranscriptRecord,
	"codex":       codex.MapTranscriptRecord,
}

// Supports reports whether a harness has a transcript mapper at all. The tailer
// uses it to decide whether a session is worth watching.
func Supports(harness string) bool {
	_, found := Mappers[harness]
	return found
}

// Map resolves the harness and applies its mapper. An unregistered harness
// yields no events and ok=false.
func Map(harness string, line []byte) ([]domain.BlockTranscriptEvent, bool) {
	mapper, found := Mappers[harness]
	if !found {
		return nil, false
	}
	return mapper(line)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd backend && go test ./internal/adapters/agent/blocktranscript/`
Expected: PASS

- [ ] **Step 5: Run the gates and commit**

```bash
cd backend && go build ./... && go test ./... && go vet ./...
git add backend/internal/adapters/agent/blocktranscript
git commit -m "feat(blocks): register the per-harness transcript mappers"
```

---

## Part C — The tailer

One new package, `backend/internal/observe/transcript`. It sits beside the usage
observer and shares no state with it: both read the same files, for different
reasons, on different cursors. It reuses the usage package's proven
`TranscriptWatcher` by constructing its **own instance** — the watch mechanics
are already correct and duplicating them would be a hundred lines of drift.

### Task 7: Resolve a session's transcript path

**Files:**
- Create: `backend/internal/observe/transcript/resolve.go`
- Create: `backend/internal/observe/transcript/resolve_test.go`

**Interfaces:**
- Produces:
  ```go
  func NewResolver(agents ports.AgentResolver) *Resolver
  func (r *Resolver) Path(ctx context.Context, rec domain.SessionRecord) string
  ```
  Task 9 constructs the resolver; Task 8's tail consumes the path it returns.

- [ ] **Step 1: Write the failing resolver test**

Create `backend/internal/observe/transcript/resolve_test.go`:

```go
package transcript

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeAgent struct {
	ports.Agent
	configDir string
	located   string
	found     bool
}

func (a *fakeAgent) NativeSessionConfigDir(context.Context, map[string]string) (string, error) {
	return a.configDir, nil
}

func (a *fakeAgent) LocateTranscript(context.Context, ports.NativeSessionRef) (string, bool, error) {
	return a.located, a.found, nil
}

type fakeResolver struct{ agent *fakeAgent }

func (r fakeResolver) Agent(domain.AgentHarness) (ports.Agent, bool) {
	if r.agent == nil {
		return nil, false
	}
	return r.agent, true
}

func writeTranscript(t *testing.T, dir, name string) string {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte("{}\n"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	return path
}

func TestPathPrefersTheHookReportedTranscript(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "native.jsonl")

	resolver := NewResolver(fakeResolver{agent: &fakeAgent{configDir: configDir}})
	rec := domain.SessionRecord{Harness: "claude-code"}
	rec.Metadata.NativeTranscriptPath = path

	got := resolver.Path(context.Background(), rec)
	want, _ := filepath.EvalSymlinks(path)
	if got != want {
		t.Fatalf("Path = %q want %q", got, want)
	}
}

func TestPathFallsBackToTheAdapterLocator(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "sessions"), "rollout.jsonl")

	resolver := NewResolver(fakeResolver{agent: &fakeAgent{configDir: configDir, located: path, found: true}})
	rec := domain.SessionRecord{Harness: "codex"}
	rec.Metadata.AgentSessionID = "native-1"

	got := resolver.Path(context.Background(), rec)
	want, _ := filepath.EvalSymlinks(path)
	if got != want {
		t.Fatalf("Path = %q want %q", got, want)
	}
}

func TestPathRejectsAPathOutsideTheConfigDir(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	outside := writeTranscript(t, filepath.Join(root, "elsewhere"), "evil.jsonl")

	resolver := NewResolver(fakeResolver{agent: &fakeAgent{configDir: configDir}})
	rec := domain.SessionRecord{Harness: "claude-code"}
	rec.Metadata.NativeTranscriptPath = outside

	if got := resolver.Path(context.Background(), rec); got != "" {
		t.Fatalf("Path = %q, want empty for a path outside the provider config dir", got)
	}
}

func TestPathIsEmptyWithoutAnAdapter(t *testing.T) {
	resolver := NewResolver(fakeResolver{})
	if got := resolver.Path(context.Background(), domain.SessionRecord{Harness: "nope"}); got != "" {
		t.Fatalf("Path = %q", got)
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/observe/transcript/`
Expected: FAIL — the package does not exist.

- [ ] **Step 3: Write the resolver**

Create `backend/internal/observe/transcript/resolve.go`:

```go
// Package transcript projects a live session's native provider transcript into
// block events. Hooks are the status channel of the blocks view; this is the
// body channel — what the agent actually said, thought, ran and got back.
//
// It deliberately sits beside the usage observer rather than inside it. Both
// read the same provider files, for unrelated reasons and on independent
// cursors; coupling usage accounting to block projection would make either
// one's failure the other's.
package transcript

import (
	"context"
	"os"
	"path/filepath"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// Resolver turns a session record into the absolute path of the provider
// transcript that session is currently writing.
type Resolver struct {
	agents ports.AgentResolver
}

// NewResolver builds a resolver over the daemon's per-session agent registry.
func NewResolver(agents ports.AgentResolver) *Resolver {
	return &Resolver{agents: agents}
}

// Path returns the transcript path for a session, or "" when the harness has no
// adapter, the adapter exposes no config directory, or no readable transcript
// exists yet. The hook-reported path is externally supplied, so every candidate
// must be a regular file inside the provider's own config directory before it
// is opened.
func (r *Resolver) Path(ctx context.Context, rec domain.SessionRecord) string {
	if r == nil || r.agents == nil {
		return ""
	}
	agent, found := r.agents.Agent(rec.Harness)
	if !found || agent == nil {
		return ""
	}
	provider, ok := agent.(ports.AgentNativeSessionConfigProvider)
	if !ok {
		return ""
	}
	configDir, err := provider.NativeSessionConfigDir(ctx, nil)
	if err != nil || strings.TrimSpace(configDir) == "" {
		return ""
	}
	if path := containedPath(ctx, rec.Metadata.NativeTranscriptPath, configDir); path != "" {
		return path
	}
	locator, ok := agent.(ports.AgentTranscriptLocator)
	nativeID := strings.TrimSpace(rec.Metadata.AgentSessionID)
	if !ok || nativeID == "" {
		return ""
	}
	located, ok, err := locator.LocateTranscript(ctx, ports.NativeSessionRef{
		NativeSessionID: nativeID,
		ConfigDir:       configDir,
	})
	if err != nil || !ok {
		return ""
	}
	return containedPath(ctx, located, configDir)
}

func containedPath(ctx context.Context, path, configDir string) string {
	if ctx.Err() != nil {
		return ""
	}
	path = strings.TrimSpace(path)
	if path == "" || !filepath.IsAbs(path) || strings.TrimSpace(configDir) == "" {
		return ""
	}
	realConfigDir, err := filepath.EvalSymlinks(filepath.Clean(configDir))
	if err != nil {
		return ""
	}
	realPath, err := filepath.EvalSymlinks(filepath.Clean(path))
	if err != nil {
		return ""
	}
	rel, err := filepath.Rel(realConfigDir, realPath)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return ""
	}
	info, err := os.Stat(realPath)
	if err != nil || !info.Mode().IsRegular() {
		return ""
	}
	return realPath
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd backend && go test ./internal/observe/transcript/`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/observe/transcript
git commit -m "feat(transcript): resolve a session's provider transcript path"
```

---

### Task 8: The per-session tail

Reads new complete lines from the persisted offset, maps them, emits them, and
advances the cursor. Never emits a partial trailing record; a later write
completes it.

**Files:**
- Create: `backend/internal/observe/transcript/tail.go`
- Create: `backend/internal/observe/transcript/tail_test.go`

**Interfaces:**
- Consumes: `blocktranscript.Map` / `blocktranscript.Supports` (Task 6), `blockevent.Service.RecordTranscript` (Task 3) through the `Sink` interface, `Store.GetTranscriptOffset` / `UpsertTranscriptOffset` (Task 2) through `OffsetStore`.
- Produces:
  ```go
  type Sink interface {
      RecordTranscript(ctx context.Context, sessionID domain.SessionID, harness string, ev domain.BlockTranscriptEvent) error
  }
  type OffsetStore interface {
      GetTranscriptOffset(ctx context.Context, sessionID string) (string, int64, bool, error)
      UpsertTranscriptOffset(ctx context.Context, sessionID, path string, offset int64, at time.Time) error
  }
  ```
  plus the unexported `tail` type and `(*tail).pump`. Task 9's `Supervisor` owns a map of tails.

- [ ] **Step 1: Write the failing tail test**

Create `backend/internal/observe/transcript/tail_test.go`:

```go
package transcript

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type recordedEvent struct {
	sessionID domain.SessionID
	harness   string
	event     domain.BlockTranscriptEvent
}

// fakeSink is read from the test goroutine while the supervisor writes it in
// Task 9, so it is mutex-guarded from the start and `go test -race` stays clean.
type fakeSink struct {
	mu     sync.Mutex
	events []recordedEvent
	failOn int
	calls  int
}

func (s *fakeSink) RecordTranscript(_ context.Context, id domain.SessionID, harness string, ev domain.BlockTranscriptEvent) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.calls++
	if s.failOn > 0 && s.calls == s.failOn {
		return os.ErrClosed
	}
	s.events = append(s.events, recordedEvent{sessionID: id, harness: harness, event: ev})
	return nil
}

func (s *fakeSink) recorded() []recordedEvent {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]recordedEvent(nil), s.events...)
}

func (s *fakeSink) setFailOn(n int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.failOn = n
}

type fakeOffsets struct {
	path   string
	offset int64
	found  bool
	writes int
}

func (o *fakeOffsets) GetTranscriptOffset(context.Context, string) (string, int64, bool, error) {
	return o.path, o.offset, o.found, nil
}

func (o *fakeOffsets) UpsertTranscriptOffset(_ context.Context, _, path string, offset int64, _ time.Time) error {
	o.writes++
	o.path, o.offset, o.found = path, offset, true
	return nil
}

func appendLines(t *testing.T, path string, lines ...string) {
	t.Helper()
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer func() { _ = file.Close() }()
	for _, line := range lines {
		if _, err := file.WriteString(line + "\n"); err != nil {
			t.Fatalf("write: %v", err)
		}
	}
}

const (
	assistantLine = `{"type":"assistant","uuid":"u-1","message":{"model":"claude-sonnet-5","content":[{"type":"text","text":"hello"}]}}`
	toolLine      = `{"type":"assistant","uuid":"u-2","message":{"model":"claude-sonnet-5","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"ls"}}]}}`
	resultLine    = `{"type":"user","uuid":"u-3","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"a.txt"}]}}`
)

func newTail(path string) *tail {
	return &tail{sessionID: "s-1", harness: "claude-code", path: path}
}

func TestPumpEmitsCompleteLinesAndAdvancesTheCursor(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine, toolLine)

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	if err := tl.pump(context.Background(), sink, offsets, time.Now); err != nil {
		t.Fatalf("pump: %v", err)
	}
	got := sink.recorded()
	if len(got) != 3 {
		t.Fatalf("emitted %d events: %+v", len(got), got)
	}
	if got[0].event.Kind != domain.BlockEventTurnModel ||
		got[1].event.Kind != domain.BlockEventAssistantText ||
		got[2].event.Kind != domain.BlockEventToolStart {
		t.Fatalf("kinds = %+v", got)
	}
	info, _ := os.Stat(path)
	if tl.offset != info.Size() || offsets.offset != info.Size() {
		t.Fatalf("offset = %d/%d want %d", tl.offset, offsets.offset, info.Size())
	}
}

func TestPumpDoesNotRepeatTheSameModel(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine, toolLine)

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	_ = tl.pump(context.Background(), sink, offsets, time.Now)

	models := 0
	for _, e := range sink.recorded() {
		if e.event.Kind == domain.BlockEventTurnModel {
			models++
		}
	}
	if models != 1 {
		t.Fatalf("emitted %d turn_model events, want 1", models)
	}
}

func TestPumpResumesWithoutRepeating(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine)

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	_ = tl.pump(context.Background(), sink, offsets, time.Now)
	first := len(sink.recorded())

	appendLines(t, path, toolLine, resultLine)
	_ = tl.pump(context.Background(), sink, offsets, time.Now)

	got := sink.recorded()
	if len(got) != first+2 {
		t.Fatalf("second pump emitted %d events, want 2", len(got)-first)
	}
	if got[first].event.Kind != domain.BlockEventToolStart ||
		got[first+1].event.Kind != domain.BlockEventToolResult {
		t.Fatalf("second pump kinds = %+v", got[first:])
	}
}

func TestPumpIgnoresAPartialTrailingRecord(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine)
	file, _ := os.OpenFile(path, os.O_WRONLY|os.O_APPEND, 0o600)
	_, _ = file.WriteString(`{"type":"assistant","uuid":"u-9","mess`)
	_ = file.Close()

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	_ = tl.pump(context.Background(), sink, offsets, time.Now)

	if got := sink.recorded(); len(got) != 2 {
		t.Fatalf("emitted %d events, want the 2 from the one complete line", len(got))
	}
	info, _ := os.Stat(path)
	if tl.offset >= info.Size() {
		t.Fatal("the cursor must stop before the partial record")
	}
}

func TestPumpCountsUnrecognisedRecords(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, `{"type":"future-record-kind"}`, `not json`, assistantLine)

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	if err := tl.pump(context.Background(), sink, offsets, time.Now); err != nil {
		t.Fatalf("pump: %v", err)
	}
	if tl.unknown != 2 {
		t.Fatalf("unknown = %d want 2", tl.unknown)
	}
	if got := sink.recorded(); len(got) != 2 {
		t.Fatalf("an unrecognised record must not stop the pump: %+v", got)
	}
}

func TestPumpRewindsToTheLastCommittedLineOnSinkFailure(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine, toolLine)

	sink := &fakeSink{failOn: 3}
	offsets := &fakeOffsets{}
	tl := newTail(path)
	if err := tl.pump(context.Background(), sink, offsets, time.Now); err == nil {
		t.Fatal("pump must surface a sink failure")
	}
	info, _ := os.Stat(path)
	if tl.offset == 0 || tl.offset >= info.Size() {
		t.Fatalf("offset = %d; want the end of the first line", tl.offset)
	}

	sink.setFailOn(0)
	before := len(sink.recorded())
	if err := tl.pump(context.Background(), sink, offsets, time.Now); err != nil {
		t.Fatalf("retry: %v", err)
	}
	if got := len(sink.recorded()) - before; got != 1 {
		t.Fatalf("retry emitted %d events, want only the failed line's one", got)
	}
}

func TestPumpResetsWhenTheFileShrinks(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native.jsonl")
	appendLines(t, path, assistantLine, toolLine)

	sink, offsets := &fakeSink{}, &fakeOffsets{}
	tl := newTail(path)
	_ = tl.pump(context.Background(), sink, offsets, time.Now)

	if err := os.WriteFile(path, []byte(resultLine+"\n"), 0o600); err != nil {
		t.Fatalf("truncate: %v", err)
	}
	before := len(sink.recorded())
	_ = tl.pump(context.Background(), sink, offsets, time.Now)

	got := sink.recorded()
	if len(got)-before != 1 || got[before].event.Kind != domain.BlockEventToolResult {
		t.Fatalf("after shrink emitted %+v", got[before:])
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/observe/transcript/ -run Pump`
Expected: FAIL — `tail` undefined.

- [ ] **Step 3: Write the tail**

Create `backend/internal/observe/transcript/tail.go`:

```go
package transcript

import (
	"bufio"
	"bytes"
	"context"
	"io"
	"os"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/blocktranscript"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

// maxTranscriptLineBytes bounds one record. A line larger than this is a
// generated artifact, not something a phone renders; it is counted and skipped
// rather than buffered.
const maxTranscriptLineBytes = 1 << 20

// Sink receives one mapped transcript event. blockevent.Service satisfies it.
type Sink interface {
	RecordTranscript(ctx context.Context, sessionID domain.SessionID, harness string, ev domain.BlockTranscriptEvent) error
}

// OffsetStore persists the read cursor so a daemon restart resumes instead of
// re-emitting.
type OffsetStore interface {
	GetTranscriptOffset(ctx context.Context, sessionID string) (string, int64, bool, error)
	UpsertTranscriptOffset(ctx context.Context, sessionID, path string, offset int64, at time.Time) error
}

type tail struct {
	sessionID domain.SessionID
	harness   string
	path      string
	offset    int64
	lastModel string
	unknown   int
	logged    int
}

func (t *tail) pump(ctx context.Context, sink Sink, offsets OffsetStore, now func() time.Time) error {
	file, err := os.Open(t.path)
	if err != nil {
		return err
	}
	defer func() { _ = file.Close() }()
	info, err := file.Stat()
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return nil
	}
	if info.Size() < t.offset {
		t.offset = 0
		t.lastModel = ""
	}
	if info.Size() == t.offset {
		return nil
	}
	if _, err := file.Seek(t.offset, io.SeekStart); err != nil {
		return err
	}

	reader := bufio.NewReaderSize(file, 64<<10)
	committed := t.offset
	consumed := t.offset
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		line, readErr := reader.ReadBytes('\n')
		if readErr != nil {
			break
		}
		consumed += int64(len(line))
		record := bytes.TrimRight(line, "\r\n")
		if len(bytes.TrimSpace(record)) == 0 {
			committed = consumed
			continue
		}
		if len(record) > maxTranscriptLineBytes {
			t.unknown++
			committed = consumed
			continue
		}
		events, known := blocktranscript.Map(t.harness, record)
		if !known {
			t.unknown++
		}
		for _, event := range events {
			if event.Kind == domain.BlockEventTurnModel {
				if event.Text == t.lastModel {
					continue
				}
				t.lastModel = event.Text
			}
			if err := sink.RecordTranscript(ctx, t.sessionID, t.harness, event); err != nil {
				t.offset = committed
				_ = offsets.UpsertTranscriptOffset(ctx, string(t.sessionID), t.path, t.offset, now())
				return err
			}
		}
		committed = consumed
	}
	if committed == t.offset {
		return nil
	}
	t.offset = committed
	return offsets.UpsertTranscriptOffset(ctx, string(t.sessionID), t.path, t.offset, now())
}
```

A sink failure mid-record rewinds to the start of that record, so the retry
re-emits that record's events from the beginning. Duplicating one record's
events is preferable to losing them, and the projection collapses events that
share a source id.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && go test ./internal/observe/transcript/`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/observe/transcript
git commit -m "feat(transcript): tail a session's transcript from a durable cursor"
```

---

### Task 9: The supervisor, and daemon wiring

Reconciles the live-session set on a ticker, keeps the fsnotify watch set in
step, pumps a file when it changes, and pumps everything on each tick so a
missed filesystem event costs latency, never correctness.

**Files:**
- Create: `backend/internal/observe/transcript/supervisor.go`
- Create: `backend/internal/observe/transcript/supervisor_test.go`
- Modify: `backend/internal/daemon/daemon.go`

**Interfaces:**
- Consumes: everything from Tasks 6–8, plus `usage.TranscriptWatcher` and `usagesvc.DefaultSourceRoots`.
- Produces:
  ```go
  type SessionSource interface { ListAllSessions(ctx context.Context) ([]domain.SessionRecord, error) }
  type Watcher interface {
      Events() <-chan usagepipeline.TranscriptEvent
      Errors() <-chan error
      Rebuild(ctx context.Context, sourcePaths []string) error
      Start(ctx context.Context) <-chan struct{}
  }
  type Deps struct { Sessions SessionSource; Offsets OffsetStore; Sink Sink; Resolver *Resolver; Watcher Watcher; Interval time.Duration; Logger *slog.Logger; Clock func() time.Time }
  func NewSupervisor(deps Deps) *Supervisor
  func (s *Supervisor) Start(ctx context.Context) <-chan struct{}
  ```

- [ ] **Step 1: Write the failing supervisor test**

Create `backend/internal/observe/transcript/supervisor_test.go`:

```go
package transcript

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	usagepipeline "github.com/OmarAly92/operator/backend/internal/observe/usage"
)

type fakeSessions struct{ sessions []domain.SessionRecord }

func (f *fakeSessions) ListAllSessions(context.Context) ([]domain.SessionRecord, error) {
	return f.sessions, nil
}

type fakeWatcher struct {
	events chan usagepipeline.TranscriptEvent
	errors chan error
	built  [][]string
}

func newFakeWatcher() *fakeWatcher {
	return &fakeWatcher{
		events: make(chan usagepipeline.TranscriptEvent, 4),
		errors: make(chan error, 4),
	}
}

func (w *fakeWatcher) Events() <-chan usagepipeline.TranscriptEvent { return w.events }
func (w *fakeWatcher) Errors() <-chan error                         { return w.errors }
func (w *fakeWatcher) Start(context.Context) <-chan struct{} {
	done := make(chan struct{})
	close(done)
	return done
}

func (w *fakeWatcher) Rebuild(_ context.Context, paths []string) error {
	w.built = append(w.built, append([]string(nil), paths...))
	return nil
}

func session(id, harness, transcriptPath string, terminated bool) domain.SessionRecord {
	rec := domain.SessionRecord{
		ID:           domain.SessionID(id),
		Harness:      domain.AgentHarness(harness),
		IsTerminated: terminated,
	}
	rec.Metadata.NativeTranscriptPath = transcriptPath
	return rec
}

func newSupervisor(t *testing.T, sessions *fakeSessions, sink Sink, offsets OffsetStore, watcher Watcher, configDir string) *Supervisor {
	t.Helper()
	return NewSupervisor(Deps{
		Sessions: sessions,
		Offsets:  offsets,
		Sink:     sink,
		Resolver: NewResolver(fakeResolver{agent: &fakeAgent{configDir: configDir}}),
		Watcher:  watcher,
	})
}

func TestReconcileTailsOnlyLiveMappedSessions(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	live := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "live.jsonl")
	dead := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "dead.jsonl")

	sessions := &fakeSessions{sessions: []domain.SessionRecord{
		session("s-live", "claude-code", live, false),
		session("s-dead", "claude-code", dead, true),
		session("s-unmapped", "opencode", live, false),
	}}
	watcher := newFakeWatcher()
	sup := newSupervisor(t, sessions, &fakeSink{}, &fakeOffsets{}, watcher, configDir)

	sup.reconcile(context.Background())

	if len(sup.tails) != 1 {
		t.Fatalf("tails = %d, want only the live mapped session", len(sup.tails))
	}
	if _, ok := sup.tails["s-live"]; !ok {
		t.Fatalf("tails = %+v", sup.tails)
	}
	if len(watcher.built) != 1 || len(watcher.built[0]) != 1 {
		t.Fatalf("watch set = %+v", watcher.built)
	}
}

func TestReconcileSeedsTheCursorFromTheStore(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "live.jsonl")
	resolved, _ := filepath.EvalSymlinks(path)
	appendLines(t, path, assistantLine)

	sessions := &fakeSessions{sessions: []domain.SessionRecord{session("s-1", "claude-code", path, false)}}
	offsets := &fakeOffsets{path: resolved, offset: 3, found: true}
	sup := newSupervisor(t, sessions, &fakeSink{}, offsets, newFakeWatcher(), configDir)

	sup.reconcile(context.Background())

	if got := sup.tails["s-1"].offset; got != 3 {
		t.Fatalf("offset = %d want the persisted 3", got)
	}
}

func TestReconcileResetsTheCursorWhenThePathChanges(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "live.jsonl")

	sessions := &fakeSessions{sessions: []domain.SessionRecord{session("s-1", "claude-code", path, false)}}
	offsets := &fakeOffsets{path: "/somewhere/else.jsonl", offset: 9000, found: true}
	sup := newSupervisor(t, sessions, &fakeSink{}, offsets, newFakeWatcher(), configDir)

	sup.reconcile(context.Background())

	if got := sup.tails["s-1"].offset; got != 0 {
		t.Fatalf("offset = %d want 0 for a different file", got)
	}
}

func TestPumpAllEmitsForEveryTail(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "live.jsonl")
	appendLines(t, path, assistantLine)

	sessions := &fakeSessions{sessions: []domain.SessionRecord{session("s-1", "claude-code", path, false)}}
	sink := &fakeSink{}
	sup := newSupervisor(t, sessions, sink, &fakeOffsets{}, newFakeWatcher(), configDir)

	sup.reconcile(context.Background())
	sup.pumpAll(context.Background())

	if len(sink.recorded()) == 0 {
		t.Fatal("pumpAll emitted nothing")
	}
	before := len(sink.recorded())
	sup.pumpAll(context.Background())
	if len(sink.recorded()) != before {
		t.Fatal("a second pump with no new bytes must emit nothing")
	}
}

func TestStartStopsWithTheContext(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	path := writeTranscript(t, filepath.Join(configDir, "projects", "p"), "live.jsonl")
	appendLines(t, path, assistantLine)

	sessions := &fakeSessions{sessions: []domain.SessionRecord{session("s-1", "claude-code", path, false)}}
	sink := &fakeSink{}
	sup := NewSupervisor(Deps{
		Sessions: sessions,
		Offsets:  &fakeOffsets{},
		Sink:     sink,
		Resolver: NewResolver(fakeResolver{agent: &fakeAgent{configDir: configDir}}),
		Watcher:  newFakeWatcher(),
		Interval: 10 * time.Millisecond,
	})

	ctx, cancel := context.WithCancel(context.Background())
	done := sup.Start(ctx)
	deadline := time.After(2 * time.Second)
	for len(sink.recorded()) == 0 {
		select {
		case <-deadline:
			cancel()
			<-done
			t.Fatal("supervisor emitted nothing before the deadline")
		case <-time.After(5 * time.Millisecond):
		}
	}
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("supervisor did not stop with its context")
	}
	_ = os.Remove(path)
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/observe/transcript/ -run 'Reconcile|PumpAll|Start'`
Expected: FAIL — `NewSupervisor`, `Deps`, `Supervisor` undefined.

- [ ] **Step 3: Write the supervisor**

Create `backend/internal/observe/transcript/supervisor.go`:

```go
package transcript

import (
	"context"
	"log/slog"
	"sort"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/blocktranscript"
	"github.com/OmarAly92/operator/backend/internal/domain"
	usagepipeline "github.com/OmarAly92/operator/backend/internal/observe/usage"
)

// DefaultInterval is how often the supervisor re-reads the live session set and
// re-checks every tracked file. The filesystem watch is a latency optimisation
// on top of it, so a dropped filesystem event costs a tick, not a block.
const DefaultInterval = 2 * time.Second

// unknownRecordLogEvery bounds how often an unrecognised-record count is
// reported. A harness release that renames a record type would otherwise log
// once per record.
const unknownRecordLogEvery = 100

// SessionSource is the slice of the store the supervisor needs.
type SessionSource interface {
	ListAllSessions(ctx context.Context) ([]domain.SessionRecord, error)
}

// Watcher is the filesystem watch the supervisor drives. usage.TranscriptWatcher
// satisfies it; the supervisor constructs its own instance so no state is shared
// with usage accounting.
type Watcher interface {
	Events() <-chan usagepipeline.TranscriptEvent
	Errors() <-chan error
	Rebuild(ctx context.Context, sourcePaths []string) error
	Start(ctx context.Context) <-chan struct{}
}

// Deps are the supervisor's collaborators. Watcher may be nil, in which case
// projection still works on the reconcile interval alone.
type Deps struct {
	Sessions SessionSource
	Offsets  OffsetStore
	Sink     Sink
	Resolver *Resolver
	Watcher  Watcher
	Interval time.Duration
	Logger   *slog.Logger
	Clock    func() time.Time
}

// Supervisor owns one tail per live session whose harness has a transcript
// mapper.
type Supervisor struct {
	deps  Deps
	tails map[domain.SessionID]*tail
}

// NewSupervisor constructs the transcript projection supervisor.
func NewSupervisor(deps Deps) *Supervisor {
	if deps.Interval <= 0 {
		deps.Interval = DefaultInterval
	}
	if deps.Logger == nil {
		deps.Logger = slog.Default()
	}
	if deps.Clock == nil {
		deps.Clock = func() time.Time { return time.Now().UTC() }
	}
	return &Supervisor{deps: deps, tails: map[domain.SessionID]*tail{}}
}

// Start runs until ctx is cancelled. The returned channel closes after the
// goroutine exits.
func (s *Supervisor) Start(ctx context.Context) <-chan struct{} {
	done := make(chan struct{})
	go func() {
		defer close(done)
		var events <-chan usagepipeline.TranscriptEvent
		var errs <-chan error
		if s.deps.Watcher != nil {
			s.deps.Watcher.Start(ctx)
			events = s.deps.Watcher.Events()
			errs = s.deps.Watcher.Errors()
		}
		s.tick(ctx)
		ticker := time.NewTicker(s.deps.Interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				s.tick(ctx)
			case event, ok := <-events:
				if !ok {
					events = nil
					continue
				}
				s.pumpPath(ctx, event.Path)
			case err, ok := <-errs:
				if !ok {
					errs = nil
					continue
				}
				if err != nil {
					s.deps.Logger.Warn("transcript watcher", "err", err)
				}
			}
		}
	}()
	return done
}

func (s *Supervisor) tick(ctx context.Context) {
	s.reconcile(ctx)
	s.pumpAll(ctx)
}

func (s *Supervisor) reconcile(ctx context.Context) {
	if s.deps.Sessions == nil || s.deps.Resolver == nil {
		return
	}
	sessions, err := s.deps.Sessions.ListAllSessions(ctx)
	if err != nil {
		s.deps.Logger.Warn("transcript projection could not list sessions", "err", err)
		return
	}
	seen := make(map[domain.SessionID]struct{}, len(sessions))
	paths := make([]string, 0, len(sessions))
	for _, rec := range sessions {
		if ctx.Err() != nil {
			return
		}
		if rec.IsTerminated || !blocktranscript.Supports(string(rec.Harness)) {
			continue
		}
		path := s.deps.Resolver.Path(ctx, rec)
		if path == "" {
			continue
		}
		seen[rec.ID] = struct{}{}
		paths = append(paths, path)
		existing, tracked := s.tails[rec.ID]
		if tracked && existing.path == path {
			continue
		}
		if tracked {
			existing.path = path
			existing.offset = 0
			existing.lastModel = ""
			continue
		}
		s.tails[rec.ID] = s.newTail(ctx, rec, path)
	}
	for id := range s.tails {
		if _, live := seen[id]; !live {
			delete(s.tails, id)
		}
	}
	if s.deps.Watcher != nil {
		sort.Strings(paths)
		if err := s.deps.Watcher.Rebuild(ctx, paths); err != nil {
			s.deps.Logger.Warn("transcript watch rebuild", "err", err)
		}
	}
}

func (s *Supervisor) newTail(ctx context.Context, rec domain.SessionRecord, path string) *tail {
	created := &tail{sessionID: rec.ID, harness: string(rec.Harness), path: path}
	if s.deps.Offsets == nil {
		return created
	}
	storedPath, offset, found, err := s.deps.Offsets.GetTranscriptOffset(ctx, string(rec.ID))
	if err != nil {
		s.deps.Logger.Warn("transcript cursor read", "session", rec.ID, "err", err)
		return created
	}
	if found && storedPath == path {
		created.offset = offset
	}
	return created
}

func (s *Supervisor) pumpAll(ctx context.Context) {
	for _, tracked := range s.tails {
		if ctx.Err() != nil {
			return
		}
		s.pump(ctx, tracked)
	}
}

func (s *Supervisor) pumpPath(ctx context.Context, path string) {
	for _, tracked := range s.tails {
		if tracked.path == path {
			s.pump(ctx, tracked)
		}
	}
}

func (s *Supervisor) pump(ctx context.Context, tracked *tail) {
	if s.deps.Sink == nil || s.deps.Offsets == nil {
		return
	}
	if err := tracked.pump(ctx, s.deps.Sink, s.deps.Offsets, s.deps.Clock); err != nil && ctx.Err() == nil {
		s.deps.Logger.Warn("transcript projection", "session", tracked.sessionID, "err", err)
	}
	if tracked.unknown-tracked.logged >= unknownRecordLogEvery {
		tracked.logged = tracked.unknown
		s.deps.Logger.Info(
			"transcript records not recognised",
			"session", tracked.sessionID,
			"harness", tracked.harness,
			"count", tracked.unknown,
		)
	}
}
```

- [ ] **Step 4: Run the tests, including the race detector**

```bash
cd backend
go test ./internal/observe/transcript/
go test -race ./internal/observe/transcript/
```

Expected: PASS both.

- [ ] **Step 5: Wire it into the daemon**

In `backend/internal/daemon/daemon.go`:

Add the import, grouped with the other observe imports:

```go
	transcriptsvc "github.com/OmarAly92/operator/backend/internal/observe/transcript"
```

Immediately after the existing `if usagePipeline != nil { usageDone = usagePipeline.Start(ctx) }` block (around line 462), add:

```go
	var transcriptDone <-chan struct{}
	if roots, rootsErr := usagesvc.DefaultSourceRoots(ctx); rootsErr != nil {
		log.Warn("transcript block projection disabled", "err", rootsErr)
	} else if watcher, watchErr := usagepipeline.NewTranscriptWatcher(ctx, []string{
		roots.ClaudeProjects,
		roots.CodexSessions,
	}); watchErr != nil {
		log.Warn("transcript block projection disabled", "err", watchErr)
	} else {
		transcriptDone = transcriptsvc.NewSupervisor(transcriptsvc.Deps{
			Sessions: store,
			Offsets:  store,
			Sink:     blockEvents,
			Resolver: transcriptsvc.NewResolver(agents),
			Watcher:  watcher,
			Logger:   log,
		}).Start(ctx)
	}
```

Declare `transcriptDone` beside `usageDone` if the compiler complains about
placement. In the shutdown sequence, immediately after the `if usageDone != nil { <-usageDone }`
block, add:

```go
	if transcriptDone != nil {
		<-transcriptDone
	}
```

- [ ] **Step 6: Verify the daemon still builds and its wiring test passes**

```bash
cd backend
go build ./...
go test ./internal/daemon/...
```

Expected: PASS. If `daemon/wiring_test.go` asserts the set of started goroutines, extend it rather than weakening it.

- [ ] **Step 7: Full backend gate and commit**

```bash
cd backend && go test ./... && go vet ./...
cd .. && npm run lint
git add backend/internal/observe/transcript backend/internal/daemon/daemon.go
git commit -m "feat(transcript): project live session transcripts into block events"
```

- [ ] **Step 8: Prove it end to end by hand**

Start the daemon, spawn one Claude Code session and one Codex session, send each a prompt that runs a tool, then:

```bash
sqlite3 ~/.operator/<data dir>/operator.db \
  "SELECT source, kind, substr(text,1,40) FROM block_events ORDER BY seq DESC LIMIT 20;"
```

Expected: rows with `source = 'transcript'` for `assistant_text`, `reasoning`, `tool_start` and `tool_result` interleaved with the `hook` rows. If only `hook` rows appear, check the daemon log for "transcript block projection disabled" and for the resolver returning an empty path (a session whose `native_transcript_path` is empty and whose `agent_session_id` is empty has no transcript yet — send it a prompt first).

---

## Part D — The mobile projection

Everything here is `packages/mobile`. The gate for every task is
`flutter analyze` printing `No issues found!` followed by the touched tests, and
the full `flutter test` before the last commit of the Part.

### Task 10: Model and block-shape changes

Adds the wire field the precedence rule needs, the two new `SessionBlock` fields
the tool result and the turn model live on, and the parsed question detail.

**Files:**
- Modify: `packages/mobile/lib/feature/blocks/data/model/block_event_model.dart`
- Modify: `packages/mobile/test/feature/blocks/data/block_event_model_test.dart`
- Modify: `packages/mobile/lib/feature/blocks/logic/session_block.dart`
- Create: `packages/mobile/lib/feature/blocks/logic/block_question.dart`
- Create: `packages/mobile/test/feature/blocks/logic/block_question_test.dart`

**Interfaces:**
- Produces: `BlockEventModel.source` and `BlockEventModel.rawEvent` (the latter already exists); `SessionBlock.result`, `SessionBlock.model`, and a `copyWith` that also takes `kind`, `title`, `result` and `model`; `QuestionBlockDetail`, `BlockQuestion`, `BlockQuestionOption` in `session_block.dart`; `QuestionBlockDetail? parseQuestionDetail(String toolInput)` in `block_question.dart`. Tasks 11–13 consume all of these.

- [ ] **Step 1: Write the failing tests**

Append to `packages/mobile/test/feature/blocks/data/block_event_model_test.dart`:

```dart
  test('reads the source channel off the wire', () {
    final model = BlockEventModel.fromJson(const {
      'seq': 1,
      'sessionId': 's-1',
      'kind': 'assistant_text',
      'source': 'transcript',
      'text': 'hello',
    });

    expect(model.source, 'transcript');
  });

  test('a record with no source parses with a null source', () {
    final model = BlockEventModel.fromJson(const {'seq': 1, 'kind': 'stop'});

    expect(model.source, isNull);
  });
```

Create `packages/mobile/test/feature/blocks/logic/block_question_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/block_question.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

const _input =
    '{"questions":[{"question":"Which branch?","header":"Branch","multiSelect":false,'
    '"options":[{"label":"main","description":"the default branch"},'
    '{"label":"develop","description":"the integration branch"}]}]}';

void main() {
  test('parses the AskUserQuestion input into questions and options', () {
    final detail = parseQuestionDetail(_input);

    expect(detail, isNotNull);
    expect(detail!.questions, hasLength(1));
    final question = detail.questions.first;
    expect(question.question, 'Which branch?');
    expect(question.header, 'Branch');
    expect(question.multiSelect, isFalse);
    expect(question.options.map((option) => option.label), ['main', 'develop']);
    expect(question.options.first.description, 'the default branch');
  });

  test('returns null for input that is not a question payload', () {
    expect(parseQuestionDetail(''), isNull);
    expect(parseQuestionDetail('not json'), isNull);
    expect(parseQuestionDetail('{"command":"ls"}'), isNull);
    expect(parseQuestionDetail('{"questions":[]}'), isNull);
  });

  test('a question detail is a BlockDetail', () {
    expect(parseQuestionDetail(_input), isA<BlockDetail>());
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
cd packages/mobile
flutter test test/feature/blocks/data/block_event_model_test.dart test/feature/blocks/logic/block_question_test.dart
```

Expected: FAIL — `source` is not a member of `BlockEventModel`; `block_question.dart` does not exist.

- [ ] **Step 3: Add `source` to the model**

In `packages/mobile/lib/feature/blocks/data/model/block_event_model.dart`, add `final String? source;` after `final String? kind;`, add `this.source,` to the constructor, add `source: json['source'] as String?,` to `fromJson`, and add `source` to `props`. Field order in the class stays fields → constructor → `fromJson` → `props`.

- [ ] **Step 4: Extend `SessionBlock`**

In `packages/mobile/lib/feature/blocks/logic/session_block.dart`:

Add the question detail beside the other `BlockDetail` subclasses (a sealed class's subtypes must live in the same library, which is why these are here and the parser is not):

```dart
class QuestionBlockDetail extends BlockDetail {
  const QuestionBlockDetail({required this.questions});

  final List<BlockQuestion> questions;

  @override
  List<Object?> get props => [questions];
}

class BlockQuestion extends Equatable {
  const BlockQuestion({this.question, this.header, this.multiSelect, this.options = const []});

  final String? question;
  final String? header;
  final bool? multiSelect;
  final List<BlockQuestionOption> options;

  @override
  List<Object?> get props => [question, header, multiSelect, options];
}

class BlockQuestionOption extends Equatable {
  const BlockQuestionOption({this.label, this.description});

  final String? label;
  final String? description;

  @override
  List<Object?> get props => [label, description];
}
```

Add the two fields to `SessionBlock`, after `toolName`:

```dart
    this.result,
    this.model,
```

in the constructor, and

```dart
  final String? result;
  final String? model;
```

in the field list. Add them to `props`.

Widen `copyWith` so the projection can upgrade a block in place. Replace the whole method with:

```dart
  SessionBlock copyWith({
    BlockKind? kind,
    BlockStatus? status,
    String? turnId,
    String? title,
    String? body,
    String? result,
    String? model,
    BlockDetail? detail,
    int? lastSeq,
    String? errorType,
    int? truncatedLines,
    bool? redacted,
    String? createdAt,
    List<SessionBlock>? children,
  }) => SessionBlock(
    id: id,
    firstSeq: firstSeq,
    lastSeq: lastSeq ?? this.lastSeq,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    turnId: turnId ?? this.turnId,
    title: title ?? this.title,
    body: body ?? this.body,
    result: result ?? this.result,
    model: model ?? this.model,
    detail: detail ?? this.detail,
    toolName: toolName,
    errorType: errorType ?? this.errorType,
    truncatedLines: truncatedLines ?? this.truncatedLines,
    redacted: redacted ?? this.redacted,
    createdAt: createdAt ?? this.createdAt,
    children: children ?? this.children,
  );
```

Add the exhaustive-switch case to `blockDisplay`, beside the other detail variants:

```dart
    QuestionBlockDetail() => BlockDisplay(
      displayName: block.title,
      summary: block.body,
    ),
```

- [ ] **Step 5: Write the question parser**

Create `packages/mobile/lib/feature/blocks/logic/block_question.dart`:

```dart
import 'dart:convert';

import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

QuestionBlockDetail? parseQuestionDetail(String toolInput) {
  if (toolInput.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(toolInput);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final raw = decoded['questions'];
  if (raw is! List || raw.isEmpty) return null;

  final questions = <BlockQuestion>[];
  for (final item in raw) {
    if (item is! Map<String, dynamic>) continue;
    final options = <BlockQuestionOption>[];
    final rawOptions = item['options'];
    if (rawOptions is List) {
      for (final option in rawOptions) {
        if (option is! Map<String, dynamic>) continue;
        options.add(
          BlockQuestionOption(
            label: option['label'] as String?,
            description: option['description'] as String?,
          ),
        );
      }
    }
    questions.add(
      BlockQuestion(
        question: item['question'] as String?,
        header: item['header'] as String?,
        multiSelect: item['multiSelect'] as bool?,
        options: options,
      ),
    );
  }
  return questions.isEmpty ? null : QuestionBlockDetail(questions: questions);
}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd packages/mobile
flutter analyze
flutter test test/feature/blocks/data/block_event_model_test.dart test/feature/blocks/logic/block_question_test.dart
```

Expected: `No issues found!` and both files green. If `flutter analyze` reports a non-exhaustive switch in `blockDisplay`, you skipped the `QuestionBlockDetail()` case.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib/feature/blocks packages/mobile/test/feature/blocks
git commit -m "feat(mobile): carry the block event source, tool result and turn model"
```

---

### Task 11: The assembler learns the transcript kinds

The heart of the phase. Events sharing a `SourceID` collapse into one block;
**transcript wins on body, hook wins on status**.

**Files:**
- Modify: `packages/mobile/lib/feature/blocks/logic/block_assembly.dart`
- Create: `testdata/blocks/assembly_transcript_turn.json`
- Create: `testdata/blocks/assembly_transcript_tool_merge.json`
- Create: `testdata/blocks/assembly_transcript_codex.json`
- Create: `testdata/blocks/assembly_transcript_question.json`
- Create: `packages/mobile/test/feature/blocks/logic/block_assembly_transcript_test.dart`

**Interfaces:**
- Consumes: everything Task 10 produced.
- Produces: an `assembleBlocks` that additionally handles `assistant_text`, `reasoning`, `tool_start`, `tool_result`, `todo`, `turn_model` and `compaction`, and enriches `question_asked`. Its signature does not change. Task 12 groups its output; Task 13 renders it.

- [ ] **Step 1: Write the four shared fixtures**

Create `testdata/blocks/assembly_transcript_turn.json`:

```json
{
  "records": [
    { "seq": 1, "sessionId": "s-1", "kind": "prompt_submit", "source": "hook", "text": "run the tests" },
    { "seq": 2, "sessionId": "s-1", "kind": "turn_model", "source": "transcript", "sourceId": "u-1", "text": "claude-sonnet-5" },
    { "seq": 3, "sessionId": "s-1", "kind": "reasoning", "source": "transcript", "sourceId": "u-1", "text": "Checking the suite." },
    { "seq": 4, "sessionId": "s-1", "kind": "assistant_text", "source": "transcript", "sourceId": "u-2", "text": "Running the backend suite." },
    { "seq": 5, "sessionId": "s-1", "kind": "tool_start", "source": "transcript", "sourceId": "toolu_1", "toolUseId": "toolu_1", "toolName": "Bash", "toolInput": "{\"command\":\"go test ./...\"}" },
    { "seq": 6, "sessionId": "s-1", "kind": "tool_complete", "source": "hook", "sourceId": "toolu_1", "toolUseId": "toolu_1", "toolName": "Bash", "text": "exit 0" },
    { "seq": 7, "sessionId": "s-1", "kind": "tool_result", "source": "transcript", "sourceId": "toolu_1", "toolUseId": "toolu_1", "text": "ok 42 tests" },
    { "seq": 8, "sessionId": "s-1", "kind": "assistant_text", "source": "transcript", "sourceId": "u-3", "text": "All green." },
    { "seq": 9, "sessionId": "s-1", "kind": "stop", "source": "hook", "text": "All green." }
  ],
  "expected": [
    { "id": "seq-1", "kind": "prompt", "status": "ok", "title": "Prompt", "body": "run the tests" },
    { "id": "src-u-1", "kind": "reasoning", "status": "ok", "title": "Reasoning", "body": "Checking the suite.", "model": "claude-sonnet-5" },
    { "id": "src-u-2", "kind": "assistant", "status": "ok", "title": "Assistant", "body": "Running the backend suite.", "model": "claude-sonnet-5" },
    { "id": "src-toolu_1", "kind": "tool", "status": "ok", "title": "Bash", "body": "{\"command\":\"go test ./...\"}", "result": "ok 42 tests", "model": "claude-sonnet-5" },
    { "id": "src-u-3", "kind": "assistant", "status": "ok", "title": "Assistant", "body": "All green.", "model": "claude-sonnet-5" }
  ]
}
```

The hook's `stop` text produces no sixth block: the transcript already delivered
that assistant message, and the projection prefers it.

Create `testdata/blocks/assembly_transcript_tool_merge.json`:

```json
{
  "records": [
    { "seq": 1, "sessionId": "s-1", "kind": "prompt_submit", "source": "hook", "text": "edit the file" },
    { "seq": 2, "sessionId": "s-1", "kind": "tool_start", "source": "transcript", "sourceId": "toolu_1", "toolUseId": "toolu_1", "toolName": "Edit", "toolInput": "{\"file\":\"a.go\",\"new\":\"package main\"}" },
    { "seq": 3, "sessionId": "s-1", "kind": "permission_request", "source": "hook", "sourceId": "toolu_1", "toolUseId": "toolu_1", "toolName": "Edit", "toolInput": "a.go" },
    { "seq": 4, "sessionId": "s-1", "kind": "tool_result", "source": "transcript", "sourceId": "toolu_orphan", "toolUseId": "toolu_orphan", "text": "orphan output", "errorType": "tool_failed" }
  ],
  "expected": [
    { "id": "seq-1", "kind": "prompt", "status": "running", "title": "Prompt", "body": "edit the file" },
    { "id": "src-toolu_1", "kind": "permission", "status": "blocked", "title": "Permission requested", "body": "{\"file\":\"a.go\",\"new\":\"package main\"}" },
    { "id": "src-toolu_orphan", "kind": "tool", "status": "failed", "title": "Tool", "body": "", "result": "orphan output", "errorType": "tool_failed" }
  ]
}
```

Create `testdata/blocks/assembly_transcript_codex.json`:

```json
{
  "records": [
    { "seq": 1, "sessionId": "s-1", "kind": "prompt_submit", "source": "hook", "text": "run it" },
    { "seq": 2, "sessionId": "s-1", "kind": "turn_model", "source": "transcript", "sourceId": "h-1", "text": "gpt-5.4" },
    { "seq": 3, "sessionId": "s-1", "kind": "assistant_text", "source": "transcript", "sourceId": "c-1", "rawEvent": "commentary", "text": "Running now." },
    { "seq": 4, "sessionId": "s-1", "kind": "tool_start", "source": "transcript", "sourceId": "call_1", "toolUseId": "call_1", "toolName": "exec_command", "toolInput": "{\"cmd\":\"go test\"}" },
    { "seq": 5, "sessionId": "s-1", "kind": "tool_result", "source": "transcript", "sourceId": "call_1", "toolUseId": "call_1", "text": "ok" },
    { "seq": 6, "sessionId": "s-1", "kind": "assistant_text", "source": "transcript", "sourceId": "c-2", "rawEvent": "final_answer", "text": "All green." },
    { "seq": 7, "sessionId": "s-1", "kind": "stop", "source": "hook", "text": "All green." }
  ],
  "expected": [
    { "id": "seq-1", "kind": "prompt", "status": "ok", "title": "Prompt", "body": "run it" },
    { "id": "src-c-1", "kind": "assistant", "status": "ok", "title": "Assistant · note", "body": "Running now.", "model": "gpt-5.4" },
    { "id": "src-call_1", "kind": "tool", "status": "ok", "title": "exec_command", "body": "{\"cmd\":\"go test\"}", "result": "ok", "model": "gpt-5.4" },
    { "id": "src-c-2", "kind": "assistant", "status": "ok", "title": "Assistant", "body": "All green.", "model": "gpt-5.4" }
  ]
}
```

Codex emits no tool hook at all: the transcript's `tool_start` opens the block
and `tool_result` closes it. That is the row this fixture exists to pin.

Create `testdata/blocks/assembly_transcript_question.json`:

```json
{
  "records": [
    { "seq": 1, "sessionId": "s-1", "kind": "prompt_submit", "source": "hook", "text": "which branch" },
    { "seq": 2, "sessionId": "s-1", "kind": "question_asked", "source": "hook", "sourceId": "native-1", "text": "Waiting on you" },
    { "seq": 3, "sessionId": "s-1", "kind": "question_asked", "source": "transcript", "sourceId": "toolu_9", "toolUseId": "toolu_9", "toolName": "AskUserQuestion", "toolInput": "{\"questions\":[{\"question\":\"Which branch?\",\"header\":\"Branch\",\"multiSelect\":false,\"options\":[{\"label\":\"main\",\"description\":\"the default branch\"},{\"label\":\"develop\",\"description\":\"the integration branch\"}]}]}" },
    { "seq": 4, "sessionId": "s-1", "kind": "todo", "source": "transcript", "sourceId": "toolu_t1", "text": "{\"todos\":[{\"content\":\"Rename the branch\",\"status\":\"pending\"}]}" },
    { "seq": 5, "sessionId": "s-1", "kind": "todo", "source": "transcript", "sourceId": "toolu_t2", "text": "{\"todos\":[{\"content\":\"Rename the branch\",\"status\":\"completed\"}]}" },
    { "seq": 6, "sessionId": "s-1", "kind": "compaction", "source": "transcript", "sourceId": "compaction:2026-09-04T11:00:00", "text": "Conversation compacted" },
    { "seq": 7, "sessionId": "s-1", "kind": "compaction", "source": "transcript", "sourceId": "compaction:2026-09-04T11:00:00", "text": "Conversation compacted" }
  ],
  "expected": [
    { "id": "seq-1", "kind": "prompt", "status": "running", "title": "Prompt", "body": "which branch" },
    { "id": "src-toolu_9", "kind": "notice", "status": "blocked", "title": "Which branch?", "body": "", "questions": [{ "question": "Which branch?", "options": ["main", "develop"] }] },
    { "id": "src-toolu_t1", "kind": "todo", "status": "ok", "title": "Todo", "body": "{\"todos\":[{\"content\":\"Rename the branch\",\"status\":\"completed\"}]}" },
    { "id": "src-compaction:2026-09-04T11:00:00", "kind": "compaction", "status": "ok", "title": "Compaction", "body": "Conversation compacted" }
  ]
}
```

Three rules are pinned here at once: the transcript question replaces the hook's
bare "Waiting on you" notice in place, a later `todo` in the same turn replaces
the earlier one rather than stacking, and Codex's two compaction records collapse
to one block because the mapper gave them the same source id.

- [ ] **Step 2: Write the failing assembler test**

Create `packages/mobile/test/feature/blocks/logic/block_assembly_transcript_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/logic/block_assembly.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

const _fixtures = [
  'assembly_transcript_turn',
  'assembly_transcript_tool_merge',
  'assembly_transcript_codex',
  'assembly_transcript_question',
];

void main() {
  for (final name in _fixtures) {
    test('$name assembles as the shared fixture says', () {
      final file = File('../../testdata/blocks/$name.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'the shared fixture is missing; never fix a failing fixture by editing it',
      );

      final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final records = (fixture['records'] as List<dynamic>)
          .map((raw) => BlockEventModel.fromJson(raw as Map<String, dynamic>))
          .toList();
      final expected = (fixture['expected'] as List<dynamic>).cast<Map<String, dynamic>>();

      final blocks = assembleBlocks(records);

      expect(blocks, hasLength(expected.length), reason: 'block count for $name: ${blocks.map((b) => b.id)}');
      for (var i = 0; i < expected.length; i++) {
        final want = expected[i];
        final got = blocks[i];
        expect(got.id, want['id'], reason: '$name block $i id');
        expect(got.kind.name, want['kind'], reason: '$name block $i kind');
        expect(got.status.name, want['status'], reason: '$name block $i status');
        expect(got.title, want['title'], reason: '$name block $i title');
        expect(got.body, want['body'] ?? '', reason: '$name block $i body');
        expect(got.result ?? '', want['result'] ?? '', reason: '$name block $i result');
        expect(got.model ?? '', want['model'] ?? '', reason: '$name block $i model');
        expect(got.errorType ?? '', want['errorType'] ?? '', reason: '$name block $i errorType');

        final wantQuestions = want['questions'] as List<dynamic>?;
        if (wantQuestions == null) continue;
        final detail = got.detail;
        expect(detail, isA<QuestionBlockDetail>(), reason: '$name block $i detail');
        final questions = (detail as QuestionBlockDetail).questions;
        expect(questions, hasLength(wantQuestions.length), reason: '$name block $i question count');
        for (var q = 0; q < wantQuestions.length; q++) {
          final wantQuestion = wantQuestions[q] as Map<String, dynamic>;
          expect(questions[q].question, wantQuestion['question'], reason: '$name block $i question $q');
          expect(
            questions[q].options.map((option) => option.label).toList(),
            wantQuestion['options'],
            reason: '$name block $i options $q',
          );
        }
      }
    });
  }
}
```

- [ ] **Step 3: Run it to verify it fails**

```bash
cd packages/mobile
flutter test test/feature/blocks/logic/block_assembly_transcript_test.dart
```

Expected: FAIL on every fixture — the new kinds all fall through to the `default`
branch and become notices.

- [ ] **Step 4: Rewrite `assembleBlocks`**

Replace the whole body of `packages/mobile/lib/feature/blocks/logic/block_assembly.dart` with:

```dart
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/logic/block_question.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

List<SessionBlock> assembleBlocks(Iterable<BlockEventModel> events) {
  final ordered = events.where((event) => event.seq != null).toList()..sort((a, b) => a.seq!.compareTo(b.seq!));

  final blocks = <SessionBlock>[];
  final indexById = <String, int>{};
  final consumed = <int>{};
  final bodyFromTranscript = <String>{};
  final statusFromHook = <String>{};

  String? model;
  int? todoIndex;
  int? questionIndex;
  var sawTranscriptAssistant = false;

  for (final event in ordered) {
    final seq = event.seq!;
    if (!consumed.add(seq)) continue;

    final key = _correlationKey(event);
    final id = _blockId(event, key);
    final text = event.text ?? '';
    final fromTranscript = event.source == 'transcript';

    switch (event.kind) {
      case 'idle_prompt':
        continue;

      case 'session_start':
        _upsert(blocks, indexById, _create(event, id, BlockKind.notice, BlockStatus.ok, 'Session started', text, model));

      case 'prompt_submit':
        todoIndex = null;
        questionIndex = null;
        sawTranscriptAssistant = false;
        _upsert(blocks, indexById, _create(event, id, BlockKind.prompt, BlockStatus.running, 'Prompt', text, model));

      case 'turn_model':
        if (text.isNotEmpty) model = text;

      case 'assistant_text':
        sawTranscriptAssistant = true;
        final title = event.rawEvent == 'commentary' ? 'Assistant · note' : 'Assistant';
        _upsert(blocks, indexById, _create(event, id, BlockKind.assistant, BlockStatus.ok, title, text, model));

      case 'reasoning':
        _upsert(blocks, indexById, _create(event, id, BlockKind.reasoning, BlockStatus.ok, 'Reasoning', text, model));

      case 'compaction':
        _upsert(blocks, indexById, _create(event, id, BlockKind.compaction, BlockStatus.ok, 'Compaction', text, model));

      case 'todo':
        if (todoIndex != null) {
          blocks[todoIndex] = blocks[todoIndex].copyWith(body: text, lastSeq: seq);
        } else {
          todoIndex = blocks.length;
          _upsert(blocks, indexById, _create(event, id, BlockKind.todo, BlockStatus.ok, 'Todo', text, model));
        }

      case 'tool_start':
        bodyFromTranscript.add(id);
        final at = indexById[id];
        final body = event.toolInput ?? '';
        if (at != null) {
          blocks[at] = blocks[at].copyWith(
            body: body,
            lastSeq: seq,
            status: statusFromHook.contains(id) ? null : BlockStatus.running,
          );
        } else {
          _upsert(
            blocks,
            indexById,
            _create(event, id, BlockKind.tool, BlockStatus.running, event.toolName ?? 'Tool', body, model),
          );
        }

      case 'tool_result':
        final failed = (event.errorType ?? '').isNotEmpty;
        final resolved = failed ? BlockStatus.failed : BlockStatus.ok;
        final at = indexById[id];
        if (at != null) {
          blocks[at] = blocks[at].copyWith(
            result: text,
            lastSeq: seq,
            errorType: event.errorType,
            status: statusFromHook.contains(id) ? null : resolved,
          );
        } else {
          _upsert(
            blocks,
            indexById,
            _create(event, id, BlockKind.tool, resolved, event.toolName ?? 'Tool', '', model, result: text),
          );
        }

      case 'tool_complete':
        statusFromHook.add(id);
        final failed = (event.errorType ?? '').isNotEmpty;
        final status = failed ? BlockStatus.failed : BlockStatus.ok;
        final hookBody = _join([event.toolInput ?? '', text], '\n\n');
        final at = indexById[id];
        if (at != null) {
          blocks[at] = blocks[at].copyWith(
            status: status,
            body: bodyFromTranscript.contains(id) ? null : hookBody,
            lastSeq: seq,
            errorType: event.errorType,
            truncatedLines: event.truncatedLines ?? 0,
            redacted: _isRedacted(event) || blocks[at].redacted,
          );
        } else {
          _upsert(
            blocks,
            indexById,
            _create(event, id, BlockKind.tool, status, event.toolName ?? 'Tool', hookBody, model),
          );
        }

      case 'permission_request':
        statusFromHook.add(id);
        final at = indexById[id];
        if (at != null) {
          blocks[at] = blocks[at].copyWith(
            kind: BlockKind.permission,
            title: 'Permission requested',
            status: BlockStatus.blocked,
            lastSeq: seq,
          );
        } else {
          final detail = (event.toolInput ?? '').isNotEmpty ? event.toolInput! : text;
          _upsert(
            blocks,
            indexById,
            _create(
              event,
              id,
              BlockKind.permission,
              BlockStatus.blocked,
              'Permission requested',
              _join([event.toolName ?? '', detail], '\n'),
              model,
            ),
          );
        }

      case 'question_asked':
        final questions = fromTranscript ? parseQuestionDetail(event.toolInput ?? '') : null;
        if (!fromTranscript && questionIndex != null) continue;
        final title = questions?.questions.first.question ?? 'Waiting on you';
        final body = fromTranscript ? '' : text;
        final block = _create(event, id, BlockKind.notice, BlockStatus.blocked, title, body, model, detail: questions);
        if (fromTranscript && questionIndex != null) {
          indexById.remove(blocks[questionIndex].id);
          blocks[questionIndex] = block;
          indexById[block.id] = questionIndex;
        } else {
          questionIndex = blocks.length;
          _upsert(blocks, indexById, block);
        }

      case 'permission_replied':
        final at = indexById[id];
        if (at != null) {
          blocks[at] = blocks[at].copyWith(status: BlockStatus.ok, lastSeq: seq);
        }

      case 'stop':
      case 'stop_failure':
        questionIndex = null;
        final failed = event.kind == 'stop_failure';
        final at = _lastRunningPrompt(blocks);
        if (at != null) {
          blocks[at] = blocks[at].copyWith(status: failed ? BlockStatus.failed : BlockStatus.ok, lastSeq: seq);
        }
        if (text.isNotEmpty && !sawTranscriptAssistant) {
          _upsert(
            blocks,
            indexById,
            _create(
              event,
              id,
              BlockKind.assistant,
              failed ? BlockStatus.failed : BlockStatus.ok,
              'Assistant',
              text,
              model,
            ),
          );
        }

      default:
        final raw = event.rawEvent ?? '';
        _upsert(
          blocks,
          indexById,
          _create(event, id, BlockKind.notice, BlockStatus.ok, raw.isNotEmpty ? raw : 'Event', text, model),
        );
    }
  }

  return blocks;
}

List<SessionBlock> resolveStranded(List<SessionBlock> blocks, String reason) => blocks
    .map(
      (block) => block.status == BlockStatus.running || block.status == BlockStatus.blocked
          ? block.copyWith(status: BlockStatus.failed, body: reason)
          : block,
    )
    .toList();

String _join(List<String> parts, String separator) => parts.where((part) => part.isNotEmpty).join(separator);

String? _correlationKey(BlockEventModel event) {
  final source = event.sourceId ?? '';
  if (source.isNotEmpty) return source;
  final toolUse = event.toolUseId ?? '';
  return toolUse.isNotEmpty ? toolUse : null;
}

bool _isRedacted(BlockEventModel event) => (event.redactedSpans ?? const []).isNotEmpty;

String _blockId(BlockEventModel event, String? key) =>
    key != null && _correlates(event.kind) ? 'src-$key' : 'seq-${event.seq}';

const _correlatingKinds = {
  'tool_complete',
  'tool_start',
  'tool_result',
  'permission_request',
  'permission_replied',
  'question_asked',
  'compaction',
  'todo',
  'assistant_text',
  'reasoning',
};

bool _correlates(String? kind) => _correlatingKinds.contains(kind);

SessionBlock _create(
  BlockEventModel event,
  String id,
  BlockKind kind,
  BlockStatus status,
  String title,
  String body,
  String? model, {
  String? result,
  BlockDetail? detail,
}) => SessionBlock(
  id: id,
  firstSeq: event.seq!,
  lastSeq: event.seq!,
  kind: kind,
  status: status,
  title: title,
  body: body,
  result: result,
  model: model,
  toolName: event.toolName,
  errorType: event.errorType,
  truncatedLines: event.truncatedLines ?? 0,
  redacted: _isRedacted(event),
  createdAt: event.createdAt,
  turnId: null,
  detail: detail ?? UnknownBlockDetail(raw: event.toolInput ?? event.text ?? ''),
);

void _upsert(List<SessionBlock> blocks, Map<String, int> indexById, SessionBlock block) {
  final at = indexById[block.id];
  if (at != null) {
    blocks[at] = blocks[at].copyWith(body: block.body, status: block.status, lastSeq: block.lastSeq);
    return;
  }
  indexById[block.id] = blocks.length;
  blocks.add(block);
}

int? _lastRunningPrompt(List<SessionBlock> blocks) {
  for (var i = blocks.length - 1; i >= 0; i--) {
    if (blocks[i].kind == BlockKind.prompt && blocks[i].status == BlockStatus.running) return i;
  }
  return null;
}
```

Two details that are easy to get wrong. `copyWith(status: null)` means "leave it
alone", which is exactly the hook-wins-on-status rule; do not replace those with
a conditional that passes the current status. And the question branch clears the
old id out of `indexById` before writing the new one, or a later event keyed on
the hook's id would land in the wrong slot.

- [ ] **Step 5: Run the new and the existing assembler tests**

```bash
cd packages/mobile
flutter analyze
flutter test test/feature/blocks/logic/
```

Expected: `No issues found!` and green, including the pre-existing
`block_assembly_test.dart` and `block_assembly_fixtures_test.dart` — the hook-only
fixtures (`assembly_turn`, `assembly_permission`, `assembly_out_of_order`,
`assembly_truncation`, `assembly_tool_failure`, `assembly_question`) must still
pass unchanged. If `assembly_question` now fails, your `question_asked` branch
broke the hook-only path: a hook question with no prior question block must still
append a "Waiting on you" notice.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib/feature/blocks/logic/block_assembly.dart \
        packages/mobile/test/feature/blocks/logic/block_assembly_transcript_test.dart \
        testdata/blocks
git commit -m "feat(mobile): project transcript block events into the blocks view"
```

---

### Task 12: The turn's model, and a working indicator between records

Both harnesses write a record only when a content block completes, so there are
gaps of seconds between blocks. The turn footer already counts elapsed time when
a block is running; this makes it also read as working when the hook says the
session is active and nothing is running yet.

**Files:**
- Modify: `packages/mobile/lib/feature/blocks/logic/turn_grouping.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/turn_group_status.dart`
- Create: `packages/mobile/test/feature/blocks/logic/turn_grouping_transcript_test.dart`
- Modify: `packages/mobile/test/feature/blocks/presentation/blocks_cubit_test.dart`

**Interfaces:**
- Consumes: `SessionBlock.model` (Task 10), `assembleBlocks` (Task 11).
- Produces: `TurnGroup.model`; `groupBlocksByTurn(List<SessionBlock> blocks, {bool sessionActive = false})`; `BlocksCubit.active`; `BlockList.sessionActive`.

- [ ] **Step 1: Write the failing tests**

Create `packages/mobile/test/feature/blocks/logic/turn_grouping_transcript_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart';

SessionBlock _block(String id, BlockKind kind, BlockStatus status, {String? model}) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: kind,
  status: status,
  title: id,
  body: '',
  model: model,
);

void main() {
  test('a turn carries the first model any of its blocks reported', () {
    final groups = groupBlocksByTurn([
      _block('p', BlockKind.prompt, BlockStatus.ok),
      _block('a', BlockKind.assistant, BlockStatus.ok, model: 'claude-sonnet-5'),
      _block('b', BlockKind.assistant, BlockStatus.ok, model: 'claude-opus-5'),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.model, 'claude-sonnet-5');
  });

  test('an active session marks only the last turn as running', () {
    final groups = groupBlocksByTurn([
      _block('p1', BlockKind.prompt, BlockStatus.ok),
      _block('a1', BlockKind.assistant, BlockStatus.ok),
      _block('p2', BlockKind.prompt, BlockStatus.ok),
      _block('a2', BlockKind.assistant, BlockStatus.ok),
    ], sessionActive: true);

    expect(groups, hasLength(2));
    expect(groups.first.running, isFalse);
    expect(groups.last.running, isTrue);
    expect(groups.last.completedAt, isNull);
  });

  test('an idle session leaves every turn finished', () {
    final groups = groupBlocksByTurn([
      _block('p1', BlockKind.prompt, BlockStatus.ok),
      _block('a1', BlockKind.assistant, BlockStatus.ok),
    ]);

    expect(groups.single.running, isFalse);
  });
}
```

Append to `packages/mobile/test/feature/blocks/presentation/blocks_cubit_test.dart`:

```dart
  test('tracks the session activity the hooks report', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.active, isFalse);

    patches.add(const [
      SessionPatch(
        id: 's-1',
        status: 'working',
        activity: 'active',
        attentionLevel: 'none',
        lastActivityAt: '2026-09-04T00:00:00.000Z',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.active, isTrue);

    patches.add(const [
      SessionPatch(
        id: 's-1',
        status: 'idle',
        activity: 'idle',
        attentionLevel: 'none',
        lastActivityAt: '2026-09-04T00:00:01.000Z',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.active, isFalse);

    await cubit.close();
  });
```

- [ ] **Step 2: Run them to verify they fail**

```bash
cd packages/mobile
flutter test test/feature/blocks/logic/turn_grouping_transcript_test.dart \
             test/feature/blocks/presentation/blocks_cubit_test.dart
```

Expected: FAIL — `groupBlocksByTurn` takes no `sessionActive`, `TurnGroup` has no `model`, `BlocksCubit` has no `active`.

- [ ] **Step 3: Extend `TurnGroup` and `groupBlocksByTurn`**

In `packages/mobile/lib/feature/blocks/logic/turn_grouping.dart`, add `this.model` to the `TurnGroup` constructor, `final String? model;` to its fields, and `model` to `props`.

Change the signature to `List<TurnGroup> groupBlocksByTurn(List<SessionBlock> blocks, {bool sessionActive = false})`.

In the closing `.map((group) { ... })`, add `model: _groupModel(group.blocks),` to the returned `TurnGroup`. Change the trailing `.toList();` into a named local and add the active-turn rule after it:

```dart
  final result = groups.map((group) {
    // ... the existing body, unchanged, plus model: _groupModel(group.blocks)
  }).toList();

  if (!sessionActive || result.isEmpty || result.last.running) return result;
  final last = result.last;
  result[result.length - 1] = TurnGroup(
    turnId: last.turnId,
    blocks: last.blocks,
    startedAt: last.startedAt,
    running: true,
    model: last.model,
  );
  return result;
}

String? _groupModel(List<SessionBlock> blocks) {
  for (final block in blocks) {
    final model = block.model;
    if (model != null && model.isNotEmpty) return model;
  }
  return null;
}
```

A running turn deliberately carries no `completedAt` and no `durationMs`, so the
footer counts up from `startedAt` exactly as it does for a running block.

- [ ] **Step 4: Track activity on the cubit**

In `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart`, add `bool active = false;` beside `bool loading = false;`, and replace `_onPatches` with:

```dart
  void _onPatches(List<SessionPatch> patches) {
    for (final patch in patches) {
      if (patch.id != sessionId) continue;
      final ended = patch.activity == 'exited' || patch.status == 'terminated';
      final busy = patch.activity == 'active';
      if (ended != _ended || busy != active) {
        _ended = ended;
        active = busy;
        _rebuild();
      }
      return;
    }
  }
```

- [ ] **Step 5: Thread it to the turn footer**

In `block_list.dart`, add `this.sessionActive = false,` to the `BlockList` constructor and `final bool sessionActive;` to its fields, then change the grouping call in `build`:

```dart
      for (final group in groupBlocksByTurn(blocks, sessionActive: widget.sessionActive))
```

In `blocks_body.dart`, pass it where `BlockList` is constructed:

```dart
                        sessionActive: cubit.active,
```

In `turn_group_status.dart`, show the model beside the state. Replace the `text` local's use in the `AppText` with a model-aware label:

```dart
    final model = group.model;
    final label = model == null || model.isEmpty ? text : '$text · $model';
```

and render `label` instead of `text`.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd packages/mobile
flutter analyze
flutter test test/feature/blocks/
```

Expected: `No issues found!` and green, including `turn_grouping_fixtures_test.dart`, `block_list_test.dart`, `blocks_body_test.dart` and `turn_group_status_rollback_test.dart` — `sessionActive` defaults to false, so nothing that does not pass it changes.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib/feature/blocks packages/mobile/test/feature/blocks
git commit -m "feat(mobile): show the turn's model and keep the open turn working between records"
```

---

### Task 13: Render results, questions and todos

**Files:**
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_result_section.dart`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_question_options.dart`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_todo_list.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart`
- Modify: `packages/mobile/lib/feature/blocks/logic/session_block.dart` (`blockDisplay` only)
- Modify: `packages/mobile/lib/feature/blocks/logic/block_actions.dart`
- Create: `packages/mobile/test/feature/blocks/presentation/blocks_screen/transcript_rendering_test.dart`

**Interfaces:**
- Consumes: `SessionBlock.result`, `QuestionBlockDetail` (Task 10).
- Produces: `BlockResultSection`, `BlockQuestionOptions`, `BlockTodoList`. Phase 3 turns the question and permission surfaces into controls; this task renders them read-only.

- [ ] **Step 1: Write the failing widget test**

Create `packages/mobile/test/feature/blocks/presentation/blocks_screen/transcript_rendering_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

Widget _host(SessionBlock block) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: BlockCard(block: block))),
);

SessionBlock _base({
  required String id,
  required BlockKind kind,
  String title = 'Tool',
  String body = '',
  String? result,
  BlockDetail? detail,
}) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: kind,
  status: BlockStatus.ok,
  title: title,
  body: body,
  result: result,
  detail: detail,
);

void main() {
  testWidgets('a tool block shows its input and its result separately', (tester) async {
    await tester.pumpWidget(
      _host(_base(id: 'b-1', kind: BlockKind.tool, title: 'Bash', body: 'go test ./...', result: 'ok 42 tests')),
    );

    expect(find.text('go test ./...'), findsOneWidget);
    expect(find.text('ok 42 tests'), findsOneWidget);
  });

  testWidgets('a long result is collapsed behind a toggle', (tester) async {
    final long = List.generate(40, (index) => 'line $index').join('\n');
    await tester.pumpWidget(_host(_base(id: 'b-2', kind: BlockKind.tool, result: long)));

    expect(find.text('Show full result'), findsOneWidget);
    expect(find.text('line 39'), findsNothing);

    await tester.tap(find.text('Show full result'));
    await tester.pumpAndSettle();

    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('a question block lists every option', (tester) async {
    await tester.pumpWidget(
      _host(
        _base(
          id: 'b-3',
          kind: BlockKind.notice,
          title: 'Which branch?',
          detail: const QuestionBlockDetail(
            questions: [
              BlockQuestion(
                question: 'Which branch?',
                header: 'Branch',
                multiSelect: false,
                options: [
                  BlockQuestionOption(label: 'main', description: 'the default branch'),
                  BlockQuestionOption(label: 'develop', description: 'the integration branch'),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('main'), findsOneWidget);
    expect(find.text('develop'), findsOneWidget);
    expect(find.text('the default branch'), findsOneWidget);
    expect(find.text('Answer in the terminal'), findsOneWidget);
  });

  testWidgets('a todo block renders a checklist', (tester) async {
    await tester.pumpWidget(
      _host(
        _base(
          id: 'b-4',
          kind: BlockKind.todo,
          title: 'Todo',
          body: '{"todos":[{"content":"Rename the branch","status":"completed"},'
              '{"content":"Push it","status":"pending"}]}',
        ),
      ),
    );

    expect(find.text('Rename the branch'), findsOneWidget);
    expect(find.text('Push it'), findsOneWidget);
  });

  testWidgets('a todo block that is not a todo payload falls back to its text', (tester) async {
    await tester.pumpWidget(_host(_base(id: 'b-5', kind: BlockKind.todo, title: 'Todo', body: 'plain text')));

    expect(find.text('plain text'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/mobile
flutter test test/feature/blocks/presentation/blocks_screen/transcript_rendering_test.dart
```

Expected: FAIL — the result, options and checklist are not rendered.

- [ ] **Step 3: Write the result section**

Create `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_result_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

const int kResultPreviewLines = 12;

class BlockResultSection extends StatefulWidget {
  const BlockResultSection({super.key, required this.result});

  final String result;

  @override
  State<BlockResultSection> createState() => _BlockResultSectionState();
}

class _BlockResultSectionState extends State<BlockResultSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final lines = widget.result.split('\n');
    final long = lines.length > kResultPreviewLines;
    final shown = !long || _expanded ? widget.result : lines.take(kResultPreviewLines).join('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: skin.borderSubtle),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: AppText(
            shown,
            style: AppTextStyle.mono12Regular.copyWith(color: skin.textSecondary),
            maxLines: 400,
          ),
        ),
        if (long)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: AppText(
                _expanded ? 'Show less' : 'Show full result',
                style: AppTextStyle.style10SemiBold.copyWith(color: skin.blue),
              ),
            ),
          ),
      ],
    );
  }
}
```

If `AppText` does not accept `maxLines` the way this uses it, match the call
shape the neighbouring widgets in `block_card.dart` already use.

- [ ] **Step 4: Write the question options**

Create `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_question_options.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

class BlockQuestionOptions extends StatelessWidget {
  const BlockQuestionOptions({super.key, required this.questions});

  final List<BlockQuestion> questions;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final question in questions) ...[
            if ((question.header ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: AppText(
                  question.header!,
                  style: AppTextStyle.style10SemiBold.copyWith(color: skin.textTertiary),
                ),
              ),
            for (final option in question.options)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: skin.bgElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: skin.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      option.label ?? '',
                      style: AppTextStyle.style12SemiBold.copyWith(color: skin.textPrimary),
                    ),
                    if ((option.description ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: AppText(
                          option.description!,
                          style: AppTextStyle.style10Regular.copyWith(color: skin.textSecondary),
                          maxLines: 4,
                        ),
                      ),
                  ],
                ),
              ),
          ],
          AppText(
            'Answer in the terminal',
            style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
  }
}
```

"Answer in the terminal" is the honest copy for this phase: the phone can see the
question but not yet answer it. Phase 3 replaces this line with real controls.

- [ ] **Step 5: Write the todo checklist**

Create `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_todo_list.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class BlockTodoList extends StatelessWidget {
  const BlockTodoList({super.key, required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final items = _parse(body);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: AppText(
          body,
          style: AppTextStyle.mono12Regular.copyWith(color: skin.textSecondary),
          maxLines: 200,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.done ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 14,
                    color: item.done ? skin.green : skin.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AppText(
                      item.text,
                      style: AppTextStyle.style12Regular.copyWith(
                        color: item.done ? skin.textTertiary : skin.textPrimary,
                      ),
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TodoItem {
  const _TodoItem(this.text, this.done);

  final String text;
  final bool done;
}

List<_TodoItem> _parse(String body) {
  if (body.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map<String, dynamic>) return const [];
  final raw = decoded['todos'];
  if (raw is! List) return const [];
  final items = <_TodoItem>[];
  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) continue;
    final text = entry['content'] as String?;
    if (text == null || text.isEmpty) continue;
    items.add(_TodoItem(text, entry['status'] == 'completed'));
  }
  return items;
}
```

If `skin.green` is not the accessor name in `AppSkin`, use whatever the skin
calls its success colour — check `lib/core/app_themes/colors/` and use an
existing token; never inline a `Color(0x...)`.

- [ ] **Step 6: Render them from `BlockCard`**

In `block_card.dart`, import the three new widgets. Inside the `body` `Column`,
replace the summary `Padding` with a kind-aware body and add the result section:

```dart
        if (block.kind == BlockKind.todo)
          BlockTodoList(body: block.body)
        else if (display.summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: _highlightedField(
              context: context,
              text: display.summary,
              ranges: summaryHighlight?.ranges ?? const <MatchRange>[],
              base: AppTextStyle.mono12Regular.copyWith(color: skin.textSecondary),
              softWrap: true,
            ),
          ),
        if (block.detail is QuestionBlockDetail)
          BlockQuestionOptions(questions: (block.detail! as QuestionBlockDetail).questions),
        if ((block.result ?? '').isNotEmpty) BlockResultSection(result: block.result!),
```

Leave everything after it — children, error text, redaction notice, truncation
notice, actions — exactly as it is.

- [ ] **Step 7: Make a string `UnknownBlockDetail` render verbatim**

In `session_block.dart`, `blockDisplay`'s `UnknownBlockDetail` case currently
JSON-encodes the raw payload when the body is empty, which turns a plain string
into a quoted one. Change that case to:

```dart
    UnknownBlockDetail(:final raw) => BlockDisplay(
      displayName: block.title,
      summary: block.body.isNotEmpty
          ? block.body
          : raw is String
          ? raw
          : jsonEncode(raw),
    ),
```

A structured payload still encodes, which is what
`testdata/blocks/acp_detail_variants.json` asserts.

- [ ] **Step 8: Let copy carry the result**

In `block_actions.dart`, prefer the result for the copy-output action:

```dart
    } else if (block.kind == BlockKind.tool && (block.result ?? '').isNotEmpty) {
      actions.add(BlockAction(kind: BlockActionKind.copyOutput, payload: block.result));
    } else if (block.kind == BlockKind.tool && block.body.isNotEmpty) {
      actions.add(BlockAction(kind: BlockActionKind.copyOutput, payload: block.body));
    }
```

and append it in `copyText`, immediately after `rendered` is built:

```dart
    final result = block.result ?? '';
    final withResult = result.isEmpty ? rendered : '$rendered\n\n$result';
```

then use `withResult` everywhere `rendered` was used below that line.

- [ ] **Step 9: Run the tests**

```bash
cd packages/mobile
flutter analyze
flutter test test/feature/blocks/
```

Expected: `No issues found!` and green, including `block_actions_fixtures_test.dart`
and `block_card_collapse_test.dart` — the existing fixture blocks carry no
`result`, so their expectations are unchanged.

- [ ] **Step 10: Commit**

```bash
git add packages/mobile/lib/feature/blocks packages/mobile/test/feature/blocks
git commit -m "feat(mobile): render tool results, question options and todo lists"
```

---

### Task 14: Reasoning is collapsed by default

Per the spec's recorded decision: collapsed with a one-line preview, no setting.

**Files:**
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`
- Modify: `packages/mobile/test/feature/blocks/presentation/blocks_screen/blocks_body_test.dart`

**Interfaces:**
- Consumes: `BlockKind.reasoning` blocks from Task 11.
- Produces: no new API. `BlocksBodyState` gains a private `_expandedReasoning` set.

- [ ] **Step 1: Write the failing test**

Append to `packages/mobile/test/feature/blocks/presentation/blocks_screen/blocks_body_test.dart` a test that pumps a `BlocksBody` whose cubit reports one prompt block and one reasoning block, and asserts the reasoning body is not shown until its header is tapped. Mirror the pump/cubit-stub helper the tests already in that file use — do not invent a second harness.

```dart
  testWidgets('reasoning starts collapsed and expands on tap', (tester) async {
    await pumpBlocksBody(tester, blocks: [
      block(id: 'seq-1', kind: BlockKind.prompt, title: 'Prompt', body: 'go'),
      block(id: 'src-u-1', kind: BlockKind.reasoning, title: 'Reasoning', body: 'thinking out loud'),
    ]);

    expect(find.text('thinking out loud'), findsNothing);

    await tester.tap(find.text('Reasoning'));
    await tester.pumpAndSettle();

    expect(find.text('thinking out loud'), findsOneWidget);
  });
```

Name `pumpBlocksBody` and `block` after whatever that file already defines; if it
has no helpers, copy the exact `pumpWidget` setup from its first test.

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/mobile
flutter test test/feature/blocks/presentation/blocks_screen/blocks_body_test.dart
```

Expected: FAIL — the reasoning body renders immediately.

- [ ] **Step 3: Collapse reasoning by default**

In `blocks_body.dart`, add a field beside `_collapsed`:

```dart
  final Set<String> _expandedReasoning = <String>{};
```

Clear it in `_syncCollapsed` alongside `_collapsed.clear()`.

In `build`, after `visibleBlocks` is computed, derive the effective collapsed set
rather than mutating state during a build:

```dart
        final collapsedIds = <String>{
          ..._collapsed,
          for (final block in visibleBlocks)
            if (block.kind == BlockKind.reasoning && !_expandedReasoning.contains(block.id)) block.id,
        };
```

Pass `collapsedIds: collapsedIds` to `BlockList` instead of `_collapsed`, and
route the toggle through the right set:

```dart
                        onToggleCollapse: (id) => setState(() {
                          final block = visibleBlocks.firstWhere(
                            (candidate) => candidate.id == id,
                            orElse: () => visibleBlocks.first,
                          );
                          if (block.kind == BlockKind.reasoning) {
                            if (!_expandedReasoning.add(id)) _expandedReasoning.remove(id);
                            return;
                          }
                          if (!_collapsed.add(id)) _collapsed.remove(id);
                        }),
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd packages/mobile
flutter analyze
flutter test
```

Expected: `No issues found!` and the whole suite green.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/blocks packages/mobile/test/feature/blocks
git commit -m "feat(mobile): collapse reasoning blocks by default"
```

---

## Part E — Land it

### Task 15: Documentation and the deferral ledger

**Files:**
- Modify: `docs/superpowers/specs/2026-09-04-single-session-interface-design.md:3`
- Modify: `docs/STATUS.md:166-167`
- Modify: `docs/architecture.md:3` and `:768-773`
- Modify: `todo_without_tmux.md` (section 15)

- [ ] **Step 1: Update the spec's status line**

In `docs/superpowers/specs/2026-09-04-single-session-interface-design.md`, change line 3 from

```
Status: Phase 1 implemented; Phases 2–4 unimplemented
```

to

```
Status: Phases 1–2 implemented; Phases 3–4 unimplemented
```

Do not change anything else in the spec: it is the design record, not a progress log.

- [ ] **Step 2: Update `docs/STATUS.md`**

Replace the two-line bullet at `docs/STATUS.md:166-167`:

```markdown
- Mobile's blocks view is fed by two channels: agent hooks report status and the
  session's native transcript reports body. A per-session tailer projects Claude
  Code JSONL and Codex rollout records into assistant text, reasoning, full tool
  input, tool results, todo lists, the turn's model, compaction, and the options
  of a pending question. Precedence is fixed: transcript wins on body, hook wins
  on status, and a session whose transcript is unreadable degrades to the
  hook-only projection. Harnesses other than Claude Code and Codex contribute
  hook blocks only. Phase 3 adds deterministic terminal controls.
```

- [ ] **Step 3: Update `docs/architecture.md`**

At line 3, change "mobile renders hook-derived blocks by default" to "mobile renders blocks derived from agent hooks and the session's native transcript by default".

In the mobile paragraph at lines 769-773, change "renders hook-derived blocks for a covered harness by default" to "renders blocks for a covered harness by default, merged from the hook channel and the daemon's transcript tailer".

Add a subsection immediately before `### Durable shell-block capture`:

```markdown
### Transcript block projection

`internal/observe/transcript` runs one tail per live session whose harness has a
mapper in `adapters/agent/blocktranscript` (Claude Code and Codex today). It
resolves the session's provider transcript through the adapter's own
`AgentTranscriptLocator`, rejecting any path outside that provider's config
directory, reads new complete JSONL lines from a cursor persisted in
`transcript_offsets`, and records each mapped record through the same
`blockevent.Service` a hook uses — same redaction, same caps, same mux publish —
marked `source = transcript`. It shares no state with the usage observer, which
reads the same files on its own cursor for unrelated reasons. An unrecognised
record type produces nothing and is counted, so a harness upgrade degrades to
fewer blocks rather than to a crash.
```

- [ ] **Step 4: Update the deferral ledger**

In `todo_without_tmux.md`, section 15.1 says "Phase 2 of that spec tails ...". Change its opening sentence to past tense — "Phase 2 tails the native transcript of Claude Code and Codex ..." — and leave the grok deferral itself unchanged. Do the same for 15.2's opening sentence ("Phase 2 drops both" is already correct; only fix a tense that reads as future work).

- [ ] **Step 5: Commit**

```bash
git add docs todo_without_tmux.md
git commit -m "docs: record transcript-backed blocks on mobile"
```

---

### Task 16: Full-repo verification

No new code. This is the gate before the branch is offered for review.

- [ ] **Step 1: Backend**

```bash
cd backend
go build ./...
go test ./...
go test -race ./internal/observe/transcript/ ./internal/service/blockevent/
go vet ./...
```

Expected: all green.

- [ ] **Step 2: Repo lint and generated-artifact drift**

```bash
cd .. 
npm run lint
npm run sqlc
npm run api
git status --porcelain
```

Expected: `npm run lint` green; `git status --porcelain` empty after the two
regenerations. A non-empty status means a generated artifact was committed stale
— commit the regenerated files.

- [ ] **Step 3: Frontend**

```bash
cd frontend
npm run typecheck
npm run lint
npx vitest run
```

Expected: green. Phase 2 touches the desktop only through the generated
`schema.ts`, so a failure here means the API regeneration broke a consumer.

- [ ] **Step 4: Mobile**

```bash
cd packages/mobile
flutter analyze
flutter test
```

Expected: `No issues found!` and the full suite green.

- [ ] **Step 5: Live smoke on both harnesses**

Start the daemon and the desktop app. For **each** of Claude Code and Codex:

1. Spawn a session and send a prompt that runs at least one tool and produces at
   least one paragraph of assistant text.
2. Open the session on the paired phone in blocks view.
3. Confirm you can see, without opening the raw terminal: the prompt, the
   assistant's text as it lands, a collapsed reasoning block, the tool with its
   **full** input, the tool's result inside that block, and the model on the
   turn footer.
4. Kill the daemon mid-turn and restart it. Confirm the blocks list does not
   duplicate anything already shown, and that new records still arrive.
5. For Claude Code only: trigger a question (any prompt that makes the agent ask)
   and confirm the phone shows the question text and its options rather than
   "Waiting on you".

Record anything that did not work in the PR body rather than silently narrowing
the scope.

- [ ] **Step 6: Open the PR**

```bash
git push -u origin feat/single-session-phase-2
gh pr create --base master --title "feat: transcript-backed blocks on mobile (single-session Phase 2)" --body "$(cat <<'BODY'
Implements Phase 2 of docs/superpowers/specs/2026-09-04-single-session-interface-design.md.

The phone now sees what the agent says and does, not just that it is doing something:
a per-session transcript tailer projects Claude Code JSONL and Codex rollout records
into block events beside the hook channel, and the mobile assembler merges them with
a fixed precedence — transcript wins on body, hook wins on status.

- new block-event kinds: assistant_text, reasoning, tool_start, tool_result, todo,
  turn_model, compaction; question_asked is enriched with its options
- block events carry a `source` channel marker (hook | transcript)
- `internal/observe/transcript` tails each live session from a durable cursor in
  `transcript_offsets`; per-harness mappers live in the adapter packages
- mobile renders tool results inside the tool block, reasoning collapsed by default,
  todos as a checklist, the turn's model on the footer, and a working indicator on the
  open turn between records
- a session with no readable transcript projects exactly as it did before

Deliberately out of scope: grok (todo_without_tmux.md 15.1), subagent nesting (15.2),
and every control action (Phase 3).
BODY
)"
```

---

## Verification checklist for the reviewer

Every row is an acceptance criterion from the spec.

| the spec says | where it is proved |
|---|---|
| assistant text, every message as it completes | `testdata/transcripts/*_turn.expected.json`, `assembly_transcript_turn.json` |
| reasoning, collapsed with a preview | Task 14's `blocks_body_test.dart` case |
| tool call with full input, both harnesses | `assembly_transcript_turn.json`, `assembly_transcript_codex.json` |
| tool result inside the tool block | `assembly_transcript_*.json` `result` field; `transcript_rendering_test.dart` |
| todo list when the harness uses a todo tool | `assembly_transcript_question.json`; `transcript_rendering_test.dart` |
| question and its options | `claude_code_edge.expected.json`, `assembly_transcript_question.json` |
| compaction | `claude_code_edge`, `codex_edge`, `assembly_transcript_question.json` |
| model per turn | `turn_grouping_transcript_test.dart` |
| `Source` on the record, hook vs transcript | Task 1's store test; Task 3's service test |
| transcript wins on body, hook wins on status | `assembly_transcript_turn.json` (tool_complete does not clobber the input), `assembly_transcript_tool_merge.json` (permission blocks a transcript-bodied block) |
| a Codex tool_start with no hook opens a block that tool_result closes | `assembly_transcript_codex.json` |
| a tool_result on an unknown id is its own block, not a crash | `assembly_transcript_tool_merge.json` |
| a session with no readable transcript projects identically to today | the six pre-existing `assembly_*.json` fixtures still pass unchanged |
| tailing resumes from a persisted offset without duplicates | `TestPumpResumesWithoutRepeating`, `TestReconcileSeedsTheCursorFromTheStore` |
| a path change resets the offset | `TestReconcileResetsTheCursorWhenThePathChanges` |
| an unknown record type is counted, not fatal | `TestPumpCountsUnrecognisedRecords`; `known: false` rows in both `*_edge.expected.json` |
| a capped body is marked, never silent | `TestRecordTranscriptCapsAndMarksTruncation` |
| the working indicator between records | `turn_grouping_transcript_test.dart`, `blocks_cubit_test.dart` |
