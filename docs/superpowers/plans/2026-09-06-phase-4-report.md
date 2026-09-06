# Phase 4 completion report: delete the ACP/Chat subsystem

**Date:** 2026-09-06
**Branch:** `phase-4-delete-acp` (worktree `.claude/worktrees/phase-4-delete-acp`)
**Scope:** Tasks 1-13 of `docs/superpowers/plans/2026-09-06-phase-4-delete-acp.md`

This report is written by Task 13 (full-tree verification and documentation), the
final task of the phase. It records the audit, every verification gate run against
the finished tree, the documentation sweep, and the measured size of the deletion.

## Step 1: full-tree audit

Command run verbatim from the brief:

```bash
cd /Users/omaraly/development/AI/Operator
grep -rn "chatdriver\|ChatDriver\|acp-runtime\|SessionModeChat\|/conversation" \
  backend/internal backend/cmd frontend/src packages/mobile/lib packages/mobile/test \
  .github package.json 2>/dev/null | grep -v node_modules | sort
```

First run (before any Task 13 fix), output:

```
backend/internal/cli/hooks_test.go:370:		payload := []byte(`{"prompt":"continue investigating","lastAssistantMessage":"updated","transcriptPath":"/tmp/conversation.jsonl","model":false}`)
backend/internal/cli/hooks_test.go:372:		if conversation.LatestUserPrompt != "continue investigating" || conversation.LatestAssistantUpdate != "updated" || conversation.TranscriptPath != "/tmp/conversation.jsonl" {
```

**Investigated and resolved as a false positive, not a gap.** This is
`backend/internal/cli/hooks_test.go`, which tests the Claude Code CLI hook
metadata parser (`hookConversationFacts`, `hookUsageMetadata`) — nothing to do
with the ACP/chat subsystem. The match is on the literal path string
`/tmp/conversation.jsonl`, a test fixture transcript path, coincidentally
containing the substring `/conversation`. No code change was needed; this hit
is permanent and expected as long as this variable name is grepped for.

Re-run after all Task 13 fixes below, output: identical (same two lines, same
false positive, no other hits). The grep is otherwise clean.

### Real gap found and fixed (not caught by the grep pattern above)

`golangci-lint` (run via Step 2's `npm run lint`) found two `unused` findings
in `backend/internal/storage/sqlite/store/store.go`:

```
backend/internal/storage/sqlite/store/store.go:57:17: func (*Store).conversationWriter is unused (unused)
backend/internal/storage/sqlite/store/store.go:65:17: func (*Store).conversationReader is unused (unused)
```

These were dead leftovers of a removed "conversation-projection transaction"
mechanism: a `conversationProjectionTxKey` context key, `conversationWriter`/
`conversationReader` helpers that consulted it, and a matching branch inside
`inTx`. Confirmed via
`grep -rn "conversationProjectionTxKey" backend/internal` that nothing in the
codebase ever sets this context value (the only reader was `inTx`'s own dead
branch) — the writer side of the mechanism was deleted by an earlier task in
this phase without its now-unreachable reader side. Deleted:

- The `conversationProjectionTxKey` type
- `Store.conversationWriter` and `Store.conversationReader`
- The `if q, ok := ctx.Value(conversationProjectionTxKey{})...` branch inside
  `Store.inTx`

Re-ran `gofmt -l internal/`, `go vet ./...`, `go build ./...`, and
`npm run lint` after the deletion: all clean, `0 issues.` (see Step 2 below for
the full transcript).

### Minor deviations swept per the brief's discretion clause

Two items flagged as Minor by earlier task reviews (not gaps in the audit
grep, but the kind of stale-vocabulary cleanup this step is for) were fixed as
trivial, zero-behavior-impact edits:

1. `backend/internal/lifecycle/manager.go:777` — `isTurnBoundaryEvent`
   checked `event == "chat.controller.stopped"` alongside real events.
   Confirmed nothing in the tree ever emits this string any more
   (`grep -rn "chat.controller.stopped" backend` only matched this check and
   its own test case). Removed the disjunct and the matching test case
   (`"chat-controller-stopped"`) in `backend/internal/lifecycle/toolflight_test.go`.
2. `backend/internal/domain/session.go` and
   `backend/internal/lifecycle/manager.go:1225-1227` — stale comments on
   `ProviderConversationID` describing "a Chat driver" and "the chat
   controller's resume handle". The field itself is untouched (it is still a
   real DB-backed column wired through `sessions.sql`/`gen/`/`session_store.go`
   — confirmed no current code path sets it to a non-empty value, but removing
   the column is a migration change and out of this task's scope). Only the
   comment text was rewritten to describe the field without referencing the
   removed chat subsystem as if it still existed.

Both edits are comment/dead-branch removal only; no method signatures, no
schema, no other prior task's committed logic was touched.

## Step 2: gates (verbatim, run after the fixes above)

### Backend

```
$ cd backend && gofmt -l internal/
(no output)

$ go vet ./...
(no output, exit 0)

$ go test ./... 2>&1 | grep -c "^FAIL"
0
```

Full `go test ./...` output was 149 lines, all `ok` or `[no test files]`, zero
`FAIL` lines.

### `npm run lint` (root) — after fixing the two `unused` findings above

`golangci-lint cache clean` itself is not applicable here: this repo does not
invoke a standalone `golangci-lint` binary (`golangci-lint cache clean` ⇒
`command not found` — there is no such binary on PATH). `npm run lint` instead
runs `go test ./... && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs`,
which uses Go's own build cache, not a golangci-lint CLI result cache — so the
"stale-cache phantom" this step warns about does not apply to this repo's
invocation style. The two `unused` findings below were real (verified by
manual inspection, see Step 1), not phantoms:

First run (before the Step 1 fix):
```
backend/internal/storage/sqlite/store/store.go:57:17: func (*Store).conversationWriter is unused (unused)
func (s *Store) conversationWriter(ctx context.Context) (*gen.Queries, func()) {
                ^
backend/internal/storage/sqlite/store/store.go:65:17: func (*Store).conversationReader is unused (unused)
func (s *Store) conversationReader(ctx context.Context) *gen.Queries {
                ^
2 issues:
* unused: 2
exit status 1
```

Final run (after the fix):
```
... (full go test ./... package list, all ok) ...
0 issues.
```

### `packages/mobile`

```
$ flutter analyze
Analyzing mobile...
No issues found! (ran in 3.1s)

$ flutter test 2>&1 | tail -3
00:36 +1150: .../orchestrator_card_test.dart: opens the orchestrator session
00:36 +1151: .../orchestrator_card_test.dart: (tearDownAll)
00:36 +1151: All tests passed!
```

1151/1151 tests passed, 0 failures.

### `frontend`

```
$ npm run typecheck
> operator@0.10.3 typecheck
> tsc --noEmit
(no errors)
```

```
$ npm run lint 2>&1 | tail -5
✖ 140 problems (0 errors, 140 warnings)
  0 errors and 1 warning potentially fixable with the `--fix` option.
```

0 errors, 140 warnings — all pre-existing ESLint style warnings (React
Compiler memoization notes, fast-refresh export-shape notes) unrelated to the
ACP/chat deletion; none reference chat, ACP, session mode, or conversation
code.

```
$ npm test 2>&1 | tail -5
 Test Files  7 failed | 122 passed (129)
      Tests  5 failed | 1421 passed (1426)
```

**All 7 failing files/5 failing tests are pre-existing and unrelated to Phase
4.** They are entirely inside `frontend/src/landing/` (the marketing website,
not the Tauri desktop app):

- `src/landing/scripts/generate-markdown-twins.test.mjs` (5 tests) — fails
  with a Node `ERR_MODULE_NOT_FOUND` inside the script under test, unrelated
  to any file this phase touched.
- `src/landing/src/app/download/{AndroidAppCTA,AndroidBetaDialog,
  AndroidBetaInstructions,AndroidBetaMobileSheet}.test.tsx`,
  `src/landing/src/lib/analytics/posthog-config.test.ts`,
  `src/landing/src/app/components/DownloadButton/DownloadButton.test.tsx` —
  all fail at Vite transform time with
  `Error: Failed to resolve import "react-icons/fa" ... Does the file exist?`.

Verified this is pre-existing, not caused by this phase:
- `react-icons` is absent from `frontend/package.json` at the branch's fork
  commit (`git show b71cafb0a7a9a850425dabf1e1a30feceb99fc2c:frontend/package.json | grep react-icons` — no output) and absent from
  `node_modules` today — a missing dependency that predates this branch.
- `git log --oneline b71cafb0a7a9a850425dabf1e1a30feceb99fc2c..HEAD -- frontend/src/landing/` — no output: no commit in this
  phase touched `src/landing/` at all.
- The file last touched was `c17b6c3f5 feat: add Android beta landing flow
  (#3799)`, which predates this branch.

No fix was applied — this is out of Phase 4's scope (a pre-existing landing-site
dependency gap, not an ACP/chat remnant) and the brief's mandate is to prove the
ACP/chat deletion is clean, not to fix unrelated pre-existing breakage.

### `npm run api` contract regeneration

```
$ npm run api
> api:spec
> cd backend && go generate ./internal/httpd/apispec/...

> api:ts
> openapi-typescript backend/internal/httpd/apispec/openapi.yaml -o frontend/src/api/schema.ts

✨ openapi-typescript 7.4.4
🚀 backend/internal/httpd/apispec/openapi.yaml → frontend/src/api/schema.ts [150.7ms]

$ git diff --stat backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
(no output)
```

Empty diff, as required — Task 12's regeneration (commit `58c860ce6`) already
left the contract in its final state; nothing regenerated differently here.

## Step 3: documentation sweep

Search command run (per brief):

```bash
grep -rn -i "chat mode\|chat driver\|ACP\|session mode" CLAUDE.md AGENTS.md DESIGN.md docs/architecture.md docs/STATUS.md
```

Hits found and fixed (`AGENTS.md` and `DESIGN.md` had zero hits from this
search):

- `docs/STATUS.md:44-46` — replaced "The ACP/chat subsystem is still in the
  tree but unreachable, and is deleted in Phase 4 of ..." /
  "The dormant ACP/chat implementation and its schema remain compilable
  during the staged removal..." with a single past-tense statement that it
  **was** removed in Phase 4, pointing at this report.
- `docs/STATUS.md:132-133` — replaced "There is no desktop blocks view, Chat
  composer, interface picker, or interface-switch action" (naming three
  concepts that no longer exist anywhere in the codebase, not just on
  desktop) with "There is no other session interface to pick or switch to —
  the desktop has no blocks view" (states the current single-mode fact
  without naming defunct concepts).
- `docs/architecture.md:52-54` — replaced "The legacy `session_mode`,
  conversation, and interface-transition schema remains temporarily so the
  dormant ACP packages compile... Phase 4 deletes that schema" with a
  past-tense statement that this schema **was** deleted in Phase 4.

Broader sweep (beyond the four keywords, since the brief also says "do not
leave 'chat mode is deprecated' wording anywhere") found and fixed:

- `docs/architecture.md:221` — directory-tree line `└── chat/  # Dormant
  until removal in Phase 4` under `backend/internal/service/`. Verified
  `backend/internal/service/chat` no longer exists on disk; removed the tree
  entry.
- `docs/architecture.md:269` — same pattern for
  `backend/internal/adapters/chatdriver/`. Verified the directory no longer
  exists; removed the tree entry.
- `docs/architecture.md` ER diagram (`erDiagram` block, formerly lines
  ~419-476) — removed the `conversations`, `conversation_turns`,
  `conversation_messages`, `conversation_activities`,
  `session_interface_transitions`, `session_interface_transition_messages`
  entities and their relationships (all dropped by migration `0101` in Task
  12), and removed `session_mode` from the `sessions` entity's field list
  (also dropped by `0101`). Kept `provider_conversation_id` and
  `controller_generation` on `sessions`, since both remain real, non-dropped
  columns wired through `gen/` and `store/session_store.go` today.
- `docs/architecture.md` diagram caption — replaced "the `conversations*` and
  `session_interface_*` families are the dormant legacy schema Phase 4
  deletes" with a past-tense statement naming exactly what was dropped
  (including `sessions.session_mode` and `app_settings.default_session_mode`).
- `CLAUDE.md` mobile section — "SSE for chat" was stale (the mobile chat
  feature that consumed `/api/v1/events` for a chat stream was removed in
  Task 3; the endpoint is now consumed by the `blocks`/`terminal` features
  only, confirmed via `grep -rln "events" packages/mobile/lib` — no `chat`
  hits, real hits in `feature/blocks/logic/block_assembly.dart`,
  `blocks_cubit.dart`, `terminal_cubit.dart`, etc.). Reworded to "SSE for the
  daemon's event stream (blocks, terminal)".
- `CLAUDE.md` mobile "Architecture" section — "Twelve features: ...
  `spawn`, `chat`, `terminal`, ..." was stale on two counts: `chat` no longer
  exists (`packages/mobile/lib/feature/` has no `chat` directory — deleted in
  Task 3), and `dictation` (split out of `chat` in this branch's first
  commit, `70b331799`) and `usage` (a pre-existing feature missing from the
  old list) were absent. Corrected to "Thirteen features: ... `terminal`,
  ..., `dictation`, `usage`" with an explicit "There is no `chat` feature"
  sentence, matching the actual 13 directories under
  `packages/mobile/lib/feature/` today.

## `RUN_APP_COMMANDS.md` and `docs/development.md` — stale `acp-runtime` sweep

Task 9's review flagged these as Minor and deferred. Verified
`npm run build:acp-runtime` no longer exists in `frontend/package.json` or
root `package.json` (Task 9 removed it). Fixed:

- `RUN_APP_COMMANDS.md:33` — removed `&& npm run build:acp-runtime` from the
  sidecar-build command line.
- `docs/development.md:174` — removed the `npm run build:acp-runtime` line
  from the sidecar-build code block.
- `docs/development.md:351` — removed `, build:acp-runtime` from the
  troubleshooting table's "cannot find sidecar resources" fix column.

Re-ran the audit grep (Step 1) and a targeted
`grep -rn -i "acp-runtime" RUN_APP_COMMANDS.md docs/development.md CLAUDE.md
AGENTS.md DESIGN.md docs/architecture.md docs/STATUS.md
docs/mobile-parity-ledger.md` after these edits: no output.

## `docs/mobile-parity-ledger.md` — marking chat files as removed in Phase 4

Added a note under the existing header explaining that Phase 4 subsequently
deleted the mobile `chat` feature and its ACP-driven voice/interface-transition
support.

Checked every row's recorded Dart destination against the actual tree
(`packages/mobile/`) with a small script; 41 rows pointed at a path that no
longer exists. Of those, 1 (`lib/feature/pull_request/.../project_switcher.dart`)
is unrelated pre-existing drift (a `pull_request` file, nothing to do with
chat) and was left untouched — out of this task's scope. The remaining 40 rows
were annotated:

- 33 rows whose destination was inside `lib/feature/chat/` (or its test
  counterpart `test/feature/chat/`) and has no surviving replacement — e.g.
  `chat_remote_data_source.dart`, `chat_cubit.dart`, `chat_body.dart`,
  `conversation_*_model.dart`, `elicitation_model.dart`,
  `composer_suggestions.dart`, `chat_preflight.dart` (and its test) — marked
  "Removed in Phase 4 (the ACP/chat subsystem)."
- 7 rows whose destination moved again before/during the chat removal rather
  than disappearing outright, each annotated with its real current path,
  verified to exist on disk:
  - `lib/feature/chat/voice/voice_types.dart` → `lib/feature/dictation/voice_types.dart`
  - `lib/feature/chat/voice/device_provider.dart` → `lib/feature/dictation/device_provider.dart`
  - `lib/feature/chat/voice/logic/voice_input_cubit.dart` → `lib/feature/dictation/logic/voice_input_cubit.dart`
  - `lib/feature/chat/voice/ui/mic_key.dart` → `lib/feature/dictation/ui/mic_key.dart`
  - `lib/feature/chat/logic/keyboard_inset.dart` → `lib/core/utils/keyboard_inset.dart`
  - `test/feature/chat/logic/keyboard_inset_test.dart` → `test/core/utils/keyboard_inset_test.dart`
  - `test/feature/chat/voice/device_provider_test.dart` → `test/feature/dictation/device_provider_test.dart`

## Step 4/5: this report and the measured deletion

This file is `docs/superpowers/plans/2026-09-06-phase-4-report.md`, written as
part of this task. All numbers in this report are measured, not estimated —
see the `git diff --shortstat` commands below and the gate transcripts above.

### Fork point verification

```
$ git log --oneline -1 b71cafb0a7a9a850425dabf1e1a30feceb99fc2c
b71cafb0a docs: add the phase 4 dispatch prompt

$ git log --oneline -1 70b331799
70b331799 refactor(mobile): move dictation out of the chat feature

$ git log --oneline b71cafb0a7a9a850425dabf1e1a30feceb99fc2c..HEAD | tail -1
70b331799 refactor(mobile): move dictation out of the chat feature
```

Confirmed: `70b331799` is the oldest commit reachable from `HEAD` but not from
`b71cafb0a7a9a850425dabf1e1a30feceb99fc2c` — i.e. `b71cafb0a` really is the
commit this branch's work forked from, one commit before Task 1's first
commit, exactly as the brief states.

### Measured `git diff --shortstat`

```
$ git diff --shortstat b71cafb0a7a9a850425dabf1e1a30feceb99fc2c^..HEAD
312 files changed, 1427 insertions(+), 82838 deletions(-)
```

Per-area breakdown (same range, path-scoped; these are not mutually
exclusive of the total — they partition it):

```
$ git diff --shortstat b71cafb0a7a9a850425dabf1e1a30feceb99fc2c^..HEAD -- backend/
137 files changed, 1262 insertions(+), 50846 deletions(-)

$ git diff --shortstat b71cafb0a7a9a850425dabf1e1a30feceb99fc2c^..HEAD -- frontend/
66 files changed, 23 insertions(+), 14894 deletions(-)

$ git diff --shortstat b71cafb0a7a9a850425dabf1e1a30feceb99fc2c^..HEAD -- packages/mobile/
101 files changed, 37 insertions(+), 17080 deletions(-)

$ git diff --shortstat b71cafb0a7a9a850425dabf1e1a30feceb99fc2c^..HEAD -- . ':!backend' ':!frontend' ':!packages/mobile'
8 files changed, 105 insertions(+), 18 deletions(-)
```

The last bucket (8 files, mostly plan/report docs under
`docs/superpowers/`) is planning documentation, not product code.

Within the `frontend/` (desktop) bucket, the Task 9 build/CI removal (ACP
runtime sidecar resource and its pipeline) is a sub-slice:

```
$ git diff --shortstat b71cafb0a7a9a850425dabf1e1a30feceb99fc2c^..HEAD -- \
  frontend/acp-runtime frontend/scripts .github/workflows package.json \
  frontend/package.json frontend/src-tauri/tauri.conf.json \
  frontend/scripts/verify-tauri-artifacts.sh
18 files changed, 15 insertions(+), 1864 deletions(-)
```

So of the frontend bucket's 66 files / 14894 deletions, 18 files / 1864
deletions are build/CI plumbing (the ACP runtime sidecar, its npm scripts, and
the workflow lines that invoked it) and the remaining 48 files / ~13030
deletions are the desktop renderer's chat pane, blocks component tree, and
related UI removed in Tasks 4-5.

**Note on this diff range:** it includes Task 13's own documentation edits
(this report, `CLAUDE.md`, `docs/*.md`, `docs/mobile-parity-ledger.md`,
`RUN_APP_COMMANDS.md`) since it was measured against the working tree before
Task 13's commit. Those are a small number of insertion-heavy doc edits (the
"docs / other" bucket above) and do not materially change the deletion-heavy
character of the phase.

## Migration verification (from Task 12, `task-12-report.md`)

Reproduced verbatim from `.superpowers/sdd/2026-09-06-phase-4-delete-acp/task-12-report.md`,
since the brief calls for it to be recorded here too.

**Step 1 gate (both databases had zero conversation/session-interface rows
before the migration ran):**

```
~/.operator/data/opr.db      conversations: 0
~/.operator/data/opr.db      session_interface_transitions: 0
~/.operator/dev/data/opr.db  conversations: 0
~/.operator/dev/data/opr.db  session_interface_transitions: 0
```

**Migration:** `backend/internal/storage/sqlite/migrations/0101_drop_conversations.sql`
drops `sessions.session_mode` and `app_settings.default_session_mode`, and
drops the `conversations`, `conversation_turns`, `conversation_messages`,
`conversation_activities`, `conversation_branches`, `conversation_provider_events`,
`session_interface_transitions`, and `session_interface_transition_messages`
tables. It also rebuilds the `sessions_cdc_update` trigger without the
`OLD.session_mode <> NEW.session_mode` clause (SQLite refuses `DROP COLUMN`
against a column referenced by a trigger body) and explicitly drops
`conversation_branch_root_provider_update` (a trigger on `sessions` that
referenced the `conversation_branches` table being dropped in the same
migration) — both are narrow, mechanical fixes the brief's literal SQL did
not anticipate, documented in full in `task-12-report.md`.

**Step 5 verification, against a scratch copy of the real dev database:**

```
$ go run ./internal/tmpmigratecheck <scratch dir with a copy of ~/.operator/dev/data/opr.db>
migrations applied

$ sqlite3 <scratch>/opr.db "select max(version_id) from goose_db_version;"
101

$ sqlite3 <scratch>/opr.db "select count(*) from sqlite_master where name in ('conversations','conversation_turns','session_interface_transitions');"
0

$ sqlite3 <scratch>/opr.db "pragma integrity_check;"
ok
```

Additionally exercised the rebuilt `sessions_cdc_update` trigger against the
cloned real database with
`UPDATE sessions SET display_name = 'trigger-test' WHERE id = 'scratch-1';` —
no error, confirming the recreated trigger is functionally sound, not just
syntactically present. Scratch files and the `internal/tmpmigratecheck`
throwaway tool were deleted afterward.

Task 12 additionally had to regenerate `frontend/src/api/schema.ts` a second
time (`npm run api`) after discovering `go generate ./...` only regenerates
`openapi.yaml`, not the TypeScript client — the diff was exactly the removal
of the `mode: "chat" | "tui"` enum field from the `Session` component type,
verified with `npm run typecheck` (no errors). That fix is commit `58c860ce6`,
the current tip of the branch before this task's commit.

## Where the plan turned out to be wrong (all tasks, verified against this
## plan's workspace, not just summarized)

- **Task 6** found **17** conversation/chat routes to delete, not 18 as the
  plan's text said — a harmless miscount with no functional consequence
  (verified: `task-6-report.md` records the enumerated route list and the
  final route-count gate).
- **Task 9** had to expand its scope to 6 files not in its original brief to
  make its own "no acp-runtime string anywhere" grep pass clean:
  `frontend/scripts/build-acp-runtime-helpers.mjs` (and its test),
  `benchmark-artifact.mjs`, `benchmark-result.test.mjs`, `no-electron.test.mjs`,
  and `phase0-platform-summary.test.mjs` — all of which referenced the
  ACP runtime resource or its build script and had to be updated or deleted
  alongside the primary removal (`task-9-report.md`).
- **Task 6** also found `backend/e2e/chat_*_test.go` (9 files) plus
  `harness_test.go` were permanently dead — they called routes Task 6 was
  about to delete, and were gated behind `OPERATOR_CHAT_E2E=1`, so CI never
  ran them and never would have caught the break. Deleted alongside the route
  removal.
- **Task 10** found and deleted a dead `TerminalInputGate` /
  `beginTerminalInputDrain` / `CommitControllerEpoch` mechanism spanning
  `session_manager/manager.go`, `lifecycle/manager.go`, `lifecycle_wiring.go`,
  and `daemon.go` — a chat-interface-transition leftover not named in any
  task's original file list, found only because Task 10 traced every caller
  of the code it was asked to delete (`task-10-report.md`).
- **Task 11** found `domain.SessionMode` was far more load-bearing than the
  plan assumed: a real DB-backed column, a parameter threaded through the
  agent-port interface (`AgentInterfaceHandoff.NativeConversationID`), and
  present in sqlc-generated code — removing it cleanly required deferring the
  schema-level drop to Task 12 rather than doing it all in one task
  (`task-11-report.md`).
- **Task 12**'s migration had to extend beyond its literal SQL text to rebuild
  two triggers (`sessions_cdc_update`, and drop
  `conversation_branch_root_provider_update`) that referenced the column/table
  being dropped — the plan's SQL alone does not apply cleanly to a real
  database with production history. Verified against a real cloned copy of
  the dev database (see Migration verification above).
- **Task 12** also found `frontend/src/api/schema.ts` needed a second
  regeneration pass (`npm run api`, not just `go generate ./...`) after the
  Go-side OpenAPI spec changed — `go generate` only touches the spec's Go
  side, not the generated TypeScript client.
- **Task 9**'s review flagged (Minor) stale `acp-runtime` mentions in
  `RUN_APP_COMMANDS.md` and `docs/development.md`, deferred to this task and
  fixed above.
- **Task 11**'s review flagged (Minor) a stale `"chat.controller.stopped"`
  event-string literal in `lifecycle/manager.go:777` and a stale comment near
  `ProviderConversationID`, deferred to this task and fixed above (see "Minor
  deviations swept" under Step 1).
- **This task (13)** found one gap none of the above caught: two now-dead
  `Store` methods (`conversationWriter`/`conversationReader`) and their
  backing context key, orphaned when an earlier task deleted the writer side
  of a conversation-projection-transaction mechanism but left the reader side
  in place. Caught by `golangci-lint`'s `unused` check during Step 2, not by
  the Step 1 grep pattern (the identifiers don't contain any of the grep's
  literal search strings). Fixed by deletion; see Step 1 above.

## Checkbox left unticked, and why

**Task 13 Step 7 (live verification) is intentionally left unticked in
`docs/superpowers/plans/2026-09-06-phase-4-delete-acp.md`.** That step requires
restarting the daemon **from the desktop app**, not from an agent shell — an
agent shell leaks environment variables (`CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`,
`ANTHROPIC_BASE_URL`, and roughly thirty others) into any process it spawns,
and a daemon started that way would have those variables and could interfere
with or be killed alongside the agent session within about 300ms. This is
explicitly the user's step per the brief and the dispatch instructions, and no
substitute was attempted. Every other checkbox for Tasks 1-13 in the plan file
is ticked.

## Self-review

- Step 1's audit grep genuinely ran twice (before and after fixes) with real,
  pasted output both times; the one surviving hit was investigated down to
  the exact test file, function, and reason it's a false positive, not
  asserted away.
- A real gap (`conversationWriter`/`conversationReader`) was found by a gate
  this step also runs (`npm run lint`), even though the Step 1 grep pattern
  itself missed it — investigated fully, confirmed dead via a targeted grep
  for every reference to `conversationProjectionTxKey`, and fixed by
  deletion, then all gates re-run clean.
- Every Step 2 gate output above is pasted from an actual command run in this
  session (backend gofmt/vet/test, npm run lint before-and-after, flutter
  analyze/test, frontend typecheck/lint/test, npm run api + diff), not
  assumed or inferred from prior task reports.
- The `npm run api` diff is genuinely empty — verified with the actual
  `git diff --stat` command, not merely stated.
- This report contains no placeholders — every number is either pasted
  command output or a `git diff --shortstat` result run in this session.
- All checkboxes for Tasks 1-13 are ticked in the plan file except Task 13's
  own Step 7, left unticked per the brief's explicit instruction.

## Concerns

1. The frontend `npm test` suite has 7 pre-existing failing files / 5 failing
   tests, entirely inside `frontend/src/landing/` (marketing site), caused by
   a missing `react-icons` dependency and an unrelated Node module-resolution
   error in a build script. Verified pre-existing (predates this branch's
   fork point, no commit in this phase touches `src/landing/`). Not fixed,
   since it is out of Phase 4's scope — flagging here so it isn't mistaken for
   fallout from the ACP/chat deletion.
2. Task 13 Step 7 (live verification) is explicitly not attempted by this
   agent, per the brief and per the standing rule against agents restarting
   the daemon. See "Checkbox left unticked" above.
