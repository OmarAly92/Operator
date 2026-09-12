# Orchestrator Ears (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wake the orchestrator when a worker's turn ends, tell it what happened, and let it acknowledge what it consumed — without any retry/backoff/timer, because that machinery is exactly what #3274 built and #3394 reverted.

**Architecture:** A durable coalescing inbox table (`orchestrator_inbox`) is written in the same transaction as the activity-state flip that creates it. A reducer function in `lifecycle.Manager` resolves the project's live orchestrator and pushes a content-free nudge through `sessionguard.NudgeCoordination`. The orchestrator pulls digests with `opr inbox` (built by re-resolving each pending row against the live session record — rows carry no content) and clears them with `opr inbox ack`. Three re-announcement triggers — a worker crossing to idle, the orchestrator itself reaching idle, and the orchestrator's first post-restore hook signal — plus one daemon-startup sweep replace every retry loop. A new daemon-side mechanism (this plan's required addition) prevents Operator's own coordination text, including this nudge, from ever being stored as a session's `latestUserPrompt`.

**Tech Stack:** Go 1.x, sqlc-generated SQLite queries, goose migrations, chi router, code-first OpenAPI (`npm run api`), Cobra CLI, table-driven Go tests with `httptest` and in-memory SQLite (`sqlitetest`).

**Spec:** `docs/superpowers/specs/2026-09-11-autonomous-orchestrator-design.md` (§5.1 inbox, §5.2 digest, §6 data model, §7 delivery protocol — the core of this plan, §8 wire surface, §9 prompt, §14 Phase 1)

## Global Constraints

- **No code comments.** The user's standing global instruction. Names and tests carry the intent.
- **No retry, backoff, escalation, attempt counter, `next_attempt_at`, or timer of any kind.** The single hardest rule in this design (spec §7, §12). Re-announcing on an existing state transition (worker idle, orchestrator idle, orchestrator restore, daemon start) is not a retry: it is event-driven and stateless, fires on a transition that already happens, carries no attempt counter, sets no timer, and escalates nothing.
- The CLI is a thin client: it calls daemon HTTP through the shared helpers in `internal/cli/client.go` and never opens SQLite, spawns runtimes, or calls adapters directly (`AGENTS.md`).
- CLI DTOs are hand-mirrored from controller DTOs on purpose. Do not import `httpd/controllers` into `internal/cli`.
- After editing `controllers/dto.go`, run `npm run api` and commit `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts` in the same commit as the Go change. CI fails if they drift.
- Any new named DTO type needs a `schemaNames` entry in `backend/internal/httpd/apispec/specgen/build.go` if `npm run api` reports an unnamed-schema error.
- Every migration file needs an entry in `shippedMigrations` in `backend/internal/storage/sqlite/migrate_burned_versions_test.go` in the same change — `TestMigrationVersionLedger` fails otherwise.
- Migration queries go in `backend/internal/storage/sqlite/queries/*.sql`; generated code comes from `npm run sqlc`, never hand-edited.
- Acking an unknown or already-acked id is a no-op, not an error.
- The duplicate-delivery regression test (spec §13) must produce exactly one digest and one acked row from N duplicate nudges, and must not be weakened.
- Usage errors return `usageError` (exit 2); runtime failures exit 1.
- Gate for every task: `npm run lint` from the repo root (`go test ./...` plus golangci-lint v2.12.2) and `cd backend && go test ./internal/httpd/...` for spec drift.
- Do not restart or stop the user's daemon (pid 97452, `~/.operator`). End-to-end checks use an isolated daemon under `OPERATOR_DATA_DIR`/`OPERATOR_RUN_FILE` in a scratch directory, run via `opr daemon` (not `opr start`, which is desktop-launcher-only), seeded with `sqlite3` directly rather than a spawned agent — the exact recipe Phase 0's plan used under "Verification".

## Required addition: coordination-echo suppression

**Verified before writing this plan.** `sessionguard`'s own package doc says every pane-writing path funnels through it, and `Deliver`/`Nudge` write bytes into the pane followed by Enter — indistinguishable from the human typing and pressing Enter (`session_manager/manager.go:395`'s `sendConfirmConfig` doc states this plainly: "opr send returns 200 the moment the runtime accepts keystrokes... UserPromptSubmit" fires from that same paste). The harness's `UserPromptSubmit` hook therefore fires on Operator's own coordination writes exactly as it would on a human's, and `opr hooks` reports whatever text was in the composer as `latest_user_prompt`, which lifecycle stores verbatim as `Metadata.LatestUserPrompt` unless something strips it first.

`isOperatorCoordinationMessage` (`backend/internal/cli/hooks.go:234`) is that "something," but it is a hand-maintained prefix list, and grepping the four producers that actually exist today shows it catches two of four:

| Producer | Text | Filtered today? |
| --- | --- | --- |
| `agent_switching.go:1520` `<opr-handoff-request...>` | handoff request | Yes |
| `agent_switching.go:42` `operatorTargetActivationPrompt` | "Operator transferred the previous agent's context..." | Yes |
| `service/session/delegation.go:176` `taskTitleDelegationMessage` | "Operator TASK TITLE UPDATE..." | Yes (fixed in `f0e5b0678`, this branch's prior commit) |
| `lifecycle/reactions.go:663` `formatCIFailureMessage` | "CI is failing on your PR...." | **No** |
| `lifecycle/reactions.go:72` review-batch message | "[Operator reviewer] Operator's internal code reviewer submitted..." | **No** |

Phase 1 adds a fifth producer — the inbox nudge itself, "[Operator] N inbox item(s). Run `opr inbox`." — which would also leak unfiltered were it added to the same list. The premise stated in the task brief ("this has occurred twice") is therefore wrong: it has occurred at least three times counting the fifth about to be added, and two live producers leak right now. Evidence: `grep -rn '\[Operator' backend/internal --include="*.go" | grep -v _test.go` plus a manual check of `isOperatorCoordinationMessage`'s three prefixes against all five producers' literal text.

**Mechanism chosen: (c) — record at send time, consume at ingest time, structurally exact.**

Every coordination write in this codebase already funnels through exactly one chokepoint: `sessionguard.Guard`'s `Nudge` and `NudgeCoordination` methods (`Deliver`/`DeliverWithPostWrite`/`DeliverUnderMutation` are user-initiated and out of scope — they write what a human or the human's own command asked for, which is real user intent, not something to suppress). `lifecycle.Manager` already owns both the guard (every coordination send in this codebase originates from `lifecycle.Manager`: `sendOnce`'s `Nudge` call in `reactions.go:844`, and this plan's new `NudgeCoordination` call) and `ApplyActivitySignal` (the ingest path every hook resolves to). So the fix does not enumerate producers at all: `lifecycle.Manager` remembers, per session, the exact text of the last coordination message it sent (trimmed), and `ApplyActivitySignal` clears an incoming `LatestUserPrompt` that matches it exactly, consuming the memory so a genuine identical follow-up prompt from the human is not silently dropped a second time.

This is not a retry, backoff, or timer: it holds no attempt count, schedules nothing, and expires nothing — it is a single overwritable slot per session, consumed on first match or replaced by the next coordination send. It does not conflict with the hard no-timer constraint above.

Cost of being wrong: the echo is compared by exact string equality after `strings.TrimSpace`, matching what `hookConversationFacts`'s own `firstHookValue` does. Two known residual risks, both narrow and worth stating rather than silently accepting:
1. `capHookText` (`cli/hooks.go`) truncates any hook value over 16KB with a middle marker before it ever reaches the daemon. A coordination message that exceeds that cap (the review-batch message, which includes a full review body, is the only one of the five that plausibly could) would not match the recorded echo and would leak through unfiltered — the same failure mode as before, but now confined to one identifiable oversized-message case instead of "forgot to register a new producer." Not fixed in this plan: doing so would require sharing `capHookText`'s exact truncation function between the `cli` and `lifecycle` packages, which is disproportionate to how rarely a review body exceeds 16KB.
2. If a human starts typing into the orchestrator's pane in the narrow window between a coordination write being sent and its `UserPromptSubmit` firing, the human's keystrokes could concatenate with the echo and the exact match would fail (again: leaks through, same as today). `NudgeCoordination`'s own guard already refuses delivery whenever the session needs input, narrowing but not eliminating this window.

The existing `isOperatorCoordinationMessage` prefix list in `cli/hooks.go` is left in place unmodified: it is cheap, already tested, and provides defense-in-depth for the three prefixes it already knows, filtering client-side before the daemon ever sees the text (so the daemon-side echo check never even runs for those three). It is not extended with a fourth entry for the inbox nudge — the daemon-side mechanism covers it, and every future coordination-write producer, automatically.

## File Structure

| File | Responsibility | Task |
| --- | --- | --- |
| `backend/internal/storage/sqlite/migrations/0106_orchestrator_inbox.sql` | New table + coalescing partial unique index | 1 |
| `backend/internal/storage/sqlite/migrate_burned_versions_test.go` | `shippedMigrations[106]` entry | 1 |
| `backend/internal/domain/inbox.go` (new) | `OrchestratorInboxEvent`, `InboxEventWorkerIdle` | 1 |
| `backend/internal/storage/sqlite/queries/orchestrator_inbox.sql` (new) | sqlc queries: enqueue, count, list-by-project, list-projects-pending, ack-one | 1 |
| `backend/internal/storage/sqlite/gen/*` | Generated by `npm run sqlc` | 1 |
| `backend/internal/storage/sqlite/store/orchestrator_inbox_store.go` (new) | Atomic enqueue-with-activity-update, count, list, ack, list-projects-pending | 2 |
| `backend/internal/lifecycle/manager.go` | `sessionStore` interface gains the 5 new methods; `ApplyActivitySignal` gains crossedToIdle detection, echo consumption, orchestrator-drain trigger, restore-sweep trigger | 3, 4, 5 |
| `backend/internal/lifecycle/inbox.go` (new) | `dispatchInboxNudge`, `resolveLiveOrchestrator`, coordination-echo bookkeeping, per-project dispatch lock, public `ListPendingInboxEvents`/`AckInboxEvents`/`DispatchPendingInboxEventsOnStartup` | 4, 5 |
| `backend/internal/lifecycle/reactions.go:844` | `sendOnce`'s `Nudge` call records its echo too | 4 |
| `backend/internal/lifecycle/manager_test.go` | `fakeStore` gains the 5 new methods | 3 |
| `backend/internal/daemon/daemon.go` | Startup sweep call after `lcStack.ReconcileRuntime` | 5 |
| `backend/internal/httpd/controllers/dto.go` | `InboxEntryView`, `InboxResponse`, `AckInboxEventsRequest`, `AckInboxEventsResponse` | 6 |
| `backend/internal/httpd/controllers/inbox.go` (new) | `InboxController`, routes | 6 |
| `backend/internal/httpd/api.go`, `backend/internal/daemon/daemon.go` | Wire `InboxController` into `APIDeps`/`API` | 6 |
| `backend/internal/cli/inbox.go` (new) | `opr inbox`, `opr inbox ack` | 7 |
| `backend/internal/cli/root.go` | Register the inbox command | 7 |
| `backend/internal/session_manager/prompt.go` | Pull protocol: `opr inbox`, act, `opr inbox ack`; empty inbox ends the turn | 8 |
| `backend/internal/lifecycle/manager.go:30` | Delete the stale "the dispatcher reads it" comment | 8 |

---

### Task 1: Migration, domain type, and sqlc queries

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0106_orchestrator_inbox.sql`
- Modify: `backend/internal/storage/sqlite/migrate_burned_versions_test.go` (append `106: "0106_orchestrator_inbox.sql",`)
- Create: `backend/internal/domain/inbox.go`
- Create: `backend/internal/storage/sqlite/queries/orchestrator_inbox.sql`
- Generated: `backend/internal/storage/sqlite/gen/*`

**Interfaces:**
- Produces: table `orchestrator_inbox`; `domain.OrchestratorInboxEvent{ID, ProjectID, WorkerID, Kind, State, OccurredAt, AckedAt, CreatedAt, UpdatedAt}`; `domain.InboxEventWorkerIdle = "worker_idle"`; `domain.InboxStatePending = "pending"`, `domain.InboxStateAcked = "acked"`; sqlc-generated `gen.EnqueueOrchestratorInboxEventParams`, `gen.CountPendingInboxEventsParams` (wait — no params, project id only, see below), `gen.ListPendingInboxEventsByProjectParams`, `gen.ListProjectsWithPendingInboxEventsRow`, `gen.AckInboxEventParams`. Task 2 consumes all of these.

- [ ] **Step 1: Write the migration**

```sql
-- +goose Up
-- +goose StatementBegin
CREATE TABLE orchestrator_inbox (
    id          TEXT PRIMARY KEY,
    project_id  TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    worker_id   TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    kind        TEXT NOT NULL CHECK (kind IN ('worker_idle','ci_failed','review_changes_requested')),
    occurred_at TIMESTAMP NOT NULL,
    state       TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','acked')),
    acked_at    TIMESTAMP,
    created_at  TIMESTAMP NOT NULL,
    updated_at  TIMESTAMP NOT NULL
);
-- +goose StatementEnd

-- +goose StatementBegin
CREATE UNIQUE INDEX idx_orchestrator_inbox_pending_worker
    ON orchestrator_inbox(worker_id, kind) WHERE state = 'pending';
-- +goose StatementEnd

-- +goose StatementBegin
CREATE INDEX idx_orchestrator_inbox_pending_project
    ON orchestrator_inbox(project_id) WHERE state = 'pending';
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE orchestrator_inbox;
-- +goose StatementEnd
```

- [ ] **Step 2: Register the migration in the burned-versions ledger**

In `migrate_burned_versions_test.go`, append after the `105` entry:

```go
	106: "0106_orchestrator_inbox.sql",
```

- [ ] **Step 3: Run the ledger test**

```bash
cd backend && go test ./internal/storage/sqlite/ -run TestMigrationVersionLedger -v
```

Expected: PASS. If it fails complaining the file isn't registered, the entry above is missing or misspelled.

- [ ] **Step 4: Write the domain type**

Create `backend/internal/domain/inbox.go`:

```go
package domain

import "time"

type OrchestratorInboxEventKind string

const (
	InboxEventWorkerIdle                OrchestratorInboxEventKind = "worker_idle"
	InboxEventCIFailed                  OrchestratorInboxEventKind = "ci_failed"
	InboxEventReviewChangesRequested    OrchestratorInboxEventKind = "review_changes_requested"
)

type OrchestratorInboxEventState string

const (
	InboxStatePending OrchestratorInboxEventState = "pending"
	InboxStateAcked   OrchestratorInboxEventState = "acked"
)

type OrchestratorInboxEvent struct {
	ID         string
	ProjectID  ProjectID
	WorkerID   SessionID
	Kind       OrchestratorInboxEventKind
	State      OrchestratorInboxEventState
	OccurredAt time.Time
	AckedAt    time.Time
	CreatedAt  time.Time
	UpdatedAt  time.Time
}
```

- [ ] **Step 5: Write the sqlc queries**

Create `backend/internal/storage/sqlite/queries/orchestrator_inbox.sql`:

```sql
-- name: EnqueueOrchestratorInboxEvent :exec
INSERT INTO orchestrator_inbox (
    id, project_id, worker_id, kind, occurred_at, state, created_at, updated_at
) VALUES (
    ?, ?, ?, ?, ?, 'pending', ?, ?
)
ON CONFLICT (worker_id, kind) WHERE state = 'pending' DO NOTHING;

-- name: CountPendingInboxEvents :one
SELECT COUNT(*) FROM orchestrator_inbox WHERE project_id = ? AND state = 'pending';

-- name: ListPendingInboxEventsByProject :many
SELECT * FROM orchestrator_inbox WHERE project_id = ? AND state = 'pending' ORDER BY occurred_at ASC;

-- name: ListProjectsWithPendingInboxEvents :many
SELECT DISTINCT project_id FROM orchestrator_inbox WHERE state = 'pending';

-- name: AckInboxEvent :execrows
UPDATE orchestrator_inbox SET state = 'acked', acked_at = ?, updated_at = ?
WHERE id = ? AND project_id = ? AND state = 'pending';

-- name: DeleteAckedInboxEventsOlderThan :execrows
DELETE FROM orchestrator_inbox WHERE project_id = ? AND state = 'acked' AND acked_at < ?;
```

- [ ] **Step 6: Regenerate sqlc code**

```bash
npm run sqlc
git status --short backend/internal/storage/sqlite/gen/
```

Expected: new/modified generated files for the five queries above (likely `orchestrator_inbox.sql.go` and an updated `models.go` for the new table's Go struct).

- [ ] **Step 7: Build the package**

```bash
cd backend && go build ./...
```

Expected: builds clean (domain and gen compile; nothing yet consumes them, so no "declared and not used" errors are possible at this layer).

- [ ] **Step 8: Commit**

```bash
git add backend/internal/storage/sqlite/migrations/0106_orchestrator_inbox.sql \
        backend/internal/storage/sqlite/migrate_burned_versions_test.go \
        backend/internal/domain/inbox.go \
        backend/internal/storage/sqlite/queries/orchestrator_inbox.sql \
        backend/internal/storage/sqlite/gen/
git commit -m "feat(storage): add orchestrator_inbox table and queries

Migration 0106 creates the coalescing inbox table from spec section 6: one
pending row per (worker, kind) via a partial unique index. Rows carry no
digest content by design -- callers resolve it from the session record at
read time.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Atomic store layer

**Files:**
- Create: `backend/internal/storage/sqlite/store/orchestrator_inbox_store.go`
- Test: `backend/internal/storage/sqlite/store/orchestrator_inbox_store_test.go` (new)

**Interfaces:**
- Consumes: `gen.Queries`, `s.writeDB`, `s.writeMu`, `s.qw`/`s.qr` (existing `*Store` fields, `store.go`); `domain.OrchestratorInboxEvent`, `domain.SessionRecord` (Task 1).
- Produces:
  - `func (s *Store) UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx context.Context, rec domain.SessionRecord, event domain.OrchestratorInboxEvent) (bool, error)`
  - `func (s *Store) CountPendingInboxEvents(ctx context.Context, project domain.ProjectID) (int, error)`
  - `func (s *Store) ListPendingInboxEvents(ctx context.Context, project domain.ProjectID) ([]domain.OrchestratorInboxEvent, error)`
  - `func (s *Store) ListProjectsWithPendingInboxEvents(ctx context.Context) ([]domain.ProjectID, error)`
  - `func (s *Store) AckInboxEvents(ctx context.Context, project domain.ProjectID, ids []string) (int, error)`

  Task 3 consumes all five as part of `lifecycle.sessionStore`.

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/storage/sqlite/store/orchestrator_inbox_store_test.go`. Use the existing `sqlitetest` helper the rest of this package's tests use to get an in-memory migrated DB — check `session_store_test.go`'s top-of-file setup for the exact helper call and copy it.

```go
package store

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestUpdateSessionFromActivitySignalAndEnqueueInboxEvent_AtomicAndCoalesced(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	proj := seedProject(t, s, "proj-1")
	rec := seedSession(t, s, proj, "worker-1", domain.KindWorker)

	rec.Activity = domain.Activity{State: domain.ActivityIdle, LastActivityAt: time.Now().UTC()}
	rec.UpdatedAt = time.Now().UTC()
	event := domain.OrchestratorInboxEvent{
		ID: "evt-1", ProjectID: proj, WorkerID: rec.ID,
		Kind: domain.InboxEventWorkerIdle, OccurredAt: rec.Activity.LastActivityAt,
	}
	applied, err := s.UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx, rec, event)
	if err != nil || !applied {
		t.Fatalf("applied=%v err=%v", applied, err)
	}

	count, err := s.CountPendingInboxEvents(ctx, proj)
	if err != nil || count != 1 {
		t.Fatalf("count=%d err=%v, want 1", count, err)
	}

	event2 := event
	event2.ID = "evt-2"
	applied, err = s.UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx, rec, event2)
	if err != nil || !applied {
		t.Fatalf("second call: applied=%v err=%v", applied, err)
	}
	count, err = s.CountPendingInboxEvents(ctx, proj)
	if err != nil || count != 1 {
		t.Fatalf("count after duplicate=%d err=%v, want 1 (coalesced)", count, err)
	}
}

func TestUpdateSessionFromActivitySignalAndEnqueueInboxEvent_NoRowWhenActivityWriteMisses(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	proj := seedProject(t, s, "proj-1")
	rec := seedSession(t, s, proj, "worker-1", domain.KindWorker)
	rec.Harness = "codex"

	stale := rec
	stale.Metadata.RuntimeLaunchID = "stale-launch"
	event := domain.OrchestratorInboxEvent{
		ID: "evt-1", ProjectID: proj, WorkerID: rec.ID,
		Kind: domain.InboxEventWorkerIdle, OccurredAt: time.Now().UTC(),
	}
	applied, err := s.UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx, stale, event)
	if err != nil {
		t.Fatal(err)
	}
	if applied {
		t.Fatal("expected applied=false when the activity write's WHERE clause misses")
	}
	count, err := s.CountPendingInboxEvents(ctx, proj)
	if err != nil || count != 0 {
		t.Fatalf("count=%d err=%v, want 0: the insert must not survive a rolled-back transaction", count, err)
	}
}

func TestAckInboxEvents_UnknownAndAlreadyAckedAreNoops(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	proj := seedProject(t, s, "proj-1")
	rec := seedSession(t, s, proj, "worker-1", domain.KindWorker)
	rec.Activity = domain.Activity{State: domain.ActivityIdle, LastActivityAt: time.Now().UTC()}
	event := domain.OrchestratorInboxEvent{ID: "evt-1", ProjectID: proj, WorkerID: rec.ID, Kind: domain.InboxEventWorkerIdle, OccurredAt: time.Now().UTC()}
	if _, err := s.UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx, rec, event); err != nil {
		t.Fatal(err)
	}

	n, err := s.AckInboxEvents(ctx, proj, []string{"evt-1", "unknown-id"})
	if err != nil || n != 1 {
		t.Fatalf("n=%d err=%v, want 1", n, err)
	}

	n, err = s.AckInboxEvents(ctx, proj, []string{"evt-1"})
	if err != nil || n != 0 {
		t.Fatalf("re-ack n=%d err=%v, want 0 (no-op, not an error)", n, err)
	}

	pending, err := s.ListPendingInboxEvents(ctx, proj)
	if err != nil || len(pending) != 0 {
		t.Fatalf("pending=%v err=%v, want none", pending, err)
	}
}
```

Look at an existing test in this package (`session_store_test.go` or `agent_switching_store_test.go`) for the exact `newTestStore`/`seedProject`/`seedSession` helper names and signatures already in this package — reuse them verbatim; do not invent parallel helpers. `domain.KindWorker` — check `domain/session.go` for the exact constant name if it differs.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && go test ./internal/storage/sqlite/store/ -run TestUpdateSessionFromActivitySignalAndEnqueueInboxEvent -v
cd backend && go test ./internal/storage/sqlite/store/ -run TestAckInboxEvents -v
```

Expected: build failure — the methods don't exist yet. That is the correct RED.

- [ ] **Step 3: Write the implementation**

Create `backend/internal/storage/sqlite/store/orchestrator_inbox_store.go`, following the manual-`BeginTx` shape at `agent_switching_store.go:386` (`ConfirmAgentSwitchSourceStopped`) exactly — same `writeMu` + `BeginTx` + `defer tx.Rollback()` + `WithTx` + explicit `tx.Commit()` pattern:

```go
package store

import (
	"context"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

func (s *Store) UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx context.Context, rec domain.SessionRecord, event domain.OrchestratorInboxEvent) (bool, error) {
	activity := normalActivity(rec.Activity, rec.UpdatedAt)
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	tx, err := s.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return false, fmt.Errorf("begin enqueue inbox event for %s: %w", rec.ID, err)
	}
	defer func() { _ = tx.Rollback() }()
	q := s.qw.WithTx(tx)

	rows, err := q.UpdateSessionFromActivitySignal(ctx, gen.UpdateSessionFromActivitySignalParams{
		ActivityState:           activity.State,
		ActivityLastAt:          activity.LastActivityAt,
		FirstSignalAt:           timeToNullTime(rec.FirstSignalAt),
		AgentSessionID:          rec.Metadata.AgentSessionID,
		LatestUserPrompt:        rec.Metadata.LatestUserPrompt,
		LatestAssistantUpdate:   rec.Metadata.LatestAssistantUpdate,
		NativeTranscriptPath:    rec.Metadata.NativeTranscriptPath,
		UpdatedAt:               rec.UpdatedAt,
		ID:                      rec.ID,
		ExpectedHarness:         rec.Harness,
		ExpectedRuntimeLaunchID: rec.Metadata.RuntimeLaunchID,
	})
	if err != nil {
		return false, fmt.Errorf("update session %s from activity signal: %w", rec.ID, err)
	}
	if rows == 0 {
		return false, nil
	}

	now := time.Now().UTC()
	if err := q.EnqueueOrchestratorInboxEvent(ctx, gen.EnqueueOrchestratorInboxEventParams{
		ID:         event.ID,
		ProjectID:  event.ProjectID,
		WorkerID:   event.WorkerID,
		Kind:       string(event.Kind),
		OccurredAt: event.OccurredAt,
		CreatedAt:  now,
		UpdatedAt:  now,
	}); err != nil {
		return false, fmt.Errorf("enqueue inbox event for %s: %w", rec.ID, err)
	}

	if err := tx.Commit(); err != nil {
		return false, fmt.Errorf("commit enqueue inbox event for %s: %w", rec.ID, err)
	}
	return true, nil
}

func (s *Store) CountPendingInboxEvents(ctx context.Context, project domain.ProjectID) (int, error) {
	n, err := s.qr.CountPendingInboxEvents(ctx, project)
	if err != nil {
		return 0, fmt.Errorf("count pending inbox events for %s: %w", project, err)
	}
	return int(n), nil
}

func (s *Store) ListPendingInboxEvents(ctx context.Context, project domain.ProjectID) ([]domain.OrchestratorInboxEvent, error) {
	rows, err := s.qr.ListPendingInboxEventsByProject(ctx, project)
	if err != nil {
		return nil, fmt.Errorf("list pending inbox events for %s: %w", project, err)
	}
	out := make([]domain.OrchestratorInboxEvent, 0, len(rows))
	for _, r := range rows {
		out = append(out, inboxEventFromGen(r))
	}
	return out, nil
}

func (s *Store) ListProjectsWithPendingInboxEvents(ctx context.Context) ([]domain.ProjectID, error) {
	rows, err := s.qr.ListProjectsWithPendingInboxEvents(ctx)
	if err != nil {
		return nil, fmt.Errorf("list projects with pending inbox events: %w", err)
	}
	return rows, nil
}

func (s *Store) AckInboxEvents(ctx context.Context, project domain.ProjectID, ids []string) (int, error) {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	now := time.Now().UTC()
	acked := 0
	for _, id := range ids {
		n, err := s.qw.AckInboxEvent(ctx, gen.AckInboxEventParams{AckedAt: now, UpdatedAt: now, ID: id, ProjectID: project})
		if err != nil {
			return acked, fmt.Errorf("ack inbox event %s: %w", id, err)
		}
		acked += int(n)
	}
	if acked > 0 {
		cutoff := now.AddDate(0, 0, -7)
		if _, err := s.qw.DeleteAckedInboxEventsOlderThan(ctx, gen.DeleteAckedInboxEventsOlderThanParams{ProjectID: project, AckedAt: cutoff}); err != nil {
			return acked, fmt.Errorf("prune acked inbox events for %s: %w", project, err)
		}
	}
	return acked, nil
}
```

Check the exact generated type/field names `gen.EnqueueOrchestratorInboxEventParams`, `gen.AckInboxEventParams`, `gen.DeleteAckedInboxEventsOlderThanParams`, and the row type returned by `ListPendingInboxEventsByProject` (likely `gen.OrchestratorInbox`) against what `npm run sqlc` actually generated in Task 1 — sqlc's exact field naming (e.g. whether `kind` becomes `Kind string` or something else) may differ slightly from this sketch; match the generated code, not this listing.

Add `inboxEventFromGen` near the other `*FromGen` converters in this package (see `agentSwitchFromGen` in `agent_switching_store.go` for the pattern):

```go
func inboxEventFromGen(row gen.OrchestratorInbox) domain.OrchestratorInboxEvent {
	ev := domain.OrchestratorInboxEvent{
		ID:         row.ID,
		ProjectID:  row.ProjectID,
		WorkerID:   row.WorkerID,
		Kind:       domain.OrchestratorInboxEventKind(row.Kind),
		State:      domain.OrchestratorInboxEventState(row.State),
		OccurredAt: row.OccurredAt,
		CreatedAt:  row.CreatedAt,
		UpdatedAt:  row.UpdatedAt,
	}
	if row.AckedAt.Valid {
		ev.AckedAt = row.AckedAt.Time
	}
	return ev
}
```

Adjust for however sqlc actually names the nullable `acked_at` field (`sql.NullTime` vs a generated nullable wrapper) — match `session_store.go`'s existing `timeToNullTime`/`NullTime` handling for other nullable timestamp columns in this same file.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && go test ./internal/storage/sqlite/store/ -run "TestUpdateSessionFromActivitySignalAndEnqueueInboxEvent|TestAckInboxEvents" -v
cd backend && go test ./internal/storage/sqlite/store/
```

Expected: PASS, whole package ok.

- [ ] **Step 5: Run the full gate**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
git add backend/internal/storage/sqlite/store/orchestrator_inbox_store.go \
        backend/internal/storage/sqlite/store/orchestrator_inbox_store_test.go
git commit -m "feat(storage): atomic activity-update-plus-inbox-insert store method

UpdateSessionFromActivitySignalAndEnqueueInboxEvent writes the activity
transition and the coalesced inbox row inside one BeginTx, so a crash
between the two writes cannot persist idle-ness while losing the event
(spec section 5.1). Precedent: agent_switching_store.go's
ConfirmAgentSwitchSourceStopped.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: crossedToIdle detection in the reducer

**Files:**
- Modify: `backend/internal/lifecycle/manager.go` (the `sessionStore` interface near the top; `ApplyActivitySignal`'s post-`next`-construction branch, currently the single call `applied, err := m.store.UpdateSessionFromActivitySignal(ctx, next)`)
- Modify: `backend/internal/lifecycle/manager_test.go` (`fakeStore` gains the 5 new methods)
- Test: `backend/internal/lifecycle/manager_test.go`

**Interfaces:**
- Consumes: the 5 store methods from Task 2.
- Produces: `next.Kind`-and-transition-derived `crossedToIdleWorker bool` local in `ApplyActivitySignal`; this is internal to the function, but Task 4 reads the same derivation for `orchestratorReadyToDrain`, so keep both computed together in one place, not duplicated.

- [ ] **Step 1: Add the 5 methods to the `sessionStore` interface**

In `manager.go`, inside the `sessionStore` interface (the block starting `type sessionStore interface {`), add after `UpdatePRLastNudgeSignature`:

```go
	UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx context.Context, rec domain.SessionRecord, event domain.OrchestratorInboxEvent) (bool, error)
	CountPendingInboxEvents(ctx context.Context, project domain.ProjectID) (int, error)
	ListPendingInboxEvents(ctx context.Context, project domain.ProjectID) ([]domain.OrchestratorInboxEvent, error)
	ListProjectsWithPendingInboxEvents(ctx context.Context) ([]domain.ProjectID, error)
	AckInboxEvents(ctx context.Context, project domain.ProjectID, ids []string) (int, error)
```

- [ ] **Step 2: Add no-op implementations to `fakeStore`**

In `manager_test.go`, add to `fakeStore`:

```go
	inboxEvents map[string]domain.OrchestratorInboxEvent
```

to the struct, initialize it in `newFakeStore`:

```go
		inboxEvents: map[string]domain.OrchestratorInboxEvent{},
```

and add the methods:

```go
func (f *fakeStore) UpdateSessionFromActivitySignalAndEnqueueInboxEvent(_ context.Context, rec domain.SessionRecord, event domain.OrchestratorInboxEvent) (bool, error) {
	f.sessions[rec.ID] = rec
	for _, existing := range f.inboxEvents {
		if existing.WorkerID == event.WorkerID && existing.Kind == event.Kind && existing.State == domain.InboxStatePending {
			return true, nil
		}
	}
	event.State = domain.InboxStatePending
	f.inboxEvents[event.ID] = event
	return true, nil
}

func (f *fakeStore) CountPendingInboxEvents(_ context.Context, project domain.ProjectID) (int, error) {
	n := 0
	for _, ev := range f.inboxEvents {
		if ev.ProjectID == project && ev.State == domain.InboxStatePending {
			n++
		}
	}
	return n, nil
}

func (f *fakeStore) ListPendingInboxEvents(_ context.Context, project domain.ProjectID) ([]domain.OrchestratorInboxEvent, error) {
	var out []domain.OrchestratorInboxEvent
	for _, ev := range f.inboxEvents {
		if ev.ProjectID == project && ev.State == domain.InboxStatePending {
			out = append(out, ev)
		}
	}
	return out, nil
}

func (f *fakeStore) ListProjectsWithPendingInboxEvents(_ context.Context) ([]domain.ProjectID, error) {
	seen := map[domain.ProjectID]bool{}
	var out []domain.ProjectID
	for _, ev := range f.inboxEvents {
		if ev.State == domain.InboxStatePending && !seen[ev.ProjectID] {
			seen[ev.ProjectID] = true
			out = append(out, ev.ProjectID)
		}
	}
	return out, nil
}

func (f *fakeStore) AckInboxEvents(_ context.Context, project domain.ProjectID, ids []string) (int, error) {
	acked := 0
	for _, id := range ids {
		ev, ok := f.inboxEvents[id]
		if !ok || ev.ProjectID != project || ev.State != domain.InboxStatePending {
			continue
		}
		ev.State = domain.InboxStateAcked
		f.inboxEvents[id] = ev
		acked++
	}
	return acked, nil
}
```

- [ ] **Step 3: Confirm the package still builds (interface satisfaction check)**

```bash
cd backend && go build ./internal/lifecycle/...
```

Expected: compiles. This is not yet a behavior test — it only proves `fakeStore` satisfies the widened `sessionStore` interface.

- [ ] **Step 4: Write the failing reducer tests**

Add to `manager_test.go`:

```go
func TestApplyActivitySignal_WorkerCrossingActiveToIdleEnqueuesExactlyOneInboxEvent(t *testing.T) {
	m, st, _ := newManager()
	rec := working("mer-1")
	st.sessions["mer-1"] = rec

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	pending, err := st.ListPendingInboxEvents(ctx, "mer")
	if err != nil || len(pending) != 1 {
		t.Fatalf("pending=%v err=%v, want exactly 1", pending, err)
	}
	if pending[0].WorkerID != "mer-1" || pending[0].Kind != domain.InboxEventWorkerIdle {
		t.Fatalf("event=%+v", pending[0])
	}
}

func TestApplyActivitySignal_IdleToIdleDoesNotEnqueue(t *testing.T) {
	m, st, _ := newManager()
	rec := working("mer-1")
	rec.Activity.State = domain.ActivityIdle
	rec.FirstSignalAt = time.Now()
	st.sessions["mer-1"] = rec

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	pending, err := st.ListPendingInboxEvents(ctx, "mer")
	if err != nil || len(pending) != 0 {
		t.Fatalf("pending=%v err=%v, want none: idle-to-idle is not a crossing", pending, err)
	}
}

func TestApplyActivitySignal_WaitingInputToIdleDoesNotEnqueue(t *testing.T) {
	m, st, _ := newManager()
	rec := working("mer-1")
	rec.Activity.State = domain.ActivityWaitingInput
	st.sessions["mer-1"] = rec

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	pending, err := st.ListPendingInboxEvents(ctx, "mer")
	if err != nil || len(pending) != 0 {
		t.Fatalf("pending=%v err=%v, want none: waiting_input->idle is a demotion, not a crossing", pending, err)
	}
}

func TestApplyActivitySignal_OrchestratorCrossingToIdleDoesNotEnqueue(t *testing.T) {
	m, st, _ := newManager()
	rec := working("mer-1")
	rec.Kind = domain.KindOrchestrator
	st.sessions["mer-1"] = rec

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	pending, err := st.ListPendingInboxEvents(ctx, "mer")
	if err != nil || len(pending) != 0 {
		t.Fatalf("pending=%v err=%v, want none: orchestrators never get worker_idle events for themselves", pending, err)
	}
}

func TestApplyActivitySignal_RepeatedIdleCoalescesToOnePendingRow(t *testing.T) {
	m, st, _ := newManager()
	rec := working("mer-1")
	st.sessions["mer-1"] = rec
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	st.sessions["mer-1"] = working("mer-1")
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	pending, err := st.ListPendingInboxEvents(ctx, "mer")
	if err != nil || len(pending) != 1 {
		t.Fatalf("pending=%v err=%v, want exactly 1 across two idle crossings for the same worker", pending, err)
	}
}
```

Check `working(id)`'s exact literal (already shown above from `manager_test.go`) for the correct `ProjectID` ("mer") and starting `Activity.State` (`ActivityActive`) before writing assertions — these tests build on it directly.

- [ ] **Step 5: Run tests to verify they fail**

```bash
cd backend && go test ./internal/lifecycle/ -run TestApplyActivitySignal_WorkerCrossing -v
```

Expected: FAIL — `pending` is empty because nothing calls the new store method yet.

- [ ] **Step 6: Implement crossedToIdle detection**

In `manager.go`, in `ApplyActivitySignal`, locate:

```go
	next.UpdatedAt = now
	applied, err := m.store.UpdateSessionFromActivitySignal(ctx, next)
	if err != nil {
		m.mu.Unlock()
		return err
	}
```

Replace with:

```go
	next.UpdatedAt = now
	crossedToIdleWorker := next.Kind != domain.KindOrchestrator &&
		prevState == domain.ActivityActive && next.Activity.State == domain.ActivityIdle
	orchestratorReadyToDrain := next.Kind == domain.KindOrchestrator &&
		((prevState == domain.ActivityActive && next.Activity.State == domain.ActivityIdle) ||
			(rec.FirstSignalAt.IsZero() && !next.FirstSignalAt.IsZero()))

	var applied bool
	if crossedToIdleWorker {
		applied, err = m.store.UpdateSessionFromActivitySignalAndEnqueueInboxEvent(ctx, next, domain.OrchestratorInboxEvent{
			ID:         uuid.NewString(),
			ProjectID:  next.ProjectID,
			WorkerID:   next.ID,
			Kind:       domain.InboxEventWorkerIdle,
			OccurredAt: next.Activity.LastActivityAt,
		})
	} else {
		applied, err = m.store.UpdateSessionFromActivitySignal(ctx, next)
	}
	if err != nil {
		m.mu.Unlock()
		return err
	}
```

`uuid` is already imported in this file (`github.com/google/uuid`, used elsewhere in `manager.go`) — confirm before adding a duplicate import.

`orchestratorReadyToDrain` is computed here but not yet consumed — Task 4 reads it (as a local var passed into the post-unlock dispatch call), so leave it in place; Go will flag it as unused only if nothing in the same function references it, so do not run `go vet`/build in isolation between Task 3 and Task 4 as a completion gate — Task 4 lands in the same function body immediately after.

- [ ] **Step 7: Run tests to verify they pass**

```bash
cd backend && go test ./internal/lifecycle/ -run "TestApplyActivitySignal_(WorkerCrossing|IdleToIdle|WaitingInputToIdle|OrchestratorCrossing|RepeatedIdle)" -v
```

Expected: PASS. `TestApplyActivitySignal_OrchestratorCrossingToIdleDoesNotEnqueue` may still fail to build until Task 4 consumes `orchestratorReadyToDrain` — if `go vet` complains about the unused variable, wrap it in `_ = orchestratorReadyToDrain` as a placeholder for this step only, removed in Task 4's first edit.

- [ ] **Step 8: Run the package tests and the full gate**

```bash
cd backend && go test ./internal/lifecycle/
npm run lint
```

- [ ] **Step 9: Commit**

```bash
git add backend/internal/lifecycle/manager.go backend/internal/lifecycle/manager_test.go
git commit -m "feat(lifecycle): detect a worker crossing active to idle and enqueue an inbox event

crossedToIdleWorker fires only from active specifically, so neither the
spawn-time idle seed nor a waiting_input->idle demotion enqueues an event
(spec section 7 step 1). Orchestrators never get worker_idle rows for
their own transitions -- orchestratorReadyToDrain (consumed next) covers
that case separately.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Dispatch, coordination-echo suppression, and the duplicate-delivery regression test

This is the heart of the design (spec §7, §3). Read `sessionguard/guard.go`'s full doc comment and `NudgeCoordination` (`guard.go:247`) before starting.

**Files:**
- Create: `backend/internal/lifecycle/inbox.go`
- Modify: `backend/internal/lifecycle/manager.go` (struct fields, `ApplyActivitySignal`'s post-unlock section, echo consumption near the top)
- Modify: `backend/internal/lifecycle/reactions.go:844` (`sendOnce`'s `Nudge` call records its echo)
- Test: `backend/internal/lifecycle/inbox_test.go` (new)

**Interfaces:**
- Consumes: `m.store` (Task 2/3 methods), `m.guard` (`sessionguard.Guard`, existing field), `m.steerActive` (existing field, the same predicate `NudgeCoordination` needs), `domain.KindOrchestrator`.
- Produces:
  - `func (m *Manager) dispatchInboxNudge(ctx context.Context, project domain.ProjectID) error` — consumed by Task 5's sweeps.
  - `func (m *Manager) ListPendingInboxEvents(ctx context.Context, project domain.ProjectID) ([]domain.OrchestratorInboxEvent, error)` — consumed by Task 6's HTTP controller.
  - `func (m *Manager) AckInboxEvents(ctx context.Context, project domain.ProjectID, ids []string) (int, error)` — consumed by Task 6.

- [ ] **Step 1: Write the failing dispatch tests**

Add to `manager_test.go` (or a new `inbox_test.go` in `package lifecycle` — either is fine, but keep dispatch tests together in one file):

```go
func orchestrator(id domain.SessionID, project domain.ProjectID) domain.SessionRecord {
	return domain.SessionRecord{
		ID: id, ProjectID: project, Kind: domain.KindOrchestrator,
		Activity: domain.Activity{State: domain.ActivityIdle, LastActivityAt: time.Now()},
		FirstSignalAt: time.Now(),
	}
}

func TestApplyActivitySignal_WorkerIdleNudgesTheLiveOrchestrator(t *testing.T) {
	m, st, msg := newManager()
	st.sessions["mer-2"] = orchestrator("mer-2", "mer")
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 1 || msg.ids[0] != "mer-2" {
		t.Fatalf("messenger calls = %+v / %+v, want exactly one nudge to mer-2", msg.msgs, msg.ids)
	}
	if !strings.Contains(msg.msgs[0], "1 inbox item") || !strings.Contains(msg.msgs[0], "opr inbox") {
		t.Fatalf("nudge text = %q", msg.msgs[0])
	}
}

func TestApplyActivitySignal_NoOrchestratorLeavesRowPendingAndSendsNothing(t *testing.T) {
	m, st, msg := newManager()
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 0 {
		t.Fatalf("messenger calls = %v, want none", msg.msgs)
	}
	pending, _ := st.ListPendingInboxEvents(ctx, "mer")
	if len(pending) != 1 {
		t.Fatalf("pending = %v, want the row to stay pending", pending)
	}
}

func TestApplyActivitySignal_OrchestratorNeedsInputSuppressesTheNudge(t *testing.T) {
	m, st, msg := newManager()
	orch := orchestrator("mer-2", "mer")
	orch.Activity.State = domain.ActivityWaitingInput
	st.sessions["mer-2"] = orch
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 0 {
		t.Fatalf("messenger calls = %v, want none: orchestrator needs input", msg.msgs)
	}
}

func TestApplyActivitySignal_OrchestratorZeroFirstSignalSuppressesTheNudge(t *testing.T) {
	m, st, msg := newManager()
	orch := orchestrator("mer-2", "mer")
	orch.FirstSignalAt = time.Time{}
	st.sessions["mer-2"] = orch
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 0 {
		t.Fatalf("messenger calls = %v, want none: a restored orchestrator's hooks are not yet proven up", msg.msgs)
	}
}

func TestApplyActivitySignal_OrchestratorActiveOnNonSteeringHarnessSuppressesTheNudge(t *testing.T) {
	m, st, msg := newManager()
	orch := orchestrator("mer-2", "mer")
	orch.Activity.State = domain.ActivityActive
	orch.Harness = domain.HarnessClaudeCode
	st.sessions["mer-2"] = orch
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 0 {
		t.Fatalf("messenger calls = %v, want none: claude-code cannot be steered mid-turn", msg.msgs)
	}
}

func TestApplyActivitySignal_OrchestratorActiveOnSteeringHarnessDelivers(t *testing.T) {
	m, st, msg := newManager()
	m.steerActive = func(h domain.AgentHarness) bool { return h == domain.HarnessCodex }
	orch := orchestrator("mer-2", "mer")
	orch.Activity.State = domain.ActivityActive
	orch.Harness = domain.HarnessCodex
	st.sessions["mer-2"] = orch
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 1 {
		t.Fatalf("messenger calls = %v, want exactly one: codex steers active turns", msg.msgs)
	}
}

func TestApplyActivitySignal_OrchestratorEnteringIdleDrainsExistingBacklog(t *testing.T) {
	m, st, msg := newManager()
	orch := orchestrator("mer-2", "mer")
	orch.Activity.State = domain.ActivityActive
	st.sessions["mer-2"] = orch
	st.inboxEvents["evt-1"] = domain.OrchestratorInboxEvent{
		ID: "evt-1", ProjectID: "mer", WorkerID: "mer-1", Kind: domain.InboxEventWorkerIdle, State: domain.InboxStatePending,
	}

	if err := m.ApplyActivitySignal(ctx, "mer-2", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 1 || msg.ids[0] != "mer-2" {
		t.Fatalf("messenger calls = %+v / %+v, want the orchestrator nudged about its own pending backlog", msg.msgs, msg.ids)
	}
}

func TestDispatchInboxNudge_DuplicateCallsProduceOneDigestAndOneAckedRow(t *testing.T) {
	m, st, msg := newManager()
	st.sessions["mer-2"] = orchestrator("mer-2", "mer")
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}
	if err := m.dispatchInboxNudge(ctx, "mer"); err != nil {
		t.Fatal(err)
	}
	if err := m.dispatchInboxNudge(ctx, "mer"); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 3 {
		t.Fatalf("messenger calls = %d, want 3 (the original plus two duplicate dispatches -- duplicates are safe, not free)", len(msg.msgs))
	}

	digests, err := m.ListPendingInboxEvents(ctx, "mer")
	if err != nil || len(digests) != 1 {
		t.Fatalf("digests=%v err=%v, want exactly one despite 3 nudges", digests, err)
	}

	acked, err := m.AckInboxEvents(ctx, "mer", []string{digests[0].ID})
	if err != nil || acked != 1 {
		t.Fatalf("acked=%d err=%v, want 1", acked, err)
	}

	if err := m.dispatchInboxNudge(ctx, "mer"); err != nil {
		t.Fatal(err)
	}
	if len(msg.msgs) != 3 {
		t.Fatalf("messenger calls after ack = %d, want still 3: nothing pending, nothing to send", len(msg.msgs))
	}
}

func TestApplyActivitySignal_TheNudgeIsNotStoredAsTheOrchestratorsOwnLatestUserPrompt(t *testing.T) {
	m, st, _ := newManager()
	st.sessions["mer-2"] = orchestrator("mer-2", "mer")
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	nudgeText := "[Operator] 1 inbox item(s). Run `opr inbox`."
	if err := m.ApplyActivitySignal(ctx, "mer-2", ports.ActivitySignal{
		Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit", LatestUserPrompt: nudgeText,
	}); err != nil {
		t.Fatal(err)
	}

	got := st.sessions["mer-2"]
	if got.Metadata.LatestUserPrompt == nudgeText {
		t.Fatalf("orchestrator's own nudge was echoed back as its latestUserPrompt: %q", got.Metadata.LatestUserPrompt)
	}
}

func TestSendOnceReviewNudgeIsNotStoredAsTheWorkersOwnLatestUserPrompt(t *testing.T) {
	m, st, _ := newManager()
	rec := working("mer-1")
	rec.AutoInjectReview = true
	st.sessions["mer-1"] = rec

	outcome, err := m.ApplyReviewBatch(ctx, "mer-1", "batch-1", []ReviewResult{{
		RunID: "run-1", BatchID: "batch-1", WorkerID: "mer-1", PRURL: "https://x/pr/1", Verdict: domain.VerdictChangesRequested,
	}})
	if err != nil || outcome != ReviewDeliverySent {
		t.Fatalf("outcome=%v err=%v", outcome, err)
	}

	sentText := st.sessions["mer-1"]
	_ = sentText
	echoed := "[Operator reviewer] Operator's internal code reviewer submitted 1 review(s) requesting changes."
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{
		Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit", LatestUserPrompt: echoed,
	}); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(st.sessions["mer-1"].Metadata.LatestUserPrompt, "Operator reviewer") {
		t.Fatalf("worker's own review nudge was echoed back as its latestUserPrompt: %q", st.sessions["mer-1"].Metadata.LatestUserPrompt)
	}
}
```

Check `ApplyReviewBatch`'s exact call signature and `ReviewResult` fields against `reactions.go` (already read above) before finalizing this test — adjust field names if they differ from this sketch. The echoed text in the last test must match the review message's ACTUAL first-line format exactly (verbatim from `reactions.go:72`), not an approximation — read it from the source, not from this plan, since exactness is what the mechanism depends on.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && go test ./internal/lifecycle/ -run "TestApplyActivitySignal_WorkerIdleNudges|TestDispatchInboxNudge" -v
```

Expected: FAIL — `dispatchInboxNudge` undefined, or zero messenger calls.

- [ ] **Step 3: Write `inbox.go`**

```go
package lifecycle

import (
	"context"
	"fmt"
	"strings"
	"sync"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/sessionguard"
)

func (m *Manager) resolveLiveOrchestrator(ctx context.Context, project domain.ProjectID) (domain.SessionID, bool, error) {
	recs, err := m.store.ListSessions(ctx, project)
	if err != nil {
		return "", false, fmt.Errorf("list sessions for %s: %w", project, err)
	}
	for _, rec := range recs {
		if rec.Kind == domain.KindOrchestrator && !rec.IsTerminated {
			return rec.ID, true, nil
		}
	}
	return "", false, nil
}

func (m *Manager) dispatchLockFor(project domain.ProjectID) *sync.Mutex {
	m.dispatchLocksMu.Lock()
	defer m.dispatchLocksMu.Unlock()
	if m.dispatchLocks == nil {
		m.dispatchLocks = map[domain.ProjectID]*sync.Mutex{}
	}
	lock, ok := m.dispatchLocks[project]
	if !ok {
		lock = &sync.Mutex{}
		m.dispatchLocks[project] = lock
	}
	return lock
}

func (m *Manager) dispatchInboxNudge(ctx context.Context, project domain.ProjectID) error {
	if m.guard == nil {
		return nil
	}
	lock := m.dispatchLockFor(project)
	lock.Lock()
	defer lock.Unlock()

	orchestratorID, found, err := m.resolveLiveOrchestrator(ctx, project)
	if err != nil {
		return err
	}
	if !found {
		return nil
	}
	rec, ok, err := m.store.GetSession(ctx, orchestratorID)
	if err != nil {
		return err
	}
	if !ok || rec.FirstSignalAt.IsZero() {
		return nil
	}
	count, err := m.store.CountPendingInboxEvents(ctx, project)
	if err != nil {
		return err
	}
	if count == 0 {
		return nil
	}
	msg := fmt.Sprintf("[Operator] %d inbox item(s). Run `opr inbox`.", count)
	outcome, err := m.guard.NudgeCoordination(ctx, orchestratorID, msg, m.steerActive)
	if err != nil {
		return err
	}
	if outcome == sessionguard.Sent {
		m.rememberCoordinationEcho(orchestratorID, msg)
	}
	return nil
}

func (m *Manager) rememberCoordinationEcho(id domain.SessionID, msg string) {
	trimmed := strings.TrimSpace(msg)
	if trimmed == "" {
		return
	}
	m.echoMu.Lock()
	if m.pendingEcho == nil {
		m.pendingEcho = map[domain.SessionID]string{}
	}
	m.pendingEcho[id] = trimmed
	m.echoMu.Unlock()
}

func (m *Manager) consumeCoordinationEcho(id domain.SessionID, prompt string) bool {
	m.echoMu.Lock()
	defer m.echoMu.Unlock()
	pending, ok := m.pendingEcho[id]
	if !ok || pending != prompt {
		return false
	}
	delete(m.pendingEcho, id)
	return true
}

func (m *Manager) ListPendingInboxEvents(ctx context.Context, project domain.ProjectID) ([]domain.OrchestratorInboxEvent, error) {
	return m.store.ListPendingInboxEvents(ctx, project)
}

func (m *Manager) AckInboxEvents(ctx context.Context, project domain.ProjectID, ids []string) (int, error) {
	return m.store.AckInboxEvents(ctx, project, ids)
}
```

- [ ] **Step 4: Add the new fields to `Manager`**

In `manager.go`, in the `Manager` struct, add near `flights`/`pendingLaunches`:

```go
	echoMu          sync.Mutex
	pendingEcho     map[domain.SessionID]string
	dispatchLocksMu sync.Mutex
	dispatchLocks   map[domain.ProjectID]*sync.Mutex
```

- [ ] **Step 5: Consume `crossedToIdleWorker`/`orchestratorReadyToDrain` after unlock**

In `ApplyActivitySignal`, locate the existing post-unlock block:

```go
	resolutions := needsInputResolutions(rec, next, now)
	waitingEvents := m.waitingInputEvents(next, prevState, prevAt, now)
	m.mu.Unlock()
	if err := m.acknowledgeAgentSwitchTarget(ctx, id, s, now); err != nil {
		return err
	}
```

Insert immediately after `m.mu.Unlock()` (before or after `acknowledgeAgentSwitchTarget` — after is fine, order relative to it does not matter since they touch unrelated state):

```go
	if crossedToIdleWorker || orchestratorReadyToDrain {
		if dispatchErr := m.dispatchInboxNudge(ctx, next.ProjectID); dispatchErr != nil {
			m.logger().Error("dispatch inbox nudge failed", "project", next.ProjectID, "err", dispatchErr)
		}
	}
```

Check whether `Manager` already has a logger field/method (`m.logger()` or similar) by grepping `manager.go` for `slog` usage — if there is no existing logger accessor on `Manager`, drop the dispatch error on the floor with a comment-free `_ = dispatchErr` instead of inventing new logging plumbing; the row stays pending either way and the next trigger (worker idle, orchestrator idle, restore, or startup sweep) will retry the dispatch attempt (not a retry loop — the same at-least-once-delivery-by-construction property spec §7 relies on).

- [ ] **Step 6: Consume the coordination echo at ingest**

Near the top of `ApplyActivitySignal`, immediately after the existing trim block:

```go
	s.AgentSessionID = strings.TrimSpace(s.AgentSessionID)
	s.LatestUserPrompt = strings.TrimSpace(s.LatestUserPrompt)
	s.LatestAssistantUpdate = strings.TrimSpace(s.LatestAssistantUpdate)
	s.TranscriptPath = strings.TrimSpace(s.TranscriptPath)
	s.LaunchID = strings.TrimSpace(s.LaunchID)
	s.ControllerGeneration = strings.TrimSpace(s.ControllerGeneration)
```

add:

```go
	if s.LatestUserPrompt != "" && m.consumeCoordinationEcho(id, s.LatestUserPrompt) {
		s.LatestUserPrompt = ""
	}
```

- [ ] **Step 7: Record the echo for `sendOnce`'s existing `Nudge` call**

In `reactions.go`, locate:

```go
func (m *Manager) sendOnce(ctx context.Context, id domain.SessionID, prURL, key, sig, msg string, maxAttempts int) (sendOnceOutcome, error) {
```

Find the line `outcome, err := m.guard.Nudge(ctx, id, msg)` (line 844) and, immediately after its error check, before any other use of `outcome`, add:

```go
	if outcome == sessionguard.Sent {
		m.rememberCoordinationEcho(id, msg)
	}
```

Read the surrounding function first — do not disturb the existing `err != nil` handling above this line; only insert the new block after it, at the same indentation level as the existing code that inspects `outcome`.

- [ ] **Step 8: Run all the new tests**

```bash
cd backend && go test ./internal/lifecycle/ -v -run "TestApplyActivitySignal_(WorkerIdleNudges|NoOrchestrator|OrchestratorNeedsInput|OrchestratorZeroFirstSignal|OrchestratorActiveOn|OrchestratorEnteringIdle|TheNudgeIsNotStored)|TestDispatchInboxNudge|TestSendOnceReviewNudge"
```

Expected: PASS.

- [ ] **Step 9: Run the full package and gate**

```bash
cd backend && go test ./internal/lifecycle/
npm run lint
```

- [ ] **Step 10: Commit**

```bash
git add backend/internal/lifecycle/inbox.go \
        backend/internal/lifecycle/manager.go \
        backend/internal/lifecycle/reactions.go \
        backend/internal/lifecycle/manager_test.go
git commit -m "feat(lifecycle): dispatch the content-free inbox nudge, suppress its own echo

dispatchInboxNudge resolves the project's live orchestrator, applies the
same guard policy #2836 used (needs-input refuses, active refuses unless
the harness steers, zero FirstSignalAt refuses), and pastes
'[Operator] N inbox item(s). Run \`opr inbox\`.' through NudgeCoordination.
Delivery is serialized per project. Every coordination write this daemon
makes -- this nudge, the existing CI-failure and review-batch nudges --
now has its exact text remembered and stripped back out if the harness
echoes it as the session's own latestUserPrompt, closing the leak the
plan's premise review found in 3 of 5 known producers.

The duplicate-delivery regression test proves N repeated dispatch calls
for one pending event still resolve to exactly one digest and one acked
row -- this is the property that lets this feature be attempted a third
time after #3274/#3394.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Startup sweep and restore sweep

The restore sweep is already implemented by Task 4's `orchestratorReadyToDrain` (it fires whenever an orchestrator's `FirstSignalAt` transitions from zero, which is exactly "an orchestrator finishing restore"). Only the startup sweep remains.

**Files:**
- Modify: `backend/internal/lifecycle/inbox.go` (add `DispatchPendingInboxEventsOnStartup`)
- Modify: `backend/internal/daemon/daemon.go` (call it once after `lcStack.ReconcileRuntime`)
- Test: `backend/internal/lifecycle/inbox_test.go`

**Interfaces:**
- Consumes: `m.store.ListProjectsWithPendingInboxEvents`, `m.dispatchInboxNudge` (Task 4).
- Produces: `func (m *Manager) DispatchPendingInboxEventsOnStartup(ctx context.Context) error`.

- [ ] **Step 1: Write the failing test**

```go
func TestDispatchPendingInboxEventsOnStartup_AnnouncesEveryProjectWithPendingRows(t *testing.T) {
	m, st, msg := newManager()
	st.sessions["mer-2"] = orchestrator("mer-2", "mer")
	st.inboxEvents["evt-1"] = domain.OrchestratorInboxEvent{
		ID: "evt-1", ProjectID: "mer", WorkerID: "mer-1", Kind: domain.InboxEventWorkerIdle, State: domain.InboxStatePending,
	}

	if err := m.DispatchPendingInboxEventsOnStartup(ctx); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 1 || msg.ids[0] != "mer-2" {
		t.Fatalf("messenger calls = %+v / %+v, want one startup nudge to mer-2", msg.msgs, msg.ids)
	}
}

func TestDispatchPendingInboxEventsOnStartup_NoPendingRowsSendsNothing(t *testing.T) {
	m, _, msg := newManager()

	if err := m.DispatchPendingInboxEventsOnStartup(ctx); err != nil {
		t.Fatal(err)
	}
	if len(msg.msgs) != 0 {
		t.Fatalf("messenger calls = %v, want none", msg.msgs)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && go test ./internal/lifecycle/ -run TestDispatchPendingInboxEventsOnStartup -v
```

Expected: FAIL — undefined method.

- [ ] **Step 3: Implement**

Append to `inbox.go`:

```go
func (m *Manager) DispatchPendingInboxEventsOnStartup(ctx context.Context) error {
	projects, err := m.store.ListProjectsWithPendingInboxEvents(ctx)
	if err != nil {
		return err
	}
	for _, project := range projects {
		if err := m.dispatchInboxNudge(ctx, project); err != nil {
			return err
		}
	}
	return nil
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && go test ./internal/lifecycle/ -run TestDispatchPendingInboxEventsOnStartup -v
cd backend && go test ./internal/lifecycle/
```

- [ ] **Step 5: Wire the startup sweep into daemon boot**

In `daemon.go`, locate:

```go
	if reconcileErr := lcStack.ReconcileRuntime(ctx); reconcileErr != nil {
		log.Error("reconcile agent processes on boot failed", "err", reconcileErr)
	}
```

Add immediately after:

```go
	if sweepErr := lcStack.LCM.DispatchPendingInboxEventsOnStartup(ctx); sweepErr != nil {
		log.Error("dispatch pending inbox events on startup failed", "err", sweepErr)
	}
```

A failure here must not block daemon boot — same pattern as the `ReconcileRuntime` call immediately above it, which only logs. Confirm `lcStack.LCM`'s exported type is `*lifecycle.Manager` (it is — see `lifecycleStack.LCM`'s doc comment already read above) so this method is reachable.

- [ ] **Step 6: Run the full gate**

```bash
cd backend && go build ./...
npm run lint
```

- [ ] **Step 7: Commit**

```bash
git add backend/internal/lifecycle/inbox.go backend/internal/lifecycle/manager_test.go backend/internal/daemon/daemon.go
git commit -m "feat(daemon): sweep pending inbox events once at startup

A pending row written while the orchestrator was busy, or left over
across a daemon restart, would otherwise sit until some worker happens to
go idle again -- an already-idle orchestrator produces no transition to
fire on. The restore sweep (an orchestrator's first post-restart hook
signal) was already covered by orchestratorReadyToDrain in the previous
commit; this is the daemon-start half of spec section 7 step 5.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: HTTP wire surface

**Files:**
- Modify: `backend/internal/httpd/controllers/dto.go`
- Create: `backend/internal/httpd/controllers/inbox.go`
- Test: `backend/internal/httpd/controllers/inbox_test.go` (new, `package controllers` — needs the unexported `sessionView`)
- Modify: `backend/internal/httpd/api.go` (`APIDeps`, `API`, `NewAPI`, `Register`)
- Modify: `backend/internal/daemon/daemon.go` (pass `Inbox: lcStack.LCM` and `InboxSessions: sessionSvc` into `APIDeps`)
- Generated: `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`

**Interfaces:**
- Consumes: `lifecycle.Manager.ListPendingInboxEvents`/`AckInboxEvents` (Task 4); `sessionsvc.Manager.Get` (existing, already used by `SessionsController.get`); `sessionView` (existing unexported func in `controllers/sessions.go`).
- Produces: `GET /api/v1/projects/{id}/inbox`, `POST /api/v1/projects/{id}/inbox/ack`. Task 7 (CLI) hand-mirrors `InboxEntryView`, `InboxResponse`, `AckInboxEventsRequest`, `AckInboxEventsResponse`.

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/httpd/controllers/inbox_test.go`:

```go
package controllers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeInboxStore struct {
	events []domain.OrchestratorInboxEvent
	acked  []string
}

func (f *fakeInboxStore) ListPendingInboxEvents(_ context.Context, project domain.ProjectID) ([]domain.OrchestratorInboxEvent, error) {
	var out []domain.OrchestratorInboxEvent
	for _, ev := range f.events {
		if ev.ProjectID == project {
			out = append(out, ev)
		}
	}
	return out, nil
}

func (f *fakeInboxStore) AckInboxEvents(_ context.Context, _ domain.ProjectID, ids []string) (int, error) {
	f.acked = append(f.acked, ids...)
	return len(ids), nil
}

type fakeInboxSessions struct {
	sessions map[domain.SessionID]domain.Session
}

func (f *fakeInboxSessions) Get(_ context.Context, id domain.SessionID) (domain.Session, error) {
	sess, ok := f.sessions[id]
	if !ok {
		return domain.Session{}, ports.ErrSessionNotFound
	}
	return sess, nil
}

func TestInboxListResolvesEachEventAgainstTheLiveSessionRecord(t *testing.T) {
	worker := domain.Session{}
	worker.ID = "opr-1"
	worker.Metadata.LatestUserPrompt = "search for new iphone 18"
	worker.Metadata.LatestAssistantUpdate = "Here is what I found."

	c := &InboxController{
		Events:   &fakeInboxStore{events: []domain.OrchestratorInboxEvent{{ID: "evt-1", ProjectID: "proj-1", WorkerID: "opr-1", Kind: domain.InboxEventWorkerIdle}}},
		Sessions: &fakeInboxSessions{sessions: map[domain.SessionID]domain.Session{"opr-1": worker}},
	}
	r := chi.NewRouter()
	c.Register(r)

	req := httptest.NewRequest(http.MethodGet, "/projects/proj-1/inbox", nil)
	rr := httptest.NewRecorder()
	r.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rr.Code, rr.Body.String())
	}
	var res InboxResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &res); err != nil {
		t.Fatal(err)
	}
	if len(res.Entries) != 1 || res.Entries[0].Worker.LatestUserPrompt != "search for new iphone 18" {
		t.Fatalf("entries = %+v", res.Entries)
	}
}

func TestInboxAckIsANoopForUnknownIds(t *testing.T) {
	store := &fakeInboxStore{}
	c := &InboxController{Events: store, Sessions: &fakeInboxSessions{sessions: map[domain.SessionID]domain.Session{}}}
	r := chi.NewRouter()
	c.Register(r)

	body := strings.NewReader(`{"ids":["unknown-1"]}`)
	req := httptest.NewRequest(http.MethodPost, "/projects/proj-1/inbox/ack", body)
	rr := httptest.NewRecorder()
	r.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rr.Code, rr.Body.String())
	}
}
```

`ports.ErrSessionNotFound` (`internal/ports/session.go:10`) is the sentinel `sessionsvc.Manager.Get` returns for an unknown id — the same one `sessions.go:439`'s `get` handler relies on via `envelope.WriteError`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && go test ./internal/httpd/controllers/ -run TestInbox -v
```

Expected: build failure — `InboxController` undefined.

- [ ] **Step 3: Add the DTOs**

In `dto.go`, after `SessionView`/`ListSessionsResponse`:

```go
type InboxEntryView struct {
	ID         string      `json:"id"`
	Kind       string      `json:"kind" enum:"worker_idle,ci_failed,review_changes_requested"`
	OccurredAt time.Time   `json:"occurredAt"`
	Worker     SessionView `json:"worker"`
}

type InboxResponse struct {
	Entries []InboxEntryView `json:"entries"`
}

type AckInboxEventsRequest struct {
	IDs []string `json:"ids"`
}

type AckInboxEventsResponse struct {
	Acked int `json:"acked"`
}
```

Check whether `dto.go` already imports `time` (it does, `SessionRecord`/other DTOs use `time.Time` throughout this file).

- [ ] **Step 4: Write the controller**

Create `backend/internal/httpd/controllers/inbox.go`:

```go
package controllers

import (
	"context"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
)

type InboxEventStore interface {
	ListPendingInboxEvents(ctx context.Context, project domain.ProjectID) ([]domain.OrchestratorInboxEvent, error)
	AckInboxEvents(ctx context.Context, project domain.ProjectID, ids []string) (int, error)
}

type InboxSessionReader interface {
	Get(ctx context.Context, id domain.SessionID) (domain.Session, error)
}

type InboxController struct {
	Events   InboxEventStore
	Sessions InboxSessionReader
}

func (c *InboxController) Register(r chi.Router) {
	r.Get("/projects/{id}/inbox", c.list)
	r.Post("/projects/{id}/inbox/ack", c.ack)
}

func (c *InboxController) list(w http.ResponseWriter, r *http.Request) {
	if c.Events == nil || c.Sessions == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/projects/{id}/inbox")
		return
	}
	events, err := c.Events.ListPendingInboxEvents(r.Context(), projectID(r))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	entries := make([]InboxEntryView, 0, len(events))
	for _, ev := range events {
		sess, err := c.Sessions.Get(r.Context(), ev.WorkerID)
		if err != nil {
			continue
		}
		entries = append(entries, InboxEntryView{
			ID: ev.ID, Kind: string(ev.Kind), OccurredAt: ev.OccurredAt, Worker: sessionView(sess),
		})
	}
	envelope.WriteJSON(w, http.StatusOK, InboxResponse{Entries: entries})
}

func (c *InboxController) ack(w http.ResponseWriter, r *http.Request) {
	if c.Events == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/inbox/ack")
		return
	}
	var req AckInboxEventsRequest
	if err := decodeJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	acked, err := c.Events.AckInboxEvents(r.Context(), projectID(r), req.IDs)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, AckInboxEventsResponse{Acked: acked})
}
```

A worker whose session was deleted (FK cascade should prevent this, but guard anyway) is silently skipped from the digest rather than erroring the whole list — an orphaned inbox row for a gone session is not actionable and should not break the read.

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd backend && go test ./internal/httpd/controllers/ -run TestInbox -v
```

- [ ] **Step 6: Wire into `APIDeps`/`API`**

In `api.go`:
- Add to `APIDeps`: `Inbox controllers.InboxEventStore` and `InboxSessions controllers.InboxSessionReader`.
- Add to `API` struct: `inbox *controllers.InboxController`.
- In `NewAPI`: `inbox: &controllers.InboxController{Events: deps.Inbox, Sessions: deps.InboxSessions},`.
- In `Register`, inside the existing `r.Group(func(r chi.Router) { ... })` REST block, add `a.inbox.Register(r)` next to `a.projects.Register(r)`.

In `daemon.go`, in the `httpd.APIDeps{...}` literal, add:

```go
		Inbox:         lcStack.LCM,
		InboxSessions: sessionSvc,
```

`lcStack.LCM` (`*lifecycle.Manager`) satisfies `controllers.InboxEventStore` structurally via the two methods Task 4 added. `sessionSvc` already satisfies `controllers.SessionService`, which is a superset containing `Get(ctx, id) (domain.Session, error)` — confirm it structurally satisfies the narrower `InboxSessionReader` too (it will, Go interfaces are structural).

- [ ] **Step 7: Run the drift gate and regenerate the API artifacts**

```bash
cd backend && go test ./internal/httpd/...
npm run api
git diff --stat backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
```

Expected: both files show the new paths/schemas. If `npm run api` reports an unnamed-schema error for `InboxEntryView`/`InboxResponse`/etc., add the entries it names to `specgen/build.go`'s `schemaNames` map (pattern: `"ControllersInboxEntryView": "InboxEntryView"`, etc.) and rerun.

- [ ] **Step 8: Run the full gate**

```bash
npm run lint
```

- [ ] **Step 9: Commit**

```bash
git add backend/internal/httpd/controllers/dto.go \
        backend/internal/httpd/controllers/inbox.go \
        backend/internal/httpd/controllers/inbox_test.go \
        backend/internal/httpd/api.go \
        backend/internal/daemon/daemon.go \
        backend/internal/httpd/apispec/openapi.yaml \
        frontend/src/api/schema.ts
git commit -m "feat(api): add GET /projects/{id}/inbox and POST /projects/{id}/inbox/ack

Rows carry no digest content (spec section 6); the controller resolves
each pending event against the live session record through the same
sessionView() Phase 0 already built, so a digest is never stale and PR/CI
state is never duplicated storage.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: `opr inbox` and `opr inbox ack`

**Files:**
- Create: `backend/internal/cli/inbox.go`
- Create: `backend/internal/cli/inbox_test.go`
- Modify: `backend/internal/cli/root.go` (register after `newBoardCommand`)

**Interfaces:**
- Consumes: `c.getJSON`/`c.postJSON`, `apiPath`, `c.resolveBoardProject` (all existing, `board.go`/`client.go`/`session.go`), `sessionDTO`/`sessionPRDTO` (existing, `session.go`), `writeJSON`, `usageError`.
- Produces: `newInboxCommand(ctx *commandContext) *cobra.Command` with a `ack` subcommand.

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/cli/inbox_test.go`:

```go
package cli

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestInboxRendersPendingDigestsWithAckLine(t *testing.T) {
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"entries":[
			{"id":"evt-1","kind":"worker_idle","occurredAt":"2026-09-12T10:00:00Z",
			 "worker":{"id":"opr-1","projectId":"proj-1","kind":"worker","displayName":"resize fix","status":"idle",
			 "activity":{"state":"idle"},"brief":"fix the resize bug","latestUserPrompt":"also check codex",
			 "latestAssistantUpdate":"Pushed a fix.",
			 "prs":[{"url":"u","number":7,"state":"open","ci":"failing","review":"none"}]}}
		]}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "inbox", "--project", "proj-1")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"evt-1", "worker_idle", "opr-1", "resize fix", "also check codex", "Pushed a fix.", "#7 open ci=failing", "opr inbox ack evt-1"} {
		if !strings.Contains(out, want) {
			t.Fatalf("output missing %q:\n%s", want, out)
		}
	}
}

func TestInboxReportsAnEmptyInbox(t *testing.T) {
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"entries":[]}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "inbox", "--project", "proj-1")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, "(no pending inbox items)") {
		t.Fatalf("output = %q", out)
	}
}

func TestInboxAckSendsTheGivenIds(t *testing.T) {
	cfg := setConfigEnv(t)
	var gotBody string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		gotBody = string(body)
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"acked":2}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "inbox", "ack", "--project", "proj-1", "evt-1", "evt-2")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(gotBody, "evt-1") || !strings.Contains(gotBody, "evt-2") {
		t.Fatalf("request body = %q", gotBody)
	}
	if !strings.Contains(out, "acked 2") {
		t.Fatalf("output = %q", out)
	}
}

func TestInboxAckIsANoopWithoutError(t *testing.T) {
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"acked":0}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	_, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "inbox", "ack", "--project", "proj-1", "already-acked")
	if err != nil {
		t.Fatalf("ack of an unknown/already-acked id must not error: %v", err)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && go test ./internal/cli/ -run TestInbox -v
```

Expected: FAIL — `unknown command "inbox"`.

- [ ] **Step 3: Write `inbox.go`**

```go
package cli

import (
	"context"
	"fmt"
	"net/url"
	"time"

	"github.com/spf13/cobra"
)

type inboxOptions struct {
	project string
	json    bool
}

type inboxEntryDTO struct {
	ID         string     `json:"id"`
	Kind       string     `json:"kind"`
	OccurredAt time.Time  `json:"occurredAt"`
	Worker     sessionDTO `json:"worker"`
}

type inboxListResponse struct {
	Entries []inboxEntryDTO `json:"entries"`
}

type inboxAckRequest struct {
	IDs []string `json:"ids"`
}

type inboxAckResponse struct {
	Acked int `json:"acked"`
}

func newInboxCommand(ctx *commandContext) *cobra.Command {
	var opts inboxOptions
	cmd := &cobra.Command{
		Use:   "inbox",
		Short: "Show pending worker-idle digests for this project",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return ctx.showInbox(cmd.Context(), cmd, opts)
		},
	}
	cmd.Flags().StringVar(&opts.project, "project", "", "Project id (defaults to the current session's project)")
	cmd.Flags().BoolVar(&opts.json, "json", false, "Output as JSON")
	cmd.AddCommand(newInboxAckCommand(ctx))
	return cmd
}

func newInboxAckCommand(ctx *commandContext) *cobra.Command {
	var project string
	cmd := &cobra.Command{
		Use:   "ack <id> [<id>...]",
		Short: "Acknowledge one or more inbox items",
		Args:  usageArgs(cobra.MinimumNArgs(1)),
		RunE: func(cmd *cobra.Command, args []string) error {
			return ctx.ackInbox(cmd.Context(), cmd, project, args)
		},
	}
	cmd.Flags().StringVar(&project, "project", "", "Project id (defaults to the current session's project)")
	return cmd
}

func (c *commandContext) showInbox(ctx context.Context, cmd *cobra.Command, opts inboxOptions) error {
	project, err := c.resolveBoardProject(ctx, opts.project)
	if err != nil {
		return err
	}
	var res inboxListResponse
	if err := c.getJSON(ctx, apiPath("projects/"+url.PathEscape(project)+"/inbox", nil), &res); err != nil {
		return err
	}
	if opts.json {
		return writeJSON(cmd.OutOrStdout(), res)
	}
	return writeInbox(cmd, res.Entries)
}

func (c *commandContext) ackInbox(ctx context.Context, cmd *cobra.Command, projectFlag string, ids []string) error {
	project, err := c.resolveBoardProject(ctx, projectFlag)
	if err != nil {
		return err
	}
	var res inboxAckResponse
	if err := c.postJSON(ctx, "projects/"+url.PathEscape(project)+"/inbox/ack", inboxAckRequest{IDs: ids}, &res); err != nil {
		return err
	}
	_, err = fmt.Fprintf(cmd.OutOrStdout(), "acked %d\n", res.Acked)
	return err
}

func writeInbox(cmd *cobra.Command, entries []inboxEntryDTO) error {
	out := cmd.OutOrStdout()
	if len(entries) == 0 {
		_, err := fmt.Fprintln(out, "(no pending inbox items)")
		return err
	}
	var ids []string
	for i, e := range entries {
		if i > 0 {
			if _, err := fmt.Fprintln(out); err != nil {
				return err
			}
		}
		w := e.Worker
		header := fmt.Sprintf("%s  %s", e.ID, e.Kind)
		if w.ID != "" {
			header += "  " + w.ID
		}
		if w.DisplayName != "" {
			header += "  " + w.DisplayName
		}
		if _, err := fmt.Fprintln(out, header); err != nil {
			return err
		}
		for _, line := range [][2]string{
			{"brief", w.Brief},
			{"last prompt", w.LatestUserPrompt},
			{"last update", w.LatestAssistantUpdate},
		} {
			if line[1] == "" {
				continue
			}
			if _, err := fmt.Fprintf(out, "  %s: %s\n", line[0], line[1]); err != nil {
				return err
			}
		}
		for _, pr := range w.PRs {
			if _, err := fmt.Fprintf(out, "  #%d %s ci=%s review=%s\n", pr.Number, pr.State, pr.CI, pr.Review); err != nil {
				return err
			}
		}
		ids = append(ids, e.ID)
	}
	if _, err := fmt.Fprintln(out); err != nil {
		return err
	}
	_, err := fmt.Fprintf(out, "opr inbox ack %s\n", joinArgs(ids))
	return err
}

func joinArgs(ids []string) string {
	out := ""
	for i, id := range ids {
		if i > 0 {
			out += " "
		}
		out += id
	}
	return out
}
```

Check whether a `joinArgs`-shaped helper (or `strings.Join`) is already used elsewhere in this package under a different name — if `strings.Join(ids, " ")` suffices (it does), drop the custom `joinArgs` function entirely and use `strings.Join` directly, adding `"strings"` to the import block instead. The custom loop above is only a fallback if for some reason `strings.Join` is disallowed by a lint rule in this repo, which is unlikely — prefer the standard library call.

Register in `root.go`, beside `newBoardCommand`:

```go
	root.AddCommand(newInboxCommand(ctx))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && go test ./internal/cli/ -run TestInbox -v
cd backend && go test ./internal/cli/
```

- [ ] **Step 5: Run the full gate**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
git add backend/internal/cli/inbox.go backend/internal/cli/inbox_test.go backend/internal/cli/root.go
git commit -m "feat(cli): add opr inbox and opr inbox ack

opr inbox resolves the project from OPERATOR_SESSION_ID the same way opr
board does, renders each pending digest with its worker's brief/last
prompt/last update/PR state, and ends its human-readable output with a
ready-to-paste ack line so an event landing between read and ack is never
swallowed (spec section 8). Acking an unknown or already-acked id is a
no-op, not an error.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Prompt pull protocol and stale-comment cleanup

**Files:**
- Modify: `backend/internal/session_manager/prompt.go` (Core Commands list, Coordination Workflow list)
- Modify: `backend/internal/session_manager/prompt_test.go`
- Modify: `backend/internal/lifecycle/manager.go:30` (delete the stale comment)

**Interfaces:**
- Consumes: nothing new — text only.
- Produces: no Go API change.

- [ ] **Step 1: Write the failing test**

Add to `prompt_test.go`:

```go
func TestOrchestratorPromptTeachesThePullProtocol(t *testing.T) {
	got := orchestratorSystemPrompt(promptProject{ID: "proj-1", Name: "Operator"})

	for _, want := range []string{
		"`opr inbox`",
		"`opr inbox ack",
		"empty inbox is a normal outcome",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("prompt missing %q:\n%s", want, got)
		}
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && go test ./internal/session_manager/ -run TestOrchestratorPromptTeachesThePullProtocol -v
```

Expected: FAIL.

- [ ] **Step 3: Add the pull protocol to the prompt**

In `orchestratorSystemPrompt`, in the Core Commands list (right after the `opr board` bullet added in Phase 0), add:

```go
- `+"`opr inbox`"+` - pending worker-idle digests for this project. You are nudged with a bare count; always call this to see what changed, never act on the nudge text alone.
- `+"`opr inbox ack <id> [<id>...]`"+` - acknowledge inbox items after acting on them. An empty inbox is a normal outcome: end your turn without action rather than inventing work.
```

In the Coordination Workflow list, add a new first step (renumbering the rest) or append as a new step describing the pull-act-ack cycle — read the existing numbered list first and pick whichever keeps it coherent as a sequence; do not just append disconnected text. A reasonable placement: after existing step 1 (`Inspect current state with opr board`), insert:

```go
2. On a `[Operator] N inbox item(s)` nudge, run `opr inbox`, act on what changed, then run `opr inbox ack` for everything you acted on. If the inbox is empty, end the turn.
```

renumbering subsequent steps accordingly.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && go test ./internal/session_manager/ -run TestOrchestratorPrompt -v
cd backend && go test ./internal/session_manager/
```

Expected: PASS. If an existing test asserts the old numbered workflow list verbatim, update its expected text to match the renumbering — do not weaken what it checks, only its numbers.

- [ ] **Step 5: Delete the stale comment**

In `manager.go:30`, delete the comment referencing "the dispatcher reads it" (the exact line the spec names, in `ListSessions`'s doc comment) — Task 4/5 is the change that touches this interface, satisfying the spec's "delete in whichever phase first touches that interface."

- [ ] **Step 6: Run the full gate**

```bash
npm run lint
```

- [ ] **Step 7: Update the spec to record what shipped**

In `docs/superpowers/specs/2026-09-11-autonomous-orchestrator-design.md`, under §14 Phase 1, mark it done and note the coordination-echo mechanism added beyond the original scope, with a one-line pointer to this plan.

- [ ] **Step 8: Commit**

```bash
git add backend/internal/session_manager/prompt.go \
        backend/internal/session_manager/prompt_test.go \
        backend/internal/lifecycle/manager.go \
        docs/superpowers/specs/2026-09-11-autonomous-orchestrator-design.md
git commit -m "fix(prompt): teach the orchestrator the inbox pull protocol

opr inbox, act, opr inbox ack -- and explicitly that an empty inbox is a
normal outcome whose correct response is ending the turn, which is what
makes duplicate nudges cheap rather than something the orchestrator
escalates on (spec section 9).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Verification before calling Phase 1 done

- [ ] `npm run lint` passes from the repo root, `0 issues.`
- [ ] `cd backend && go test ./internal/httpd/...` passes (spec drift).
- [ ] `git diff --stat` on `openapi.yaml` and `frontend/src/api/schema.ts` shows only the inbox additions.
- [ ] End-to-end against an isolated daemon (never the user's `~/.operator`, pid 97452):

  ```bash
  cd backend && go build -o /tmp/opr-phase1 ./cmd/opr
  mkdir -p /tmp/opr-phase1-data
  OPERATOR_DATA_DIR=/tmp/opr-phase1-data OPERATOR_RUN_FILE=/tmp/opr-phase1-data/run.json /tmp/opr-phase1 daemon &
  ```

  Seed a project, an orchestrator session, and a worker session directly with `sqlite3` against `/tmp/opr-phase1-data/opr.db` (mirror Phase 0's exact seeding recipe from its plan's Verification section — same columns, same pattern, this time also giving the orchestrator a non-zero `first_signal_at` and the worker `activity_state='active'`). Then:

  1. Flip the worker's activity to idle through the real HTTP path (not a raw SQL update) so the reducer actually runs: `curl -X POST localhost:<port>/api/v1/sessions/<worker-id>/activity -d '{"valid":true,"state":"idle","event":"stop"}'` (check the real request shape the `opr hooks`-driven endpoint expects, in `sessions.go`'s activity handler, rather than guessing the JSON keys).
  2. Confirm exactly one row landed: `sqlite3 /tmp/opr-phase1-data/opr.db "select id,kind,state from orchestrator_inbox;"`.
  3. Confirm the orchestrator's pane received the nudge (however this daemon build surfaces sent messages without a real PTY attached — check what `ports.AgentMessenger` resolves to for a session with no live runtime process in this setup; if no messenger is wired without a real runtime, note that explicitly rather than fabricating a result).
  4. `OPERATOR_DATA_DIR=/tmp/opr-phase1-data /tmp/opr-phase1 inbox --project <project-id>` shows the digest.
  5. `OPERATOR_DATA_DIR=/tmp/opr-phase1-data /tmp/opr-phase1 inbox ack <event-id>` clears it; a repeat `opr inbox` shows `(no pending inbox items)`.
  6. Re-flip the same worker active→idle→active→idle to prove coalescing holds against the real database, not just the fake.
  7. `opr stop` (or send the process a clean shutdown signal) against **this** isolated daemon only.

  Paste the actual output for every step. If step 3 cannot be verified without a real PTY-backed session (likely, since this setup seeds rows directly rather than spawning a real agent), say so explicitly and verify what real code path *is* reachable (the DB write, the guard's decision given the seeded session state, the CLI round-trip) rather than skipping the whole check silently.

- [ ] Confirm the orchestrator's own `latestUserPrompt` is never the nudge text after a real nudge: `sqlite3 /tmp/opr-phase1-data/opr.db "select id, latest_user_prompt from sessions where kind='orchestrator';"` — paste the query and result.
