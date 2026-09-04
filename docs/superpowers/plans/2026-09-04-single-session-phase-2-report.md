# Single Session Kind, Phase 2 — Final Execution Report

Date: 2026-09-04
Branch: `feat/single-session-phase-2`
Worktree: `.worktrees/single-session-phase-2`
Status: all 16 tasks complete, final whole-branch review complete with 2 fix rounds; committed locally, not pushed or merged

## Outcome

Phase 2 makes the mobile blocks view show what the agent actually said and did,
not just that it was doing something:

- A new `backend/internal/observe/transcript` package tails each live session's
  native Claude Code JSONL transcript or Codex rollout file from a durable
  per-session byte offset (`transcript_offsets` table), resolving the file path
  through the provider's own adapter with a symlink-safe containment check.
- Per-harness pure mappers (`claudecode`, `codex` packages) turn each transcript
  record into zero or more of seven new normalized block-event kinds
  (`assistant_text`, `reasoning`, `tool_start`, `tool_result`, `todo`,
  `turn_model`, `compaction`), routed through a `blocktranscript` registry
  mirroring the existing hook-dispatch pattern.
- Every transcript event is recorded through `blockevent.Service.RecordTranscript`
  — the same redaction, caps, store, trim, and mux publish as a hook event, with
  a larger text budget and a new `Source` field (`hook` | `transcript`) so the
  projection can tell the two channels apart.
- Per-session block retention rose 500 → 2000 to absorb the multiplied event
  count; `maxBlockEventPage` stayed 500 (a client pages backwards with
  `beforeSeq`).
- The mobile assembler (`block_assembly.dart`) now merges hook and transcript
  events sharing a `SourceID` into one block under a fixed precedence rule —
  **transcript wins on body, hook wins on status** — with a Codex tool
  lifecycle opened by `tool_start` and closed by `tool_result` entirely from
  the transcript (Codex has no tool hook at all), an in-place swap of a
  transcript question over the hook's bare "Waiting on you" notice, and later
  `todo`/compaction records collapsing onto earlier ones sharing a `SourceID`.
- Mobile rendering gained a collapsible tool-result section, real question
  options ("Answer in the terminal" — Phase 3 makes them interactive), a todo
  checklist, the turn's model on the footer, a working indicator between
  records for an active session, and reasoning collapsed by default with a
  one-line preview.
- A session with no readable transcript degrades to exactly today's
  hook-only projection — proved by six pre-existing hook-only fixtures passing
  byte-unchanged throughout.

## Judgment calls and rulings made

Recorded in full, with reasoning, in the ledger at
`.worktrees/single-session-phase-2/.superpowers/sdd/2026-09-04-single-session-phase-2/progress.md`.
Summary, in the order made:

1. **Pre-flight scan**: no conflicts found between tasks or against the plan's
   Global Constraints; proceeded without ruling.
2. **Task 1 deviation**: migration 0095 required a one-line append to the
   append-only `shippedMigrations` ledger in
   `migrate_burned_versions_test.go` (not named in the brief's Files list) to
   satisfy a pre-existing repo invariant (`TestMigrationVersionLedger`).
   Confirmed minimal and required, not scope creep. Same pattern recurred
   identically for migration 0096 in Task 2.
3. **Task 9 fix round**: the task's own diff was spec-compliant, but `npm run
   lint` failed on a `dupl` finding in `block_event_store.go` introduced by
   Task 1 (two identical row-mapping loops, after the `Source` field was added
   to both). Ruled this real and load-bearing — Task 16's final gate requires
   `npm run lint` green — and fixed it in-cycle via a shared
   `blockEventRecordFromRow` helper rather than deferring.
4. **Task 12 deviation**: adding the new non-nullable `BlocksCubit.active`
   getter broke two pre-existing mocktail-based widget tests that construct a
   mock cubit without stubbing it. Confirmed genuine, unavoidable, and
   test-only — not scope creep.
5. **Task 14 deviation**: discovered and fixed a pre-existing bug in
   `block_card.dart` where `BlockCardHeader` silently dropped
   `onToggleCollapse` whenever `onLongPressHeader` was also wired — which
   `BlocksBody` always does outside selection mode. This made tap-to-collapse
   unreachable in the real widget tree (only working in isolated unit tests),
   and made Task 14's own deliverable (tap-to-expand reasoning) impossible to
   verify without the fix. Confirmed genuine via `git show` on the pre-diff
   file, not scope creep.
6. **Final whole-branch review** (dispatched on Opus) found no Critical
   issues but four Important and several Minor findings. Rulings:
   - **Fixed**: a hot-loop full directory walk in `Resolver.Path` invoked on
     every 2-second reconcile tick for every live session, including already
     tracked ones — costly for Codex sessions whose path resolution falls
     back to `LocateTranscript`'s `filepath.WalkDir`.
   - **Fixed**: a crash bug in the mobile assembler — `todoIndex`/
     `questionIndex` were set to `blocks.length` *before* `_upsert`, which
     doesn't append on a duplicate `sourceId` (reachable via the tailer's
     legitimate rewind-and-retry on a sink failure); the next event of that
     kind in the same turn threw a `RangeError`, blanking the whole blocks
     screen.
   - **Fixed**: the spec's "reasoning renders collapsed with a one-line
     preview" was only half-built by Task 14 (collapse, no preview) — a plan
     gap in Task 14's own brief, not implementer error. Implemented the
     preview rather than only amending the spec, since the fix was small.
   - **Deferred, not implemented**: the server's per-session retention rose
     500 → 2000 but the mobile client's own `kBlockWindow`/`kBlockMaxWindow`
     were not raised to match, shrinking reachable scrollback for busy
     sessions. This is a product/UX sizing decision with no spec guidance on
     the right number — recorded as a new `todo_without_tmux.md` §15.3
     deferral rather than guessed at.
   - **Fixed** (folded into the same pass): a `SourceID` collision risk
     between a `thinking` and a `text` content block sharing one Claude Code
     transcript record (empirically unreached in real transcripts sampled on
     this machine, but latent); `Supervisor.Start` discarding the transcript
     watcher's own done channel, weakening the shutdown contract; several
     smaller cosmetic notes left unfixed as genuinely Minor.
   - **Deferred as instructed, with a residual note**: `Resolver.Path` passes
     a nil env to `NativeSessionConfigDir`, missing a per-project
     `CLAUDE_CONFIG_DIR`/`CODEX_HOME` override (fails closed, not a security
     issue). The implementer judged full plumbing out of scope for the pass;
     the re-reviewer found a smaller fix was actually available
     (`store.GetProject` + `SessionRecord.ProjectID` +
     `ProjectRecord.Config.Env` are already wired) and recorded it in the
     ledger so a future pass doesn't re-derive it from scratch.
7. **Second fix round (a deliberate deviation from "no second fix wave")**:
   the first fix round's own hot-loop fix introduced a genuine regression —
   the reconcile shortcut also skipped re-resolution when the hook-reported
   transcript path itself changed (agent relaunch/switch, a first-class
   scenario this whole phase supports) while the old file remained readable,
   silently freezing block projection on the stale path. Ruled this a
   load-bearing correctness regression, not a contestable residual finding,
   and dispatched one more narrowly-scoped fix (a cheap string comparison
   gating the shortcut) plus one more scoped re-review, rather than leaving a
   known regression in a hand-off. Verified resolved.

## Verification

All required gates are green on the completed worktree:

- Backend: `go build ./...`, `go test ./...`, `go test -race
  ./internal/observe/transcript/ ./internal/service/blockevent/`, `go vet
  ./...`.
- Repo lint and generated-artifact drift: `npm run lint` (0 issues), `npm run
  sqlc`, `npm run api`, `git status --porcelain` empty after regeneration.
- Frontend: `npm run typecheck`, `npm run lint`, `npx vitest run` (154 files,
  1726 tests) — Phase 2 only touches the desktop through the regenerated
  `schema.ts`, and nothing broke.
- Mobile: `flutter analyze` → `No issues found!`; `flutter test` → full suite
  green (1295 tests after the final fix round).
- Final whole-branch review (Opus) plus two scoped fix/re-review rounds, all
  resolved.

**Unverified**: Task 16 Step 5, the live smoke test on both harnesses (spawn a
real Claude Code and a real Codex session, watch a paired phone, kill the
daemon mid-turn and confirm no duplicate blocks, trigger a Claude Code
question and confirm real options render). This requires a human at the
keyboard with a running daemon, desktop app, and paired phone — none of which
a background agent has access to. This is exactly the class of finding the
final review's hot-loop and stale-path bugs represent, so it is worth running
before merge, not just after.

**Deliberately out of scope**, per the plan and existing deferral ledger: grok
(no transcript mapper, `todo_without_tmux.md` §15.1), subagent/sidechain
nesting (dropped, §15.2), the mobile block-window capacity mismatch (new
§15.3), and every control action (Phase 3 — the phone can see but not yet
answer questions or reply to permission requests).

Step 6 of Task 16 (push and open a PR) was explicitly withheld per the
controlling session's instructions. The branch is committed locally and
unpushed, ready for review.
