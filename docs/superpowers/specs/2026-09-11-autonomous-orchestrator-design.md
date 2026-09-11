# Autonomous Orchestrator — Design

**Date:** 2026-09-11
**Status:** Approved design, not yet implemented
**Goal:** Turn the orchestrator session from a passive prompt the human drives into a self-driving coordinator that manages several worker sessions unattended.

## 1. Problem

The orchestrator today is a prompt, not a system. It runs the same machinery as a
worker — same PTY, same harness, same worktree — differing only in system prompt,
promptlessness, and branch (`backend/internal/session_manager/manager.go:2689`,
`:1325`, `:2614`). It has no tools of its own: its entire capability surface is
the underlying agent's tools plus the `opr` CLI it shells out to.

Three defects block it from replacing the human coordinator:

**It is blind.** No command returns a worker's output. `opr session get` yields
id, kind, harness, displayName, `activity.state`, timestamps, status
(`backend/internal/cli/session.go:43`). Step 5 of the orchestrator's own
documented workflow — "monitor worker output, PR state, CI, and reviews" — is
not achievable with the surface it has. It can only distinguish *active* from
*idle*.

**It is deaf.** Exactly one push into an orchestrator exists in the codebase: a
request to pick a ≤20-character session title
(`backend/internal/service/session/delegation.go:120`). Meanwhile
`backend/internal/lifecycle/reactions.go` already reacts autonomously to CI
failures, review verdicts, PR comments and tracker facts — and routes them to the
**worker** and the **human**, never the orchestrator. Worker `stop` hooks exist
for every harness and only write a DB row. The orchestrator therefore acts only
when the human types into it, which is the exact behavior we are trying to
eliminate.

**Its prompt overstates its sensors.** The prompt tells it `opr status` inspects
"project, session, PR, and review state" and makes that step 1 of its workflow.
`backend/internal/cli/status.go:77` returns daemon health only — pid, port,
uptime, dataDir. Step 1 returns nothing about the work.

A consequence worth stating plainly: the orchestrator's most-exercised function
in production today is generating session titles. The desktop "new task" button
spawns the worker itself and then asks the orchestrator to rename it after the
fact — the orchestrator is not in the delegation decision at all.

## 2. Prior art — this was built twice and removed twice

**Read this section before implementing anything.** Two prior attempts at
orchestrator wake-up exist in history and survive only as drop migrations.

| Attempt | Design | Outcome |
| --- | --- | --- |
| `worker_idle_events` (#2836) | Durable outbox. Worker active→idle wrote an event atomically with the activity transition. Per-project dispatch lock. At-most-one delivery per orchestrator turn to drain a backlog. `safeToDeliver` gating. Coalescing via unique partial index on `worker_id WHERE delivery_state='pending'`. | Removed by #3257, "remove worker idle orchestrator nudges" |
| `orchestrator_reengagements` (#3274) | Retry/backoff loop: `attempt_count`, `next_attempt_at`, `progress_since_attempt`, `state IN (active, completed, exhausted)`, exhausted → notify human. Added an `orchestratorloop` manager, a `/complete` endpoint, and an `ao orchestrator done` command. | Reverted by #3394: **"fired repeatedly at orchestrator sessions (3-4 duplicates in a row)"** |

Schema remnants: `backend/internal/storage/sqlite/migrations/0037_drop_worker_idle_outbox.sql`,
`0039_drop_orchestrator_reengagement.sql`. A stale comment on
`lifecycle.sessionStore.ListSessions` still refers to "the dispatcher"
(`backend/internal/lifecycle/manager.go:30`) — a leftover from the removed
dispatcher, worth deleting when this lands.

These PR numbers are upstream's, from before the rebrand; this repository is an
inherited clone, so the written rationale for #3257 is not recoverable here.
#3394's is.

The first attempt was **not naive**. It already had the durable outbox, the
atomic write, the coalescing index and the backlog draining that a careful
designer would reach for. It was still pulled. Any new attempt that merely
rebuilds a better outbox should be expected to fail the same way.

## 3. Root cause and the governing design principle

Both attempts built increasingly sophisticated outboxes on top of an
**unreliable delivery primitive**.

`opr send` injects keystrokes into a PTY. There is no delivery acknowledgement:
it returns 200 the moment the runtime accepts bytes. Because a large multiline
paste may not submit, `sendConfirm` deliberately **re-sends Enter up to three
times**, watching the durable activity state to infer submission
(`backend/internal/session_manager/manager.go:395`–`:418`).

So one logical nudge can already become up to three physical prompts before any
retry layer is added. Layer a re-engagement loop on top and 3–4 duplicates is
the expected outcome, not a bug — which is exactly what #3394 observed.

Exactly-once delivery into a PTY is not achievable. Therefore:

> **Principle: make delivery idempotent instead of exact.**
> The message pushed to the orchestrator carries **no content** — only a count.
> The orchestrator **pulls** the state it needs and **acknowledges** what it
> consumed. A duplicate nudge then drains an already-acked inbox, the
> orchestrator reads nothing new, and the cost is one cheap no-op turn rather
> than a duplicated action.

At-least-once delivery becomes safe by construction. This is the single
difference between this design and the two that were reverted, and every
component below exists to serve it.

## 4. Decisions taken

Recorded because they constrain the design and were chosen deliberately.

| Decision | Choice | Consequence |
| --- | --- | --- |
| Wake policy | **Every worker turn-end** (any worker crossing to idle) | Maximum awareness. Same trigger as the reverted `crossedToIdle`; idempotency is what makes it viable now. Makes durable state load-bearing, since context fills fast. |
| Autonomy | **Full, within a budget** | Orchestrator spawns, redirects and kills workers without asking. Human is notified, not consulted. |
| Budget | Per-project cap on live workers and spawns-per-hour | Enforced daemon-side, not by prompt. On exhaustion it queues and reports. |
| Merge | **Never on its own initiative; permitted when the human explicitly instructs it** | Soft control (see §10). |
| Cost ceiling | **Declined** | Accepted risk, recorded in §11. |
| Killing dirty workers | **Permitted** | Partially mitigated by the existing repo rule against force-deleting dirty registered worktrees. |

## 5. Architecture

Four components. Three are new; one is a correction.

```
worker turn-end (crossedToIdle)
  │
  ├─► lifecycle reducer ──► orchestrator_inbox (pending row, coalesced per worker)
  │                              │
  │                              ├─► content-free nudge via AgentMessenger
  │                              │     "[Operator] N inbox item(s). Run `opr inbox`."
  │                              ▼
  │                        orchestrator session (PTY)
  │                              │
  │                              ├─ opr inbox         → digests (pull)
  │                              ├─ opr inbox ack ID  → mark consumed
  │                              ├─ opr board         → full project picture (memory)
  │                              └─ opr spawn/send/kill → bounded by the leash
  ▼
existing worker-directed reactions (CI, review) — unchanged
```

**5.1 The inbox (ears + memory).** A durable table of pending events per
project. Written by the lifecycle reducer in the same transaction as the
activity change, so a crash cannot persist idle-ness while losing the event.
Coalesced: at most one pending row per worker, so a worker flapping
idle→active→idle does not queue three items.

The inbox doubles as the memory fix. An orchestrator relaunches fresh with only
its system prompt and never resumes (`manager.go:1325`, `:3401`); the inbox and
`opr board` are durable state it can re-read after relaunch, so its knowledge is
re-derivable rather than lost.

**5.2 The digest (eyes).** `opr inbox` returns, per event: worker id, display
name, the **task brief**, activity state, age, capped `latestAssistantUpdate`,
and PR/CI summary. Nearly all of this is already persisted and merely unexposed —
`LatestUserPrompt` and `LatestAssistantUpdate` are captured on every hook and
stored (`backend/internal/httpd/controllers/dto.go:892`,
`backend/internal/storage/sqlite/gen/models.go:300`), and
`session_manager/handoff_artifact.go` already builds session-state summaries from
them for handoffs. This is a read path over existing data, not a new capture
pipeline.

**5.3 The board (memory on demand).** `opr board` renders the whole project work
state in one read: every live worker with its brief, activity, PRs, CI and review
status. This is what the prompt currently, falsely, promises from `opr status`.
`opr status` keeps its existing daemon-health contract unchanged; the prompt is
corrected to point at `opr board`.

**5.4 The leash.** Budget enforced in the spawn service, not the prompt. A
prompt rule is not a limit. Orchestrator-initiated spawns are identified by
`OPERATOR_SESSION_ID` resolving to an orchestrator session — the same signal
`cliInvocationActorType` already uses (`backend/internal/cli/root.go`). Over
budget returns a typed error the orchestrator can act on.

## 6. Data model

New migration `0105_orchestrator_inbox.sql` (latest merged is 0104). Already-merged
migrations are immutable per `AGENTS.md`; queries go in
`backend/internal/storage/sqlite/queries/orchestrator_inbox.sql` and generated code
comes from `npm run sqlc` — never hand-edited.

```sql
CREATE TABLE orchestrator_inbox (
    id          TEXT PRIMARY KEY,
    project_id  TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    worker_id   TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    kind        TEXT NOT NULL CHECK (kind IN ('worker_idle','ci_failed','review_changes_requested','worker_blocked')),
    occurred_at TIMESTAMP NOT NULL,
    state       TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','acked')),
    acked_at    TIMESTAMP,
    created_at  TIMESTAMP NOT NULL,
    updated_at  TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX idx_orchestrator_inbox_pending_worker
    ON orchestrator_inbox(worker_id, kind) WHERE state = 'pending';

CREATE INDEX idx_orchestrator_inbox_pending_project
    ON orchestrator_inbox(project_id) WHERE state = 'pending';
```

The unique partial index is the coalescing mechanism, carried over from #2836
where it was sound. Note it is keyed on `(worker_id, kind)`, not `worker_id`
alone: a worker may legitimately have both a pending idle and a pending CI
failure.

Rows carry **no digest content**. Content is resolved at read time from the
session record, so a digest is never stale and the table stays small.

Retention: acked rows go when their session does, via `ON DELETE CASCADE`. There
is no generic table pruner in this codebase — `queries/cleanup.sql` is
session-cleanup-specific — so the query set includes an explicit
`DeleteAckedInboxEventsBefore` that the ack path calls to drop acked rows older
than seven days. Bounded growth is a property of the coalescing index, not of
retention.

## 7. Delivery protocol

This is the core of the design; it is what the two reverted attempts got wrong.

1. Worker crosses active→idle (`crossedToIdle` semantics: from `active`
   specifically, so the spawn-time idle seed and `waiting_input`→`idle`
   demotions do not fire). Reducer inserts a pending row **in the same write as
   the activity change**, ignoring conflict on the coalescing index.
2. Reducer resolves the project's live orchestrator. If none, or if it is not
   safe to deliver to (`cannotNudge`: terminated, needs input, exited —
   `reactions.go:579`), stop. The row stays pending; no retry is scheduled.
3. Send a **content-free nudge**: `[Operator] N inbox item(s). Run `opr inbox`.`
   One line. It carries no digest, so duplicates cost almost nothing in context.
4. Orchestrator runs `opr inbox`, receives digests, acts, then runs
   `opr inbox ack <id>...`.
5. **No retry loop, ever.** Pending rows are re-announced opportunistically when
   the orchestrator next enters idle — #2836's `orchestratorDispatchTrigger`,
   which drains a backlog one nudge per turn.

   This is not a retry, and the distinction is load-bearing: re-announcing is
   **event-driven and stateless** — it fires on a state transition that already
   happens, carries no attempt counter, sets no timer, and escalates nothing. A
   retry loop is **time-driven and stateful**: it remembers that delivery
   "failed", schedules a next attempt, and gives up after N. The latter is what
   #3274 built and #3394 reverted. Nothing in this design may count attempts,
   store a `next_attempt_at`, or escalate an undelivered event.

Why this is safe under duplicate delivery: a duplicate nudge causes one extra
`opr inbox` call, which returns nothing pending, and the orchestrator's turn
ends. The failure mode degrades from "duplicated action" to "one wasted cheap
turn".

Delivery is serialized per project so overlapping triggers cannot both announce
the same state — carried over from #2836's dispatch lock.

## 8. Wire and CLI surface

The CLI stays a thin client over daemon HTTP; no direct storage access
(`AGENTS.md`). New DTOs go in `controllers/dto.go` with `schemaNames` entries in
`apispec/specgen/build.go`, and `npm run api` regenerates `openapi.yaml` and
`frontend/src/api/schema.ts`, committed together with the Go changes.

| Endpoint | CLI | Purpose |
| --- | --- | --- |
| `GET /api/v1/projects/{id}/inbox` | `opr inbox [--json]` | Pending digests |
| `POST /api/v1/projects/{id}/inbox/ack` | `opr inbox ack <id>...` | Mark consumed |
| `GET /api/v1/projects/{id}/board` | `opr board [--json]` | Full work state |

Errors preserve the existing envelope and `requestId`. Usage errors return
`usageError` so misuse exits 2 and runtime failures exit 1.

Budget rejection reuses the standard envelope with a machine-readable code,
`ORCHESTRATOR_BUDGET_EXHAUSTED`, and a message naming the limit hit and when it
resets, so the orchestrator can queue intelligently rather than retry blindly.

Project config gains `orchestrator.maxLiveWorkers` and
`orchestrator.maxSpawnsPerHour` on the existing `RoleOverride` structure
(`backend/internal/domain/projectconfig.go:47`).

## 9. Prompt changes

`orchestratorSystemPrompt` in `backend/internal/session_manager/prompt.go:179`:

- **Correct the `opr status` claim.** Point project/session/PR/review inspection
  at `opr board`.
- **Add the pull protocol.** On a nudge: `opr inbox`, act, `opr inbox ack`. State
  explicitly that an empty inbox is a normal outcome and the correct response is
  to end the turn without action — this is what makes duplicates cheap, so it
  must be in the prompt, not merely in the code.
- **Add the budget.** On `ORCHESTRATOR_BUDGET_EXHAUSTED`, queue the work, report
  to the human, do not retry in a loop.
- **Rewrite the delegation rules for autonomy.** The current prompt is
  overwhelmingly prohibitive — never edit, never commit, never push, never open
  PRs, never claim a PR. Those stay, but the affirmative half must now authorize
  acting without asking: spawn, redirect and kill on its own judgment.
- **Add the merge boundary.** Never merge on its own initiative; merging is
  permitted when the human has explicitly instructed it.
- **Teach `opr session handoff`.** Dropped from scope: `opr pr merge`
  (initiative-bounded above), `opr review *` (already handled autonomously by
  lifecycle), and any task-queue command (see §12).

The confidentiality guard (`systemPromptGuard`) is unchanged and still applies.

## 10. Enforcement honesty

Which controls are real and which are advisory, stated plainly so nobody
mistakes a prompt rule for a guarantee:

- **Hard (daemon-enforced):** the worker cap and spawn rate. Refused in the
  spawn service; the orchestrator cannot talk its way past them.
- **Hard (pre-existing):** `AGENTS.md` forbids force-deleting dirty registered
  worktrees, so a kill cannot silently destroy a dirty worktree even though the
  orchestrator is allowed to kill workers.
- **Soft (prompt only):** the merge boundary. Because merging *is* permitted
  when the human instructs it, no mechanical check can separate an authorized
  merge from an unauthorized one without losing the authorized case. This is a
  deliberate trade, and the residual risk is an autonomous merge if the model
  misreads intent.

## 11. Risks

- **Third revert.** Mitigated by §3's idempotency and by the explicit ban on
  retry loops in §7. The regression test in §13 exists specifically to hold this.
- **Context exhaustion.** Per-turn wake-up on N workers fills the orchestrator's
  context. Mitigated by content-free nudges, on-demand pulling, and `opr board`
  making state re-derivable after a relaunch. Not eliminated — a long-running
  orchestrator will still be relaunched, and that is now a recoverable event
  rather than amnesia.
- **Unbounded spend.** A cost ceiling was declined. With per-turn wake-up and
  full autonomy, this system can burn budget unattended. The worker cap and
  spawn rate bound concurrency but not cumulative cost. `usage_quota`
  infrastructure already exists and is the natural home if this is revisited.
- **Autonomous kill of unpushed work.** Permitted by decision. Partially
  mitigated as described in §10.
- **Nudge delivery into a busy orchestrator.** `cannotNudge` refuses delivery
  when the orchestrator needs input; those rows stay pending until it next
  reaches idle. A permanently stuck orchestrator silently accumulates a backlog.
  Surfacing that is deferred (§12).

## 12. Explicitly out of scope

- **Task queue with priorities.** An agent holding a list in context with a cap
  of N workers does not need a scheduler. Real engineering, gain only at 10+
  simultaneous tasks. #3274 shipped scheduling machinery and it was reverted.
- **A notes/scratchpad table for orchestrator reasoning.** State is re-derivable
  from `opr board` plus the inbox. Add only if re-derivation proves insufficient
  in practice.
- **`opr pr merge` and `opr review *` in the prompt.** Per §9.
- **Cost ceiling.** Per §4.
- **Any retry, backoff, or escalation loop.** Per §7. This is a hard
  prohibition, not a deferral.

## 13. Testing

Gate is `npm run lint` (go test ./... + golangci-lint) plus
`cd backend && go test ./internal/httpd/...` for spec drift.

- **Reducer:** `crossedToIdle` inserts exactly one pending row; coalescing holds
  under idle→active→idle; the row and the activity change commit atomically; no
  row for the spawn-time idle seed or `waiting_input`→`idle`.
- **Dispatch:** no orchestrator, terminated orchestrator, and `cannotNudge`
  states each leave the row pending and send nothing; per-project serialization
  under concurrent triggers.
- **The regression test for #3394:** N duplicate nudges for one event produce
  exactly one digest and one acked row. This test is the reason the feature can
  be attempted a third time; it must not be weakened.
- **Ack:** acking an unknown or already-acked id is a no-op, not an error —
  idempotency reaches the API boundary, not just the protocol.
- **CLI:** table-driven in the style of `internal/cli/*_test.go` — happy path,
  missing args, daemon error envelope, `--json` shape.
- **Budget:** spawn refused at the cap with `ORCHESTRATOR_BUDGET_EXHAUSTED`;
  human-initiated spawns are unaffected by the orchestrator's budget.

No network in tests; `httptest` and fakes, per `AGENTS.md`.

## 14. Phasing

Each phase is independently shippable and independently valuable. Autonomy
lands last, and never before the leash.

**Phase 0 — Eyes.** `opr board` and the digest read path. Correct the false
`opr status` claim in the prompt. No new autonomy, no new table, no delivery.
Pure read surface over data that already exists. Immediately useful to the human
too, and it de-risks everything after it.

**Phase 1 — Ears.** Migration 0105, the reducer write, the content-free nudge,
`opr inbox` and `opr inbox ack`, and the prompt's pull protocol. The
orchestrator now wakes on worker turn-end but its authority is unchanged. This
is where the reverted designs failed, so it ships with the §13 duplicate test as
its gate.

**Phase 2 — Leash and autonomy, together.** Budget enforcement in the spawn
service, project config keys, and the prompt rewrite granting the orchestrator
authority to act unasked. These must not be split: autonomy without the budget
is an unbounded spawn loop.

Delete the stale "the dispatcher reads it" comment
(`backend/internal/lifecycle/manager.go:30`) in whichever phase first touches
that interface.
