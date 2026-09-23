# Terminal background-pane plan: execution report (2026-09-23)

Plan: `docs/superpowers/plans/2026-09-23-terminal-background-pane-cost.md`. Branch `terminal-background-pane` in the worktree `/Users/omaraly/development/AI/Operator-background-pane`, from `11323ce3d` to `e5b2a466a`. Not merged, not pushed.

**Gate status: no gate failed.** Every Part 1 gate passed on the first run (details in section 3 and the gate list below). The boundary check fails only with the 11 known file-length lines, as it did before the plan.

Whole-branch gate, run 2026-09-23 07:00–07:10 EEST at `e5b2a466a`, after `npm run build:ts` in `packages/terminal`. `uptime` at the start: `load averages: 5.51 7.57 8.33` (10 cores). Benches were run one at a time.

| gate | result |
|---|---|
| vitest core | `Test Files 8 passed (8)`, `Tests 79 passed (79)` |
| vitest renderer-dom | `Test Files 52 passed (52)`, `Tests 901 passed (901)` |
| vitest editor | `Test Files 13 passed (13)`, `Tests 127 passed (127)` |
| vitest react | `Test Files 9 passed (9)`, `Tests 115 passed (115)` |
| `npm run check:boundaries` | exit 1 from `check-boundaries.mjs`; short-circuits before the timer check |
| `check-boundaries.mjs` alone | exit 1, exactly the 11 known lines (block_grid.rs 651, parser.rs 927, row_index.rs 754, screen.rs 624, vt-host lib.rs 735, TerminalSurface.mouse.test.tsx 604, TerminalSurface.test.tsx 738, TerminalSurface.tsx 727, dom-block-renderer.test.ts 1113, dom-block-renderer.ts 1278, link-parsing.test.ts 855); no new file |
| `check-no-ownership-timer.mjs` alone | `no ownership timers found (5 files scanned)`, exit 0 |
| `npm run bench:feel` | `PASS feel gate: zero pixel diff` |
| `npm run bench:selection` | `PASS selection survived 21 repaints` |
| `npm run bench:agent:gate` | `PASS agent-session gate` (tornStates 0, tornPaints 0, longTasks 0; idle panes 1.769 s, reported not gated) |
| `npm run bench:agent:scroll` | exit 0, no FAIL: covered 60134/60134, 2245 steps, framesOver50ms 0; trim anchor row 25031 before and after; width 30066/30066 |
| `run.mjs --panes-only` | exit 0; see section 4 |
| frontend `npm test` | `Test Files 157 passed (157)`, `Tests 1595 passed (1595)` |
| frontend `npx tsc --noEmit -p .` | exit 0, no output |
| frontend `npm run lint` (`eslint src`) | exit 0, `173 problems (0 errors, 173 warnings)` |

## 1. Tasks and commits

`git log --oneline 11323ce3d..HEAD` plus Task 1.

| task | commit | subject |
|---|---|---|
| 1 | `67590e521` | bench(terminal): measure parked-pane cost and the hidden-window frame stall (pre-existing) |
| 2 | `5070bd8f7` | refactor(terminal): block-finished detection is its own renderer step |
| 3 | `dfb7728f5` | feat(terminal): a host-stated visibility seam on the renderer |
| 4 | `6f8e38973` | feat(terminal): a hidden pane drains and reports blocks but does not paint |
| 4 fix | `00e6c0007` | test(terminal): pin the one synchronous paint on a park/show within a frame |
| 5 | `35b8388e0` | feat(terminal): the line editor idles while its pane is hidden |
| 5 fix | `61a961cd5` | fix(terminal): apply visibility to a freshly-mounted renderer and editor |
| 6 | `c59ff6492` | feat(terminal): parked worker panes stop painting |
| 7 | `cb7b34b3b` | fix(terminal): drain and report finished blocks while the window is hidden |
| 7 fix | `1b76f26fd` | test(terminal): pin the hidden timer and listener cleanup on dispose |
| 8 | `3f2d8f626` | docs(terminal): parked-pane cost after the paint gate |
| 9 | `8378d78af` | bench(terminal): memory per retained pane and a long-run soak |
| 10 | `30245fc3a` | feat(terminal): unload a pane left in the background for thirty minutes |
| 11 | `13ad4994d` | feat(terminal): notify finished commands of unloaded shell panes from the daemon |
| 12 | `325409847` | docs(terminal): long-run cost after unloading background panes |
| final fix | `731a1f2a3` | test(terminal): an unloaded pane reopens with one live attachment |
| final fix | `0961fb455` | fix(terminal): re-watch an unloaded shell's blocks after the mux socket drops |
| final fix | `1dcd0c04e` | docs(terminal): group the background-pane CHANGELOG entries and correct the show paint |
| final fix | `e5b2a466a` | fix(terminal): keep a parked shell pane holding an unsent draft loaded |

## 2. Failing-first evidence per task

- **Task 2**: characterization: passed before and after (4 passed before the extraction; renderer-dom 883 passed after). The plan's original alt-screen test failed first (`expected [] to have a length of 1 but got +0`), which led to ruling R6 (section 7).
- **Task 3**: `TypeError: renderer.setVisible is not a function` (`Tests 4 failed | 4 passed (8)`); react: `Error: The property "setVisible" is not defined on the object.`
- **Task 4**: `FAIL paint gate > keeps draining a hidden pane without touching its DOM: AssertionError: expected 196 to be +0` (plus 2 more: tail not painted on reveal, `expected 1 to be +0` for round-trip sampling). Fix round sabotage: `FAIL … paints once when hidden and shown again before any frame ran: AssertionError: expected <div data-terminal-row="0" …> to be <div …>` (forced rebuild) and `AssertionError: expected +0 to be 1` (synchronous paint replaced by `scheduleRepaint`).
- **Task 5**: `TypeError: editor.setVisible is not a function`; react: `Error: The property "setVisible" is not defined on the object.` Fix round: `FAIL … mounts a fresh renderer and editor already hidden when the mount effect reruns while parked: AssertionError: expected last "setVisible" call to have been called with [ false ]`.
- **Task 6**: `Tests 4 failed | 79 passed (83)`, `Expected: "false" Received: "undefined"` (`TerminalPane.test.tsx:347`, "paints a retained terminal on screen and stops painting it while parked").
- **Task 7**: `Tests 3 failed | 8 passed | 10 skipped (21)`: `expected undefined to match object { visible: false }`, `expected true to be false` (backlog), and a 5000 ms timeout on the ~2 MiB test. With `drain()` unbounded: `expected "drain" to be called with arguments: [ 250 ]` and `expected 10 to be less than or equal to 3`. Fix round sabotage: `AssertionError: expected "clearTimeout" to be called with arguments: [ …(1) ]` and `expected "removeEventListener" to be called with arguments: [ 'visibilitychange', …(1) ]`.
- **Task 8**: N/A (measurement/docs).
- **Task 9**: N/A (measurement/docs).
- **Task 10**: `Error: Failed to resolve import "../lib/retained-terminal"`, then with the constant only: `× unloads a pane left parked for the unload delay and reopens it fresh — AssertionError: expected <div …> to be null` (`Tests 1 failed | 2 passed | 44 skipped (47)`).
- **Task 11**: `Tests 4 failed | 1 passed | 70 skipped (75)`: `Failed to resolve import "./shell-block-notifications"`, `TypeError: mux.onTerminalBlock is not a function`, `expected "show" to be called 1 times, but got 0 times`, `expected undefined to be 1` (×2).
- **Task 12**: N/A (measurement/docs).
- **Final fix wave**:
  - Finding 1: `FAIL unloaded shell notifications > watches an unloaded shell again after the mux socket drops -- AssertionError: expected 1 to be +0`. Release-during-backoff sabotage: both tests `expected 1 to be +0`.
  - Finding 2: `FAIL … reports each change of the unsent draft to the host -- AssertionError: expected [] to deeply equal [ 'l', 'ls', '', 'pwd' ]`; `FAIL … tells the host what the editor holds unsent … expected last "vi.fn()" call to have been called with [ 'l' ]`; `FAIL … keeps a parked shell holding an unsent draft loaded until the draft is gone -- AssertionError: expected false to be true`.
  - Finding 3 sabotage: `FAIL TerminalPane focus > an unloaded pane reopens once, with one attachment -- AssertionError: expected 3 to be 2`.
  - Findings 4 (CHANGELOG) and 6 (debug log): no test.

## 3. Test counts before and after

| suite | before (worktree, 2026-09-23) | after (Part 1) |
|---|---|---|
| vitest core | 79 | 79 (8 files) |
| vitest renderer-dom | 879 | 901 (52 files) |
| vitest editor | 125 | 127 (13 files) |
| vitest react | 111 | 115 (9 files) |
| frontend `TerminalPane.test.tsx` + `BlockTerminal.test.tsx` + `hooks/useTerminalSession.test.tsx` | 146 | 160 (3 files) |
| frontend full `npm test` | not measured before | 1595 (157 files) |

## 4. Pane bench before and after

`run.mjs --panes-only`, `claude-spinner-10s`, seconds of main-thread time per 10 s.

| row | before: TaskDuration (3 runs) | before: layouts / recalcs | before: `parkedMutations` | after (Task 8, 3 runs) | after (Task 8): layouts / recalcs, `parkedMutations` | after (Part 1 run) | after (Part 1): layouts / recalcs, `parkedMutations` |
|---|---|---|---|---|---|---|---|
| 1 alone | 0.354 / 0.392 / 0.232 | 122 / 222 | counter did not exist | 0.458 / 0.419 / 0.420 | 122 / 222, 0 | 0.643 | 122 / 222, 0 |
| 1 + 3 parked | 0.532 / 0.617 / 0.642 | 488–489 / 888–889 | counter did not exist; 8145 in `run.mjs --panes-only --ungated` (`2026-09-23-sources/review-ungated.json` reads 8145) | 0.445 / 0.448 / 0.478 | 122 / 222, 0 | 0.747 | 122 / 222, 0 |
| 1 + 9 parked | 0.886 (profiler) / 1.004 / 0.939 | 1220–1221 / 2220–2221 | counter did not exist; 24435 in `run.mjs --panes-only --ungated` (`2026-09-23-sources/review-ungated.json` reads 24439) | 0.526 / 0.528 / 0.518 | 122–123 / 222–223, 0 | 0.857 | 123 / 223, 0 |
| 10 visible | 1.083 / 0.855 / 1.133 | 1220–1221 / 2256–2257 | — | 1.326 / 1.324 / 1.296 | 1220–1221 / 2256–2257, 0 | 1.721 | 1221 / 2257, 0 |

Part 1 `parkedState`: parked3 3 × `{backlog false, generation 118, rows 27}`, parked9 9 × the same. The `bench:agent:gate` run in Part 1 re-ran these rows: solo 0.669, parked3 0.731, parked9 0.827, visible10 1.750 s, layouts the same, `parkedMutations` 0.

Machine load:
- Before (Task 1): load not recorded in the measurement note.
- Task 8: load average 31–54 on 10 cores during the runs, peaking near 100. Task 8 ran the pre-plan tree `11323ce3d` as a control, interleaved with the branch `1b76f26fd`, three runs each. Control solo 0.430 / 0.445 / 0.419 vs branch 0.413 / 0.432 / 0.402; parked3 0.767–0.795 (488–489 layouts) vs 0.458–0.476 (122–123); parked9 1.291–1.311 (1221 layouts) vs 0.527–0.556 (122–123); visible10 1.290–1.327 vs 1.276–1.327. Per parked pane: pre-plan 95.6–99.1 ms, branch 13.8–15.7 ms.
- Part 1: `uptime` load 6.39 / 7.86 / 8.37 before the panes-only run and 6.05 / 7.57 / 8.23 after. Absolute numbers are higher than Task 8's despite the lower load average, including the rows with no parked pane (solo 0.643 vs 0.419–0.458). No control was run in Part 1, so the cause is not known. Per parked pane over the same run's solo: 34.6 ms (1+3) and 23.8 ms (1+9) per 10 s. Layout and style-recalc counts match Task 8 exactly: parked panes add none.

## 5. Memory rows and both soaks

Memory per retained pane (Task 9, `run.mjs --panes-only`, one run):

| row | jsHeapUsedBytes | domNodes | wasmBytes |
|---|---|---|---|
| solo | 3,399,068 | 403 | 1,769,472 |
| parked3 | 3,494,264 | 479 | 2,162,688 |
| parked9 | 3,757,660 | 629 | 2,883,584 |
| visible10 | 3,807,220 | 2,941 | 2,883,584 |

Per parked pane: 39,844 B JS heap, 25.1 DOM nodes, 123,790 B wasm. `contentBytes` is 0 per core (the fixture never scrolls a row off its 27-row screen). Part 1's `bench:agent:gate` run (`gate.txt`) gave solo 3,401,660 / 403 / 1,769,472, parked3 3,496,660 / 479 / 2,162,688, parked9 3,756,928 / 629 / 2,883,584, visible10 3,811,808 / 2,941 / 2,883,584; the `--panes-only` run (`panes.txt`) read JS heap 3,401,540 / 3,496,468 / 3,760,236 / 3,806,892.

Bench soak (`npm run bench:soak -- --minutes 30`, 1 visible + 9 parked):
- Task 9 (tree `8378d78af`, load average 76.8 → 15.9): all ten cores reached the 200k-row cap (199,999 rows) at minute 7; wasm flat at 254.3 MiB from minute 6 (~25.2 MiB per core, ~132 B/row); taskDuration 1.52–2.14 s/min; JS heap +2,480 B/min at the cap; DOM nodes flat at 453.
- Task 12 (tree `13ad4994d`, load 5.7 → 7.8): memory identical at every sample; taskDuration 1.75–2.04 s/min (mean 1.866 vs 1.868); JS heap +2,545 B/min at the cap. This is a repeatability check, not a before/after of the unload: both soaks run the same `packages/terminal` code, and the bench has no cache.

Real-app soaks:
- Task 9 real-app soak (WebContent RSS/CPU): not verified — dev ports busy.
- Task 12 120-min real-app soak, 30-min minimised stretch, 2 visible + parked: not verified — dev ports busy.

## 6. Real-app steps

Every real-app step was **not verified — dev ports busy**. The user's own dev app from the main checkout (vite pid 3828 on 127.0.0.1:5173 and `opr` daemon pid 4537 on 127.0.0.1:3002) held both ports throughout, and the handoff forbade killing it. There are no evidence paths.

| step | status |
|---|---|
| Task 6: parked worker pane stops painting | not verified — dev ports busy |
| Task 7: notification while the window is hidden | not verified — dev ports busy |
| Task 8 (a): notification while minimised | not verified — dev ports busy |
| Task 8 (b): reveal shows the tail | not verified — dev ports busy |
| Task 9: real-app soak | not verified — dev ports busy |
| Task 10: unload after a temporary 60 s delay and reopen | not verified — dev ports busy (the 60 s edit was never made; `retained-terminal.ts` diff empty) |
| Task 11: unloaded shell notifies a finished command | not verified — dev ports busy |
| Task 12: 120-min soak, minimised stretch, 2 visible + parked | not verified — dev ports busy |
| Final fix wave (draft hold, socket-drop re-watch) | no real-app check; tests only |

## 7. Deviations from the plan

- **R1**: commits on `terminal-background-pane`, not `development` (user instruction).
- **R2**: the two boundary scripts run separately, since `npm run check:boundaries` short-circuits on the known failure.
- **R3**: Task 9's "ask the user before Task 10" replaced by recording the numbers; N stays 30 min.
- **R4**: Task 10 dispatched only after Task 9's real-app soak, so Vite HMR would not reload a soaked app. Moot: no real-app soak ran (ports busy) in Task 9 or Task 12.
- **R5 / Task 8**: the profile went to the session scratchpad, not `/tmp`. Task 8 also added an interleaved pre-plan control (`11323ce3d` in a scratch worktree, not committed) because of machine load. It cites the forced layout at `dom-block-renderer.ts:1141` and the alt-screen read at `TerminalSurface.tsx:298` (current lines) instead of the plan's `:1055` and `:287-291`.
- **R6 / Task 2**: the plan's alt-screen test sent `?1049h` before `133;D`. vt-core drops mark events while the alt screen is active (`crates/vt-core/src/lib.rs:262-268`), so the block never finished. The test now feeds `${CLOSE_BLOCK}\x1b[?1049h` in one feed (0 events while alt is up, 1 after `?1049l`). A second test pins that a close arriving inside the alt screen is never reported. The measurement note's "reported late, not dropped" was imprecise about the core drop; Task 8 added a sentence to the note. Task 2 also removed the brief's unused `fixture` const (`noUnusedLocals`); Task 4 re-added it.
- **Task 3**: the fourth test flushes a frame after `OPEN_BLOCK` before hiding, so `blockStates` knows the block. `surface-harness.tsx` gained an optional `visible` and a `setVisible` helper instead of the brief's illustrative `surfaceElement`.
- **R7 / Task 4**: an extra test pins Review Focus 4 while hidden ("defers a block that finishes in a hidden pane under the alternate screen until the primary screen returns"). The Focus 2 test ("paints once when hidden and shown again before any frame ran") was strengthened: synchronous text assertion, exactly one `onPaint`, `catchUp` false, pre-park row node reused.
- **Task 5**: the editor test uses the OSC 7000 `cmd=` sequence, because `HistoryModel` reads commands from it, not from bytes between `133;B` and `133;C`. **R8**: `TerminalSurface` applies the current `visible` (through a ref) to a freshly mounted renderer and editor inside the mount effect, with a test that remounts via a new `onSend` while `visible={false}`.
- **Task 6**: none in code; the `BlockTerminal.test.tsx` mock needed `visible` plumbed through.
- **R9 / Task 7**: "stops its timer when disposed while hidden" could not fail without the cleanup; it now asserts `clearTimeout` with the armed handle, `removeEventListener("visibilitychange", listener)`, and no timer or rAF after a later visibility flip.
- **Task 9**: `soak.mjs` adds a `loadAvg` field to every sample and prints start and end lines. The panes-only memory rows come from one run.
- **Task 10**: in the replacement-generation path it calls `cancelUnload(entry)` only, not `scheduleUnload`, since the entry is deleted on the next line. Provider-unmount timer cleanup is folded into the existing unmount effect.
- **Task 11**: the provider now calls `useTranslation()` and keeps `t` in a ref, so a language change does not change the identity of `scheduleUnload`, `activate` or the controller. Helper adaptations: a local `fakeMux()` in `terminal-mux.test.ts`; `vi.spyOn(operatorBridge.notifications, "show")`; `vi.mock("../lib/terminal-mux", importOriginal)`; `getApiBaseUrl` added to the api-client mock; `useTerminalSession.test.tsx` added to the commit for its fake's new `onTerminalBlock`. Two extra tests pin release on shell removal and provider unmount. The shell-query cleanup also compares the generation (`createdAt`).
- **Task 12**: an explicit before/after table in the note, and bench soak figures in the spec row, labelled bench-only.
- **R10 / final wave**: Important 1 (re-watch after a socket drop, backoff 500 ms doubling to 8 s via new `UNLOADED_SHELL_REWATCH_BASE_MS` / `UNLOADED_SHELL_REWATCH_MAX_MS` in `retained-terminal.ts`) and Important 3 (attachment count) fixed. Important 2, option (a): a shell entry whose editor holds an unsent draft is not unloaded; its timer re-arms. This needed a new generic `EditorHost.onDraftChange?(draft)` in `packages/terminal`, surfaced as a `TerminalSurface` `onDraftChange` prop and threaded to the provider's `markDraft`. The new surface test lives in `TerminalSurface.draft.test.tsx` because `TerminalSurface.test.tsx` is over 600 lines.
- **R11**: Minor 4 (CHANGELOG wording and grouping) and Minor 6 (notification failure logged through `terminalDebug`, no test) folded into the fix wave. Minor 5 (settle-frame throttle) and Minor 7 (alt-screen listener snapshot) left for the user.

## 8. Task 8 expectations

| expectation | result | number |
|---|---|---|
| Parked panes add 0 layouts / 0 style recalcs | met | 122 / 222 in parked rows = solo; one parked9 run 123 / 223 (the same ±1 seen in 10 visible) |
| `parkedMutations` 0 | met | 0 in every row and run, including the profile run |
| 1+9 near solo + parse + snapshot | met | 0.518–0.528 s; 7.6–12.1 ms per parked pane per 10 s; profile `settleHidden` 55.4 ms, `drain` 5.9 ms |
| 1+9 clearly below 10 visible | met | 0.518–0.528 vs 1.296–1.326 s |
| 10 visible unchanged within noise | met under the control | pre-plan 1.290–1.327 vs branch 1.276–1.327, identical layout counts; absolute value above the before note's 0.855–1.133 s because of load |

## 9. Found and not fixed

Final reviewer triage: the whole-branch review (`11323ce3d..325409847`) returned three Important findings (fixed, R10) and four Minors (4 and 6 fixed, R11; 5 and 7 parked for the user). The re-review of the fix wave found 5/5 addressed and no new breakage. Everything below remains open.

Parked by the final review:
- Settle frames skip the 60 Hz `PAINT_INTERVAL_MS` throttle (`settleHidden` never sets `lastPaintAt`), so on a 120 Hz display parked panes pay twice the settle cost. Fixing it changes frame pacing in `packages/terminal` and needs a re-bench (R11).
- The alt-screen listener takes a snapshot per change on parked panes (R11).
- The unloaded-shell re-watch retries every 8 s at the cap with no daemon-readiness wait.
- The re-watch attempt count resets only on an observed `"open"`.
- No test for the notification-failure debug-log line.
- A `terminal_block` that finishes while the socket is down is not replayed by the daemon.
- A whitespace-only draft counts as a draft.

Deferred minors from the ledger:
- Task 2: `lib.rs` citation 262-267 vs 262-268 (cosmetic).
- Task 4: `scheduleRepaint`'s no-rAF fallback called `repaint()` directly, bypassing the gate — fixed in the final review (`58b913f2f`).
- Task 4: `predictKey` and `selectionChanged` overlays still write DOM while hidden.
- Task 4: the report's 1200-mutation arithmetic was wrong (fixed in the report; the count went to 0 in Task 5).
- Task 7: `dispose()` calls `document.removeEventListener` unguarded (throws with no DOM on a never-mounted renderer; no current caller).
- Task 7: the Focus 3 test does not assert the shown pane stayed unpainted while hidden.
- Task 7: `setVisible(true)` while the document is hidden paints synchronously (one forced layout), untested and undocumented.
- Task 8: `bench:agent:scroll` failed once under load ("reached 59908 of 60134 rows"), then passed 4 times; it passed in Part 1.
- Task 8: parked9 run 1 0.5265 rounded to 0.526.
- Task 9: the report did not mark the vitest loop N/A explicitly.
- Task 10: "showing a parked pane cancels its unload" cannot tell the explicit cancel from the timer's phase guard.
- Task 10: the commit body omits that tests 2 and 3 pass before the change as guards.
- Task 11: an unloaded shell's subscription is not released when its session leaves the workspace snapshot.
- Task 11: no test asserts `lease.dispose()` on release.
- Task 11: not verified whether the daemon's `terminal_block` `sourceId` equals the renderer's block id (the dedupe claim is unproven; the two paths never overlap).
- Task 11's "no resubscribe after a socket drop" and "notification failure swallowed" were fixed in the final wave.

Task 9 / 12 findings:
- `WebAssembly.Memory` is shared by all cores and never shrinks. Unloading a core frees space for reuse inside vt-wasm's allocator; it does not lower resident size already reached. Whether reuse avoids fragmentation is not known.
- The 200k-row cap binds before the 128 MiB byte cap: ~132 B/row, ~25 MiB per core at the cap.
- The JS heap creeps about 2.5 KB/min at the cap (+2,480 and +2,545 B/min in the two soaks), untraced.
- The unload's real-app memory and CPU effect, and the switch-back replay time in the app, are unmeasured (dev ports busy).

## 10. Final review (planning session, 2026-09-23)

Whole-branch review of `be049b290`: every gate re-run independently, four adversarial reviewers (renderer gate, Operator cache and notifications, editor and surface, tests and claims) each required to prove a finding with a failing test, and a real-browser probe.

Fixed on the branch, each test-first:

| Finding | Commit |
|---|---|
| An unloaded shell pane would notify every command: the shell hooks send no `start_ms`, so every `terminal_block` frame carried `startedAt: 0001-01-01` (a ~63.9-billion-second duration). The daemon's `BlockAssembler` now stamps the start at `OSC 133;C` when the shell sent none; `shellBlockNotification` ignores a frame with no usable start. | `d5b15c718` |
| A hidden line editor lost a command from Up-arrow history when its block scrolled out of the core before reveal. History is now ingested on every change; only the render waits. | `942330926` |
| Disposing the editor dropped unsent text without telling the host, so Operator's `hasDraft` stuck and a parked shell never unloaded. `dispose()` now reports an empty draft. | `942330926` |
| A park and show within one frame (a split-layout change) dropped pending predictions and the in-flight round-trip sample. They are now dropped on the first hidden frame (`RttMeter.cancel()`). `noteSend` is ignored while hidden. The no-`requestAnimationFrame` fallback respects the gate. A renderer given `setVisible(false)` before `mount` does not paint, and `TerminalSurface` sets it before mounting. | `58b913f2f` |
| The reopen test passed even when nothing unloaded; a split-view test now pins that the terminal a pane replaced unloads and on-screen panes never do. | `601c18870` |
| `run.mjs --ungated` measures the pre-gate parked cost again; the measurement sources that lived only in the executing session's scratchpad are committed under `bench/agent-session/baselines/pane-cost/2026-09-23-sources/`. Doc numbers and citations corrected. | this section's commit |

Same-machine comparison from `2026-09-23-sources/review-{ungated,gated}.json` (TaskDuration per 10 s): solo 0.386 / 0.452; 1+3 parked 0.813 / 0.472; 1+9 parked 1.251 / 0.546; 10 visible 1.324 / 1.225. Layouts at 1+9: 1,221 ungated, 123 gated. `parkedMutations` at 1+9: 24,439 ungated, 0 gated.

Checked and sound:
- Parking moves the scroll container, and Chromium resets its `scrollTop` to 0 and fires a scroll event. The branch's synchronous reveal paint restores it: a bottom-stuck pane comes back at the newest row, and a scrolled-up pane comes back on the exact row it showed. On `development`, with no gate, the same reveal left the viewport at `scrollTop` 0 until the next output, so the branch fixes that. This was probed in headless Chromium only; WebKit is not installed for Playwright here.
- A revealed pane paints the same rows as a never-parked pane fed the same bytes: the spinner in 512-byte chunks and 600 KB of `claude-long-50k`, parked and revealed every 5 chunks.
- No state-machine race found across `setVisible`, pending frames, the hidden timer, `visibilitychange`, and dispose/mount.
- The `activate`-loop `scheduleUnload` has no test. It cannot be reached through `CachedTerminalSlot`: its layout-effect cleanup always `deactivate`s the old key first, and that path is tested.

Still open, not fixed here:
- Every real-app step is still not verified. The user's own dev app held ports 3002 and 5173 throughout the review too.
- vt-core times a block from its prompt (`OSC 133;A`), so a loaded pane's duration includes time spent typing. This predates the branch.
- `TerminalSurface`'s features and secret-pattern effects are not re-applied when its mount effect reruns. This predates the branch; `development` has the same deps.
- Parked panes are not paced to 60 Hz, which may double their small remaining cost on a 120 Hz display.
- The ~2.5 KB/min JS-heap creep at the row cap is untraced.
- A full rebuild runs on each window restore for a visible pane even when nothing arrived while hidden. It costs one first paint and is not a correctness problem.
