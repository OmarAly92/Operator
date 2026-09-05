# Mobile Context Readout and Usage Rollup — Implementation Report

Consolidates the per-task worker/review notes (originally scattered as
`task-*-report.md` / `task-*-rereview.md` files at the worktree root) into one
place, plus the results of the tasks completed in this session (11–13) and the
manual steps still owed for Task 14.

## Tasks 1–10 (prior sessions, committed)

All green on first or second pass. Notable findings folded in during review:

- **Task 4 (Codex context capture)** — first pass had a bug: every accepted
  Codex token-count event assigned `result.Context`, including **child**
  rollout sources (non-empty `SubagentID`), which could overwrite the parent
  session's context with a subagent's independent window (violates F7). Fixed
  by gating the assignment to `source.Source.SubagentID == ""` and adding
  `TestParseCodexChildDoesNotReportContext`. Re-review confirmed PASS.
- **Task 5 (persistence)** — the originally proposed weekly bucketing SQL,
  `date(occurred_at, 'weekday 1', '-7 days')`, was verified against a test
  proving Monday stays its own bucket. A follow-up review fix made context
  persistence transactional (`ApplyUsageChunkWithContext`): a failed context
  write now rolls back the whole chunk instead of partially persisting, and
  `SaveSessionContext` only updates when the incoming observation is dated and
  not older than what's stored (migration `0099_usage_context_model.sql` adds
  `context_model_id` for this). `golangci-lint` as a bare binary was
  unavailable in that sandbox (`command not found`); the pinned
  `go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run
  --path-mode=abs` was used instead and returned 0 issues.
- **Task 7 (HTTP endpoints)** — added a follow-up test
  (`TestRollupServiceErrorIs500`) covering a summary-service failure on a
  valid rollup request; no production code change was needed, the existing
  handler already routed it through `envelope.WriteError`. One transient,
  unrelated timeout was observed in `TestShellBlocksRestartAdoptsLiveHelperAndJournal`
  during `npm run lint`; it passed in isolation and on the full suite rerun,
  so treated as flake, not a regression.
- **Tasks 6, 8, 10** — straightforward TDD passes, no findings.

## Task 11 — Context chip on the blocks screen

**Status: DONE.**

Picked up as uncommitted work-in-progress with two defects:

1. **Trivial lint** — `session_command_cubit.dart:234`, an if-statement body
   not wrapped in braces (`curly_braces_in_flow_control_structures`). Fixed.
2. **Real bug** — `blocks_body.dart` wrapped the sticky header in an
   unconditional `BlocBuilder<SessionCommandCubit, SessionCommandState>`. The
   pre-existing (unmodified) test
   `test/feature/blocks/presentation/block_selection_test.dart` pumps
   `BlocsBody` standalone with only a `BlocProvider<BlocksCubit>` above it —
   no `SessionCommandCubit` ancestor — and started throwing
   `ProviderNotFoundException` through that `BlocBuilder`.

**Resolution chosen:** kept `contextReadout` on `SessionCommandCubit` exactly
as specced (the plan is explicit that context refresh piggybacks on the
existing `onActivity`/refresh tick and must not become a second poll loop),
but made *consumption* of that cubit defensive instead of a hard requirement.
Introduced a small private widget, `_StickyHeaderWithContextReadout`, local to
`blocks_body.dart`, that does:

```dart
try {
  readout = context.select<SessionCommandCubit, ContextReadoutData?>(
    (cubit) => cubit.state.contextReadout,
  );
} on ProviderNotFoundException {
  readout = null;
}
```

`context.select` (from `package:provider`, re-exported transitively through
`flutter_bloc`) preserves the original `BlocBuilder`'s narrow-rebuild
semantics (rebuilds only when `contextReadout` changes) while degrading
gracefully to "no observation available" — i.e. `ContextReadoutChip(readout:
null)`, which already renders `SizedBox.shrink()` — when no
`SessionCommandCubit` is above it in the tree. This is neither a pure "hoist
the provider" fix (doesn't help `block_selection_test.dart`, which pumps
`BlocsBody` in total isolation) nor a pure "decouple the data source" fix
(would contradict the plan's single-poll-loop instruction and duplicate
refresh logic) — it keeps the data source as specced and only hardens the
read site.

No import of `package:provider/provider.dart` was needed in the end —
`flutter_bloc` already re-exports the used symbols (`ProviderNotFoundException`,
`context.select`), and adding the explicit import triggered an
`unnecessary_import` lint, so it was removed again (and a `provider` pubspec
dependency add tried in passing was reverted along with it).

Gates:

```
flutter analyze
Analyzing mobile...
No issues found! (ran in 3.2s)

flutter test
...
+1382: All tests passed!
```

The 7 previously-failing tests in `block_selection_test.dart` now pass
unmodified, alongside the existing (also unmodified in behavior)
`blocks_body_test.dart` chip-rendering case ("the context readout is attached
to the sticky block header").

Commit: `9be299afb feat(mobile): show context occupancy on the blocks screen`

## Task 12 — Daily/weekly usage screen

See the session's final `git log --oneline` for the commit hash; details
recorded there since this document was written before Task 12 started.

## Task 13 — Settings entry point + final gate

See the session's final `git log --oneline` for the commit hash.

## Task 14 — Live verification against a real daemon

**Status: NOT ATTEMPTED — requires a human with the desktop app.**

Task 14 has no code deliverable; it is a live check against a running daemon.
The plan's own Step 1 warns that a daemon launched from an agent's shell
inherits `CLAUDE_*`/`ANTHROPIC_*` environment variables, and every agent that
daemon spawns then exits immediately — the daemon must be restarted from the
desktop app, which a spawned subagent with no GUI cannot do. Per explicit
instruction, this session did not hand-launch the daemon from a shell to fake
around that constraint.

**A human needs to do the following manually** (commands verbatim from the
plan) and record the actual output in place of the placeholders below:

1. Restart the daemon **from the desktop app** (not from a shell) so it picks
   up this branch.

2. Spawn a session and take a few turns:
   ```bash
   curl -s -X POST http://127.0.0.1:3002/api/v1/sessions \
     -H 'Content-Type: application/json' \
     -d '{"projectId":"scratch","prompt":"say ok","harness":"claude-code","kind":"worker"}'
   ```
   Then send two or three more messages so cumulative and occupancy diverge.

   Result: _(fill in)_

3. Confirm context is occupancy, not the cumulative total:
   ```bash
   curl -s http://127.0.0.1:3002/api/v1/usage/sessions/<id> | python3 -m json.tool
   ```
   Expected: `context.used` close to the newest turn's input total, and much
   smaller than `totals.inputTokens`. If they're equal on a multi-turn
   session, the parser is reporting the sum (the F1 bug) and the task is not
   done.

   Result: _(fill in)_

4. Confirm the rollup buckets:
   ```bash
   curl -s 'http://127.0.0.1:3002/api/v1/usage/rollup?bucket=day&days=7' | python3 -m json.tool
   curl -s 'http://127.0.0.1:3002/api/v1/usage/rollup?bucket=week&days=28' | python3 -m json.tool
   ```
   Expected: today's bucket non-zero; pre-migration events absent.

   Result: _(fill in)_

5. Confirm a Codex session reports a window: spawn with
   `"harness":"codex"`, take a turn, then check `context.window` is non-zero
   and `context.used` is below it.

   Result: _(fill in)_

6. Check it on the phone: open the session on the paired device. Claude
   sessions should show a token count with no bar; Codex sessions a
   percentage and a bar. Settings → Token usage should list today.

   Result: _(fill in)_

7. Once all of the above are recorded, tick Task 14's checkboxes in
   `docs/superpowers/plans/2026-09-05-mobile-context-and-usage.md`.

## Commit log for this session

See the final message of the session for the authoritative
`git log --oneline` covering everything done in this pass (Task 11 fix,
Task 12, Task 13).
