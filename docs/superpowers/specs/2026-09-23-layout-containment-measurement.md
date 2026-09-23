# Layout containment in the terminal renderer — measurement (2026-09-23)

Question: does CSS layout containment on `.terminal-row` (and then
`.terminal-block`) make the one layout each visible pane pays per output frame
cheaper? Origin: `docs/terminal/2026-09-23-day-to-day-suggestions.md` item 1.
Plan: `docs/superpowers/plans/2026-09-23-terminal-layout-containment.md`.

This note holds the **before** numbers, measured while writing the plan. The
plan's Task 5 appends "After".

## Before

### How it was measured

- Tree: `development` at `f4d93ba68` (Plan 4, the background-pane plan, fully
  merged), `packages/terminal` rebuilt with
  `npm run build:wasm -- --force && npm run build:ts` first, because the bench
  runs `dist/`.
- `node bench/agent-session/run.mjs --panes-only`, three runs, unchanged
  harness: `claude-spinner-10s`, 100 DEC 2026 frames at 100 ms, CDP
  `Performance.getMetrics` deltas over the 10 s, headless Chromium from
  Playwright 1.60.0, 1600×900.
- The machine was loaded: 1-minute load average 38.8–54.0 on 10 cores during
  the runs (`2026-09-23-containment-before-load.txt`). The before note
  (`2026-09-23-background-pane-cost-measurement.md` "After") showed load moves
  every absolute number, so the plan compares before and after inside one
  session, interleaved.
- Raw output:
  `packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-23-containment-before-run{1,2,3}.json`.

### Numbers (seconds of main-thread time per 10 s)

| row | TaskDuration (runs 1 / 2 / 3) | Script | Layout (runs 1 / 2 / 3) | RecalcStyle | Layouts / style recalcs |
|---|---|---|---|---|---|
| 1 visible, alone | 0.228 / 0.188 / 0.190 | 0.048–0.050 | 0.073 / 0.046 / 0.046 | 0.013 | 122 / 222 |
| 1 visible + 3 parked | 0.218 / 0.221 / 0.220 | 0.073–0.075 | 0.047 / 0.048 / 0.047 | 0.013 | 122–123 / 222–223 |
| 1 visible + 9 parked | 0.258 / 0.266 / 0.264 | 0.113–0.116 | 0.050 / 0.048 / 0.048 | 0.013 | 122–123 / 222–223 |
| 10 visible | 0.797 / 0.792 / 0.785 | 0.255–0.260 | 0.234 / 0.232 / 0.229 | 0.071–0.072 | 1220–1221 / 2256–2257 |

The gain threshold the plan uses: the minimum of the three 10-visible Layout
readings is **0.229 s**.

### Does any frame pay two layouts?

**No.** Measured with a Chromium trace (`devtools.timeline` categories) of the
same 100-frame feed, two runs; the script that produced it is written out in
the plan's Task 1 and committed there as
`bench/agent-session/layout-trace.mjs`. A layout counts as *forced* when it
starts inside a script event (`FireAnimationFrame`, `FunctionCall`,
`TimerFire`, …) and as *render step* otherwise; frames are delimited by
`BeginMainThreadFrame`. Raw output:
`2026-09-23-containment-before-trace-run{1,2}.json`.

| row | layouts | forced | render step | frames with forced + render step | forced layout ms (trace) | style recalcs (all forced) | median dirty / total layout objects |
|---|---|---|---|---|---|---|---|
| 1 visible, alone | 122 / 122 | 122 / 122 | 0 / 0 | 0 / 0 | 99.6 / 96.0 | 222 / 222 | 142 / 370 |
| 10 visible | 1220 / 1221 | 1220 / 1221 | 0 / 0 | 0 / 0 | 356.6 / 376.6 | 2256 / 2259 | 142 / 274 |

Read-outs:

- Every layout is the forced one inside `repaint`; the render step finds a
  clean tree and lays out nothing. So there is no second layout for the
  pinned-header test to remove, and deriving that test from the windowing
  result is **out of scope** for this plan.
- The 22 layouts above 100 in the solo row are not a second layout per frame:
  they land in 7 frames (at most 16 in one frame), all forced. Their source
  was not identified; the fixture's recorded resizes, replayed by
  `applyResizesUpTo` (`bench/agent-session/main.ts:125-131`), are a
  candidate, not a finding.
- The ~2.2 style recalcs per frame are both inside the frame's script: one at
  the forced layout, one later. The later one does not trigger a layout.
- **Each layout already has a median of 142 dirty layout objects out of
  274–370 in the pane** (`Layout` event `beginData.dirtyObjects` /
  `totalObjects`). What the 142 are was not broken down. The rows
  `populateBlock` rebuilds each frame are the likely bulk (the spinner adds
  ~76 DOM nodes per paint, TERMINAL.md §5), and new objects need layout
  whatever containment says; that is inference, not a measurement. Layout
  containment could at most save work on the *clean* objects. Whether
  Chromium's layout cache already skips them, and whether `contain: layout`
  without `size` makes a row a relayout boundary in Blink or WebKit at all, is
  **not known** (no engine source on this machine). The plan therefore
  expects a small gain or none; the measurement decides.

### Where the time goes (CPU profile, 10 visible)

Top self time over the 10 s, 100 µs sampling (two runs): `(idle)`
9,264 / 9,247 ms, `getBoundingClientRect` **327.2 / 334.8 ms**, `(program)`
143.9 / 157.8, `flushPending` (`row-builder.ts`) 64.6 / 65.5,
`export_screen_row` (wasm) 34.0, GC 33.0, `remove` 31.9, `append` 25.9,
`ScreenGrid::cell` (wasm) 21.8, `WidthCache.get` 20.0.

`getBoundingClientRect` self time is the forced layout, paid at the
pinned-header test (`ts/renderer-dom/src/dom-block-renderer.ts:1149`, the
first layout read after `reconcileChildren` at `:1146`). A V8 CPU profile does
not break Blink's layout out on its own: it shows up as the self time of the
DOM call that forced it, and a layout outside script would show as
`(program)`. The trace's Layout durations above are the layout-only number.

### WebKit

**Not measured yet.** Playwright's WebKit build is not installed on this machine
(`~/Library/Caches/ms-playwright` holds Chromium builds only), and installing
it is a download the user must approve. The harness's CDP metrics are
Chromium-only; the plan's Task 1 adds a synchronous repaint-loop timing that
runs in both engines, and runs it in WebKit if the download is approved.

## After (2026-09-23)

### How it was measured

- Tree: `development` at `66528b053` (the plan's Task 1 tooling on top of
  `997268a88`; `git diff f4d93ba68 HEAD -- packages/terminal/ts
  packages/terminal/crates` empty, so the renderer is the one "Before"
  measured). `npm run build:ts` before every run.
- Candidate: `.terminal-row{contain:layout}`, injected through the bench
  page's `?css=` parameter; nothing in `styles.css` changed. Control and
  candidate alternated in one session, control first in every pair.
- Every file below is in
  `packages/terminal/bench/agent-session/baselines/pane-cost/`, prefix
  `2026-09-23-containment-row-`.
- Load (1-minute average) at each run start, from `…-row-load.txt`: control1
  6.14, row1 6.32, control2 6.90, row2 10.38, control3 13.71, row3 13.06, end
  11.48. "Before" ran at 38.8–54.0.

### Row containment, Chromium (`run.mjs --panes-only`, seconds per 10 s)

Control is `…-control-run{1,2,3}.json`, containment is
`…-after-run{1,2,3}.json`.

| row | TaskDuration (runs 1 / 2 / 3) | Layout (runs 1 / 2 / 3) | RecalcStyle | Layouts / style recalcs |
|---|---|---|---|---|
| 1 visible, control | 0.365 / 0.310 / 0.353 | 0.089 / 0.077 / 0.085 | 0.025 / 0.021 / 0.025 | 122 / 222 (all three) |
| 1 visible, containment | 0.365 / 0.204 / 0.294 | 0.086 / 0.053 / 0.074 | 0.026 / 0.013 / 0.020 | 122 / 222 (all three) |
| 10 visible, control | 1.201 / 0.846 / 1.136 | 0.296 / 0.246 / 0.295 | 0.098 / 0.077 / 0.096 | 1221 / 2257, 1221 / 2258, 1220 / 2256 |
| 10 visible, containment | 1.122 / 0.945 / 0.993 | 0.274 / 0.267 / 0.264 | 0.089 / 0.083 / 0.085 | 1220 / 2256 (all three) |

The plan's rule: kept only if the containment median of the 10-visible Layout
readings is below the control minimum. Containment median **0.267 s**, control
minimum **0.246 s**: **no gain**. Containment adds no layout and no style
recalc.

Today's controls (0.246–0.296 s) lie above planning's "Before" range
(0.229–0.234 s, `2026-09-23-containment-before-run{1,2,3}.json`) by more than
that range's own 0.005 s spread, on the same renderer, while the load average
was far lower (6.1–13.7 against 38.8–54.0). Why is **not known**: the load
average does not explain it, and nothing else about the machine was recorded.
This is why the plan compares inside one session.

### Row containment, trace (`layout-trace.mjs`)

`…-control-trace.json` against `…-after-trace.json`:

| row | layouts | forced | render step | forced layout ms | style recalcs | median dirty / total objects | `getBoundingClientRect` self ms |
|---|---|---|---|---|---|---|---|
| 1 visible, control | 122 | 122 | 0 | 103.1 | 222 | 142 / 370 | — |
| 1 visible, containment | 122 | 122 | 0 | 100.9 | 222 | 142 / 370 | — |
| 10 visible, control | 1220 | 1220 | 0 | 386.3 | 2256 | 142 / 274 | 394.4 |
| 10 visible, containment | 1221 | 1221 | 0 | 392.7 | 2257 | 142 / 274 | 431.5 |

Containment changes nothing about what is laid out: the same 142 dirty
objects per layout, and still 0 render-step layouts. The profile files the
self times come from are named in each trace file's `profile.visible10.file`
(under `bench/results/`, not committed).

### Row containment, synchronous repaint loop (`repaint-loop.mjs`, ms for 100 frames)

| engine | control (runs 1 / 2 / 3) | containment (runs 1 / 2 / 3) | files |
|---|---|---|---|
| WebKit 26.4, 1 visible | 205.0 / 157.0 / 140.0 | 140.0 / 139.0 / 133.0 | `…-webkit-control-run{1,2,3}.json`, `…-webkit-after-run{1,2,3}.json` |
| WebKit 26.4, 10 visible | 1170.0 / 1127.0 / 1109.0 | 1075.0 / 1075.0 / 1164.0 | same |
| Chromium, 1 visible | 73.8 / 73.1 / 70.6 | 76.7 / 68.3 / 77.1 | `…-chromium-loop-control-run{1,2,3}.json`, `…-chromium-loop-after-run{1,2,3}.json` |
| Chromium, 10 visible | 549.8 / 560.2 / 546.4 | 540.0 / 533.9 / 573.7 | same |

WebKit was installed for this measurement (`npx playwright install webkit`,
76.7 MiB, WebKit 26.4, Playwright build v2287), with the user's approval.

By the plan's rule alone the WebKit 10-visible reading is a gain (containment
median 1075.0 ms below control minimum 1109.0 ms). It is **discarded**, by the
user's decision, because it is not a real gain:

- The control ran first in every pair, and the controls drifted down through
  the session (WebKit 1 visible 205.0 → 157.0 → 140.0 ms, 10 visible 1170.0 →
  1127.0 → 1109.0 ms), so the order favours the containment runs.
- The control spread (1109–1170 ms, about 5 %) is larger than the claimed
  gain (about 3 %).
- One containment run (1164.0 ms) is above every control run.
- The trace shows containment changes nothing that gets laid out (142 / 274
  dirty objects both ways; forced layout 386.3 against 392.7 ms).

The Chromium loop's 10-visible reading (containment median 540.0 ms, control
minimum 546.4 ms) has the same ordering problem and is not the Chromium gate,
which is the CDP Layout reading above.

### Verdict

- `.terminal-row { contain: layout }`: **not kept: no gain.** Nothing in
  `styles.css`/`styles.ts` changed.
- `.terminal-block { contain: layout }` (plan Task 3): **not measured**. The
  plan tries it only on top of kept row containment.
- The guard test `styles-parity.test.ts` "never uses a containment that clips
  paint or fixes size" landed, pinning the values TERMINAL.md §4.26 rules out.

### Pixels

The committed `feature-*` and `affordance-*` PNGs reproduce on the
unmodified tree: regenerating all six features on the four targets and the
three affordances (`hover`, `hint`, `redact`) left
`git status --porcelain -- packages/terminal/bench/agent-session/baselines`
empty, before and after. 128 PNGs (120 feature, 8 affordance) were copied as
the reference. After the whole plan, the same regeneration compared
byte-identical to that copy on all 128 (no `DIFF` line). No PNG was committed.

### Full gate on the final state (plan Task 4)

`git diff f4d93ba68 HEAD -- packages/terminal/ts` is empty, so the only
change is the bench harness. Final output lines:

- `npm run build:ts`: exit 0.
- `ts/core` vitest: `Tests  79 passed (79)`.
- `ts/renderer-dom` vitest: `Tests  906 passed (906)` (before the guard test
  landed).
- `ts/react` vitest: first run `Tests  1 failed | 117 passed (118)`, the
  failure `TerminalSurface.mouse.test.tsx` "accumulates precise trackpad pixels
  using the measured cell height" (received `\x1bOB\x1bOB` for one wheel event,
  expected `\x1bOB`). The file then passed 3 of 3 runs on its own
  (`Tests  32 passed (32)`), and the whole package passed on a rerun
  (`Tests  118 passed (118)`). No `ts/` file differs from `f4d93ba68`, so this
  plan did not cause it; root cause not investigated.
- `npm run bench:selection`: `PASS selection survived 22 repaints`.
- `npm run bench:agent:scroll`: first run `FAIL scrolling reached 59908 of
  60134 rows` (2235 steps). Four reruns covered 60134 of 60134 (2245 steps),
  the last with exit 0. It had also passed in Task 1. The harness change adds
  functions and a `?css=` branch the scroll gate never uses; root cause not
  investigated.
- `npm run bench:agent:gate`: `PASS agent-session gate`.
- `npm run bench:feel`: `PASS feel gate: zero pixel diff`.
- Feature and affordance byte comparison: `compared 128 files`, no `DIFF`.

Real app: not verified — no renderer change shipped, so there is nothing new
to see in the app. That covers all six items (split panes streaming,
overscroll, cross-block selection and copy, path hover, the Claude Code
cursor, the find bar); the seventh (pinned header) belonged to Task 3, which
did not run.
