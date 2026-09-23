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
