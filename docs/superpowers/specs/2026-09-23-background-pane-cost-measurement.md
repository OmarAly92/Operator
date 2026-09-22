# Background pane cost — measurement (2026-09-23)

Question: what does a retained Claude Code pane that the user is **not**
looking at (parked by `TerminalPane.tsx:187-195` `parkTerminal`) cost the
renderer's main thread? Nothing had measured it; the only related number was
the spec's "ten idle panes" row, where all ten panes are visible.

Answer: **a parked pane costs the same as a visible one.** `visibility:
hidden`, `inert` and the off-screen parking lot save nothing measurable — the
parked pane repaints, patches its DOM and forces a layout on every output
frame, exactly like the pane on screen. Nine parked Claude Code spinners add
0.53–0.71 s of main-thread time per 10 s; nine visible ones add 0.46–0.90 s
(each run's solo row subtracted from the same run).
The gate is worth building.

A second finding, independent of CPU: in a minimised or hidden WKWebView
window `requestAnimationFrame` stops entirely, so today **no pane drains its
backlog and no block-finished notification fires while Operator's window is
hidden** — the notification feature is silent in exactly the case it is for.

## How it was measured

- Tree: `development` at `b59c3b27c`, `packages/terminal` rebuilt
  (`npm run build:wasm -- --force && npm run build:ts`) before measuring,
  because the bench runs `dist/`.
- Tooling (committed with this note):
  `packages/terminal/bench/agent-session/run.mjs --panes-only [--profile]`
  (functions `paneRows`/`paneLoad`/`selfTimeTop`) and
  `bench/agent-session/main.ts` `mountPanes(count, "parked")` / `park()` /
  `parkedPaneState()`. The full `bench:agent` run now records the same four
  rows as `panes`.
- Parked panes are built the way `TerminalPane` parks them
  (`TerminalPane.tsx:165-195`): mounted visible at the visible pane's size,
  then given a fixed pixel width/height, `inert`, `aria-hidden`,
  `pointer-events: none`, `visibility: hidden`, and appended to a
  `position: fixed; left: -100000px; visibility: hidden` parking element
  (`TerminalPane.tsx:581-586`).
- Parked panes are fed with `core.enqueue` (the production path,
  `BlockTerminal.tsx:163`) and drain on the renderer's frame; the visible
  pane and the all-visible row keep the existing `core.feed` path so the
  10-visible row stays comparable with the spec's history.
- Each row: fresh page, `claude-spinner-10s`, the fixture's first 100 DEC
  2026 frames at 100 ms (`feedFrames(100, 100)`), CDP
  `Performance.getMetrics` deltas over the 10 s, headless Chromium
  (Playwright), 1600×900.
- Every pane is a `DomBlockRenderer` plus a `LineEditor`
  (`bench/adapters/dom.ts`), **not** a `TerminalSurface`: the React layer,
  its `ResizeObserver` and the find bar are not in these numbers. What they
  add for a parked pane is not known.
- Three runs. Run 1 also ran the CPU profiler during the 1+9 row (100 µs
  sampling), which inflates that one cell. Raw output:
  `packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-23-before-run{1,2,3}.json`.

## Numbers (seconds of main-thread time per 10 s)

| row | TaskDuration (runs 1 / 2 / 3) | Script | Layout | RecalcStyle | Layouts / style recalcs |
|---|---|---|---|---|---|
| 1 visible, alone | 0.354 / 0.392 / 0.232 | 0.059–0.107 | 0.059–0.098 | 0.015–0.026 | 122 / 222 |
| 1 visible + 3 parked | 0.532 / 0.617 / 0.642 | 0.204–0.253 | 0.143–0.176 | 0.045–0.059 | 488–489 / 888–889 |
| 1 visible + 9 parked | 0.886\* / 1.004 / 0.939 | 0.369–0.415 | 0.257–0.298 | 0.081–0.093 | 1220–1221 / 2220–2221 |
| 10 visible (re-record of the spec row) | 1.083 / 0.855 / 1.133 | 0.282–0.351 | 0.251–0.296 | 0.077–0.099 | 1220–1221 / 2256–2257 |

\* profiler running.

Read-outs:

- Each parked pane adds **exactly** the layouts and style recalcs a visible
  pane adds: +122 layouts and +222 recalcs per pane per 100 frames, i.e. one
  forced layout per output frame. `visibility: hidden` does not skip layout
  (expected — it only skips paint) and the parking lot does not either.
- Per pane over the solo row (medians): parked ≈ 0.065 s (1+9) to 0.088 s
  (1+3) per 10 s; visible ≈ 0.081 s (10-visible). Within run-to-run noise
  these are the same cost.
- The 10-visible re-record, 0.855–1.133 s, sits inside the 0.79–1.30 s spread
  Plans B–E reported; the unchanged `idlePanes` row of a full
  `npm run bench:agent:gate` on the same tree read 0.946 s. It is still **missed** against the 0.44 s target.
- Parked cores kept up: after every parked row, every parked core had no
  backlog and had reached the same model generation (118) as the others
  (`parkedPaneState()`), so today's frame-driven drain does keep a parked
  model current while the window is shown.

## Where the time goes (CPU profile, 1 visible + 9 parked)

Profile of the 10 s window; the file is written under the gitignored
`bench/results/`, reproduce with `node bench/agent-session/run.mjs
--panes-only --profile`. 9,163 ms of the 10,064 ms are idle; the rest, all
ten panes together:

Inclusive time of the paint-loop functions (`dist/` line numbers mapped back
to `ts/renderer-dom/src/dom-block-renderer.ts`):

| function | inclusive ms | source |
|---|---|---|
| `repaintOnFrame` | 695.7 | `dom-block-renderer.ts:826-840` |
| `repaint` | 615.1 | `:880-1084` |
| `populateBlock` (row build + DOM patch) | 258.2 | `block-body.ts`, called at `:1025` |
| `drain` (parse of the 9 parked cores' backlog) | 73.7 | `ts/core/src/terminal-core.ts:136-159` |
| `LineEditor` `ingestHistory` via `core.onChange` | 73.2 | `ts/editor/src/line-editor.ts:85-88`, `:474-478` |
| `reconcilePredictions` | 4.0 | `:649-660` |
| `paintDecorations` + `paintHints` + `paintRedactions` + `paintSelectionFill` + `linkifier.refresh` | 4.2 | `:1075-1079` |
| `decodeBlocks` | 1.6 | `:932` |
| `tick` | 1.5 | `:837` |

Top self time: `getBoundingClientRect` 335.7 ms, of which 320.8 ms is called
directly from `repaint` — the only `getBoundingClientRect` in `repaint` is the
pinned-header test at `dom-block-renderer.ts:1055`, the first layout read after
`reconcileChildren` has mutated the list, so it is where the frame's **forced
synchronous layout** is paid. (Removing that read would move the layout to the
next read, `applyStickiness`'s `scrollHeight` at `:1128`; it is not the pinned
header's own cost.) Then `(program)` 145.9, `flushPending` (`row-builder.ts`)
67.1, `export_screen_row` (wasm) 40.0, DOM `remove` 36.6 (all from
`reconcileChildren`, `block-body.ts`), GC 30.7, `append` 28.9,
`WidthCache.get` 21.6.

What that says about a gate:

- Skipping the DOM repaint for a parked pane removes its share of the 615 ms
  `repaint` and all of its forced layouts and style recalcs.
- What would remain per parked pane is the parse (`drain`, ~8 ms per pane per
  10 s from the profile) and the `LineEditor`'s per-change `core.snapshot()` +
  `decodeBlocks` for history (`ingestHistory`, ~7 ms per pane per 10 s across
  all ten; the visible pane's share is inside that). These are profile
  shares, not measurements; the re-measure task records the real remainder.
- `LineEditor.render()` (3.6 ms total) also runs on every change of a parked
  pane.

## Hidden window: WKWebView stops animation frames

Probe: `scripts/probe-wkwebview-hidden.swift` — a plain `WKWebView` with the
default `WKWebViewConfiguration` (Operator does not set Tauri's
`backgroundThrottling`, so wry leaves `inactiveSchedulingPolicy` at WebKit's
default: `wry-0.55.1/src/wkwebview/mod.rs:473-493` only changes it when the
attribute is set; `frontend/src-tauri` sets nothing). It counts
`requestAnimationFrame` callbacks, `setTimeout(100)` chains and
`setInterval(100)` ticks per second, then minimises (or app-hides) the window
at 4 s. macOS 26.5.2.

```bash
swiftc -O scripts/probe-wkwebview-hidden.swift -o /tmp/wk-probe && /tmp/wk-probe minimize
```

| window state | `visibilityState` | rAF / s | `setTimeout(100)` / s |
|---|---|---|---|
| shown | visible | 53–61 | 9–10 |
| minimised (`miniaturize`) | hidden | **0** | ~1 (1–2 per ~2 s logger tick; the 1 s logger itself slips to ~2 s) |
| app hidden (`NSApp.hide`) | hidden | **0** | ~1 |

So in Operator's window, minimised or hidden:

- `scheduleRepaint` → `requestAnimationFrame` (`dom-block-renderer.ts:823`)
  never fires. Every pane — the active one too — stops calling
  `core.drain()`/`core.tick()`; bytes pile up in the core's backlog
  (`terminal-core.ts:124-134`) without bound, and the model goes stale.
- Block-finished detection lives in `repaint` (`:932-942`), so **no
  `onBlockFinished` fires while the window is hidden**. When the window comes
  back the pending ones fire late; the active pane's then report
  `visible: true` (`rendererVisible` checks `document.visibilityState`, which
  is visible again by then), so `BlockTerminal.tsx:609-610` suppresses the
  notification for a command that finished while the user was away. This is a
  bug in the notification feature, independent of CPU.
- The agents are **not** stalled: the pty-host's flow-control acks are sent on
  receipt of mux data (`frontend/src/renderer/hooks/useTerminalSession.ts:590-598`),
  not on parse, so the host keeps reading the pty (`host.go:535-549`
  watermarks never trip). The cost of the stall is renderer memory and the
  missed notifications.
- A timer-driven path while hidden would run at ~1 Hz under WebKit's
  throttling. That is enough for block-finished detection and for Claude
  Code's output rate; a 12 ms `drain` budget per tick parses far less than a
  fast build log can produce, so a backlog can still grow while hidden — only
  far more slowly than today's unbounded growth.

Not probed: the Tauri app's own window (automation cannot drive it; memory
note "Verify Operator desktop via daemon API and /mux"), and a window fully
occluded by another app's window without being minimised — whether WebKit
marks that `hidden` is not known.

## Other facts the plan depends on

- Split view is planned but not built: `docs/superpowers/plans/2026-09-22-split-view.md`
  moves "the retained-terminal cache … from one live slot to one per pane".
  Today `TerminalPane.tsx` has one `activeRef` (one visible pane). A
  visibility seam must be per renderer so several can be visible later.
- The snapshot's block list is not windowed: `ExportBuffers` writes every
  block from `export_blocks(total_rows, …)` (`crates/vt-wasm/src/export.rs:226-230`)
  regardless of `setExportWindow`, so block-finished detection can read any
  snapshot.
- The alt-screen branch of `repaint` (`:898-923`) returns before block
  detection and leaves `blockStates` untouched, so a block that finishes
  while an alternate screen is up is reported late (on the first primary-screen
  paint), not dropped. Whether that is intended is not recorded anywhere.
- `rendererVisible` (`block-finished.ts:9-13`) returns false for an `inert`
  ancestor, and `setTerminalPhase` makes every phase except `"visible"`
  inert (`TerminalPane.tsx:170-172`), so today the `"preparing"`/`"ready"`/
  `"revealed"` phases already report `visible: false`.
- The find bar steps its search on its own animation frames
  (`find-bar.ts:228-234`) until complete and re-highlights after each renderer
  paint (`TerminalSurface.tsx:173`); it has no timer of its own once done.
- `TerminalSurface`'s auto-scroll uses its own `requestAnimationFrame`
  (`TerminalSurface.tsx:380-395`) only during a selection drag.

## Follow-ups outside this plan

- The forced layout per paint (`:1055`, then `:1128`) is paid by visible panes
  too; it is most of the 10-visible row's cost. Reading layout before
  mutating (or not at all) would cut the visible-pane cost without changing
  pixels. Not part of the background-pane plan.
