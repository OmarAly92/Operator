Implement the background-pane plan with the superpowers:subagent-driven-development skill: a fresh implementer subagent per task and a fresh reviewer subagent after each one, in order, Tasks 2 through 12. Do not merge, push or touch `development`; a separate session reviews the branch when you finish.

## Where you work

- Worktree: `/Users/omaraly/development/AI/Operator-background-pane`, branch `terminal-background-pane`, created from `development` at `11323ce3d`. It is already set up: `npm ci` ran in `packages/terminal` and `frontend`, and `packages/terminal` was built (`npm run build:wasm -- --force && npm run build:ts`). Baseline measured in the worktree on 2026-09-23: vitest core 79, renderer-dom 879, editor 125, react 111 passing; `frontend` `TerminalPane.test.tsx` + `BlockTerminal.test.tsx` + `hooks/useTerminalSession.test.tsx` 146 passing; `npx tsc --noEmit -p .` in `frontend` clean; `npm run bench:feel` zero pixel diff; `npm run bench:selection` passing; `node bench/agent-session/run.mjs --panes-only` runs.
- **Every command in the plan is written with `/Users/omaraly/development/AI/Operator/…`. That is the shared main checkout, where other sessions commit.** Run every command with the prefix replaced by `/Users/omaraly/development/AI/Operator-background-pane/…`. Never `cd` into, edit, build or commit in `/Users/omaraly/development/AI/Operator`. Before every commit run `git -C /Users/omaraly/development/AI/Operator-background-pane branch --show-current` and confirm it prints `terminal-background-pane`.
- The plan says commits go to `development`. **Override: every commit goes on `terminal-background-pane` in the worktree.** Commit with an explicit path list (the plan gives one per task). Never `git stash`, never `git commit -a`, never `git add -A`/`.`. Every commit message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Read first, end to end, before dispatching Task 2

1. `TERMINAL.md` (in the worktree), all of it. It holds the terminal pipeline, the hard rules (§3: `packages/terminal` is product-independent; no comments in new code; match and cite Warp), the solved bugs and the exact verify recipe (§6). Note: §4.24 now exists (the reshown-grid fix from split view), so this plan's new entry is §4.25.
2. `AGENTS.md` and `CLAUDE.md`.
3. The measurement the plan argues from: `docs/superpowers/specs/2026-09-23-background-pane-cost-measurement.md`.
4. The plan: `docs/superpowers/plans/2026-09-23-terminal-background-pane-cost.md`, all of it, including "Why this plan has this shape", "Split view has landed", "Global Constraints" and "Review Focus". Every implementer gets its own task's full text **plus** those four sections verbatim. Reviewers get the same, plus the task's diff.

## Facts implementers get wrong unless told

- **Task 1 is done.** The measurement (bench rows, WKWebView probe `scripts/probe-wkwebview-hidden.swift`, raw runs, note) is committed. Confirm it with the Task 1 command and move on.
- **The app and the bench run the built `dist/`, not source.** After any change under `packages/terminal/ts`, run `npm run build:ts` in `packages/terminal` before a bench, a Playwright gate or a real-app check.
- **No comments in new code.** The only exception is a reference citation naming a repository and path. Existing comments may be corrected when they become false (Task 10 must correct the "ownership boundary, not an LRU event" comment at `TerminalPane.tsx:508-510`).
- **`packages/terminal` never learns Operator's phases.** It only knows `visible: true | false | unset`. Operator wiring lives in `frontend/`.
- **jsdom does not reflect the `inert` property to the attribute.** Tests set `setAttribute("inert", "")`. The plan's test code already does; keep it that way.
- **Budgets.** `FEED_BUDGET_MS` (12), `PAINT_INTERVAL_MS`, `RESIZE_DEBOUNCE_MS` and every `RendererFeatures` default stay unchanged. The only other budget is Task 7's `HIDDEN_DRAIN_MS = 250`, used only by the hidden-document timer tick through `drain(deadlineMs)`.
- **`RETAINED_TERMINAL_UNLOAD_MS = 30 * 60_000` is the user's decision.** If Task 9's numbers argue for another value, write the numbers and the reason in the measurement note and in your final report. Do not change the value. Task 10's real-app check uses a temporary local 60 s value that is never committed: confirm `git diff` on `frontend/src/renderer/lib/retained-terminal.ts` is empty before that commit.
- **No visible pane may paint differently.** `npm run bench:feel` must print `PASS feel gate: zero pixel diff` after every task. Never re-record baselines (`--record`) in this plan.
- **Split view is merged.** An unfocused split pane is on screen: it must paint and report `visible: true`. `visible`/`isRendered` is never derived from `focused`. `be9d35222`'s four reshown-grid tests in `frontend/src/renderer/hooks/useTerminalSession.test.tsx` must stay green; the plan adds that file to Tasks 6, 10 and 8's runs.
- **Boundary check baseline.** `npm run check:boundaries` in `packages/terminal` already fails on `development`, with exactly these 11 file-length lines (limit 600): `crates/vt-core/src/{block_grid.rs,parser.rs,row_index.rs,screen.rs}`, `crates/vt-host/src/lib.rs`, `ts/react/src/{TerminalSurface.mouse.test.tsx,TerminalSurface.test.tsx,TerminalSurface.tsx}`, `ts/renderer-dom/src/{dom-block-renderer.test.ts,dom-block-renderer.ts,link-parsing.test.ts}`; `check-no-ownership-timer.mjs` passes. After each task that touches `packages/terminal`, run both scripts. The failure list may only contain those 11 files, and no new file. Keep new files at 600 lines or fewer: if `dom-block-renderer.visibility.test.ts` would pass 600, move the "hidden document" describe into `dom-block-renderer.hidden.test.ts` with the same helpers. The timer check must stay green; it scans line-editor files, and Task 5 adds no timer there.
- **Plan code versus reality.** The plan's code was written against the tree and is meant to be used as written. When an existing helper or a name differs (for example a test file's render helper, or a mock's shape), adapt minimally and record it under "Deviations" in the report.
  - When the plan says a characterization test must pass first (Task 2) and it does not, stop that task and record it; do not proceed on a false assumption.
  - Never loosen a test to make it pass. Two are guarded explicitly: Task 7's ~2 MiB bound (at most 3 drain calls, called with `HIDDEN_DRAIN_MS`) must not be loosened to a bound a 12 ms budget would also pass, and Task 8's expectations are reported as met or missed, never tuned.
- **Test first, and prove it.** Each new-behaviour test is run and seen failing before the implementation. Put the failing run's one-line result, e.g. `FAIL … keeps draining a hidden pane … expected 0, received 14`, in the task's commit message body and in the report. Task 2's characterization tests pass before and after, and the report says so.

## Real-app steps (Tasks 6, 7, 8, 9, 10, 11, 12)

- **Launch.**
  - Run `npm run build:ts` in the worktree's `packages/terminal` first.
  - Check that nothing already listens on the dev ports: `lsof -nP -iTCP:3002 -iTCP:5173 -sTCP:LISTEN`. If something does (the user's own dev app), do not kill it: record the step as "not verified — dev ports busy".
  - Launch from the worktree's `frontend/` with the inherited Claude environment scrubbed: `env $(env | grep -o '^CLAUDE[A-Z_0-9]*=' | sed 's/=$//; s/^/-u /') -u OPERATOR_DATA_DIR -u OPERATOR_RUN_FILE -u OPERATOR_PORT npm run tauri:dev`. Without the scrub, every agent Operator spawns inherits this session's `CLAUDE_CODE_CHILD_SESSION` and writes no transcript.
  - Confirm the daemon carries no `CLAUDE*` variables: `ps eww` on its pid.
  - The dev daemon listens on `127.0.0.1:3002` with data under `~/.operator/dev/data`. Its loopback API needs no auth; request schemas are in `backend/internal/httpd/apispec/openapi.yaml`. Terminals can be read and driven over `ws://127.0.0.1:3002/mux` (`backend/internal/terminal/protocol.go`).
- **Evidence.** Desktop automation cannot click the Tauri window. Screenshots work with `screencapture -x -l<CGWindowID> out.png`; get the window id from a small Swift `CGWindowListCopyWindowInfo` program filtered by the dev binary's pid (`pgrep -f target/debug/operator`). Hiding the app can be tried with a small Swift `NSRunningApplication(processIdentifier:)?.hide()` program: the WKWebView probe showed an app-hide makes `document.visibilityState` `hidden` just as minimising does. `osascript` keystrokes are blocked.
- **Reporting.** Every real-app step ends as **observed** (what you saw, plus the evidence file path under `docs/superpowers/evidence/2026-09-23-terminal-background-pane/`, committed on the branch) or **not verified** (with the reason). Never report one as passing from tests or bench numbers.
- **Cleanup.** Stop every session you spawned (`POST /api/v1/sessions/{id}/kill` on :3002) and stop `tauri:dev` (kill its process group) when a step is done. Agent processes outlive the daemon; `pgrep -f "pty-host .* /Users/omaraly/.operator/dev/data"` finds leftovers.
- **Soaks.**
  - The 30-minute bench soak (`npm run bench:soak -- --minutes 30`) and the 120-minute real-app soaks (Tasks 9 and 12) may run in the background while you continue with later tasks. The unload delay is fixed, so Task 10 does not wait on Task 9's numbers.
  - Task 12's real-app run needs Task 10 and Task 11 merged into the running build, so start it only after both are committed and `dist` is rebuilt.
  - If a soak cannot run to the end, report exactly how far it got, or "not verified". Never substitute bench numbers for a real-app run.

## Per-task gate (on top of the plan's own steps)

After each implementer finishes, the reviewer checks four things and records them in the report:
- the diff matches the task's text, Global Constraints and Review Focus;
- the failing-first evidence exists;
- TERMINAL.md §6 for the layers the task touched passed, with absolute worktree paths: `for p in core renderer-dom editor react; do (cd /Users/omaraly/development/AI/Operator-background-pane/packages/terminal/ts/$p && npx vitest run); done`, `npm run bench:feel`, `npm run bench:selection`, plus `bench:agent:gate`/`bench:agent:scroll` where the task says so, and for `frontend/` tasks `npx tsc --noEmit -p .` and the named vitest files;
- the boundary check shows no new violation.

The implementer fixes what the reviewer finds before the next task starts.

At the end, after Task 12, run the whole-branch gate in the worktree:
- all four package vitest suites;
- `npm run check:boundaries` (only the 11 known lines);
- `bench:feel`, `bench:selection`, `bench:agent:gate`, `bench:agent:scroll`;
- `node bench/agent-session/run.mjs --panes-only`;
- in `frontend/`: `npm test` (the full renderer suite), `npx tsc --noEmit -p .`, `npm run lint`.

## Final report

Write `docs/superpowers/reports/2026-09-23-terminal-background-pane-report.md` in the worktree and commit it on the branch. It contains:
1. a table of tasks with commit hashes;
2. failing-first evidence per task;
3. the test counts before and after for each suite;
4. the pane bench before and after (1 alone, 1+3, 1+9 and 10 visible: TaskDuration, layouts and style recalcs, `parkedMutations`);
5. the memory rows and both soaks (bench and real app), with numbers or "not verified";
6. each real-app step as observed or not verified, with evidence paths;
7. "Deviations" from the plan, each with its reason;
8. whether every Task 8 expectation was met or missed;
9. anything found and not fixed, including anything a reviewer parked as minor.

Then reply with the branch name, the head commit, and a ten-line summary. Do not merge or push.
