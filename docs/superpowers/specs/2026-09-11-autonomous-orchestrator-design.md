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
for the harnesses that ship a `hooks.go` — 21 of the 26 harness adapters under
`backend/internal/adapters/agent/` (the other directories there are shared
infrastructure: `agentbase`, `hookutil`, `activitydispatch`, `registry` and
friends, plus the `fake` test double) — and only write a DB row. Five real
harnesses have no hooks and emit no activity signal at all: **aider, auggie,
continue, grok, pi** (`backend/internal/domain/harness.go:10`–`:30`). The
orchestrator therefore acts only when the human types into it, which is the
exact behavior we are trying to eliminate.

Hook coverage is thus the common case, not the exception — which matters for
scoping: the wake-up path will work for almost every harness a user picks, and
the hookless five are a documented degradation (§5.2), not a blocker.

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
| `worker_idle_events` (#2836) | Durable outbox. Worker active→idle wrote an event atomically with the activity transition. Per-project dispatch lock. At-most-one delivery per orchestrator turn to drain a backlog. `safeToDeliver` gating (idle, or active only on a steerable harness, and never before the orchestrator's first hook signal). A startup sweep re-dispatched pending rows after a daemon restart. Coalescing via unique partial index on `worker_id WHERE delivery_state='pending'`. The nudge was **already content-free and pull-based**: "Worker X has gone idle and may be done. Inspect it with `ao session get`…". Rows were marked `delivered` daemon-side; there was no orchestrator ack. | Removed by #3257, "remove worker idle orchestrator nudges". Rationale not recorded. |
| `orchestrator_reengagements` (#3274) | **Not** a delivery layer over worker events. A separate time-driven nag: any orchestrator idle for 10 minutes was poked on a 30-second tick with exponential backoff, up to 3 attempts, then the human was notified. State: `attempt_count`, `next_attempt_at`, `progress_since_attempt`, `state IN (active, completed, exhausted)`. Added an `orchestratorloop` manager, a `/complete` endpoint, and an `ao orchestrator done` command. | Reverted by #3394: **"fired repeatedly at orchestrator sessions (3-4 duplicates in a row)"**. The duplicates were never diagnosed; the revert records the symptom only. |

Schema remnants: `backend/internal/storage/sqlite/migrations/0037_drop_worker_idle_outbox.sql`,
`0039_drop_orchestrator_reengagement.sql`. A stale comment on
`lifecycle.sessionStore.ListSessions` still refers to "the dispatcher"
(`backend/internal/lifecycle/manager.go:30`) — a leftover from the removed
dispatcher, worth deleting when this lands.

These PR numbers are upstream's, from before the rebrand; this repository is an
inherited clone, so the written rationale for #3257 is not recoverable here.
#3394 records only the symptom.

The first attempt was **not naive**. It already had the durable outbox, the
atomic write, the coalescing index, the backlog draining, the startup sweep and
a content-free nudge — most of what this design proposes. It was still pulled,
for reasons we cannot read. What it demonstrably lacked is stated in §3; any new
attempt that merely rebuilds a better outbox should be expected to fail the same
way.

## 3. What we know, what we don't, and the governing design principle

**What is not known.** Why #3257 removed the idle nudges, and what produced
#3394's 3–4 duplicates. An earlier draft of this document attributed the
duplicates to `sendConfirm` re-sending Enter. That is wrong: `sendConfirm`
re-sends **Enter only** — an empty message is an Enter-only nudge, see the
comment above `confirmActive` at `backend/internal/session_manager/manager.go:2360` —
and an Enter into an empty composer cannot resubmit a prompt. The duplicates
came from somewhere inside #3274's own tick/backoff state machine, and that
machine is gone. Do not build on a diagnosis this document does not have.

**What is known.** `opr send` injects keystrokes into a PTY with no delivery
acknowledgement: it returns 200 the moment the runtime accepts bytes
(`manager.go:395`–`:418`). Exactly-once delivery into a PTY is not achievable,
and whatever caused #3394 will have a cousin. Any design that is only correct
under exactly-once delivery is therefore wrong. Also known: #2836's orchestrator
could not act on its nudge because `ao session get` returned no output, brief or
PR state — the nudge was content-free but the pull behind it was blind.

Therefore:

> **Principle: make delivery idempotent instead of exact.**
> The message pushed to the orchestrator carries **no content** — only a count.
> The orchestrator **pulls** the state it needs and **acknowledges** what it
> consumed. A duplicate nudge then drains an already-acked inbox, the
> orchestrator reads nothing new, and the cost is one cheap no-op turn rather
> than a duplicated action.

At-least-once delivery becomes safe by construction, **whatever** produces the
duplicates. The differences from the reverted attempts, stated honestly:

1. **Eyes.** The pull returns a digest the orchestrator can act on (§5.2). This
   is the real bet of the third attempt; #2836 nudged into a blind pull.
2. **Orchestrator-side ack** instead of a daemon-side `delivered` mark, so the
   consumer, not the sender, decides what has been seen.
3. **No time-driven loop of any kind** — the thing #3274 was.

Every component below exists to serve these three.

## 4. Decisions taken

Recorded because they constrain the design and were chosen deliberately.

| Decision | Choice | Consequence |
| --- | --- | --- |
| Wake policy | **Every worker turn-end** (any worker crossing to idle) | Maximum awareness. Same trigger as the reverted `crossedToIdle`; idempotency is what makes it viable now. Makes durable state load-bearing, since context fills fast. |
| Autonomy | **Full, within a budget** | Orchestrator spawns, redirects and kills workers without asking. Human is notified, not consulted. |
| Budget | Per-project cap on live workers and spawns-per-hour | Enforced daemon-side, not by prompt. Requires the spawn request to carry the caller's session id (§5.4, §8); today it carries none. On exhaustion it queues and reports. |
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
  │                              ├─► content-free nudge via sessionguard.NudgeCoordination
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
Today's activity write is a single `UPDATE` under a mutex, not a transaction
(`store.UpdateSessionFromActivitySignal`,
`backend/internal/storage/sqlite/store/session_store.go:69`), so "same
transaction" means a **new store method** that performs the activity update and
the inbox insert inside one `BeginTx` (precedent: `store.go:72`,
`agent_switching_store.go:386`). Two separate writes do not satisfy this design.
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
`session_manager/agent_switching.go:1578` and `:1749` already build bounded
continuation facts from them for agent handoffs. PR rows already carry `CI` and
`Review` state (`backend/internal/domain/pr.go:35`). This is a read path over
existing data, not a new capture pipeline.

The smallest version of "eyes" is to add `latestUserPrompt`,
`latestAssistantUpdate` and a PR summary to the existing session DTO that
`opr session get` renders (`backend/internal/cli/session.go:43`).
That alone un-blinds the orchestrator and the human, and `opr board` and the
digest compose from the same fields. Phase 0 starts there — after the ingest
bug below is fixed, because today the stored value is **not** the worker's
last message.

**Verified 2026-09-11 against a live daemon DB and a reproduction:**
`latestAssistantUpdate` is captured correctly by the Claude Code `Stop` hook
and then overwritten about a second later. In `~/.operator/data/opr.db`,
session `scratch-14`'s `stop` block event at 07:05:34 carries the full
1,076-character answer, but `sessions.latest_assistant_update` holds the
32-character string "compare price with iPhone 17 Pro", which appears nowhere
in the native transcript; the orchestrator `operator-1` shows the same pattern
("the mobile terminal feature — let's start there"). `activity_last_at` did not
move, so the overwrite was a metadata-only write.

Reproduction (Claude Code 2.1.267, hooks for `Stop`, `SubagentStop`,
`Notification`, `SessionEnd` and `UserPromptSubmit` logging their stdin): one
turn produces `Stop` with `last_assistant_message` = the real reply, then a
**`SubagentStop`** whose `last_assistant_message` is the output of a background
sidechain agent (`"(silence)"` for a trivial prompt; a suggested next prompt
for a real one — this is Claude Code's prompt-suggestion generator, and the
strings above are its output). Operator installs `SubagentStop`
(`adapters/agent/claudecode/hooks.go:46`), and `opr hooks` runs
`hookConversationFacts` for **every** claude-code event
(`backend/internal/cli/hooks.go:313`–`:316`), so the sidechain's text lands in
`LatestAssistantUpdate` and reaches the store through the metadata-only branch
of `ApplyActivitySignal`. The existing test at `cli/hooks_test.go:75` asserts
only usage and native-session fields for `subagent-stop`, so it does not pin
the bad behaviour.

**Fixed 2026-09-11** (`fix(hooks): only turn-boundary events may set
conversation facts`), ahead of this design rather than inside it: the
corruption also reached the agent-switch continuation body
(`agent_switching.go:1578`, `:1749`), which handed an incoming agent fabricated
facts, so it was a shipped bug worth fixing on its own.

`hookConversationFacts` now takes the event and contributes neither field
unless it is `stop` or `user-prompt-submit`; any other event — `subagent-stop`,
`notification`, `session-end`, or anything upstream adds later — contributes
nothing, so the default is silence rather than overwriting. `transcriptPath`
still flows from every event. Migration `0105_clear_corrupted_conversation_facts.sql`
clears both fields on existing claude-code sessions, because the corrupt rows
are indistinguishable from good ones and an absent fact degrades to the honest
"none recorded" fallback while a wrong one does not.

An earlier draft of this section prescribed a per-field split —
`LatestAssistantUpdate` only from `stop`, `LatestUserPrompt` only from
`user-prompt-submit`. That over-reached: Claude Code's `Stop` payload
legitimately carries `prompt`, and `TestHooks_StopReportsConversationFacts`
deliberately pins that Operator records it. An **event allowlist** fixes the
corruption without deleting working behaviour. Both allowed events report both
fields.

Consequence for this design: migration numbers shift. The inbox is `0106` and
`spawned_by` is `0107`; §6 and §14 are updated to match. Every migration number
is also gated by the `shippedMigrations` ledger in
`storage/sqlite/migrate_burned_versions_test.go`, which must gain an entry in the
same change that adds the file.

Once fixed, the field is exactly the worker's last user-facing message, which is
what the digest needs; the Stop payload also carries `prompt_id`, which the
digest may later use to pair a reply with the prompt it answered.

**Verified 2026-09-11 against a live DB and an isolated daemon: the task brief is
mostly not there.** No session in `~/.operator/data/opr.db` has a `prompt` longer
than five characters — the only "populated" ones are literally `'Hi'`.
`Metadata.Prompt` holds just what a session was *spawned* with, so for work driven
by typing into the pane it is empty or trivial. `latestUserPrompt` is the field
that actually carries the direction ("search for new iphone 18", "operator own
terminal has bugs"), so the digest must lead with it and treat `brief` as
optional context. `opr board` renders `last prompt` for this reason.

A second instance of the §5.2 overwrite class is still open, and Phase 0 makes it
visible: `isOperatorCoordinationMessage` (`cli/hooks.go:234`) filters only
`<opr-handoff-request` and the "Operator transferred the previous agent's context"
prefix, so the daemon's own "Operator TASK TITLE UPDATE" message
(`service/session/delegation.go:176`) is recorded as a session's latest *user*
prompt — observed on orchestrator `scratch-11`, 368 characters of Operator's own
coordination text presented as the human's intent. Fix it before the digest
quotes `latestUserPrompt` to a coordinating orchestrator.

Digest limits: a worker on a hookless harness (§1) never produces an inbox
event and its `latestAssistantUpdate` is always empty; the digest and board must
mark such a worker as "no hook signal" rather than render its seeded activity
state as if it were observed. A worker that asks a question ends
its turn with a `stop` hook, which maps to `idle`, not `waiting_input` — so
"needs a decision" is only visible through the assistant text in the digest.

**5.3 The board (memory on demand).** `opr board` renders the whole project work
state in one read: every live worker with its brief, activity, PRs, CI and review
status. This is what the prompt currently, falsely, promises from `opr status`.
`opr status` keeps its existing daemon-health contract unchanged; the prompt is
corrected to point at `opr board`.

**5.4 The leash.** Budget enforced in the spawn service, not the prompt. A
prompt rule is not a limit.

The daemon cannot currently tell who asked for a spawn. `cliInvocationActorType`
(`backend/internal/cli/root.go:245`) reads `OPERATOR_SESSION_ID`, but that value
is only posted to the telemetry endpoint `/internal/telemetry/cli-invoked`; the
spawn request itself (`SpawnSessionRequest`, `controllers/dto.go:196`) carries
no caller identity. The leash therefore needs a wire change: `opr spawn` sends
`requestedBy` (the session id from `OPERATOR_SESSION_ID`, when set), the daemon
verifies it resolves to a live orchestrator in the same project, and the spawn
service persists it as `spawned_by` on the new session row so spawns-per-hour
can be counted from existing `created_at` data. That column is a second
migration, landing in Phase 2 (§6).

The identity is **client-asserted**: an orchestrator that runs
`env -u OPERATOR_SESSION_ID opr spawn` is indistinguishable from the human. The
cap is hard against an orchestrator behaving normally, not against one
subverting its environment; §10 records this. If a cap that survives subversion
is ever wanted, the only unspoofable form is a project-wide live-worker cap that
also refuses human spawns, which was rejected as a default.

Over budget returns a typed error the orchestrator can act on.

## 6. Data model

Two migrations, one per phase. Already-merged migrations are immutable per
`AGENTS.md`; queries go in
`backend/internal/storage/sqlite/queries/orchestrator_inbox.sql` and generated code
comes from `npm run sqlc` — never hand-edited.

**Phase 1 — `0106_orchestrator_inbox.sql`** (0105 is the conversation-facts
backfill from §5.2):

```sql
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

CREATE UNIQUE INDEX idx_orchestrator_inbox_pending_worker
    ON orchestrator_inbox(worker_id, kind) WHERE state = 'pending';

CREATE INDEX idx_orchestrator_inbox_pending_project
    ON orchestrator_inbox(project_id) WHERE state = 'pending';
```

The unique partial index is the coalescing mechanism, carried over from #2836
where it was sound. Note it is keyed on `(worker_id, kind)`, not `worker_id`
alone: a worker may legitimately have both a pending idle and a pending CI
failure.

**Producers per kind.** Phase 1 writes only `worker_idle`, from the reducer
(§7). `ci_failed` and `review_changes_requested` are reserved for
`ApplyPRObservation` (`lifecycle/reactions.go:142`) and `ApplyReviewBatch`
(`:51`), which today route those facts to the worker only; wiring them to also
insert an inbox row is a follow-up after Phase 1 proves the protocol, and until
then the CHECK list is a declaration of intent, not a promise. An earlier draft
listed `worker_blocked`; it is dropped because nothing produces it — a
permission prompt maps to `waiting_input`/`blocked` on the worker and already
notifies the human via `needs_input`, and a worker asking a question ends its
turn as plain `idle` (§5.2).

Rows carry **no digest content**. Content is resolved at read time from the
session record, so a digest is never stale and the table stays small.

**Phase 2 — `0107_sessions_spawned_by.sql`:** `ALTER TABLE sessions ADD COLUMN
spawned_by TEXT NOT NULL DEFAULT ''` (a session id, or empty for human and
system spawns). The spawn-rate query counts worker rows per project with
`spawned_by = <orchestrator>` and `created_at` in the last hour; no separate
audit table.

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
   demotions do not fire). Reducer inserts a pending row **in the same
   transaction as the activity change** (the new store method from §5.1),
   ignoring conflict on the coalescing index.
2. Reducer resolves the project's live orchestrator and hands the nudge to
   `sessionguard.NudgeCoordination` (`backend/internal/sessionguard/guard.go:247`),
   which is the existing write-boundary policy for unsolicited coordination
   messages: it re-reads the session immediately before pasting, refuses when
   the orchestrator awaits the human (`NeedsInput`), and refuses an **active**
   turn unless the harness declares `SteersActiveTurn` — today only codex and
   prime-agent do; a Claude Code orchestrator mid-turn is never written into.
   Do not use `cannotNudge` (`reactions.go:579`) here: it permits delivery into
   any active turn. Additionally skip when the orchestrator's `FirstSignalAt`
   is zero (#2836's guard): a restored orchestrator is seeded idle before its
   hooks are proven up. If there is no orchestrator or the guard refuses, stop.
   The row stays pending; no retry is scheduled.
3. Send a **content-free nudge**: `[Operator] N inbox item(s). Run `opr inbox`.`
   One line. It carries no digest, so duplicates cost almost nothing in context.
4. Orchestrator runs `opr inbox`, receives digests, acts, then runs
   `opr inbox ack <id>...`.
5. **No retry loop, ever.** Pending rows are re-announced on three events, all
   of which already happen and none of which is a timer:
   - the orchestrator next enters idle — #2836's `orchestratorDispatchTrigger`,
     which drains a backlog one nudge per turn;
   - daemon start — one sweep over projects with pending rows, as #2836's
     `DispatchAllPendingWorkerIdleEvents` did from `daemon/lifecycle_wiring.go`;
   - an orchestrator finishing restore (its first hook signal after relaunch).

   Without the last two, a backlog written while the orchestrator was busy, or
   left over across a daemon restart, sits until some worker happens to go idle
   again: an already-idle orchestrator produces no transition to fire on.

   This is not a retry, and the distinction is load-bearing: re-announcing is
   **event-driven and stateless** — it fires on a transition or startup that
   already happens, carries no attempt counter, sets no timer, and escalates
   nothing. A retry loop is **time-driven and stateful**: it remembers that
   delivery "failed", schedules a next attempt, and gives up after N. The latter
   is what #3274 built and #3394 reverted. Nothing in this design may count
   attempts, store a `next_attempt_at`, or escalate an undelivered event.

Why this is safe under duplicate delivery: a duplicate nudge causes one extra
`opr inbox` call, which returns nothing pending, and the orchestrator's turn
ends. The failure mode degrades from "duplicated action" to "one wasted cheap
turn".

Delivery is serialized per project so overlapping triggers cannot both announce
the same state — carried over from #2836's dispatch lock. There is no
coalescing delay of any kind: N workers finishing together cost N nudges, and
the at-most-one-per-turn draining plus the count in the message already
collapse them into one `opr inbox` read (§12 records why a debounce timer was
considered and left out).

## 8. Wire and CLI surface

The CLI stays a thin client over daemon HTTP; no direct storage access
(`AGENTS.md`). New DTOs go in `controllers/dto.go` with `schemaNames` entries in
`apispec/specgen/build.go`, and `npm run api` regenerates `openapi.yaml` and
`frontend/src/api/schema.ts`, committed together with the Go changes.

| Endpoint | CLI | Purpose |
| --- | --- | --- |
| `GET /api/v1/sessions/{id}` (extended) | `opr session get` | `SessionView` gains `brief`, `latestUserPrompt`, `latestAssistantUpdate`, each sanitized and capped at 2048 bytes; it already carried PR facts. `opr session ls` keeps its terse shape. |
| `GET /api/v1/projects/{id}/inbox` | `opr inbox [--json]` | Pending digests |
| `POST /api/v1/projects/{id}/inbox/ack` | `opr inbox ack <id>...` | Mark consumed |
| `POST /api/v1/sessions` (extended) | `opr spawn` | Request gains `requestedBy`; the CLI fills it from `OPERATOR_SESSION_ID` when set |

`opr board` needed no new endpoint: it reads the existing
`GET /sessions?project=&active=true` route, which the extended session DTO
(§8 row above) already carries `latestUserPrompt`, `latestAssistantUpdate`, and
PR state on.

Project routes are registered in `controllers/projects.go:30`; session routes in
`controllers/sessions.go:184`. `/sessions/{id}/pr` already exists, so the board
is a client-side join over the existing sessions list, not new capture.

`opr inbox` and `opr board` **infer the project** from `OPERATOR_SESSION_ID`
(session → project) when `--project` is omitted, so the orchestrator never has
to carry or mistype a project id. `opr inbox` ends its human-readable output
with a ready-to-paste `opr inbox ack <id> <id> ...` line for everything it just
showed; the ids are explicit so an event that lands between read and ack is
never swallowed.

Errors preserve the existing envelope and `requestId`. Usage errors return
`usageError` so misuse exits 2 and runtime failures exit 1.

Budget rejection reuses the standard envelope with a machine-readable code,
`ORCHESTRATOR_BUDGET_EXHAUSTED`, and a message naming the limit hit and when it
resets, so the orchestrator can queue intelligently rather than retry blindly.

Project config gains an `orchestratorPolicy` block with `maxLiveWorkers` and
`maxSpawnsPerHour`. It does **not** go on `RoleOverride`
(`backend/internal/domain/projectconfig.go:111`): that struct holds only
`Harness` and `AgentConfig` and is shared by the `Worker` override, where a
spawn budget would be a meaningless field.

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
- **Restate the merge boundary.** The prompt already says "Do not merge unless
  explicitly asked and supported by project rules" (`prompt.go:213`); this is a
  rewrite for the autonomous framing, not a new rule: never merge on its own
  initiative; merging is permitted when the human has explicitly instructed it.
- **Teach `opr session handoff`.** Dropped from scope: `opr pr merge`
  (initiative-bounded above), `opr review *` (already handled autonomously by
  lifecycle), and any task-queue command (see §12).

The confidentiality guard (`systemPromptGuard`) is unchanged and still applies.

## 10. Enforcement honesty

Which controls are real and which are advisory, stated plainly so nobody
mistakes a prompt rule for a guarantee:

- **Hard against normal behaviour (daemon-enforced, client-attributed):** the
  worker cap and spawn rate. Refused in the spawn service; the orchestrator
  cannot talk its way past them. Attribution rests on `requestedBy`, which the
  CLI fills from `OPERATOR_SESSION_ID` (§5.4). An orchestrator that unsets that
  variable before calling `opr spawn` is counted as the human. This is
  accepted: the leash exists to bound a well-behaved model's enthusiasm, not to
  contain an adversarial one.
- **Hard (pre-existing, runtime):** `Kill` never force-removes a worktree with
  uncommitted work; it succeeds with `freed=false` and reports
  (`backend/internal/session_manager/manager.go:1060`, `:2509`). So a kill
  cannot silently destroy a dirty worktree even though the orchestrator is
  allowed to kill workers. (The `AGENTS.md` line "do not force-delete dirty
  registered worktrees" is a rule for agents editing this repository, not the
  runtime guarantee.)
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
  spawn rate bound concurrency but not cumulative cost. If revisited, the
  per-session token ledger is the natural home: the model-usage tables from
  migration `0052_model_usage.sql` with `queries/usage.sql` and
  `usage_rollup.sql`. Not `usage_quota` (`0100`): that table is the account's
  Codex rate-limit position, a provider reading, not a cost record.
- **Autonomous kill of unpushed work.** Permitted by decision. Partially
  mitigated as described in §10.
- **Nudge delivery into a busy orchestrator.** `NudgeCoordination` refuses
  delivery when the orchestrator needs input or is mid-turn on a
  non-steering harness; those rows stay pending until it next reaches idle,
  the daemon restarts, or the orchestrator finishes a restore (§7 step 5). A
  permanently stuck orchestrator (waiting on a human decision that never
  comes) silently accumulates a backlog; the existing `needs_input`
  notification is the only signal. Surfacing the backlog itself is deferred
  (§12).
- **Blind spots by harness.** Workers on the five hookless harnesses — aider,
  auggie, continue, grok, pi (§1) — never wake the orchestrator and show no
  assistant text in the digest. The orchestrator must be told this in the prompt
  so it does not read silence as progress; extending hook coverage is a separate
  piece of work. Scope note: this is 5 of 26 harnesses, so the blind spot is
  narrow, but a project configured to one of those five gets no wake-up at all
  and the feature silently does nothing for it — worth an explicit warning at
  spawn or in `opr board` rather than leaving it to the prompt.
- **Undiagnosed prior failure.** §3 is explicit that the cause of #3394's
  duplicates is unknown. The design is safe under duplicates of any origin,
  which is the mitigation, but an implementer who finds duplicated *nudges* in
  testing should treat it as a real signal to trace, not as expected noise.

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
- **A nudge debounce timer.** A two-to-three-second `time.AfterFunc` per
  project, holding the nudge so N workers finishing together cost one
  orchestrator turn, was considered and left out. It would be the only timer
  in the design. It can be bounded honestly (no persisted state, no re-arm),
  but "no timers" is the tripwire that protects against a third revert, and a
  reviewer who does not read the justification will either strip it or grow
  it. The at-most-one-per-turn draining and the count in the message already
  collapse a burst into one `opr inbox` read, so the saving is small. If it is
  ever added, it goes in with a code comment pointing at §7's
  stateless/stateful distinction and a test that it never re-arms.

## 13. Testing

Gate is `npm run lint` (go test ./... + golangci-lint) plus
`cd backend && go test ./internal/httpd/...` for spec drift.

- **Reducer:** `crossedToIdle` inserts exactly one pending row; coalescing holds
  under idle→active→idle; the row and the activity change commit atomically; no
  row for the spawn-time idle seed or `waiting_input`→`idle`.
- **Dispatch:** no orchestrator, terminated orchestrator, `NeedsInput`, active
  on a non-steering harness (claude-code), and zero `FirstSignalAt` each leave
  the row pending and send nothing; active on a steering harness (codex)
  delivers; per-project serialization under concurrent triggers.
- **Sweeps:** a pending row survives a daemon restart and is announced once by
  the startup sweep; a pending row written while the orchestrator was
  relaunching is announced once on its first hook signal; neither sweep sends
  when the guard refuses, and neither leaves any state behind.
- **The regression test for #3394:** N duplicate nudges for one event produce
  exactly one digest and one acked row. This test is the reason the feature can
  be attempted a third time; it must not be weakened.
- **Ack:** acking an unknown or already-acked id is a no-op, not an error —
  idempotency reaches the API boundary, not just the protocol.
- **CLI:** table-driven in the style of `internal/cli/*_test.go` — happy path,
  missing args, daemon error envelope, `--json` shape.
- **Budget:** spawn refused at the cap with `ORCHESTRATOR_BUDGET_EXHAUSTED`;
  human-initiated spawns (empty `requestedBy`) are unaffected by the
  orchestrator's budget; a `requestedBy` that is not a live orchestrator in the
  same project is rejected as invalid, not silently treated as human;
  `spawned_by` is persisted and the hourly count reads it.
- **Session DTO:** `latestUserPrompt` and `latestAssistantUpdate` are capped
  and control-character-sanitized on the way out, matching the ingest cap at
  `controllers/sessions.go:1592`.

No network in tests; `httptest` and fakes, per `AGENTS.md`.

## 14. Phasing

Each phase is independently shippable and independently valuable. Autonomy
lands last, and never before the leash.

**Phase 0 — Eyes.** **Done.** The `opr hooks` ingest fix from §5.2 landed
separately, so `latestAssistantUpdate` is no longer overwritten by Claude Code's
`SubagentStop` sidechain; Phase 0 depended on that commit being present and did
not re-do it. Shipped: the session DTO extension
(`brief`, `latestUserPrompt`, `latestAssistantUpdate` on `SessionView`, plus the
PR facts it already carried), rendered by `opr session get` and by `opr board`,
and the corrected `opr status` claim in the prompt. `opr session ls` was
deliberately left alone — its `sessionListEntry` shape stays a terse index and
`opr board` is the rich per-project view. `opr board` needed no new endpoint
— it reads the existing `GET /sessions?project=&active=true` route now that
the session DTO carries the extra fields, so the `GET /api/v1/projects/{id}/board`
endpoint originally sketched in §8 was never built. No new autonomy, no new
table, no delivery. Pure read surface over data that already exists.
Immediately useful to the human too, and it de-risked everything after it.

**Phase 1 — Ears.** **Done.** Migration 0106, the transactional store method
(§5.1), the reducer write, the content-free nudge through `NudgeCoordination`,
the startup and restore sweeps, `opr inbox` and `opr inbox ack`, and the
prompt's pull protocol. The orchestrator now wakes on worker turn-end but its
authority is unchanged. This is where the reverted designs failed, so it
shipped with the §13 duplicate test as its gate.

Beyond the original scope: a coordination-echo suppression mechanism was
added so the orchestrator's own `opr send`/nudge traffic does not re-trigger
itself. See `docs/superpowers/plans/2026-09-12-orchestrator-ears-phase-1.md`
for the task breakdown.

**Phase 2 — Leash and autonomy, together.** **Done.** Migration 0107 (`spawned_by`),
the `requestedBy` wire field on spawn, budget enforcement in the spawn service,
the `orchestratorPolicy` config block, and the prompt rewrite granting the
orchestrator authority to act unasked. See
`docs/superpowers/plans/2026-09-12-orchestrator-leash-phase-2.md` for the task
breakdown. The prompt teaches `opr session switch-agent` instead of the initially
named (but never shipped) `opr session handoff`; switch-agent is the real command
that exists in the service layer and is what the orchestrator will actually
invoke.

Delete the stale "the dispatcher reads it" comment
(`backend/internal/lifecycle/manager.go:30`) in whichever phase first touches
that interface. Already done: Phase 1 removed it (verified 2026-09-12 by a
full-file grep of `manager.go` for "dispatcher reads" — zero matches). Phase 2
does not need to touch this again.
