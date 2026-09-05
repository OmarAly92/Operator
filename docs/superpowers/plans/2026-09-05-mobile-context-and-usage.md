# Mobile Context Readout and Usage Rollup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the mobile app how full the current session's context window is, and how many tokens the machine burned per day and per week.

**Architecture:** Everything comes from `internal/observe/usage`, the transcript parser that already tails Claude Code JSONL and Codex rollout files for TUI sessions. No ACP, no pane scraping. Two new facts get persisted where the parser already writes: a per-event timestamp (for time bucketing) and a per-binding context snapshot (occupancy + window). Two endpoints expose them; the Flutter client renders a readout in the blocks screen and a rollup in settings.

**Tech Stack:** Go 1.x, chi, sqlc + goose (SQLite), code-first OpenAPI via `specgen`; Flutter (cubit-only, hand-written models, `AppSkin` theming).

**Spec:** No spec document exists for this work. It was scoped in conversation on 2026-09-05, and the findings that ground it are reproduced in full below. **Read the Findings section before Task 1** — several of them contradict what the code looks like at first glance, and one of them removes work you would otherwise do.

---

## Global Constraints

- **Mobile is a thin client.** It computes no limits and no percentages that the daemon can compute instead. Every number it renders arrives from the daemon. (`AGENTS.md`, mobile section of `CLAUDE.md`.)
- **No `freezed`, no `json_serializable`** in first-party mobile code. Models are hand-written, all fields nullable, `fromJson` does wire→domain mapping. One params class per method under `data/model/params/`.
- **Cubit only** — never `Bloc` with events. Static-only classes are `sealed class X`.
- **Parameterized paths get static methods on `EndPoints`.** Interpolating a path at a call site is forbidden.
- **Mobile feature code never imports `flutter_screenutil`.** Spacing, padding and radii take raw ints.
- **User-facing copy is inline English.** There is no `LocaleKeys` catalogue for product copy on mobile.
- **Response envelope:** every mobile parse is `GlobalResponse.fromJson(response.data, withDataKey: false)`. Keep `requestId` on errors.
- **Gates.** Backend: `gofmt -l internal/` clean, `go vet ./...`, `go test ./...`, `golangci-lint run ./...`. Mobile: `flutter analyze` must print `No issues found!`, then `flutter test`. Frontend (only if `openapi.yaml` changes): `npm run api` then `cd backend && go test ./internal/httpd/...`.
- **`golangci-lint` caches deleted worktrees.** If it reports issues in paths under `.worktrees/` that do not exist, run `golangci-lint cache clean` and re-run before believing the failure.
- **Do not write code comments unless they explain non-obvious intent.** Match the density of the file you are editing.

---

## Findings that ground this plan

These were established against the live daemon and real transcripts on 2026-09-05. They are not assumptions.

**F1 — Cumulative usage is not context occupancy, and the gap is large.**
`GET /api/v1/usage/sessions/{id}` sums every turn, and cache reads are re-counted each turn. Measured on real sessions:

| session | turns | cumulative input | last-turn context |
|---|---|---|---|
| `scratch-1` | 16 | 966,626 | **64,880** |
| `scratch-7` | 3 | 168,319 | **56,313** |
| `scratch-8` | 1 | 30,713 | 30,713 |

You cannot derive occupancy from the existing endpoint. They coincide only for single-turn sessions.

**F2 — For Claude, context occupancy needs no new column.**
`internal/observe/usage/parser.go:271-286` already stores, per assistant turn, `InputTokens = input_tokens + cache_creation_input_tokens + cache_read_input_tokens` — that sum *is* the context occupied by that turn. Sidechains are already excluded from `claude_main` (`parser.go:267`). So Claude's occupancy is the newest `model_usage_events.input_tokens` for the main source.

**F3 — For Codex, the same column is a delta, not an absolute.**
`parseCodexEvent` (`parser.go:519-560`) stores `input = total.InputTokens - state.Baseline.InputTokens`. Do **not** read Codex occupancy from `input_tokens`. Codex's absolute is `total_token_usage` in the rollout's `token_count` event.

**F4 — Codex already reports its context window, and the parser throws it away.**
`parser.go:524` parses `model_context_window`, and `isCodexContextFill` (`parser.go:614`) uses it only to detect a context reset. The value is never persisted.

**F5 — Claude reports no context window anywhere Operator can read.**
The JSONL `message.usage` object contains exactly: `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`, `output_tokens_details`, `server_tool_use`, `service_tier`, `cache_creation`, `inference_geo`, `iterations`, `speed`. No window. `agent_model_catalog` stores only `{id, label, isDefault}`. The captured pane `backend/testdata/panes/claudecode_idle.txt` shows a bare `61343 tokens` with no limit; `codex_idle.txt` shows no token information at all. **Claude therefore gets a token count with no percentage — exactly what its own TUI shows.** This is the intended behavior, not a shortfall.

**F6 — `model_usage_events` has no timestamp.** Columns are `id, binding_id, usage_source_id, model_id, input_tokens, uncached_input_tokens, cache_read_tokens, cache_write_tokens, output_tokens, reasoning_tokens, source_event_key`. `usage_bindings.updated_at` and `usage_sources.updated_at` are mutable last-touched fields, not event times. Daily/weekly bucketing is impossible without a migration. Every Claude JSONL record carries a `timestamp`; Codex rollout envelopes carry one too.

**F7 — Subagents share a binding.** `usage_sources.kind` is one of `claude_main`, `claude_subagent`, `codex_rollout`. `scratch-8` reports 30,713 from its main transcript but 169,675 from the endpoint, because subagent sources are folded in. A subagent has its own separate context window, so **context occupancy must come from `claude_main` / `codex_rollout` only**, while rollup totals keep counting everything.

**F8 — Quota limits are out of scope, because no source exists.**
"Daily and weekly limits" in the sense of *how much of my plan's quota is left* (Claude's 5-hour and weekly caps, what `/usage` shows inside Claude Code) cannot be built. The figures are not in the JSONL — a scan for `ratelimit`, `rate_limit`, `resets_at`, `quota`, `weekly`, `five_hour` across a real transcript found nothing — not in the rollout, and not in the pane. Obtaining them would mean Operator calling Anthropic's API with the user's credentials, which it does not do. **This plan therefore delivers usage totals bucketed by day and week — how much was consumed — and not quota remaining.** Do not invent a quota number, do not display a percentage-of-plan, and do not label anything in the UI as a "limit".

---

## File Structure

**Backend — new**
- `backend/internal/storage/sqlite/migrations/0098_usage_time_and_context.sql` — adds `occurred_at` to `model_usage_events`; adds `context_used`, `context_window`, `context_at` to `usage_bindings`.
- `backend/internal/storage/sqlite/queries/usage_rollup.sql` — the two new read queries.

**Backend — modified**
- `backend/internal/domain/usage.go` — `ModelUsageEvent` gains `OccurredAt`; new `SessionContext`, `UsageRollupBucket` types.
- `backend/internal/observe/usage/parser.go` — capture timestamps; capture Codex window + absolute total.
- `backend/internal/storage/sqlite/store/usage_store.go` — persist and read the new columns.
- `backend/internal/service/usage/summary.go` — expose context on the summary; add `Rollup`.
- `backend/internal/httpd/controllers/usage.go` — context on the session response; new `GET /usage/rollup`.

**Mobile — new**
- `lib/feature/usage/data/model/session_context_model.dart`
- `lib/feature/usage/data/model/usage_rollup_model.dart`
- `lib/feature/usage/data/model/params/usage_rollup_params.dart`
- `lib/feature/usage/data/data_source/usage_remote_data_source.dart`
- `lib/feature/usage/data/repository/usage_repository.dart`
- `lib/feature/usage/logic/context_readout.dart` — pure formatting, unit-tested without a widget.
- `lib/feature/usage/presentation/usage_screen/logic/usage_cubit.dart` + `usage_state.dart`
- `lib/feature/usage/presentation/usage_screen/ui/usage_screen.dart`
- `lib/feature/blocks/presentation/blocks_screen/ui/widgets/context_readout_chip.dart`

**Mobile — modified**
- `lib/core/api/api_request_helpers/end_points.dart`
- `lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`
- `lib/feature/settings/...` — one row linking to the usage screen (exact file located in Task 13).

---

## Task 1: Migration for event time and context snapshot

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0098_usage_time_and_context.sql`
- Test: `backend/internal/storage/sqlite/migrations_test.go` (existing; add a case)

**Interfaces:**
- Consumes: nothing.
- Produces: columns `model_usage_events.occurred_at` (TIMESTAMP NULL), `usage_bindings.context_used` (INTEGER NOT NULL DEFAULT 0), `usage_bindings.context_window` (INTEGER NOT NULL DEFAULT 0), `usage_bindings.context_at` (TIMESTAMP NULL), and index `idx_model_usage_events_occurred_at`.

`occurred_at` is nullable because rows written before this migration have no knowable time, and backfilling them would mean re-reading every transcript. A NULL row is excluded from rollups rather than bucketed wrongly.

- [x] **Step 1: Write the migration**

```sql
-- Migration 0098: when a usage event happened, and how full the context is.
--
-- model_usage_events stored per-turn deltas keyed only by source_event_key, so
-- "how many tokens did this week cost" had no way to be asked. The provider
-- records carry a timestamp; occurred_at is where it lands. It is nullable
-- because rows written before this migration have no knowable time, and a NULL
-- is excluded from a rollup rather than bucketed into the wrong day.
--
-- The context columns are a snapshot, not a history: what matters is how full
-- the window is now. They live on the binding because that is the grain of one
-- live agent context (session + harness + native root). Subagents share the
-- binding but have their own windows, so only main sources write here.

-- +goose Up
-- +goose StatementBegin
ALTER TABLE model_usage_events ADD COLUMN occurred_at TIMESTAMP;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE INDEX idx_model_usage_events_occurred_at
    ON model_usage_events (occurred_at);
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE usage_bindings ADD COLUMN context_used INTEGER NOT NULL DEFAULT 0
    CHECK (context_used >= 0);
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE usage_bindings ADD COLUMN context_window INTEGER NOT NULL DEFAULT 0
    CHECK (context_window >= 0);
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE usage_bindings ADD COLUMN context_at TIMESTAMP;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP INDEX IF EXISTS idx_model_usage_events_occurred_at;
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE usage_bindings DROP COLUMN context_at;
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE usage_bindings DROP COLUMN context_window;
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE usage_bindings DROP COLUMN context_used;
-- +goose StatementEnd

-- +goose StatementBegin
ALTER TABLE model_usage_events DROP COLUMN occurred_at;
-- +goose StatementEnd
```

- [x] **Step 2: Verify the migration applies to a fresh database**

Run: `cd backend && go test ./internal/storage/sqlite/... -run Migration -v`
Expected: PASS. If the repo has no migration test that opens a fresh DB, run instead:
`cd backend && go test ./internal/storage/sqlite/sqlitetest/...`
Expected: PASS — `sqlitetest.MustOpen` runs every migration, so any SQL error fails here.

- [x] **Step 3: Verify the new columns exist**

```bash
cd backend && cat > /tmp/schemacheck_test.go <<'EOF'
package sqlitetest_test
EOF
go test ./internal/storage/sqlite/... 2>&1 | tail -5
```
Then confirm by hand against a scratch DB:
```bash
cd backend && go run ./cmd/opr dev --help >/dev/null 2>&1 || true
```
Expected: the `sqlitetest` package tests pass, which is the real gate. Delete `/tmp/schemacheck_test.go`.

- [x] **Step 4: Commit**

```bash
git add backend/internal/storage/sqlite/migrations/0098_usage_time_and_context.sql
git commit -m "feat(usage): add event time and context snapshot columns"
```

---

## Task 2: Domain types

**Files:**
- Modify: `backend/internal/domain/usage.go`
- Test: `backend/internal/domain/usage_test.go`

**Interfaces:**
- Consumes: Task 1's columns.
- Produces:
  - `ModelUsageEvent.OccurredAt time.Time` (zero value means unknown)
  - `type SessionContext struct { Harness string; ModelID string; Used int64; Window int64; ObservedAt time.Time }`
  - `func (c SessionContext) Fraction() (float64, bool)` — returns `(used/window, true)` only when `Window > 0 && Used >= 0`; otherwise `(0, false)`
  - `type UsageRollupBucket struct { Start time.Time; Totals UsageMetricTotals }`

- [x] **Step 1: Write the failing test**

```go
func TestSessionContextFraction(t *testing.T) {
	cases := []struct {
		name   string
		ctx    domain.SessionContext
		want   float64
		wantOK bool
	}{
		{"window known", domain.SessionContext{Used: 50, Window: 200}, 0.25, true},
		{"window unknown is not zero percent", domain.SessionContext{Used: 64880, Window: 0}, 0, false},
		{"empty context with a known window", domain.SessionContext{Used: 0, Window: 200}, 0, true},
		{"over window clamps to one", domain.SessionContext{Used: 300, Window: 200}, 1, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := tc.ctx.Fraction()
			if ok != tc.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tc.wantOK)
			}
			if ok && got != tc.want {
				t.Fatalf("fraction = %v, want %v", got, tc.want)
			}
		})
	}
}
```

The "window unknown is not zero percent" case is the one that matters: Claude reports no window (F5), and a UI that reads `0` as "0% full" would tell the user the opposite of the truth.

- [x] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/domain/ -run TestSessionContextFraction -v`
Expected: FAIL — `undefined: domain.SessionContext`.

- [x] **Step 3: Add the types**

```go
// SessionContext is how full one agent's context window is right now. Window is
// 0 when the provider does not state one -- Claude Code reports no window
// anywhere Operator can read -- and callers must render a bare token count in
// that case rather than treating 0 as an empty window.
type SessionContext struct {
	Harness    string
	ModelID    string
	Used       int64
	Window     int64
	ObservedAt time.Time
}

// Fraction reports how full the window is, and whether that question has an
// answer at all.
func (c SessionContext) Fraction() (float64, bool) {
	if c.Window <= 0 || c.Used < 0 {
		return 0, false
	}
	if c.Used >= c.Window {
		return 1, true
	}
	return float64(c.Used) / float64(c.Window), true
}

// UsageRollupBucket is one day or one week of consumption.
type UsageRollupBucket struct {
	Start  time.Time
	Totals UsageMetricTotals
}
```

Add `OccurredAt time.Time` to the existing `ModelUsageEvent` struct.

- [x] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/domain/ -run TestSessionContextFraction -v`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add backend/internal/domain/usage.go backend/internal/domain/usage_test.go
git commit -m "feat(usage): add session context and rollup bucket types"
```

---

## Task 3: Parser captures event time and Claude context

**Files:**
- Modify: `backend/internal/observe/usage/parser.go`
- Test: `backend/internal/observe/usage/parser_test.go`

**Interfaces:**
- Consumes: `domain.ModelUsageEvent.OccurredAt` (Task 2).
- Produces: every event parsed from a Claude transcript carries `OccurredAt`; `parseResult` gains `Context *domain.SessionContext`, set only for `claude_main`.

Per F2 the occupancy value is already computed as `input`. This task only records it and the timestamp.

- [x] **Step 1: Write the failing test**

```go
func TestParseClaudeRecordsTimestampAndContext(t *testing.T) {
	record := `{"type":"assistant","uuid":"u1","timestamp":"2026-09-05T12:19:12.745Z",` +
		`"message":{"id":"m1","model":"claude-sonnet-5","stop_reason":"end_turn",` +
		`"usage":{"input_tokens":2,"cache_creation_input_tokens":21113,` +
		`"cache_read_input_tokens":34972,"output_tokens":4}}}`

	result := parseClaudeForTest(t, domain.UsageSourceClaudeMain, record)

	if len(result.Events) != 1 {
		t.Fatalf("events = %d, want 1", len(result.Events))
	}
	got := result.Events[0]
	if got.Tokens.InputTokens != 56087 {
		t.Fatalf("input = %d, want 56087 (2 + 21113 + 34972)", got.Tokens.InputTokens)
	}
	want := time.Date(2026, 9, 5, 12, 19, 12, 745000000, time.UTC)
	if !got.OccurredAt.Equal(want) {
		t.Fatalf("occurredAt = %v, want %v", got.OccurredAt, want)
	}
	if result.Context == nil {
		t.Fatal("context = nil, want the main source to report occupancy")
	}
	if result.Context.Used != 56087 {
		t.Fatalf("context used = %d, want 56087", result.Context.Used)
	}
	if result.Context.Window != 0 {
		t.Fatalf("context window = %d, want 0 -- Claude reports no window", result.Context.Window)
	}
}

func TestParseClaudeSubagentDoesNotReportContext(t *testing.T) {
	record := `{"type":"assistant","uuid":"u1","timestamp":"2026-09-05T12:19:12.745Z",` +
		`"message":{"id":"m1","model":"claude-sonnet-5","stop_reason":"end_turn",` +
		`"usage":{"input_tokens":10,"cache_creation_input_tokens":0,` +
		`"cache_read_input_tokens":0,"output_tokens":1}}}`

	result := parseClaudeForTest(t, domain.UsageSourceClaudeSubagent, record)

	if result.Context != nil {
		t.Fatal("a subagent has its own window; it must not overwrite the session's context")
	}
}
```

Write `parseClaudeForTest` as a helper in the test file mirroring how the existing tests in `parser_test.go` invoke `parseClaude` — read that file first and match its construction of `domain.UsageSourceContext` and `claudeParserStateV1` rather than inventing a new shape.

- [x] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/observe/usage/ -run TestParseClaude -v`
Expected: FAIL — `result.Context` undefined, and `OccurredAt` zero.

- [x] **Step 3: Implement**

Add to the `claudeTranscriptRecord` struct: `Timestamp string \`json:"timestamp"\``.

Add to `parseResult`: `Context *domain.SessionContext`.

Inside `parseClaude`, after `event` is built and appended:

```go
		if parsed, err := time.Parse(time.RFC3339Nano, native.Timestamp); err == nil {
			event.OccurredAt = parsed.UTC()
		}
```
(assign before the append; if the existing code appends a composite literal, hoist it to a variable first)

and after the loop, still inside `parseClaude`:

```go
	// Only the main transcript describes the session's own context. Subagents
	// share the binding but run their own windows (F7), so letting one report
	// here would overwrite the number the user is watching with an unrelated one.
	if source.Source.Kind == domain.UsageSourceClaudeMain && len(result.Events) > 0 {
		newest := result.Events[len(result.Events)-1]
		result.Context = &domain.SessionContext{
			Harness:    string(domain.HarnessClaudeCode),
			ModelID:    newest.ModelID,
			Used:       newest.Tokens.InputTokens,
			Window:     0,
			ObservedAt: newest.OccurredAt,
		}
	}
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/observe/usage/ -run TestParseClaude -v`
Expected: PASS.

- [x] **Step 5: Run the whole usage package to check nothing regressed**

Run: `cd backend && go test ./internal/observe/usage/`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add backend/internal/observe/usage/parser.go backend/internal/observe/usage/parser_test.go
git commit -m "feat(usage): record event time and Claude context occupancy"
```

---

## Task 4: Parser captures Codex context and window

**Files:**
- Modify: `backend/internal/observe/usage/parser.go`
- Test: `backend/internal/observe/usage/parser_test.go`

**Interfaces:**
- Consumes: `parseResult.Context` (Task 3).
- Produces: `parseCodexEvent` sets `result.Context` with both `Used` (the absolute `total_token_usage` total) and `Window` (`model_context_window`), and stamps `OccurredAt` from the rollout envelope.

Per F3 the stored `input_tokens` is a delta, so occupancy must come from the absolute total. Per F4 the window is already parsed and discarded.

- [x] **Step 1: Write the failing test**

```go
func TestParseCodexReportsAbsoluteContextAndWindow(t *testing.T) {
	// Two token_count events. The stored events are deltas, but the context is
	// the second event's absolute total -- not the sum of the deltas.
	first := codexTokenCountLine(t, "2026-09-05T12:00:00Z", 10_000, 200_000)
	second := codexTokenCountLine(t, "2026-09-05T12:05:00Z", 25_000, 200_000)

	result := parseCodexForTest(t, first, second)

	if result.Context == nil {
		t.Fatal("context = nil, want Codex to report occupancy")
	}
	if result.Context.Used != 25_000 {
		t.Fatalf("used = %d, want 25000 (the absolute total, not a delta sum)", result.Context.Used)
	}
	if result.Context.Window != 200_000 {
		t.Fatalf("window = %d, want 200000", result.Context.Window)
	}
	frac, ok := result.Context.Fraction()
	if !ok || frac != 0.125 {
		t.Fatalf("fraction = %v ok=%v, want 0.125 true", frac, ok)
	}
}
```

Write `codexTokenCountLine` and `parseCodexForTest` in the test file by reading the existing Codex tests in `parser_test.go` and matching their envelope construction. The helper must emit a `token_count` payload shaped as `{"type":"token_count","info":{"total_token_usage":{...},"model_context_window":N}}`, with `total_token_usage` populated the way `codexTokenVector` expects.

- [x] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/observe/usage/ -run TestParseCodex -v`
Expected: FAIL — `result.Context` is nil.

- [x] **Step 3: Implement**

In `parseCodexEvent`, after the existing delta computation and event append, and *outside* the `isCodexContextFill` early return:

```go
	// The window was already being parsed purely to detect a context reset (F4).
	// Persisting it is what lets the client show a percentage rather than a bare
	// number. Used is the absolute total, because the stored events are deltas.
	result.Context = &domain.SessionContext{
		Harness:    string(domain.HarnessCodex),
		ModelID:    model,
		Used:       total.TotalTokens,
		Window:     payload.Info.ModelContextWindow,
		ObservedAt: envelopeTimestamp(envelope),
	}
```

Place this immediately before `parseCodexEvent` returns on the success path, using whatever local holds the model id in that function. Add `envelopeTimestamp` as a small helper that parses the rollout envelope's timestamp field with `time.RFC3339Nano` and returns the zero time on failure — read `codexEnvelope` to find the field name before writing it.

Note: a context-fill event (`isCodexContextFill`) resets the baseline and returns early. Leave that path alone — it emits no usage event, and reporting a context reading from it would show the window as momentarily full.

- [x] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/observe/usage/ -run TestParseCodex -v`
Expected: PASS.

- [x] **Step 5: Run the whole package**

Run: `cd backend && go test ./internal/observe/usage/`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add backend/internal/observe/usage/parser.go backend/internal/observe/usage/parser_test.go
git commit -m "feat(usage): persist the Codex context window instead of discarding it"
```

---

## Task 5: Persist the new fields

**Files:**
- Modify: `backend/internal/storage/sqlite/queries/*.sql` (the file holding `InsertModelUsageEvent` — locate with `grep -rn "model_usage_events" internal/storage/sqlite/queries/`)
- Create: `backend/internal/storage/sqlite/queries/usage_rollup.sql`
- Modify: `backend/internal/storage/sqlite/store/usage_store.go`
- Test: `backend/internal/storage/sqlite/store/usage_store_test.go`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces on the store:
  - `SaveSessionContext(ctx, bindingID int64, c domain.SessionContext) error`
  - `GetSessionContext(ctx, sessionID domain.SessionID) (domain.SessionContext, bool, error)`
  - `UsageRollup(ctx, from, to time.Time, bucket string) ([]domain.UsageRollupBucket, error)` where `bucket` is `"day"` or `"week"`

- [x] **Step 1: Write the new queries**

Add `occurred_at` to the existing insert's column list and parameters. Then create `usage_rollup.sql`:

```sql
-- name: SaveSessionContext :exec
UPDATE usage_bindings
SET context_used = ?, context_window = ?, context_at = ?
WHERE id = ?;

-- name: GetSessionContext :one
-- Newest observation wins: a session with both a Claude and a Codex binding
-- (an agent switch) should report the one currently running.
SELECT harness, context_used, context_window, context_at, initial_model_id
FROM usage_bindings
WHERE session_id = ? AND context_at IS NOT NULL
ORDER BY context_at DESC
LIMIT 1;

-- name: UsageRollupByDay :many
-- occurred_at IS NULL rows predate migration 0098 and have no knowable time;
-- bucketing them into any day would be a fabrication, so they are excluded.
SELECT date(occurred_at) AS bucket_start,
       COALESCE(SUM(input_tokens), 0)          AS input_tokens,
       COALESCE(SUM(uncached_input_tokens), 0) AS uncached_input_tokens,
       COALESCE(SUM(cache_read_tokens), 0)     AS cache_read_tokens,
       COALESCE(SUM(cache_write_tokens), 0)    AS cache_write_tokens,
       COALESCE(SUM(output_tokens), 0)         AS output_tokens
FROM model_usage_events
WHERE occurred_at IS NOT NULL AND occurred_at >= ? AND occurred_at < ?
GROUP BY bucket_start
ORDER BY bucket_start;

-- name: UsageRollupByWeek :many
SELECT date(occurred_at, 'weekday 1', '-7 days') AS bucket_start,
       COALESCE(SUM(input_tokens), 0)          AS input_tokens,
       COALESCE(SUM(uncached_input_tokens), 0) AS uncached_input_tokens,
       COALESCE(SUM(cache_read_tokens), 0)     AS cache_read_tokens,
       COALESCE(SUM(cache_write_tokens), 0)    AS cache_write_tokens,
       COALESCE(SUM(output_tokens), 0)         AS output_tokens
FROM model_usage_events
WHERE occurred_at IS NOT NULL AND occurred_at >= ? AND occurred_at < ?
GROUP BY bucket_start
ORDER BY bucket_start;
```

`date(occurred_at, 'weekday 1', '-7 days')` yields the Monday on or before each event. Verify this in Step 3 rather than trusting it.

- [x] **Step 2: Regenerate sqlc and write the failing store test**

Run: `cd backend && go generate ./internal/storage/sqlite/...` (or the repo's sqlc command — check `AGENTS.md`).

```go
func TestUsageRollupBucketsByDayAndExcludesUndatedRows(t *testing.T) {
	store := sqlitetest.MustOpen(t)
	ctx := context.Background()
	binding := seedUsageBinding(t, store, "scratch-1", domain.HarnessClaudeCode)

	mustInsertUsageEvent(t, store, binding, 100, parseTime(t, "2026-09-01T10:00:00Z"))
	mustInsertUsageEvent(t, store, binding, 250, parseTime(t, "2026-09-01T23:59:00Z"))
	mustInsertUsageEvent(t, store, binding, 40, parseTime(t, "2026-09-02T00:01:00Z"))
	mustInsertUsageEventUndated(t, store, binding, 9999)

	got, err := store.UsageRollup(ctx,
		parseTime(t, "2026-09-01T00:00:00Z"),
		parseTime(t, "2026-09-03T00:00:00Z"), "day")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("buckets = %d, want 2", len(got))
	}
	if got[0].Totals.InputTokens != 350 {
		t.Fatalf("day one = %d, want 350", got[0].Totals.InputTokens)
	}
	if got[1].Totals.InputTokens != 40 {
		t.Fatalf("day two = %d, want 40", got[1].Totals.InputTokens)
	}
	// The undated row must appear in no bucket at all.
	var total int64
	for _, b := range got {
		total += b.Totals.InputTokens
	}
	if total != 390 {
		t.Fatalf("total = %d, want 390 -- an undated row leaked into a bucket", total)
	}
}

func TestSessionContextRoundTrips(t *testing.T) {
	store := sqlitetest.MustOpen(t)
	ctx := context.Background()
	binding := seedUsageBinding(t, store, "scratch-1", domain.HarnessCodex)

	want := domain.SessionContext{
		Harness: "codex", ModelID: "gpt-5.6-luna",
		Used: 25_000, Window: 200_000,
		ObservedAt: parseTime(t, "2026-09-05T12:05:00Z"),
	}
	if err := store.SaveSessionContext(ctx, binding, want); err != nil {
		t.Fatal(err)
	}
	got, ok, err := store.GetSessionContext(ctx, "scratch-1")
	if err != nil || !ok {
		t.Fatalf("get = %v %v", ok, err)
	}
	if got.Used != want.Used || got.Window != want.Window {
		t.Fatalf("got %d/%d, want %d/%d", got.Used, got.Window, want.Used, want.Window)
	}
}
```

Write `seedUsageBinding`, `mustInsertUsageEvent`, `mustInsertUsageEventUndated` and `parseTime` as helpers in this test file, following how existing tests in `usage_store_test.go` seed rows.

- [x] **Step 3: Run to verify failure, then implement the store methods**

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run "TestUsageRollup|TestSessionContext" -v`
Expected: FAIL — methods undefined.

Implement `SaveSessionContext`, `GetSessionContext` and `UsageRollup` on `*Store`, following the write-lock convention used by neighbouring write methods (`s.writeMu.Lock()` for writes; the reader queries `s.qr` for reads). `UsageRollup` switches on `bucket` and returns an error for any value other than `"day"` or `"week"`.

- [x] **Step 4: Run to verify it passes**

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run "TestUsageRollup|TestSessionContext" -v`
Expected: PASS. If the week test disagrees with the SQL, fix the SQL — do not adjust the expectation to match a wrong Monday.

- [x] **Step 5: Wire the collector to save context**

In `backend/internal/service/usage/collector.go`, wherever the collector persists a `parseResult`'s events, add: if `result.Context != nil`, call `SaveSessionContext` for that binding. Find the existing persist call with `grep -n "Events" internal/service/usage/collector.go`.

- [x] **Step 6: Run the usage service tests**

Run: `cd backend && go test ./internal/service/usage/ ./internal/storage/sqlite/...`
Expected: PASS.

- [x] **Step 7: Commit**

```bash
git add backend/internal/storage/sqlite backend/internal/service/usage
git commit -m "feat(usage): persist context snapshots and add time-bucketed rollups"
```

---

## Task 6: Service layer

**Files:**
- Modify: `backend/internal/service/usage/summary.go`
- Test: `backend/internal/service/usage/summary_test.go`

**Interfaces:**
- Consumes: store methods from Task 5.
- Produces:
  - `domain.SessionUsageSummary` gains `Context *domain.SessionContext`
  - `func (r *SummaryReader) Rollup(ctx context.Context, from, to time.Time, bucket string) ([]domain.UsageRollupBucket, error)`

- [x] **Step 1: Write the failing test**

```go
func TestGetIncludesContextWhenObserved(t *testing.T) {
	reader := usage.NewSummaryReader(&fakeUsageStore{
		context: domain.SessionContext{Harness: "claude-code", Used: 64880, Window: 0},
		hasContext: true,
	})
	got, err := reader.Get(context.Background(), "scratch-1")
	if err != nil {
		t.Fatal(err)
	}
	if got.Context == nil {
		t.Fatal("context = nil, want the observed context")
	}
	if got.Context.Used != 64880 {
		t.Fatalf("used = %d, want 64880", got.Context.Used)
	}
}

func TestGetOmitsContextWhenNeverObserved(t *testing.T) {
	reader := usage.NewSummaryReader(&fakeUsageStore{hasContext: false})
	got, err := reader.Get(context.Background(), "scratch-1")
	if err != nil {
		t.Fatal(err)
	}
	if got.Context != nil {
		t.Fatal("context must stay nil so the client renders nothing rather than zero")
	}
}

func TestRollupRejectsUnknownBucket(t *testing.T) {
	reader := usage.NewSummaryReader(&fakeUsageStore{})
	if _, err := reader.Rollup(context.Background(), time.Now().Add(-time.Hour), time.Now(), "fortnight"); err == nil {
		t.Fatal("want an error for an unsupported bucket")
	}
}
```

Extend the existing `fakeUsageStore` in `summary_test.go` with `context`/`hasContext` fields and the two new methods.

- [x] **Step 2: Run to verify failure**

Run: `cd backend && go test ./internal/service/usage/ -run "TestGet|TestRollup" -v`
Expected: FAIL.

- [x] **Step 3: Implement**

Extend `usageSummaryStore` with `GetSessionContext` and `UsageRollup`, populate `Context` in `Get`, and add `Rollup` that validates the bucket and delegates.

- [x] **Step 4: Run to verify it passes**

Run: `cd backend && go test ./internal/service/usage/ -v`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add backend/internal/service/usage backend/internal/domain
git commit -m "feat(usage): expose session context and rollups from the summary reader"
```

---

## Task 7: HTTP endpoints and OpenAPI

**Files:**
- Modify: `backend/internal/httpd/controllers/usage.go`
- Modify: `backend/internal/httpd/apispec/specgen/build.go` (register new named types)
- Test: `backend/internal/httpd/controllers/usage_test.go`

**Interfaces:**
- Consumes: `SummaryReader.Rollup`, `SessionUsageSummary.Context`.
- Produces:
  - `GET /api/v1/usage/sessions/{sessionId}` response gains optional `context: {harness, modelId, used, window, observedAt}`. `window` is `0` when unknown; the client must branch on that.
  - `GET /api/v1/usage/rollup?bucket=day|week&days=N` → `{"bucket":"day","buckets":[{"start":"2026-09-01","totals":{...}}]}`. `days` defaults to 14, max 90. Invalid `bucket` → `400 INVALID_BUCKET`; invalid `days` → `400 INVALID_RANGE`.

- [x] **Step 1: Write the failing test**

```go
func TestGetSessionUsageIncludesContext(t *testing.T) {
	rec := doRequest(t, newUsageController(&fakeSummary{
		summary: domain.SessionUsageSummary{
			SessionID: "scratch-1",
			Context: &domain.SessionContext{
				Harness: "claude-code", ModelID: "claude-sonnet-5",
				Used: 64880, Window: 0,
			},
		},
	}), http.MethodGet, "/usage/sessions/scratch-1", nil)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var body SessionUsageResponse
	mustDecode(t, rec, &body)
	if body.Context == nil || body.Context.Used != 64880 {
		t.Fatalf("context = %+v, want used 64880", body.Context)
	}
	if body.Context.Window != 0 {
		t.Fatalf("window = %d, want 0 for Claude", body.Context.Window)
	}
}

func TestRollupRejectsBadBucket(t *testing.T) {
	rec := doRequest(t, newUsageController(&fakeSummary{}), http.MethodGet, "/usage/rollup?bucket=fortnight", nil)
	assertErrorCode(t, rec, http.StatusBadRequest, "INVALID_BUCKET")
}

func TestRollupRejectsTooLongRange(t *testing.T) {
	rec := doRequest(t, newUsageController(&fakeSummary{}), http.MethodGet, "/usage/rollup?bucket=day&days=500", nil)
	assertErrorCode(t, rec, http.StatusBadRequest, "INVALID_RANGE")
}
```

`doRequest`, `assertErrorCode` and `mustDecode` already exist in this package's test helpers — read `usage_test.go` and reuse them rather than writing new ones.

- [x] **Step 2: Run to verify failure**

Run: `cd backend && go test ./internal/httpd/controllers/ -run "TestGetSessionUsage|TestRollup" -v`
Expected: FAIL.

- [x] **Step 3: Implement the handler and DTOs**

Register `r.Get("/usage/rollup", c.rollup)` alongside the existing two routes. Add `SessionContextResponse` and `UsageRollupResponse` DTOs in the same file as the existing usage DTOs, and register any new named types in `specgen/build.go` per `AGENTS.md:117`.

- [x] **Step 4: Run to verify it passes**

Run: `cd backend && go test ./internal/httpd/... -v 2>&1 | tail -20`
Expected: PASS, including the spec-drift and route-parity tests.

- [x] **Step 5: Regenerate the API artifacts**

```bash
cd /Users/omaraly/development/AI/Operator && npm run api
cd backend && go test ./internal/httpd/...
```
Expected: PASS. Commit `openapi.yaml` and `frontend/src/api/schema.ts` together with the Go changes (`AGENTS.md:138`).

- [x] **Step 6: Full backend gate**

```bash
cd backend && gofmt -l internal/ && go vet ./... && go test ./... && golangci-lint run ./...
```
Expected: no gofmt output, no vet output, all tests pass, `0 issues`.

- [x] **Step 7: Commit**

```bash
git add backend frontend/src/api/schema.ts
git commit -m "feat(usage): serve session context and day/week rollups over HTTP"
```

---

## Task 8: Mobile endpoints and models

**Files:**
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Create: `packages/mobile/lib/feature/usage/data/model/session_context_model.dart`
- Create: `packages/mobile/lib/feature/usage/data/model/usage_rollup_model.dart`
- Create: `packages/mobile/lib/feature/usage/data/model/params/usage_rollup_params.dart`
- Test: `packages/mobile/test/feature/usage/session_context_model_test.dart`

**Interfaces:**
- Consumes: the wire shapes from Task 7.
- Produces: `SessionContextModel{harness, modelId, used, window, observedAt}`, `UsageRollupModel{bucket, buckets}`, `UsageBucketModel{start, inputTokens, outputTokens, ...}`, `UsageRollupParams{bucket, days}`, and `EndPoints.usageSession(String sessionId)` / `EndPoints.usageRollup`.

- [x] **Step 1: Write the failing test**

```dart
void main() {
  group('SessionContextModel', () {
    test('parses a Codex context with a known window', () {
      final model = SessionContextModel.fromJson(const {
        'harness': 'codex',
        'modelId': 'gpt-5.6-luna',
        'used': 25000,
        'window': 200000,
        'observedAt': '2026-09-05T12:05:00Z',
      });
      expect(model.used, 25000);
      expect(model.window, 200000);
      expect(model.fraction, closeTo(0.125, 0.0001));
      expect(model.hasWindow, isTrue);
    });

    test('treats a zero window as unknown, not as an empty context', () {
      final model = SessionContextModel.fromJson(const {
        'harness': 'claude-code',
        'used': 64880,
        'window': 0,
      });
      expect(model.hasWindow, isFalse);
      expect(model.fraction, isNull);
    });

    test('tolerates missing fields', () {
      final model = SessionContextModel.fromJson(const {});
      expect(model.used, isNull);
      expect(model.hasWindow, isFalse);
      expect(model.fraction, isNull);
    });
  });
}
```

- [x] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/usage/session_context_model_test.dart`
Expected: FAIL — file not found / undefined class.

- [x] **Step 3: Implement the model**

```dart
class SessionContextModel extends Equatable {
  final String? harness;
  final String? modelId;
  final int? used;
  final int? window;
  final DateTime? observedAt;

  const SessionContextModel({this.harness, this.modelId, this.used, this.window, this.observedAt});

  factory SessionContextModel.fromJson(Map<String, dynamic> json) => SessionContextModel(
        harness: json['harness'] as String?,
        modelId: json['modelId'] as String?,
        used: (json['used'] as num?)?.toInt(),
        window: (json['window'] as num?)?.toInt(),
        observedAt: json['observedAt'] == null ? null : DateTime.tryParse(json['observedAt'] as String),
      );

  // The daemon sends 0 when the provider states no window. Claude Code states
  // none, so this is the common case, and rendering it as "0% full" would say
  // the opposite of the truth.
  bool get hasWindow => (window ?? 0) > 0;

  double? get fraction {
    if (!hasWindow) return null;
    final u = used ?? 0;
    if (u >= window!) return 1;
    return u / window!;
  }

  @override
  List<Object?> get props => [harness, modelId, used, window, observedAt];
}
```

Write `UsageRollupModel`/`UsageBucketModel` in the same hand-written style, and `UsageRollupParams` with a `toJson()` returning `{'bucket': bucket, 'days': days}`. Add to `EndPoints`:

```dart
  static String usageSession(String sessionId) =>
      '/api/v1/usage/sessions/${Uri.encodeComponent(sessionId)}';
  static const String usageRollup = '/api/v1/usage/rollup';
```

- [x] **Step 4: Run to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/usage/`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/usage packages/mobile/lib/core packages/mobile/test/feature/usage
git commit -m "feat(mobile): add usage context and rollup models"
```

---

## Task 9: Mobile data source and repository

**Files:**
- Create: `packages/mobile/lib/feature/usage/data/data_source/usage_remote_data_source.dart`
- Create: `packages/mobile/lib/feature/usage/data/repository/usage_repository.dart`
- Test: `packages/mobile/test/feature/usage/usage_repository_test.dart`

**Interfaces:**
- Consumes: Task 8's models and endpoints.
- Produces: `UsageRepository.sessionContext(String sessionId) → Future<SessionContextModel?>` and `UsageRepository.rollup(UsageRollupParams) → Future<UsageRollupModel>`.

- [x] **Step 1: Write the failing test**

```dart
void main() {
  test('returns null context when the daemon omits it', () async {
    final repo = UsageRepository(FakeUsageRemoteDataSource(sessionJson: const {'sessionId': 'scratch-1'}));
    expect(await repo.sessionContext('scratch-1'), isNull);
  });

  test('parses the context when present', () async {
    final repo = UsageRepository(FakeUsageRemoteDataSource(sessionJson: const {
      'sessionId': 'scratch-1',
      'context': {'harness': 'claude-code', 'used': 64880, 'window': 0},
    }));
    final ctx = await repo.sessionContext('scratch-1');
    expect(ctx!.used, 64880);
    expect(ctx.hasWindow, isFalse);
  });
}
```

Write `FakeUsageRemoteDataSource` in the test file. Follow the existing repository tests under `packages/mobile/test/feature/` for the fake style used in this codebase.

- [x] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/usage/usage_repository_test.dart`
Expected: FAIL.

- [x] **Step 3: Implement**

The data source uses the injected `ApiConsumer` and parses with `GlobalResponse.fromJson(response.data, withDataKey: false)`, matching `sessions_remote_data_source.dart`. Read that file first and mirror its error handling.

- [x] **Step 4: Run to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/usage/`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/usage packages/mobile/test/feature/usage
git commit -m "feat(mobile): add usage data source and repository"
```

---

## Task 10: Context readout formatting

**Files:**
- Create: `packages/mobile/lib/feature/usage/logic/context_readout.dart`
- Test: `packages/mobile/test/feature/usage/context_readout_test.dart`

**Interfaces:**
- Consumes: `SessionContextModel`.
- Produces: `sealed class ContextReadout` with `static ContextReadoutData? of(SessionContextModel? context)`, returning `null` when there is nothing to show; `ContextReadoutData{label, percentLabel, fraction, severity}` where `severity` is `ContextSeverity.normal | warn | critical`.

Thresholds match the desktop's retired `ContextMeter`: warn at 0.7, critical at 0.9. Keeping them identical means both clients read the same way.

- [x] **Step 1: Write the failing test**

```dart
void main() {
  test('shows a bare token count when the window is unknown', () {
    final r = ContextReadout.of(const SessionContextModel(used: 64880, window: 0))!;
    expect(r.label, '64.9k tokens');
    expect(r.percentLabel, isNull);
    expect(r.fraction, isNull);
    expect(r.severity, ContextSeverity.normal);
  });

  test('shows a percentage when the window is known', () {
    final r = ContextReadout.of(const SessionContextModel(used: 25000, window: 200000))!;
    expect(r.percentLabel, '13%');
    expect(r.fraction, closeTo(0.125, 0.0001));
    expect(r.severity, ContextSeverity.normal);
  });

  test('escalates at the desktop thresholds', () {
    expect(ContextReadout.of(const SessionContextModel(used: 70, window: 100))!.severity, ContextSeverity.warn);
    expect(ContextReadout.of(const SessionContextModel(used: 90, window: 100))!.severity, ContextSeverity.critical);
    expect(ContextReadout.of(const SessionContextModel(used: 69, window: 100))!.severity, ContextSeverity.normal);
  });

  test('renders nothing when there is no observation', () {
    expect(ContextReadout.of(null), isNull);
    expect(ContextReadout.of(const SessionContextModel()), isNull);
  });
}
```

- [x] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/usage/context_readout_test.dart`
Expected: FAIL.

- [x] **Step 3: Implement**

`used` formats as `<1000` verbatim, otherwise one decimal place with a `k` suffix (`64880 → '64.9k tokens'`). Percentage rounds to the nearest whole number.

- [x] **Step 4: Run to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/usage/`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/usage/logic packages/mobile/test/feature/usage
git commit -m "feat(mobile): add context readout formatting"
```

---

## Task 11: Context chip in the blocks screen

**Files:**
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/context_readout_chip.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart` and `session_command_state.dart`
- Test: `packages/mobile/test/feature/blocks/context_readout_chip_test.dart`

**Interfaces:**
- Consumes: `ContextReadout`, `UsageRepository`.
- Produces: `ContextReadoutChip({required ContextReadoutData? readout})`.

**Placement decision:** the chip goes on the sticky block header, **not** the command row. The command row already carries `/stop`, `/compact` and `/model`; on a phone a fourth item there competes for tap targets with three destructive-ish actions.

The cubit refreshes context on the same tick that already refreshes command state — do not add a second poll loop. Follow the existing `onActivity` pattern in `session_command_cubit.dart`.

- [x] **Step 1: Write the failing widget test**

```dart
void main() {
  testWidgets('renders a bare token count with no bar when the window is unknown', (tester) async {
    await tester.pumpWidget(_wrap(ContextReadoutChip(
      readout: ContextReadout.of(const SessionContextModel(used: 64880, window: 0)),
    )));
    expect(find.text('64.9k tokens'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('renders a percentage and a bar when the window is known', (tester) async {
    await tester.pumpWidget(_wrap(ContextReadoutChip(
      readout: ContextReadout.of(const SessionContextModel(used: 25000, window: 200000)),
    )));
    expect(find.text('13%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('renders nothing at all when there is no observation', (tester) async {
    await tester.pumpWidget(_wrap(const ContextReadoutChip(readout: null)));
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.textContaining('tokens'), findsNothing);
  });
}
```

Write `_wrap` to provide `SkinScope` — copy it from an existing widget test under `packages/mobile/test/feature/blocks/`.

- [x] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/blocks/context_readout_chip_test.dart`
Expected: FAIL.

- [x] **Step 3: Implement the chip and wire it in**

Use `context.skin` for colours and `AppTextStyle.style11Regular` (or the neighbouring header's size) for type. Raw ints for padding. Return `const SizedBox.shrink()` when `readout == null`.

- [x] **Step 4: Run to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/blocks/`
Expected: PASS.

- [x] **Step 5: Gate**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!`, then all tests pass.

- [x] **Step 6: Commit**

```bash
git add packages/mobile
git commit -m "feat(mobile): show context occupancy on the blocks screen"
```

---

## Task 12: Daily and weekly usage screen

**Files:**
- Create: `packages/mobile/lib/feature/usage/presentation/usage_screen/logic/usage_cubit.dart`
- Create: `packages/mobile/lib/feature/usage/presentation/usage_screen/logic/usage_state.dart`
- Create: `packages/mobile/lib/feature/usage/presentation/usage_screen/ui/usage_screen.dart`
- Test: `packages/mobile/test/feature/usage/usage_cubit_test.dart`

**Interfaces:**
- Consumes: `UsageRepository.rollup`.
- Produces: `UsageCubit{load(String bucket)}`, `UsageState{status, bucket, buckets, error}`, and route `RoutesStrings.usage`.

**Copy constraint from F8:** this screen shows *consumption*, never *quota*. Title it "Token usage". Do not use the words "limit", "quota", or "remaining" anywhere on it, and do not render a percentage-of-plan — Operator has no source for one, and a number that looks like a quota would be read as one.

- [x] **Step 1: Write the failing cubit test**

```dart
void main() {
  test('emits loaded buckets for the requested grain', () async {
    final cubit = UsageCubit(FakeUsageRepository(rollup: UsageRollupModel(
      bucket: 'day',
      buckets: [UsageBucketModel(start: DateTime.utc(2026, 9, 1), inputTokens: 350, outputTokens: 20)],
    )));
    await cubit.load('day');
    expect(cubit.state.status, UsageStatus.loaded);
    expect(cubit.state.buckets.single.inputTokens, 350);
    expect(cubit.state.bucket, 'day');
  });

  test('surfaces the error code rather than a generic failure', () async {
    final cubit = UsageCubit(FakeUsageRepository(error: 'INVALID_RANGE'));
    await cubit.load('day');
    expect(cubit.state.status, UsageStatus.error);
    expect(cubit.state.error, 'INVALID_RANGE');
  });
}
```

- [x] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/usage/usage_cubit_test.dart`
Expected: FAIL.

- [x] **Step 3: Implement the cubit, state and screen**

Cubit only, `Equatable` state, no `Bloc` events. The screen has a day/week segmented control and a list of buckets. Navigation uses `Navigator.of(context)` with a new `RoutesStrings.usage` constant.

- [x] **Step 4: Run to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/usage/`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add packages/mobile
git commit -m "feat(mobile): add the daily and weekly token usage screen"
```

---

## Task 13: Settings entry point and final gate

**Files:**
- Modify: the settings screen — locate with `grep -rn "RoutesStrings" packages/mobile/lib/feature/settings/ | head`
- Modify: `packages/mobile/lib/core/routing/` route table (locate with `grep -rn "RoutesStrings.settings" packages/mobile/lib | head`)
- Test: `packages/mobile/test/feature/settings/` — add a case to the existing settings test

**Interfaces:**
- Consumes: `RoutesStrings.usage`, `UsageScreen`.
- Produces: nothing downstream.

- [x] **Step 1: Write the failing test**

```dart
testWidgets('settings offers a token usage row', (tester) async {
  await tester.pumpWidget(_wrapSettings());
  expect(find.text('Token usage'), findsOneWidget);
});
```

- [x] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/settings/`
Expected: FAIL.

- [x] **Step 3: Add the row and register the route**

- [x] **Step 4: Run the full mobile gate**

```bash
cd packages/mobile && flutter analyze && flutter test
```
Expected: `No issues found!` then all tests pass.

- [x] **Step 5: Run the full backend gate one final time**

```bash
cd backend && gofmt -l internal/ && go vet ./... && go test ./... && golangci-lint run ./...
```
Expected: clean, all pass, `0 issues`. If golangci reports paths under `.worktrees/`, run `golangci-lint cache clean` first.

- [x] **Step 6: Commit**

```bash
git add packages/mobile
git commit -m "feat(mobile): link the token usage screen from settings"
```

---

## Task 14: Live verification against a real daemon

**Files:** none — this is a verification task with no deliverable code.

This exists because every prior task's tests use fixtures, and the entire feature is a claim about what real providers write into real files. A green suite does not establish that the parser reads an actual transcript correctly.

- [x] **Step 1: Restart the daemon so it runs this branch**

The daemon is owned by the desktop app. Restart it from the app rather than from a shell — a daemon launched from an agent shell inherits that shell's environment, and a `claude` process started with `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID` or `ANTHROPIC_BASE_URL` set will exit immediately. If you must launch it by hand, unset every `CLAUDE_*` and `ANTHROPIC_*` variable and set `TERM` and `LANG`.

- [x] **Step 2: Spawn a session and take several turns**

```bash
curl -s -X POST http://127.0.0.1:3002/api/v1/sessions \
  -H 'Content-Type: application/json' \
  -d '{"projectId":"scratch","prompt":"say ok","harness":"claude-code","kind":"worker"}'
```
Then send two or three more messages so cumulative and occupancy diverge.

- [x] **Step 3: Confirm context is occupancy, not the cumulative total**

```bash
curl -s http://127.0.0.1:3002/api/v1/usage/sessions/<id> | python3 -m json.tool
```
Expected: `context.used` is close to the newest turn's input total and **much smaller** than `totals.inputTokens`. If they are equal on a multi-turn session, the parser is reporting the sum — that is the F1 bug, and the task is not done.

- [x] **Step 4: Confirm the rollup buckets**

```bash
curl -s 'http://127.0.0.1:3002/api/v1/usage/rollup?bucket=day&days=7' | python3 -m json.tool
curl -s 'http://127.0.0.1:3002/api/v1/usage/rollup?bucket=week&days=28' | python3 -m json.tool
```
Expected: today's bucket is non-zero. Events written before migration 0098 are absent, which is correct.

- [x] **Step 5: Confirm a Codex session reports a window**

Spawn with `"harness":"codex"`, take a turn, then check that `context.window` is non-zero and `context.used` is below it. This is the only path that produces a percentage.

- [ ] **Step 6: Check it on the phone**

Open the session on the paired device. Claude sessions show a token count with no bar; Codex sessions show a percentage and a bar. Settings → Token usage lists today.

- [x] **Step 7: Record the results**

Write what each step actually returned into `docs/superpowers/plans/2026-09-05-mobile-context-and-usage-report.md`, including the numbers. State each gate as pass or fail, not as "was run".

---

## Self-Review

**Spec coverage.** There is no spec; the Findings section is the source. F1 → Tasks 3–6 (occupancy separate from cumulative). F2 → Task 3. F3, F4 → Task 4. F5 → Task 2's `Fraction`, Task 8's `hasWindow`, Task 10's bare-count branch. F6 → Tasks 1, 5. F7 → Task 3's subagent guard, Task 5's newest-binding query. F8 → Task 12's copy constraint; no task builds a quota reading, deliberately.

**Placeholders.** None. Three tasks direct the implementer to read a neighbouring file before writing a test helper (Tasks 3, 4, 9) rather than inventing a fixture shape; that is deliberate, because the existing helper signatures are the contract and guessing them produces tests that compile against nothing.

**Type consistency.** `SessionContext{Harness, ModelID, Used, Window, ObservedAt}` is used identically in Tasks 2–7. `Fraction()` returns `(float64, bool)` in Go; the Dart mirror is `fraction` returning `double?` plus `hasWindow`, which is the same contract in idiomatic Dart. `UsageRollupBucket{Start, Totals}` matches the SQL's `bucket_start` alias through the store mapping. `bucket` is the string `"day"`/`"week"` at every layer.

**Known risk.** Task 5's `date(occurred_at, 'weekday 1', '-7 days')` is asserted, not verified — Step 4 says to fix the SQL if the test disagrees, and not to adjust the expectation.
