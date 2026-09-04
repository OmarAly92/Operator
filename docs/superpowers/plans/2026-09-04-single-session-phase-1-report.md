# Single Session Kind, Phase 1 — Execution Report

Executed via superpowers:subagent-driven-development: one fresh implementer
subagent per task, a two-stage (spec + quality) review between tasks, a fix loop
where needed, and a final whole-branch review + one scoped fix wave.

## 1. Workspace

- **Worktree:** `/Users/omaraly/development/AI/Operator/.worktrees/single-session-phase-1`
- **Branch:** `feat/single-session-phase-1` (cut from `master` @ `a2ed653fe`)
- **Not pushed, not merged.** Awaiting review.

### `git log --oneline master..HEAD`

```
cf5cee90a fix: strip mode from mobile orchestrator launch and drop obsolete interface-choice test remnants
dd3f03bee docs: record the collapse to one session kind
1ac65411a feat(api): remove the session interface-transition routes
89634b939 feat(settings): remove the default session interface preference
0be54565f feat(cli): remove the spawn --mode flag
09776c924 feat(api): reject a session mode on spawn, delegate and orchestrator requests
37e28a2f6 feat(session): drop the requested session mode from spawn and delegation
35d9f6fef feat(session): spawn every session as the agent's terminal UI
4d661f6d4 feat(mobile): remember the blocks/raw view per session on the device
84b564b7f feat(mobile): route every session to the terminal
0b71b0bdc feat(mobile): delete the interface transition coordinator
86d30ee99 feat(mobile): remove the interface picker from spawn
b29bfbc80 feat(desktop): render the terminal for every session and drop the dead blocks pane
b99f9e5af feat(desktop): remove the chat preflight terminal fallbacks
6694ac200 feat(desktop): drop the default session interface setting
ba229ff35 feat(desktop): remove the session interface switch
```

15 task commits + 1 fix-wave commit. **Task 9 was not implemented — see §3.**
Branch totals: 141 files, +461 / -7408.

## 2. Task-by-task table

| Task | Commit | Gate commands run (this session) | Result |
|---|---|---|---|
| 1 — desktop interface switch | `ba229ff35` | `vitest run SessionView.test.tsx renderer-coverage.test.ts`; `npm run typecheck`; `npm run lint` | PASS (27 tests; typecheck 0; lint 0 errors) |
| 2 — default-interface setting | `6694ac200` | `vitest run GlobalSettingsForm.test.tsx instance.test.ts TaskComposer.test.tsx`; `npm run typecheck`; `npm run lint` | PASS (50 tests; typecheck 0; lint 0 errors) |
| 3 — chat-preflight fallbacks | `b99f9e5af` | `vitest run TaskComposer/spawn-orchestrator/restart-orchestrator/board-empty-states/SessionsBoard/instance`; `npm run typecheck`; `npm run lint` | PASS (89 tests) |
| 4 — terminal-only SessionView + drop blocks path | `b29bfbc80` | `vitest run SessionView/CenterPane/lib`; `npm run typecheck`; `npm run typecheck:e2e`; `npm run lint`; `npm run check:desktop-parity` | PASS (524 tests; parity 102) |
| 5 — mobile spawn picker | `86d30ee99` | `flutter analyze`; `flutter test` (full) | PASS (`No issues found!`; 1294 tests) |
| 6 — mobile transition coordinator | `0b71b0bdc` | `flutter analyze`; `flutter test test/feature/{terminal,chat,sessions} test/core` | PASS (`No issues found!`; 699 tests) |
| 7 — mobile route to terminal | `84b564b7f` | `flutter analyze`; `flutter test test/feature/sessions test/core/app_routes` | PASS (`No issues found!`; 117 tests) |
| 8 — persist view toggle | `4d661f6d4` | `flutter analyze`; `flutter test` (full) | PASS (`No issues found!`; 1271 tests) |
| 9 — migration 0094 clears store | *(none)* | `go test ./internal/storage/sqlite/...` | **BLOCKED / PARKED** — see §3 |
| 10 — unconditional TUI spawn | `35d9f6fef` | `go test -run TestSpawnAlwaysRecordsTUIMode`; `go build ./...`; `go test ./internal/session_manager/... ./internal/daemon/...`; `go test ./...`; `npm run lint` | PASS (build/test green; `npm run lint` = 1 pre-existing `nilerr` only, see §7) |
| 11 — drop RequestedMode | `37e28a2f6` | `go build ./...`; `go test ./internal/ports/... ./internal/service/session/... ./internal/session_manager/... ./internal/httpd/controllers/...`; `npm run lint` | PASS (`npm run lint` = pre-existing `nilerr` only) |
| 12 — API 400 SESSION_MODE_REMOVED | `09776c924` | `go test -run RemovedMode|DelegateTask`; `npm run api`; `go build ./...`; `go test ./internal/httpd/...`; frontend `npm run typecheck`; `npm run lint` | PASS (`npm run lint` = pre-existing `nilerr` only) |
| 13 — CLI drops `--mode` | `0be54565f` | `go test -run TestSpawnCommand_HasNoModeFlag`; `go test ./internal/cli/...`; `go build ./...`; `npm run lint` | PASS (`npm run lint` = pre-existing `nilerr` only) |
| 14 — settings lose default interface | `89634b939` | `go test -run Settings`; `npm run sqlc`; `npm run api`; `go build ./...`; `go test ./internal/httpd/... ./internal/service/settings/... ./internal/storage/sqlite/... ./internal/daemon/...`; `go vet ./e2e/...`; frontend `npm run typecheck`; `npm run lint` | PASS (`npm run lint` = pre-existing `nilerr` only) |
| 15 — remove interface-transition routes | `1ac65411a` | `npm run api`; `go build ./...`; `go test ./internal/httpd/...`; `go test ./...`; frontend `npm run typecheck`; `npm run lint` | PASS (`npm run lint` = pre-existing `nilerr` only) |
| 16 — docs | `dd3f03bee` | docs-only: `git diff --stat docs/` + stale-reference grep | PASS |
| Fix wave (final review) | `cf5cee90a` | mobile `flutter analyze` + `flutter test test/feature/orchestrator`; frontend `vitest run NewTaskDialog.test.tsx` + `typecheck` + `typecheck:e2e` + `lint`; backend `go build ./...` + `go test ./internal/session_manager/...` | PASS (`No issues found!`; NewTaskDialog 11/11; typecheck 0; lint 0 errors; go green) |

Every gate above was run in this session and its output observed. `npm run lint`
exits non-zero on exactly one pre-existing finding (§7); every other gate is green.

## 3. Task 9 — parked (plan defect requiring a plan-owner decision)

**Plan text:** Task 9 creates
`internal/storage/sqlite/migrations/0094_clear_pre_release_data.sql` — a flat list
of `DELETE FROM <table>` — plus `migrate_clear_data_test.go`, so that "every table
except `app_settings` and `goose_db_version` is empty". The spec's Phase 1 bullet:
"**The database is cleared.** A goose migration empties every table except
`app_settings`."

**What was done:** Nothing was committed. The implementer attempted it, verified
the plan's fixtures against the real v93 schema (all 32 table names and both seed
inserts are correct), wrote the test and migration verbatim, and hit a wall that
the plan did not anticipate. The controller independently confirmed the analysis
and the migration runner details, then parked the task.

**Why — three independent problems, one of them structural:**

1. **STRUCTURAL.** `TestMigrateRepairsSkippedMuseHarnessConstraint` and
   `…WithLegacyQM` (in `internal/storage/sqlite/`) reproduce the real field
   history #3475/#3476 — `goose_db_version` rows 0044–0051 recorded as applied
   but never run, so tables such as `agent_model_catalog` were never created.
   `migrate()` then runs 0094 under `goose.Up(..., WithAllowMissing())`, and
   `DELETE FROM agent_model_catalog` raises `no such table`, which aborts
   `migrate()` and wedges daemon startup on those profiles. SQLite has no
   `DELETE ... IF EXISTS`. The only mechanisms that keep the spec's outcome
   **and** stay CI-green are structural: a goose **Go** migration guarding each
   delete with a `sqlite_master` lookup (this repo has zero Go migrations —
   `//go:embed migrations/*.sql` only), or extending the bespoke
   `prepare*`/`repair*` machinery in `internal/storage/sqlite/db.go` (a
   load-bearing function the plan's Task 9 file list never mentions), or a
   `CREATE TABLE IF NOT EXISTS` preamble.
2. **SEMANTIC.** Three existing tests seed rows, run `migrate()` to head, and
   assert survival: `TestMigrateAppliesMissingMigrationsBeforeCurrentVersion`,
   `TestUsageSchemaUpgradePreservesEarlierPRData`,
   `TestMigrateRepairsKimchiConstraintWithPrimeAgentAndLegacyQM`. 0094
   deliberately deletes those rows — whether those contracts should change is a
   design decision.
3. **LEDGER.** `TestMigrationVersionLedger` requires a `shippedMigrations` entry
   for any new migration — trivial, but a third file beyond the plan's "exactly
   two files" scope.

**Ruling:** Per the executor brief ("If a deviation would change what the spec
promises, stop and ask") and the skill's "a plan so broken that every path
forward is a guess" stop condition, this was **escalated, not ruled**: the fix is
structural, spans 4–6 files the plan never named, has multiple valid shapes with
real repo-specific convention questions, and touching the three survival tests
changes what they promise. Nothing downstream consumes migration 0094, so Tasks
10–16 proceeded. The blocked attempt's two uncommitted files were removed from the
worktree (an uncommitted `0094_*.sql` would be picked up by
`//go:embed migrations/*.sql` and break Task 14's gate).

**Consequence recorded (from the final review):** with the store un-cleared, a
developer's existing DB still holds `mode = 'chat'` rows, and the daemon still
honours them (`manager.go`, `service/session/status.go` branch on
`SessionModeChat`), while both clients now unconditionally render a terminal.
Those pre-existing chat sessions become unreachable ghost rows behind an empty
terminal pane. Nothing crashes and no new session can enter that state, but it
argues for landing the clearing migration (or a targeted chat-row purge) before
this reaches any real store rather than deferring indefinitely.

## 4. All deviations from the plan

Every deviation below is a *forced mechanical consequence* of a change the plan
itself mandates, unless marked otherwise. Each was disclosed by the implementer,
confirmed by the task reviewer, and recorded in the ledger.

| # | Task | Plan said | What was done | Why |
|---|---|---|---|---|
| D1 | Global | Commit trailer `Co-Authored-By: Claude Fable 5.1 …` + a `Claude-Session:` line | Used `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` | This session's system instructions explicitly override attribution; the executor brief says "use whatever commit attribution trailers your own session's system instructions specify". No code impact. |
| D2 | Setup | Line numbers read at `333566b1a` | Worktree cut from `master` @ `a2ed653fe` (one commit ahead); every quoted region re-located by content before editing | The brief says "worktree from master"; master is the authority. The extra commit (`fix(session): handle agent not responding error`) shifted `manager.go` / `manager_test.go` / `service.go` line numbers, all handled by content-matching. |
| D3 | 4 | Files listed: SessionView, CenterPane, session-block, workspace.ts, tests | Also edited `frontend/src/renderer/hooks/useWorkspaceQuery.ts` (dropped a `mode:` property assignment) | Removing `WorkspaceSession.mode` makes that assignment a `tsc` TS2353 excess-property error; required for the typecheck gate. Pure deletion, disclosed in the commit body. |
| D4 | 5 | Delete `lib/core/error_handling/chat_preflight.dart`; strip the picker from spawn only | Also stripped chat-preflight from the mobile **orchestrator** feature: `orchestrator_state.dart` (`LaunchFailureState` drops `chatUnavailable`), `orchestrator_cubit.dart`, `orchestrator_body.dart` (+ their tests), and `git rm test/core/error_handling/chat_preflight_test.dart` | The plan's Task 5 deletes `chat_preflight.dart` but the mobile orchestrator — named in **no** task's file map — also imported it (`isChatPreflightFailure`, `chatErrorCopy`, `LaunchFailureState.chatUnavailable`). Deleting the file without this leaves `flutter analyze` red; keeping the file leaves the Step-6 grep non-empty and a permanent dangling ref (repo-forbidden). This mirrors what desktop Task 3 did to `OrchestratorReplacementDialog`. **Ruling** (spec-consistent: the orchestrator preflight fallback is a "surface that lets someone choose chat"). |
| D5 | 5 | — | Also edited `test/core/telemetry/call_sites_test.dart` (dropped `mode:` from a `registerFallbackValue`) | `SpawnSessionParams` lost its `mode` param; the fallback value no longer compiles. Mechanical. |
| D6 | 6 | Test files listed did not include `chat_sheets_test.dart` | Applied a mechanical caller-fix to `test/feature/chat/.../chat_sheets_test.dart` (removed 3 `interfaceSupported:` args + 2 `Open Terminal UI` assertions, renamed one test) and removed a now-orphaned `bloc_test` import from `terminal_harness.dart` + `session_route_screen_test.dart` | `showConversationMenuSheet` lost its `interfaceSupported` param and the `Open Terminal UI` row; the untouched test file would not compile. No coverage of surviving behaviour weakened (reviewer verified). |
| D7 | 10 | `wiring_test.go` has 2 `startSession` call sites | All **4** `startSession` sites in `wiring_test.go` updated to the new arity | The `startSession` signature lost a parameter; all call sites must match. |
| D8 | 11 | Files listed did not include `manager_test.go` | `TestSpawnAlwaysRecordsTUIMode` in `manager_test.go` had `RequestedMode: domain.SessionModeChat` removed (one token) | Task 10's brief **explicitly foresaw this**: "Task 11 deletes `RequestedMode` … drop that argument from this test and keep the assertions." |
| D9 | 12 | `frontend/src/api/schema.ts` diff should be "only the removed `mode` properties" | The mandatory `npm run api` also added `fromLatest?: null \| boolean;` to `schema.ts` and dropped 3 stray `/** @enum */` lines | Master `a2ed653fe` had `fromLatest` in `openapi.yaml` (count 1) but not `schema.ts` (count 0) — a pre-existing generator drift from ancestor commit `4ebd70fde`. `npm run api` reconciles it; reverting would mean hand-editing a generated file (forbidden) or desyncing the two. Net effect **improves** master's drift state. |
| D10 | 14 | Test files: `settings_test.go`, `service_test.go`, `app_settings_store_test.go` | Also edited `internal/service/settings/legacy_import_test.go` (`New(...)` calls → 2-arg) and removed the dead `harnessWithoutChatDriver` helper from `e2e/harness_test.go` | `settingssvc.New` lost a parameter — the brief's Step 3 says "do the same for any other `New(` call"; `legacy_import_test.go` is the same package. `harnessWithoutChatDriver`'s only caller was the deleted `chat_mode_test.go` and it read the removed `chatHarnesses` field — dead + broken, fails `go vet`/lint. |
| D11 | Final review fix wave | — | New commit `cf5cee90a` fixing 1 Critical + 1 Important + 2 Minor from the whole-branch review (see §6) | Standard SDD final-review fix wave. |

## 5. Files the plan named but did NOT get touched, and files touched that the plan did not name

### Plan-named, not touched

- **`internal/storage/sqlite/migrations/0094_clear_pre_release_data.sql` and
  `internal/storage/sqlite/migrate_clear_data_test.go`** — Task 9's two files.
  Never created; Task 9 parked (§3).
- The plan's Task 9 also implicitly touches the migration test suite; none of
  that was done.

Every other file in the plan's file map was touched. (Spot-checked the desktop
delete/modify lists, the mobile delete/modify lists, and the backend
create/delete/modify lists against `git diff --name-only master..HEAD`; the only
gap is the Task 9 set above.)

### Touched, not named by the plan

All are forced mechanical consequences (cross-referenced to the deviations in §4):

| File | Deviation | Kind |
|---|---|---|
| `frontend/src/renderer/hooks/useWorkspaceQuery.ts` | D3 | forced TS2353 fix |
| `frontend/src/renderer/components/NewTaskDialog.test.tsx` | D11 | obsolete-test deletion (final review) |
| `frontend/e2e/chat-scroll-overflow.spec.ts` | D11 | dead route-mock removal (final review) |
| `packages/mobile/lib/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_state.dart` | D4 | chat-preflight strip |
| `…/orchestrator_screen/logic/orchestrator_cubit.dart` | D4, D11 | chat-preflight strip + `mode` removal |
| `…/orchestrator_screen/ui/widgets/orchestrator_body.dart` | D4 | chat-preflight strip |
| `packages/mobile/lib/feature/orchestrator/data/model/params/launch_orchestrator_params.dart` | D11 | `mode`-on-the-wire fix (final review Critical) |
| `packages/mobile/test/core/error_handling/chat_preflight_test.dart` | D4 | deleted (tests deleted file) |
| `packages/mobile/test/core/telemetry/call_sites_test.dart` | D5 | forced fallback-value fix |
| `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_sheets_test.dart` | D6 | forced caller fix |
| `packages/mobile/test/feature/terminal/terminal_harness.dart` | D6 | orphaned `bloc_test` import |
| `packages/mobile/test/feature/orchestrator/**` (`_cubit_test`, `_body_test`, `_card_test`, `data_source_test`, `repository_test`) | D4, D11 | forced test fixes for the two orchestrator changes |
| `backend/internal/session_manager/manager_test.go` | D8 | one-token, foreseen by Task 10's brief |
| `backend/internal/session_manager/wiring_test.go` → *(actually `daemon/wiring_test.go`, plan-named)* | D7 | 4 sites vs 2 named |
| `backend/internal/service/settings/legacy_import_test.go` | D10 | forced `New(...)` arity fix |
| `backend/internal/session_manager/manager.go` (comment lines only, final review) | D11 | 2 stale comments corrected |

## 6. Final whole-branch review + fix wave

Whole-branch review (opus, `a2ed653fe..dd3f03bee`): **"Ready to merge? With fixes."**

- **CRITICAL** — mobile orchestrator launch always 400s. `OrchestratorCubit.launch`
  had a default `String mode = 'chat'` that `LaunchOrchestratorParams.toJson()`
  serialised unconditionally to `POST /api/v1/orchestrators`, which this same
  branch (Task 12) now rejects with `400 SESSION_MODE_REMOVED`. Confirmed
  end-to-end from the "Start/Restart orchestrator" button. The Task 5 ledger had
  flagged this exact leftover as "dead but still on the wire"; the final review
  confirmed it as a live regression.
- **IMPORTANT** — `frontend/src/renderer/components/NewTaskDialog.test.tsx` still
  had the obsolete "offers an explicit Terminal UI retry when Chat preflight
  fails" test (Task 3 removed the feature; its brief named only
  `TaskComposer.test.tsx`, whose parallel test *was* deleted). The reviewer
  grepped the whole tree and confirmed this was the only surviving stale
  reference.
- **MINOR** — dead `/interface-transition` route mock in
  `frontend/e2e/chat-scroll-overflow.spec.ts`; stale "chat spawn is refused"
  comments in `session_manager/manager.go`.
- Deferred minors triaged as **non-blocking**: `BLOCK_HARNESSES` orphaned export;
  `tuiWorker` name; `EndPoints.settings` unreferenced; unbounded per-session
  `shared_preferences` key (matches existing `chatDraft` precedent); Task 6's
  red-log passing test.

**One fix wave** (`cf5cee90a`): all four addressed —
1. Removed `mode` from `LaunchOrchestratorParams` (field/ctor/`toJson`/`props`) and
   `OrchestratorCubit.launch`; dropped `mode:` at all 5 test call sites; added a
   wire-contract test asserting `toJson()` has no `'mode'` key.
2. Deleted the one obsolete `it` block in `NewTaskDialog.test.tsx`.
3. Removed the dead `/interface-transition` route-mock branch (4 other route
   mocks intact).
4. Corrected 2 factually-wrong comments in `manager.go` (comment text only).

**Scoped re-review** (`dd3f03bee..cf5cee90a`): all 4 findings **ADDRESSED**, no new
Critical/Important breakage.

## 7. Final verification block — full output

Run from the worktree root after the fix wave (`HEAD = cf5cee90a`).

```
backend  go build ./...                     → PASS (exit 0)
backend  go test ./...                       → PASS (all packages ok)
backend  go vet ./...                        → PASS (exit 0)

root     npm run lint                        → EXIT 1 — one finding only:
  backend/internal/session_manager/manager.go:2561:4:
    error is not nil (line 2559) but it returns nil (nilerr)
  PRE-EXISTING: byte-identical on master a2ed653fe (function confirmActiveWithNudge,
  no //nolint), introduced by the unrelated master commit a2ed653fe
  ("fix(session): handle agent not responding error"). NO branch hunk touches that
  function (manager.go hunks are at ~276/482/521/613/2776). The 16-commit branch
  adds ZERO new lint findings. master's own `npm run lint` is red on this line.

frontend npm run typecheck                    → PASS (exit 0)
frontend npm run typecheck:e2e                → PASS (exit 0)
frontend npm run lint                         → PASS (exit 0; 0 errors, 146 warnings,
                                                all pre-existing style — 151 before
                                                the branch; deleted files removed 5)
frontend npx vitest run                       → 5 failed | 1704 passed (1709);
                                                7 failed files, ALL under
                                                frontend/src/landing/**:
                                                  AndroidAppCTA / AndroidBetaDialog /
                                                  AndroidBetaInstructions /
                                                  AndroidBetaMobileSheet /
                                                  posthog-config / DownloadButton /
                                                  generate-markdown-twins
                                                Cause: `Failed to resolve import
                                                "@operator/shared/constants"`.
                                                NOT a regression: the branch touches
                                                nothing under frontend/src/landing/
                                                (git diff --stat master...HEAD -- that
                                                path is empty); these files PASS on the
                                                user's main checkout at master (27/27
                                                sampled). Root cause is the fresh
                                                worktree's `npm ci` not wiring the
                                                @operator/shared pub-workspace symlink
                                                that the main checkout carries
                                                (stash "local monorepo wiring before
                                                the M4 merge"). The one real vitest
                                                regression — NewTaskDialog.test.tsx —
                                                was fixed in cf5cee90a and now passes.
frontend npm run check:desktop-parity         → PASS (102 entries)

mobile   flutter analyze                      → PASS ("No issues found!")
mobile   flutter test                         → PASS ("All tests passed!", 1272 tests)

git diff --stat master..HEAD -- backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
  backend/internal/httpd/apispec/openapi.yaml | 336 ----------------------------
  frontend/src/api/schema.ts                  | 335 +--------------------------
  2 files changed, 2 insertions(+), 669 deletions(-)
```

The generated-file diff removes exactly: the `mode` property from the three
request schemas; `defaultSessionMode` + `chatHarnesses` from `SettingsResponse`;
`UpdateSessionInterfaceRequest` + the `/api/v1/settings/session-interface` path;
and the `/api/v1/sessions/{sessionId}/interface-transition` path + its 5 schemas.
The `+2 insertions` is the pre-existing `fromLatest` generator drift that
`npm run api` reconciled (D9).

### Verification summary

| Check | Verdict |
|---|---|
| backend build / test / vet | GREEN |
| root `npm run lint` | RED on 1 pre-existing `nilerr` only; **branch adds no new finding** |
| frontend typecheck / typecheck:e2e / lint / parity | GREEN |
| frontend vitest | 1 real regression fixed; remaining failures are a worktree wiring gap under `src/landing/**` (not this branch) |
| mobile analyze / test | GREEN |
| generated contract diff | matches the plan's stated expectation |

## 8. Things the plan or spec got wrong (worked around)

1. **Task 9's migration cannot be a flat `.sql` `DELETE` list.** The plan and spec
   both assume a trivial `DELETE FROM <table>` migration. It cannot pass CI on the
   real #3475/#3476 skipped-migration history and conflicts with three
   data-survival tests. The fix is structural and multi-file. Parked for a
   plan-owner decision (§3).
2. **Task 5's file map omits the mobile `orchestrator` feature's chat-preflight
   coupling.** `orchestrator_cubit.dart` / `orchestrator_state.dart` /
   `orchestrator_body.dart` import `chat_preflight.dart` and use
   `LaunchFailureState.chatUnavailable`. Deleting `chat_preflight.dart` (a Task 5
   step) without touching these breaks `flutter analyze`. Widened by ruling (D4).
3. **Tasks 5/7 leave `mode` on the mobile orchestrator spawn wire.**
   `LaunchOrchestratorParams` / `OrchestratorCubit.launch` keep a `mode: 'chat'`
   default that reaches `POST /orchestrators` — which Task 12 then 400s. No task's
   file map owns these files. Caught by the final whole-branch review and fixed in
   the fix wave (§6, D11). **This is the most important plan gap: a self-inflicted
   Critical regression that every per-task gate missed because the two halves
   (mobile sender, daemon rejecter) were in different tasks and neither task's
   brief named the mobile orchestrator params.**
4. **Task 3's file map omits `NewTaskDialog.test.tsx`,** which has the same
   obsolete "Create as Terminal UI" preflight test as the (named)
   `TaskComposer.test.tsx`. Caught by the final vitest run, fixed in the fix wave.
5. **Plan line numbers are stale throughout the backend section** (Tasks 10–15)
   because the plan-authoring commit `a2ed653fe` also modified `manager.go`,
   `manager_test.go`, `service.go`, `service_test.go`. Every backend edit was
   re-located by content. Not a defect in the plan's *intent*, but every backend
   dispatch had to carry an explicit "line numbers are wrong, match by content"
   instruction.
6. **The plan's per-task "exactly N files" scoping is slightly too tight in
   several places** — `wiring_test.go` had 4 `startSession` sites not 2 (D7);
   `settingssvc.New` has callers in `legacy_import_test.go` too (D10);
   `showConversationMenuSheet` has a caller in `chat_sheets_test.dart` (D6). All
   are mechanically forced by a signature change the plan *does* mandate; the plan
   just under-counted the call sites.
7. **Pre-existing `nilerr` in `manager.go` `confirmActiveWithNudge`** (from
   `a2ed653fe`, not this plan) means `npm run lint` was already red on `master`
   before this work started. The plan's "root `npm run lint` for Go" gate cannot
   be fully green regardless of this branch. Documented; not fixed (out of scope).
8. **Fresh-worktree `@operator/shared` wiring gap** makes `npx vitest run` fail 7
   `src/landing/**` files in the worktree that pass on the user's main checkout.
   Not a plan defect and not this branch's doing, but the plan's "Final
   verification" block assumes a fully-wired checkout — a reviewer must re-run
   vitest on a wired checkout / CI to close this cleanly.

---

*Report committed as the last commit on the branch. The SDD workspace
(`.superpowers/sdd/2026-09-04-single-session-phase-1/`) is retained — it holds the
per-task briefs, per-task implementer reports, per-task review diffs, and the full
`progress.md` ledger, for the reviewing session.*
