# Agent-TUI experience: Claude Code fidelity and long-session performance

**Date:** 2026-09-19
**Decision owner:** Omar Aly
**Status:** approved direction; plan A is the next document to write
**Derived from:** [`2026-09-19-terminal-reference-survey.md`](2026-09-19-terminal-reference-survey.md)
(the survey). `§N.M` refers to that document. This spec restates what it
needs, adds the long-session requirements the survey did not cover, and
carries the implementation reference (current code with file:line, target
interfaces, test names, verification recipe) a cold-start agent needs to
write the plans without re-reading the survey or the tree.

Read before writing a plan: `TERMINAL.md` end to end (the pipeline, the
solved bugs and their guards, the verify-and-ship recipe in §6), then this
document, then the survey entries this document cites.

## Why

Operator is used mainly to run Claude Code, and the terminal "feels perfect"
today for a fresh session. Two things erode that.

1. Fidelity faults an agent TUI exposes that a shell does not: tearing under
   the 100 ms spinner, stalls when a big tool result lands, dropped text
   attributes, drifting emoji rows, no way to act on the file paths it prints.
2. Long sessions. A Claude session runs for hours and produces tens of
   thousands of rows. Today the renderer keeps 5,000 rows and the pty-host
   mirror 1,000; every chunk of output re-exports the whole scrollback; and
   reopening a pane replays only the mirror's 1,000 rows. So "scroll up and
   every message is there" is false past 5,000 rows, always false after a
   reopen, and the pane gets heavier the longer the session runs.

User requirements, in intent:

1. Improve the experience with agent TUIs, Claude Code above all.
2. Long Claude sessions: scrolling up shows *all* messages and nothing breaks
   — no jumps, no missing rows, no freezes, no reflowed mess.
3. The current feel is the baseline. Anything that changes what a Claude Code
   pane looks like ships default-off behind a flag and is shown side-by-side
   first.

## Non-goals

- Shell-mode behaviour: OSC 133 options, prompt redraw on resize, quick
  fixes, run-recent, vi mode (survey §1.5, §1.6, §2.13, §6.6, §6.8, §6.11).
- The `vte::ansi` refactor (§2.2). Valuable, not agent-specific; survey plan 2.
- Accessibility (§3.9). Product timing.
- Remote agents / OSC 777 (§7.1, §7.7, §7.8).
- Anything Claude Code does *to itself*. The duplicated row after a resize is
  its own SIGWINCH repaint (`TERMINAL.md` §4.8, upstream, pyte reproduces it).
  One heuristic is offered under Decisions; nothing else chases it.

## Global constraints (every plan inherits these)

- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no
  Operator import, path, default or concept inside it. Operator wiring goes in
  `frontend/` and `backend/`.
- No comments in new code (user's global instruction). Existing comments may
  be corrected when they become false.
- A `vt-core` change is live only after **both** wasm artifacts are rebuilt
  (`vt_core` for the renderer, `vt_host.wasm` for the Go mirror) and the
  daemon is rebuilt (`TERMINAL.md` §3.5, §6). Old pty-host processes keep the
  old wasm for the life of the session; the user must restart the daemon and
  the app.
- TDD is the house style: every behaviour change lands with a failing test
  first; every `TERMINAL.md` §4 guard keeps passing.
- Reference decisions cite the file they mirror (`TERMINAL.md` §3.2). This
  spec adds the surveyed projects as citable references next to Warp; a code
  comment that cites one names the repository and path the way `styles.css`
  cites Warp.
- Rust: `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test`
  from `packages/terminal`. TS: `npx vitest run` in each of `ts/core`,
  `ts/renderer-dom`, `ts/react`; `npx tsc --noEmit -p .` in `frontend/`. Go:
  `go test ./internal/adapters/runtime/ptyhost/...` in `backend/`.
- Changelog: `packages/terminal/CHANGELOG.md`, "Unreleased", one entry per
  behaviour change. Commits go to `development`.
- Use absolute paths in every shell command (`TERMINAL.md` §6: parallel
  Bash calls share the working directory).

## What a Claude Code pane is, in our terms

- Spawned as `kind === "worker"`, so `TerminalPane` passes `agentTui = true`
  (`frontend/src/renderer/components/TerminalPane.tsx`) and `BlockTerminal`
  calls `core.setAgentTuiMode(true)`; `vt-core` then runs with
  `reflow_on_resize = false` and `ClearPolicy::ClearInPlace`
  (`packages/terminal/crates/vt-core/src/parser.rs:233-240`): the live frame
  is truncated in place on resize, `ESC[2J` clears in place, scrollback still
  rewraps on a width change (`TERMINAL.md` §2, §4.2, §4.10).
- The installed binary (`/opt/homebrew/Caskroom/claude-code@latest/2.1.273/claude`)
  emits DEC 2026 around every Ink frame **once the terminal has answered its
  XTVERSION query and reported DECRQM 2026 as supported** (with an unknown
  `TERM_PROGRAM` it probes instead of assuming; Plan A made the pty-host mirror
  answer XTVERSION, DA1 and DECRQM — `TERMINAL.md` §4.16), SGR mouse
  (`?1000`/`?1006`), `?1049` for some views; no Kitty keyboard, no mode 2048
  (survey Appendix B).
- Repaints on a ~100 ms timer while thinking (`TERMINAL.md` §4.13 measured
  a repaint every 100 ms from its spinner).
- Prints box drawing (`│ ⎿ ├ ─ ╭ ╮ ╰ ╯`), braille spinners, emoji status
  glyphs, `path:line` references and URLs in every tool result; bold, dim,
  colour bands. Whether it uses italic/underline/strikethrough: not measured
  (the baseline harness answers it).
- Two `vt-core` copies see every byte: the renderer core (wasm in the
  window, `packages/terminal/crates/vt-wasm`) and the pty-host mirror (wasm
  run by wazero in the daemon's `opr pty-host` subprocess,
  `packages/terminal/crates/vt-host` + `backend/internal/adapters/runtime/ptyhost/vtwasm`),
  which exists to produce the attach replay (`TERMINAL.md` §1).

## Current pipeline for one chunk of Claude Code output

```
child writes N bytes to the pty
  │
  ▼  backend/internal/adapters/runtime/ptyhost/host.go
readPTY (:436-448)      reads up to readBufferSize = 0x4_0000 (:363), sends chunks
pumpPTY (:372-434)      batches chunks; flushes when ≥ readBufferSize or every
                        flushInterval = time.Second/60 (:364)
deliver (:453-466)      Ring.Append (1000 lines, ring.go:8-9) → broadcastLocked
                        (MsgTerminalData frame to every client) → feedParserLocked
                        (mirror vt_feed in ≤ 0x1_0000-byte slices, :492-508)
                        → capture tee (shell terminals only)
  │  loopback TCP, proto.go
  ▼  daemon httpd/terminal_mux.go → WebSocket {ch:'terminal', type:'data', data: base64}
  ▼  frontend/src/renderer/hooks/useTerminalSession.ts
mux.onData (:564-580)   during the initial replay: buffered up to
                        REPLAY_MAX_BYTES = 1 MiB / REPLAY_CAP_MS = 750 (:122-155);
                        afterwards: every listener(bytes) synchronously (:579)
  ▼  frontend/src/renderer/components/BlockTerminal.tsx
feedToCore (:138-142)   core.feed(bytes)   (history-block ranges stripped for shells)
  ▼  packages/terminal/ts/core/src/terminal-core.ts
TerminalCore.feed (:65-85)   inner.feed(bytes); listeners(generation)
  ▼  packages/terminal/crates/vt-wasm/src/lib.rs
WasmTerminalCore::feed (:44-49)   core.feed; core.snapshot(); export.refresh(); generation += 1
  ▼  packages/terminal/crates/vt-core/src/lib.rs
TerminalCore::feed (:76-117)   marks decoded by offset, vte.advance per slice,
                               events applied in stream order, commit_evicted,
                               trim_to(scrollback_rows)
  ▼  packages/terminal/crates/vt-core/src/grid.rs
build_snapshot (:80-140)   copies EVERY completed scrollback row's bytes and
                           style pairs into fresh Vecs, then the screen rows
  ▼  packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts
listener → scheduleRepaint (:303-310) → repaintOnFrame (:313-325, one paint
per 1000/60 ms) → repaint (:362-480): core.snapshot() again (:371),
decodeBlocks (:400), computeWindow (:426-433), populateBlock for every
visible block (block-body.ts:19-44 rebuilds every row node), replaceChildren,
paintSelectionFill (:482, one more snapshot + decode)
```

Every box below the mux runs once per mux message, and the two `snapshot()`
calls copy the whole scrollback each time. That is the shape the long-session
work changes.

## Baseline — measured before any change, kept as the gate

### The harness

`packages/terminal/bench/agent-session/` (new; sibling of the existing
`bench/runner.mjs`, `bench/selection-gate.mjs`, `bench/scroll-gate.mjs`,
`bench/scenarios.json`, `bench/workloads.mjs`). It loads the DOM adapter
(`bench/adapters/dom.ts`) exactly like `bench/select.html` does and replays a
recorded Claude Code stream.

The recording: `OPERATOR_PTY_RECORD=<dir>` (Part 2.5) tees the raw pty
bytes of one session into `<dir>/<session>.recording` plus `size.json`
(`{cols, rows}` at start and each resize offset). Two fixtures are committed
under `bench/agent-session/fixtures/`: `claude-spinner-10s` (≈ 100 frames of
the idle spinner, for tearing and paint-cost tests) and `claude-long-50k`
(a real session trimmed to ≥ 50,000 rows). Fixtures are checked in as
`.recording` bytes; if a session contains secrets it is not committed —
regenerate from a scratch project.

### The table

| Metric | How | Today | After Plan A | After Plan B | After Plan C |
|---|---|---|---|---|---|
| `feed()` cost at 1k / 5k / 50k rows | `performance.now()` around `core.feed` for a 4 KiB chunk after the transcript reaches N rows | `claude-long-50k` (60,137 rows), 20 samples each: 0.40ms @ 1k (reached row 1,361) / 0.70ms @ 5k (reached row 5,610) / 5.60ms @ 50k (reached row 50,252) | `claude-long-50k`, 20 samples each: 0.40ms @ 1k (reached row 1,361) / 0.70ms @ 5k (reached row 5,610) / 5.20ms @ 50k (reached row 50,252) — unchanged within run-to-run noise (Plan B's target) | `claude-long-50k`, 20 samples @ 1k / 20 @ 5k / 11 @ 50k (the fixture ran out of remaining bytes for a full 20 at 50k): 0.20ms @ 1k (reached row 1,361) / 0.10ms @ 5k (reached row 5,610) / 0.10ms @ 50k (reached row 50,252) — unchanged within run-to-run noise | `claude-long-50k`, 20 samples @ 1k / 20 @ 5k / 4 @ 50k (the fixture ran low on remaining bytes at 50k on this run): 0.20ms @ 1k (reached row 1,361) / 0.20ms @ 5k (reached row 5,610) / 0.20ms @ 50k (reached row 50,252) — unchanged within run-to-run noise; Plan C does not touch `feed()` |
| paints/s and DOM nodes created per paint under the spinner | `onPaint` count + `MutationObserver` `addedNodes` over 10 s of `claude-spinner-10s` | 100/10 s → 10 paints/s, 28.69 nodes/paint | 100/10 s → 10 paints/s, 28.69 nodes/paint — unchanged (Plan B's target) | 100/10 s → 10 paints/s (unchanged), 73.5 DOM nodes/paint over 10.19 rebuilt rows/paint — **not comparable to the 28.69**: that counter recorded only the inserted subtree roots (a re-inserted block section counted as one node); the review fixed it to count every node in each inserted subtree (`main.ts` counts `1 + node.querySelectorAll("*").length`). The pre-Plan-B value under the corrected counter was not re-measured | `claude-spinner-10s`: 100/10 s → 10 paints/s (unchanged), 73.50 DOM nodes/paint over 10.19 rebuilt rows/paint — identical to the Plan B figures; Plan C does not touch the DOM-node cost of a paint |
| main-thread block when a 2 MB tool result arrives in one mux message | `PerformanceObserver({ entryTypes: ['longtask'] })`, and the longest gap between two `requestAnimationFrame`s while the queue drains | `claude-long-50k`: a 2 MiB synchronous `core.feed` cost 57 ms in one task (the earlier 28.9 ms figure measured a ≤1.3 MiB end-of-fixture tail — harness bug fixed in Task 8). Headless Chromium reports no `longtask` entries at all (`longestTaskMs: null`), so the long-task count is not evidence either way | the queued path (`core.enqueue` + rAF `core.drain`, Task 6) parses the same 2 MiB over 18 frames, 165 ms total, mean 9.2 ms/frame, longest frame 24 ms (12 ms parse budget + the paint). `bench:agent:gate` fails on a frame > 50 ms or an observed long task > 50 ms | the same queued path now drains over 7 frames, 52.4 ms total, mean 7.49 ms/frame, longest frame 16.7 ms. `bench:agent:gate` still passes (no frame > 50 ms, no observed long task). The drop in frame count from Plan A's 18 is consistent with Task 8's per-generation `snapshot()`/`decodeBlocks()` memoisation making each drained frame cheaper to paint, not a change to the drain loop itself | the queued path drains over 6 frames, 54.8 ms total, mean 9.13 ms/frame, longest frame 22.3 ms on `npm run bench:agent`; the same probe under `npm run bench:agent:gate` (a separate run) read 7 frames, 53.5 ms total, mean 7.64 ms/frame, longest frame 17.2 ms — both inside Plan B's range and the gate's 50 ms budget, the spread is run-to-run noise; Plan C does not touch the queued-feed path |
| scroll bottom → row 0 at 50k rows | Playwright: `wheel` steps, count frames > 50 ms, assert every `data-terminal-row` index range is contiguous | `claude-long-50k` (60,137 rows): 60,134/60,137 rows covered over 2,245 scroll steps, 0 frames > 50ms, worst frame 0ms | `claude-long-50k`: 60,134/60,137 rows covered over 2,245 scroll steps, 0 frames > 50ms, worst frame 0ms — unchanged (Plan B's target; `bench:agent:scroll` still exits non-zero on the 3-row gap, pre-existing since Task 1, not in scope for Plan A) | `claude-long-50k`: 60,134/60,134 rows covered over 2,245 scroll steps, 0 frames > 50ms, worst frame 0ms — **full coverage**; the pre-existing 3-row gap no longer reproduces (`renderableRowCount()` itself now reports 60,134, matching `covered`), confirmed on 5 of 6 local runs. Trim phase (new in Plan B): top-edge row unchanged across a trim (row 25031 before and after, `first_stable_row` 0 → 5098) — `bench:agent:scroll` exits 0. One of six runs hit a harness-level flake (an undefined top-edge row mid-trim, coverage 59,908/60,134) that did not reproduce on retry; see the landed paragraph below | `claude-long-50k`: 60,134/60,134 rows covered over 2,245 scroll steps, 0 frames > 50ms, worst frame 0ms — unchanged. Trim phase: top-edge row unchanged across a trim (row 25031 before and after, `first_stable_row` 0 → 5098) — unchanged from Plan B, same numbers. The same harness-level flake Plan B reported (the page's `visibleRows()[0]` reads `undefined` mid-trim) reproduced once more on this HEAD's first `bench:agent:scroll` run and did not reproduce on a second, immediate retry; still not chased, still not a renderer defect (no code changed here to make it stop). The width-change phase Plan C adds runs on its own page right after the trim phase and is reported in the "Plan C landed" paragraph below, not in this cell, since it is a new metric this table did not carry before |
| reopen at 1k / 5k / 50k rows: time to first paint, rows recovered | daemon API + `/mux` (memory: verify via daemon API), `vt_replay` size | measured at the mirror's 1,000-row cap (`vtwasm.New(..., 1000)`) on `claude-long-50k`: replay 1,000 rows / 17,257 bytes, Go-side `Replay()` cost 0.306ms, renderer `firstPaintMs` 13ms | measured the same way: replay 1,000 rows / 17,257 bytes, Go-side `Replay()` cost 0.315ms, renderer `firstPaintMs` 12.5ms — unchanged within run-to-run noise (Plan B's target) | measured the same way: replay 1,000 rows / 17,257 bytes, Go-side `Replay()` cost 0.296ms, renderer `firstPaintMs` 13.1ms — unchanged within run-to-run noise | Plan C's Task 1-12 work adds history streaming, so this row now measures the full reopen, not just the frame: frame (`Replay(1000)`) — 1,000 rows / 17,318 bytes (was 17,257; recording is byte-identical, the 61-byte difference is this run's cap-1000 mirror trimming at a slightly different point), Go-side render 0.335–0.445ms across two runs, renderer paints it in `firstPaintMs` 36.4ms and 41.5ms across two runs — notably higher than Plan A/B's 12.5–13.1ms on the same 1,000-row frame. The cause was not investigated (out of scope for this measurement task); it is reported as-is, not adjusted, and does not affect the < 200ms target either way. History: 116 chunks / 937,856 bytes / 59,137 rows streamed off the capped mirror in 1,338.6–1,537.9ms across two runs (Go-side `HistoryChunk` loop); the renderer applies all of it and reaches its next paint in `allRowsMs` 100.9–105.1ms, ending at `rows` 60,134 — the *entire* fixture, not the historic 1,000-row cap. Measured at the fixture's ~60k rows; the spec's target is 200k rows and < 200ms first paint on localhost — first paint (36–42ms) is comfortably under 200ms at this scale, but this is 60k rows, not 200k, so the target is not proven at spec scale |
| memory of renderer core and mirror at 50k rows | `wasm memory.buffer.byteLength`; Go `runtime.MemStats` of the pty-host | `claude-long-50k`, all 60,137 rows fed: renderer core wasm `memory.buffer.byteLength` 26,083,328 bytes (~24.9 MiB); Go mirror wasm memory 4,128,768 bytes (~3.94 MiB) at the reopen probe's 1,000-row cap (not the full 60k — the harness's mirror probe is capped, see the row above) | `claude-long-50k`, all 60,137 rows fed: renderer core wasm `memory.buffer.byteLength` 11,272,192 bytes (~10.75 MiB); Go mirror wasm memory unchanged at 4,128,768 bytes (~3.94 MiB). The drop from the Today figure is a harness fix, not a renderer change: Today's number was sampled on a page where the old (Task 1) `longTask2MiB` ran immediately before the memory sample and injected one extra ~1.3 MiB single-chunk `core.feed` call, growing the wasm heap past its steady-state size; Task 8 moved `longTask2MiB` to its own page, so the sample now reflects `feedAll`'s normal 64 KiB-chunk feed pattern only | `claude-long-50k`, all 60,137 rows fed: renderer core wasm `memory.buffer.byteLength` 8,192,000 bytes (~7.81 MiB, down further from Plan A's ~10.75 MiB); Go mirror wasm memory at the product's own `mirrorLimits` (200,000 rows / 128 MiB), the whole fixture fed: 4,980,736 bytes (~4.75 MiB) holding 60,097 rows and 343,551 bytes of content. `TestAgentSessionReplayReport` now builds a second mirror at `mirrorLimits` for the memory measurement and fails if its wasm memory passes 128 MiB; the 4,128,768-byte (~3.94 MiB) figure this row carried in the Today and Plan A columns stays alongside it as the reopen-replay probe's number, measured at that probe's own 1,000-row cap (the replay cap is real product behaviour, `Ring`/`Replay(MaxOutputLines)`, and is unchanged). Both figures are far under the Part 1.4 target of < 128 MiB each | `claude-long-50k`, all 60,137 rows fed: renderer core wasm heap 8,192,000–9,175,040 bytes across two runs (~7.81–8.75 MiB), consistent with Plan B's ~7.81 MiB within noise. Go mirror wasm memory at the product's `mirrorLimits`, whole fixture fed: 9,633,792 bytes (~9.19 MiB) holding 60,097 rows / 343,551 content bytes — **up from Plan B's 4,980,736 bytes (~4.75 MiB)**, reproduced identically across three separate runs (the run above, the gate run, and a standalone `go test` run), so this is not noise. The likely cause: this task's own `TestAgentSessionReplayReport` now runs 116 `HistoryChunk` calls against `capped` (each doing a `vt_alloc`/`vt_free` pair for a render buffer) before reading `capped.module.Memory().Size()` for this figure; wasm32 linear memory only grows, so the allocator's working set from that streaming loop is baked into the number the test reports, on top of whatever the session's own rows cost. This was not "fixed" by reordering the measurement, since the brief places the history-streaming block before the report is built and doing otherwise would be tuning the number down rather than fixing a bug. Both figures remain far under the 128 MiB budget (9.19 MiB is 7.2% of it) at the fixture's ~60k rows; the spec's target is 200k rows, unverified at that scale |
| rendered-transcript pixel diff vs the pre-change screenshot | `bench/agent-session/feel-gate.mjs` screenshots the same fixture at the same scroll offsets before and after; diff must be zero unless the task declares a scoped change | — | `npm run bench:feel` → `PASS feel gate: zero pixel diff` (both fixtures) | `npm run bench:feel` → `PASS feel gate: zero pixel diff` (both fixtures) — unchanged | `npm run bench:feel` → `PASS feel gate: zero pixel diff` — unchanged |
| torn frames in `claude-spinner-10s` | `run.mjs` `tearing`: model states that became visible inside a sync block (fed byte by byte), paints showing a partial frame and frames painted more than once (fed in thirds, one frame per third) | 7470 states / 25 paints / 18 multi-paint of 120 frames | 0 states / 0 paints / 0 multi-paint of 120 frames. `tornStates` 7470→0 is Task 5's synchronized-output buffering. `tornPaints`/`multiPaintFrames` 25/18→0/0 is a Task 8 fix to the harness itself, not the renderer: `paintsPerFrame` sampled the "before" text hash with no settle delay, racing ahead of the renderer's ~60Hz-throttled `repaintOnFrame`, so it sometimes read a still-painting-the-previous-frame state as "torn". Adding two awaited `requestAnimationFrame` waits before the "before" sample (confirmed independently by the Task 5 implementer and reviewer) drives both to 0; `tornStates` (the byte-level, load-bearing check) was already 0 before this fix | 0 states / 0 paints / 0 multi-paint of 120 frames — unchanged | 0 states / 0 paints / 0 multi-paint of 120 frames — unchanged; Plan C does not touch synchronized-output buffering |
| `feed()` + `snapshot()` cost at 1k / 5k / 50k rows | `performance.now()` around `core.feed` then `core.snapshot()` for a 4 KiB chunk | — | `claude-long-50k` (60,137 rows), 20 samples each: 0.40ms @ 1k (reached row 1,361) / 0.70ms @ 5k (reached row 5,610) / 5.30ms @ 50k (reached row 50,252) | `claude-long-50k`, 20 samples @ 1k / 7 @ 5k / 15 @ 50k: 0.20ms @ 1k (reached row 1,361) / 0.10ms @ 5k (reached row 5,610) / 0.20ms @ 50k (reached row 50,341) — this is `feedSyncCost`, the row `bench:agent:gate` checks against the 20 % + 0.2 ms budget (50k's 0.20ms is well inside 1k's 0.20ms × 1.2 + 0.2ms); Part 1.4's 200k-row target is measured here at the fixture's 50k | `claude-long-50k`, 20 samples @ 1k / 15 @ 5k / 13 @ 50k (`bench:agent:gate` run): 0.20ms @ 1k (reached row 1,361) / 0.20ms @ 5k (reached row 5,610) / 0.10ms @ 50k (reached row 50,160) — unchanged within run-to-run noise, still well inside the 20% + 0.2ms budget `bench:agent:gate` checks; Plan C does not touch `feed()`+`sync()` |
| row nodes created per paint under the spinner | `MutationObserver` `addedNodes` filtered to `.terminal-row` over 100 spinner frames | — | `claude-spinner-10s`, 100 frames: 2,469 nodes (24.69 nodes/paint) | `claude-spinner-10s`, 100 frames: 1,019 nodes (10.19 nodes/paint) — Task 10's row pool; see the paints/nodes row above (`addedNodes`/`rowNodesAdded` both 1,019, a 1.0 ratio) | `claude-spinner-10s`, 100 frames: 1,019 nodes (10.19 nodes/paint) — unchanged; Plan C does not touch the row pool |
| main-thread task time of ten idle spinner panes over 10 s | CDP `Performance.getMetrics` `TaskDuration` delta, 10 renderers fed the same 100 frames at 100 ms | — | `claude-spinner-10s`, 10 panes: 1.759 s taskDuration (17.6% of 10 s) | `claude-spinner-10s`, 10 panes: 1.30 s taskDuration in the review's run (16.8 % of 10 s; the executor's runs read 1.01–1.68 s). Spec target is ≤ 25 % of the 1.759 s baseline = 0.44 s — **missed** (74 % of baseline). Not gated | `claude-spinner-10s`, 10 panes: 0.791s and 0.874s main-thread task time over 10s across two runs (7.9–8.7% of 10s) — against the pre-Plan-B baseline of 1.759s this is 45–50% of baseline, still **missed** against the ≤25% (0.44s) target but noticeably better than Plan B's 57–95% range; not investigated further (out of scope, Plan C does not touch idle-pane cost), not gated |
| rows repainted when a mouse move extends the selection by one row | `MutationObserver` on `style` of `.terminal-row` around one `selectionUpdate` during streaming | — | `claude-spinner-10s`: 2 rows repainted | `claude-spinner-10s`: 1 row repainted — Task 11's selection-fill diff against the previous paint; meets the target of 1 exactly | `claude-spinner-10s`: 1 row repainted — unchanged; Plan C does not touch selection |
| width change at 50k rows: viewport correctness, stale-row rewrap | new (Plan C): `bench/agent-session/scroll-gate.mjs`'s width phase — `session.widthChange(40)` (a column resize) at the scroll midpoint, then 40 more scroll steps | — | — | — | `claude-long-50k`, run 1 (`npm run bench:agent`/`bench:agent:gate`, no scroll steps, just the resize): `settleMs` 24.2–28ms, top-edge row 60081 before vs 60086 after (**not equal**, differs by 5 rows) on both runs of the plain resize probe. Run 2 (`npm run bench:agent:scroll`, resize at the scrolled-to-midpoint position, then 40 scroll steps): `settleMs` 26.1ms, top-edge row 30066 before and 30066 after (**equal**), `staleRows` 58,031 (lazy rewrap engaged — not every row was rewrapped eagerly), `scrolledRows` 40 (all 40 post-resize scroll steps found a row). The gate in `scroll-gate.mjs` asserts `before === after` and failed on the plain-resize probe's own numbers when tried standalone (see the "Plan C landed" paragraph); of 8 consecutive `bench:agent:scroll` runs, 3 passed cleanly (this run among them), 3 hit the pre-existing trim-phase flake, and 2 hit a new width-phase flake (`before` reads `-1`) — see the "Plan C landed" paragraph and `TERMINAL.md` §5 for both. Measured at the fixture's ~60k rows; the spec's target is 200k |
| slow-link burst (Part 1.3.H) | Go `host_test.go::TestReadPausesPastHighWatermarkAndResumesOnAck`, `TestHistoryStreamingNeverPausesTheChild` | — | — | — | Both PASS (`go test ./internal/adapters/runtime/ptyhost/... -run 'TestReadPausesPastHighWatermarkAndResumesOnAck\|TestHistoryStreamingNeverPausesTheChild' -v`). See the "Plan C landed" paragraph for what each test proves and the real-app caveat |

The last row is the **feel gate**. Every task in every plan runs it; a task
that changes pixels must name the item that allows it (Part 4 flags).

Plan A's first task builds this harness and fills the "Today" column; the
numbers become the targets below.

Plan A landed 2026-09-20: torn states/paints 0/0 (was 7470/25, plus 18
multi-paint frames of 120, also now 0); a 2 MiB tool result no longer parses
in one task — queued over 18 frames, longest frame 24 ms (was one 57 ms
task). Known residue: a single DEC 2026 block that reaches the 2 MiB
`SYNC_BUFFER_CAP` is flushed and parsed in one go inside the frame that
receives it (`TERMINAL.md` §5). Every other row is Plan B's target and is
unchanged within run-to-run noise.

Plan B landed 2026-09-20, measured on `feat/agent-tui-plan-b` HEAD, per Part
1.4's five acceptance rows:

- **`feed()`+`sync()` at row 50k within 20 % of row 1k** — PASS. `feedSyncCost`
  (the row `bench:agent:gate` now checks): 0.20ms @ 1k vs 0.20ms @ 50k, both
  sub-millisecond and well inside the 20 % + 0.2 ms budget. Measured at the
  fixture's 50k rows; the spec's target is 200k.
- **A paint under the spinner creates ≤ 2 DOM nodes per changed row, 0 for
  unchanged rows** — **MISS on the ≤ 2, PASS on the 0**. With the corrected
  counter (every node of each inserted subtree) the spinner creates 73.5 DOM
  nodes per paint over 10.19 rebuilt rows = 7.21 nodes per changed row: a
  rebuilt row is one `div` plus one `span` and one text node per style run,
  and the spinner's rows carry about three runs each. The ≤ 2 target is
  unreachable for any styled row with this DOM shape; the per-row cost is
  bounded by the row's run count, not by the session length. Unchanged rows
  create nothing (`dom-block-renderer.test.ts` "an unchanged row is not
  rebuilt when another row changed" pins it). The executor's earlier
  "1.0 node per changed row" was an artifact of the old counter recording
  only subtree roots. Reported by `bench:agent:gate`, not gated.
- **Scroll bottom → row 0: every stable row in order, no frame > 50 ms, the
  top-edge row unchanged across a trim** — PASS. `bench:agent:scroll` reports
  full coverage (60,134/60,134) and 0 frames > 50 ms on the current branch —
  the 3-row gap this row's Plan A entry reported as pre-existing and
  out-of-scope no longer reproduces here. The trim phase (new since Task 9)
  also passes: the row under the top edge is identical before and after a
  trim past the cap. One of six local runs of this bench hit a harness-level
  flake (the page's own `visibleRows()[0]` read `undefined` mid-trim, and
  coverage came back 226 rows short); it did not reproduce on five retries
  and is reported here for completeness, not as a renderer defect — no code
  was changed to make it disappear.
- **Renderer core and mirror memory at the fixture's 60k rows, each
  < 128 MiB** — PASS. Renderer core wasm heap: 8,192,000 bytes (~7.81 MiB).
  Go mirror wasm memory at the product's real `mirrorLimits` (200,000 rows /
  128 MiB) with the whole fixture fed: 4,980,736 bytes (~4.75 MiB) at 60,097
  rows — 3.7 % of the 128 MiB budget. `TestAgentSessionReplayReport` builds
  that mirror itself and fails if its wasm memory passes 128 MiB, so the
  number is now measured at the configured cap rather than at the
  reopen-replay probe's 1,000-row one; the probe's own 4,128,768-byte
  (~3.94 MiB) figure is still reported beside it for the replay path.
- **Part 3: ten idle panes at ≤ 25 % of the baseline's CPU, and
  `selectionRepaint.rowsRepainted` = 1** — **MISS on the panes, PASS on the
  selection**. Ten panes: 1.30 s main-thread task time over 10 s in the
  review's run (executor runs: 1.01–1.68 s) against a pre-Plan-B baseline of
  1.759 s measured once — 57–95 % of baseline, target ≤ 0.44 s. The executor
  had read the target as 25 % of the 10 s window (2.5 s), which is not what
  Part 3 says; that reading was removed from the gate. Where the remaining
  time goes was not profiled in Plan B (candidates: `renderedRows()` layout
  reads, the per-paint `trimTrailingBlankRows`, the harness's own
  `MutationObserver` on ten hosts). `selectionRepaint.rowsRepainted`: 1
  (was 2 pre-Plan-B).

Three of the five rows Plan B owns pass (feed+sync flat, scroll, memory);
the DOM-nodes-per-changed-row and idle-pane rows miss as described.
`bench:agent:gate` asserts feed+sync flatness and the one-row selection
repaint and prints the two missed rows; the scroll row is asserted by
`bench:agent:scroll` and the mirror-memory row by the Go test itself. No code
was changed to make any number above hit its target — the numbers here are exactly what the commands in
this section printed on this branch's HEAD.

Plan C landed 2026-09-20, measured on `agent-tui-plan-c-long-sessions-edges`
HEAD (`dad59aba2`), per Part 1.4's four rows Plan C owns. Every number below
came from `npm run bench:agent`, `npm run bench:agent:scroll`,
`npm run bench:agent:gate`, `npm run bench:feel`, and the two Go flow-control
tests, run on this HEAD after both wasm artifacts and the daemon were
rebuilt. `claude-long-50k` (≈60,134–60,137 rows depending how a run counts
the trailing partial row) is the only long recording in this tree, so
**every number in this paragraph is measured at ~60k rows, not the spec's
200k row target** — this is the one exception the task's brief calls out
explicitly, not an extrapolation or a renamed fixture.

- **Width change at 200k rows: the viewport is correct within the debounce
  plus one frame; older rows rewrap on scroll without a jump.** Measured at
  the fixture's 60k rows. `bench:agent:scroll`'s width phase (which scrolls
  to the vertical midpoint, then calls `widthChange(40)`, then scrolls 40
  more steps) reports `settleMs` 26.1ms, top-edge row 30066 before and 30066
  after the resize (equal — **PASS**), `staleRows` 58,031 (most rows were
  marked stale rather than rewrapped eagerly — lazy rewrap is engaged, not a
  full walk), `scrolledRows` 40 (every post-resize scroll step still found a
  row). Separately, `run.mjs`'s own `widthChange` row — which calls
  `widthChange(40)` right after `feedAll()`, with **no** prior scroll to a
  stable position — read `before` 60081 and `after` 60086, **not equal**,
  reproduced identically across two runs. This is not the gated
  measurement: `scroll-gate.mjs`'s width phase, the one Part 1.4 actually
  asks about, scrolls to a known position first and passed. The
  `run.mjs`/no-prior-scroll variant is reported here for completeness and as
  a caveat on reading `before`/`after` from an unscrolled page, not
  investigated further — it was not "fixed" to agree with the gated number.
  **The gated width phase is itself flaky**, in the same family as the
  pre-existing trim-phase flake (baseline table, Plan B row): 8 consecutive
  `npm run bench:agent:scroll` runs on this HEAD gave 3 clean passes, 3 hits
  of the pre-existing trim flake, and 2 of a new width-phase flake where
  `width.before` reads `-1` (`visibleRows()[0]` empty) while `width.after`
  resolves correctly — the same "read landed before the repaint" race, now
  also around a width-change resize. Not chased down or patched around with
  more `requestAnimationFrame` waits, which would be tuning the gate to pass
  rather than fixing a diagnosed cause; see `TERMINAL.md` §5.
- **Reopen after 200k rows: first paint < 200 ms on localhost; all rows
  reachable; blocks identical (ids, exit codes, commands) to the live
  pane.** Measured at the fixture's 60k rows. `reopen.firstPaintMs` 36.4ms
  and 41.5ms across two runs — **PASS** against the < 200ms target, though
  both readings are 3× Plan A/B's 12.5–13.1ms figure for feeding the same
  1,000-row frame alone; the cause was not investigated (out of scope here).
  `reopen.allRowsMs` 100.9–105.1ms to apply all 116 history chunks after the
  frame paints. `reopen.rows` 60,134 against `mirrorCapRows` 60,097 (the
  capped mirror's own row count) — **all rows reachable, PASS**, the
  reopened session recovers the entire fixture, not the historic 1,000-row
  replay cap. For the block half: a new assertion in
  `TestAgentSessionReplayReport` feeds the frame plus every history chunk
  into a second `vtwasm` parser and compares the `id=`/`cmd=`/`exit=` marks
  recovered from that parser's own `HistoryChunk` walk against the source
  mirror's — **matched 0 blocks against 0 blocks**, because `claude-long-50k`
  has no blocks at all in its scrolled-off history (`capped.MemoryStats().Blocks`
  is 0 for this fixture, confirmed with an ad hoc check and not committed).
  The assertion is real and would fail loudly on a mismatch (`t.Errorf` with
  both lists), but this fixture cannot exercise the non-trivial case —
  neither fixture in this tree has a block that has scrolled into history.
- **Renderer core and mirror each < 128 MiB at 200k rows.** Measured at the
  fixture's 60k rows. Renderer core wasm heap 8,192,000–9,175,040 bytes
  (~7.81–8.75 MiB) across two runs — unchanged from Plan B within noise.
  Go mirror wasm memory at the product's `mirrorLimits`, whole fixture fed:
  9,633,792 bytes (~9.19 MiB), reproduced identically across three separate
  runs — up from Plan B's 4,980,736 bytes (~4.75 MiB). The likely cause: this
  task's own history-streaming loop in `TestAgentSessionReplayReport` runs
  116 `vt_alloc`/`vt_free` pairs against `capped` before the test reads
  `capped.module.Memory().Size()`, and wasm32 linear memory only grows, so
  the streaming loop's own allocator working set is now baked into the
  number this test reports. Both figures are still far under 128 MiB
  (9.19 MiB is 7.2% of the budget) — **PASS** at 60k rows, unverified at
  200k.
- **A slow-link burst (H).** `TestReadPausesPastHighWatermarkAndResumesOnAck`
  and `TestHistoryStreamingNeverPausesTheChild` both PASS. The first attaches
  to a session that already has a replay frame ("existing screen") before
  the burst starts — the test comments this explicitly, because a client
  acks every byte it consumes including the replay, and a test that attached
  to an empty session would pass even if flow control were dead for every
  real pane, since there would be no replay bytes to desynchronize the ack
  count from. It then writes 8×32 KiB from a background goroutine, confirms
  `readsPaused()` trips, acks past the burst, and confirms reads resume and
  the writer goroutine finishes. The second confirms streaming a long
  history to one client (`sendResizeWithHistory(..., true)`) never trips
  `readsPaused()` for the shared child, even while that one client is being
  paced by acks. No real-app number was obtained for this row — that would
  need a live daemon and a deliberately throttled mux connection, which was
  not set up for this measurement pass; this is stated rather than
  manufactured.

## Part 1 — Long sessions: every message stays, scrolling never breaks

### 1.1 Requirement

A session of any length (target: 200,000 rows, ~8 hours of dense agent
output) keeps every row reachable by scrolling, in the live pane and after a
reopen of the pane, with no per-frame cost that grows with the session
length and no visible jump when older rows are trimmed or rewrapped.

### 1.2 Today, with citations

- **Renderer cap.** `DEFAULT_SCROLLBACK = 5000`
  (`frontend/src/renderer/components/BlockTerminal.tsx:66`) →
  `TerminalCore.create({ scrollback })` (`packages/terminal/ts/core/src/terminal-core.ts:57`)
  → `TerminalCore::new(columns, scrollback_rows)` (`vt-core/src/lib.rs:58`)
  → `Parser::trim_to(max_total)` after every `feed` and `resize`
  (`lib.rs:116,175`; `parser.rs:296-307`):

  ```rust
  pub fn trim_to(&mut self, max_total: usize) {
      let before = self.rows.completed().len();
      if let Some(new_start) = self.rows.trim_to(max_total) {
          self.content.drop_before(new_start);
          self.styles.drop_before(new_start);
          let dropped = before - self.rows.completed().len();
          self.grid.trim_to_first_row(dropped);
      }
  }
  ```

- **Mirror cap.** `vtwasm.New(ctx, vtwasm.Module, cols, rows, MaxOutputLines)`
  with `MaxOutputLines = 1000` (`backend/internal/adapters/runtime/ptyhost/host_main.go:152`,
  `respawn.go:63`, `ring.go:8-9`). `vt_replay` renders that mirror
  (`packages/terminal/crates/vt-host/src/lib.rs:160-200`; Go side
  `vtwasm/vtwasm.go:122-124` `Replay(lines)`), so a reattach recovers at most
  1,000 rows. The raw `Ring` is 1,000 lines too. Nothing persists a worker
  session's rows across a pty-host restart: the capture journal
  (`backend/internal/service/terminalcapture/supervisor.go:100`) is started for
  `shellterm.ShellTerminalRecord` only.
- **Per-feed cost.** `WasmTerminalCore::feed` (`vt-wasm/src/lib.rs:44-49`):

  ```rust
  pub fn feed(&mut self, bytes: &[u8]) -> Result<(), JsError> {
      self.core.feed(bytes);
      let snapshot = self.core.snapshot().map_err(js_error_from_core)?;
      self.export.refresh(&snapshot)?;
      self.generation = self.generation.wrapping_add(1);
      Ok(())
  }
  ```

  `build_snapshot` (`vt-core/src/grid.rs:80-101`) allocates `all_content`,
  `row_ranges`, `row_indents`, `style_pairs`, `run_ranges` and appends every
  completed row (`for row in rows.completed()`) then every screen row. The
  renderer calls `core.snapshot()` again per paint
  (`ts/renderer-dom/src/dom-block-renderer.ts:371`) — that one only builds
  typed-array views over the export (`terminal-core.ts:87-152`), but
  `decodeBlocks(snapshot)` (`:400`) walks every block record, and the
  selection path re-exports per mouse move (`TERMINAL.md` §5, `:249`).
- **Width change.** `RowIndex::rewrap` walks all scrollback rows
  (`TERMINAL.md` §4.2, §5: "fine at 1k–10k rows with the debounce; revisit if
  scrollback caps grow"). This spec grows them 40×.
- **Virtualiser.** `computeWindow` (`ts/renderer-dom/src/viewport.ts:53-…`,
  input `{ blocks, scrollTop, viewportHeight, rowHeight, headerHeight, overscanRows, blockPaddingY }`,
  output `{ firstBlock, lastBlock, leadingSpacer, trailingSpacer, rowWindows, pinnedBlockIndex }`)
  with `OVERSCAN_ROWS = 6` (`dom-block-renderer.ts:45`) renders only visible
  blocks and windows rows inside big blocks. Block elements outside the window
  are emptied and dropped (`:465-470`) and rebuilt from scratch when scrolled
  back into view; rows inside the window are rebuilt every paint
  (`block-body.ts:19-44`, `section.replaceChildren(fragment)`).
- **Scroll anchoring while scrolled up.** `repaint` restores the pre-paint
  `scrollTop` (`:474-476`). When `trim_to` removes rows above the viewport,
  the content under that `scrollTop` shifts by the trimmed height — a
  visible jump. Not verified by a test; Part 1.3.D adds one.
- **Reopen.** Worker sessions get `NO_HISTORY_BLOCKS`
  (`frontend/src/renderer/components/TerminalPane.tsx:1043`; history blocks
  are a shell-terminal feature), so a reopened Claude pane is the mirror
  replay (≤ 1,000 rows) plus live bytes. The renderer buffers the replay for
  up to 1 MiB / 750 ms before feeding it (`useTerminalSession.ts:122-155`).

### 1.3 Design

#### A. Caps become byte budgets, large, equal in both cores (survey §1.13)

- `TerminalCore::new(columns, limits: Limits)` with
  `pub struct Limits { pub rows: usize, pub bytes: usize }` and
  `Limits::DEFAULT = Limits { rows: 200_000, bytes: 128 * 1024 * 1024 }`;
  `trim_to` trims whole rows from the front while `rows.completed().len() > rows`
  **or** `content.len() + styles.byte_len() > bytes`. Keep `new(columns, scrollback_rows)`
  as a thin constructor for existing tests (`Limits { rows: scrollback_rows, bytes: usize::MAX }`).
- `TerminalCore::memory_stats() -> MemoryStats { content_bytes, style_entries, rows, blocks }`;
  exported from `vt-wasm` (`memory_stats_ptr/len` as four `u32`) and from
  `vt-host` (`vt_memory_stats(handle, out_ptr)`).
- Wiring: `BlockTerminal.tsx:66` `DEFAULT_SCROLLBACK` → `DEFAULT_LIMITS`;
  `TerminalCoreOptions.scrollback` becomes `limits?: { rows, bytes }` with
  `scrollback` kept as an alias for one release. `host_main.go:152` and
  `respawn.go:63` pass the same numbers; `vtwasm.New` gains a `bytes` argument
  and `vt_new` a fourth parameter. `MaxOutputLines` stays for the `Ring`.
- Why these numbers: 200k rows of agent output at ~80 visible bytes/row and
  ~1 style run per 10 cells is ~16 MB content + ~8 MB styles; 128 MiB leaves
  room for wide rows and heavy colour. Two cores at that size fit a wasm heap
  and the daemon's subprocess.

Tests: `vt-core/tests/limits.rs` — `byte_cap_trims_whole_rows_and_keeps_blocks_consistent`,
`row_cap_still_applies`, `memory_stats_match_after_trim`;
`vt-wasm/tests/export_layout.rs` extended for the stats export;
Go `vtwasm/vtwasm_test.go::TestNewAcceptsByteLimit`.

#### B. Incremental export: the snapshot stops being O(session) (survey §1.2; §4.2's sequence numbers)

Content offsets never move (`TERMINAL.md` §4.2: rewrap changes row
boundaries, not bytes), so the scrollback half of the export is append-only
between width changes.

- `vt-core`: `Parser` gains
  - `generation: u64`, incremented by every mutating operation;
  - `history_exported_rows: usize` and `history_exported_bytes: usize`,
    the prefix of `rows.completed()` / `content` already handed out;
  - `screen_dirty: Vec<bool>` (one per screen row) set by every `ScreenGrid`
    write path (`print`, erase, scroll, insert/delete lines, `evict_frame`,
    `resize_cells`), plus `full_dirty: bool` set by rewrap, `trim_to` that
    trims below `history_exported_rows`, alt-screen enter/leave,
    `process_boundary`, and `resize`;
  - `pub fn take_delta(&mut self) -> Delta` where
    ```rust
    pub struct Delta {
        pub generation: u64,
        pub kind: DeltaKind,            // Full | Partial
        pub trimmed_rows: usize,        // rows dropped from the front since last delta
        pub appended_history: Range<usize>,  // completed-row indices new since last delta
        pub screen_rows: Vec<usize>,    // dirty screen rows (Partial) or all (Full)
        pub remap: Option<Vec<(usize, usize)>>, // old→new row map after a rewrap
    }
    ```
    `take_delta` clears the dirty state. `TerminalCore::feed` no longer
    trims eagerly per chunk when under the byte budget; trimming stays in
    `feed` but is recorded in the delta.
- `vt-wasm`: `ExportBuffers` keeps its vectors between calls and applies a
  `Delta`: on `Partial`, append the new history rows' bytes/ranges/indents/
  styles, rewrite only the screen section (which lives after the history
  section in `rows`/`run_ranges`/`style_pairs`, so it is a truncate-and-
  append), and drop `trimmed_rows` from the front by advancing a
  `history_start` offset rather than shifting memory (a compaction runs when
  the dead prefix exceeds 25 % of the buffer). On `Full`, rebuild as today.
  `feed()` stops calling `snapshot()`; it only feeds. A new
  `sync() -> u32` builds the export from the pending delta and returns the
  generation; `snapshot()`-style pointer getters read the synced export.
- `ts/core`: `TerminalCore.feed` calls `inner.feed` only; `TerminalCore.snapshot()`
  calls `inner.sync()` first, memoises the returned views by generation
  (`private cached: { generation, snapshot } | null`) and returns the cached
  object while the generation is unchanged, so `repaint`, `selectionView`
  and `decodeBlocks` share one export per frame. `decodeBlocks` is memoised
  per generation in `ts/core/src/blocks.ts`.
- Row events for anchors (survey §3.5) are the delta's `trimmed_rows` and
  `remap`, surfaced as `TerminalCore.onRowEvents((e: { trimmed: number; remap: ReadonlyArray<[number, number]> | null }) => void)`.

Invariant the tests pin: after any sequence of `feed`/`resize`, the export
built incrementally is byte-identical to a full rebuild from `build_snapshot`.

Tests: `vt-core/tests/delta.rs` — `printing_marks_one_screen_row_dirty`,
`scroll_off_appends_history_and_marks_moved_rows`, `rewrap_yields_full_delta_with_remap`,
`trim_reports_trimmed_rows`, `take_delta_clears`; `vt-wasm/tests/incremental_export.rs`
— `incremental_export_equals_full_rebuild` (property-style over the
`exit_encoding.rs` fixture and random chunkings), `compaction_preserves_offsets`;
`ts/core/src/terminal-core.test.ts` — "snapshot is cached per generation",
"feed alone does not export".

#### C. Stable row ids (survey §4.1)

- `Parser.trimmed_total: u64` incremented in `trim_to`; `stable_row(flat) = flat + trimmed_total`;
  `flat_row(stable) -> Option<usize>`. `GridSnapshot` and the export carry
  `first_stable_row: u64` (two `u32` words). `BlockGrid` stores stable rows:
  `trim_to_first_row(dropped)` becomes a no-op for blocks (their rows do not
  change) and is deleted once `BlockGrid` is stable-row based; `remap_rows`
  stays for rewrap.
- Renderer: `selection-model.ts` anchors, find hits (`find-bar.ts`), the
  pinned header index and the scroll anchor (D) hold stable rows;
  `row-geometry.ts` converts through `firstStableRow`. `data-terminal-row`
  attributes carry the stable row so the bench can assert contiguity across
  trims.

Tests: `vt-core/tests/stable_rows.rs` — `stable_row_survives_trim`,
`flat_row_is_none_after_trim`, `blocks_keep_rows_across_trim`;
`selection-model.test.ts` — "a selection survives a trim above it".

#### D. Scroll position anchored to a stable row, not to `scrollTop`

- `DomBlockRenderer` keeps `anchor: { stableRow: number; offsetPx: number } | null`,
  updated on every `scroll` event while `stickToBottom` is false: the first
  row whose top is at or below the container's top, and its offset. After
  each paint, if `stickToBottom` is false, `scrollTop` is recomputed from the
  anchor through `row-geometry.ts` (`rowTop(stableRow) + offsetPx`) instead of
  restored from the previous value (`:474-476` today). A trim above the
  viewport, a rewrap that changes row counts above, a block header appearing
  above: same text under the same pixel.
- `stickToBottom === true` keeps today's path (`:503-518`).
- When the anchor row itself is trimmed, the anchor clamps to the first row.

Tests: `dom-block-renderer.test.ts` — "keeps the text under the top edge
when rows are trimmed above the viewport", "keeps it across a rewrap";
`bench/agent-session/scroll-gate.mjs` — at 50k rows scroll to the middle,
feed 10k more rows so a trim happens, assert the `data-terminal-row` at the
top edge is unchanged.

#### E. Bounded element pool instead of drop-and-rebuild (survey §3.1)

- `block-body.ts`: row nodes keyed by stable row in a `Map` on the block
  element (`data-terminal-row`); `populateBlock` patches rows whose stable
  row is in the delta's dirty set or new, reuses the rest, and moves the
  cursor element instead of recreating it. Block elements leaving the window
  go to an LRU (`ts/renderer-dom/src/element-pool.ts`, cap 3× the window's
  block count); returning blocks whose generation is unchanged reattach
  their nodes untouched.
- `paintSelectionFill` diffs the previous and current selected row sets and
  touches only the difference (survey §2.3).

Tests: `dom-block-renderer.test.ts` — "row elements are reused across
paints" (identity), "an unchanged row is not rebuilt when another row
changed", "a block scrolled out and back in keeps its nodes",
"extending the selection by one row repaints one row".

#### F. Rewrap cost: lazy for cold history (survey §5.8; Ghostty `PageList.zig:1263-1265` deferred-reflow TODO)

- On a width change the core rewraps the screen and the newest `HOT_ROWS = 2_000`
  completed rows eagerly, records `width_of_rows: Vec<(range, cols)>`
  (runs of rows still cut at an older width), and marks the rest stale.
  `rows_for(range)` (used by the export for the window plus overscan)
  rewraps a stale range on first access and emits a `remap` for it. The
  total row count above the viewport is an estimate until touched; the
  anchor (D) keeps the viewport still while it corrects. Selection and find
  hold content offsets, which rewrap does not move.
- Debounce stays 100 ms trailing (`TERMINAL.md` §4.6).

Tests: `vt-core/tests/lazy_rewrap.rs` — `cold_rows_are_rewrapped_on_access`,
`hot_rows_are_rewrapped_eagerly`, `blocks_and_pins_follow_lazy_remap`,
`two_width_changes_before_access_rewrap_once`.

#### G. Reopen and reattach recover everything (survey §1.9, §3.11, §6.3)

- The mirror holds the same limits as the renderer (A), so `vt_replay` can
  reproduce the whole session. Replay order becomes:
  1. modes: `?1049h` if alt is active, `?1000/1002/1003/1006h` per
     `mouse_tracking`/`sgr_mouse`, `?2004h`, `?1004h`, `?1h`, `?25l` if the
     cursor is hidden (today `vt_replay` emits alt mode and the cursor only);
  2. the live frame (today's clipped rows, `TERMINAL.md` §4.7);
  3. `OSC 7000 ; v=1 ; ready=1 ST` — the client paints here;
  4. history newest→oldest in chunks of 512 rows, each chunk framed by
     `OSC 7000 ; v=1 ; history=<first_stable_row>,<count> ST`, with block
     records re-emitted as the existing `id=`/`cmd=`/`exit=` marks so the
     reopened pane has the same blocks, not re-derived ones.
- `vt-core`: `RowIndex::prepend(rows)` (row records only; bytes are appended
  to `Content` and the records point at them), `Parser::apply_history_chunk`,
  and `TerminalCore::feed` recognises the `ready`/`history` marks (in
  `crates/marks`). `BlockGrid` accepts prepended blocks.
- Go: `attach.go` streams the four parts; `attachHandshake` returns after
  part 3 so a client can start painting while history flows.
- App restart: the daemon's `RestoreAll` respawns; the previous pty-host's
  rows are gone. Persisting the mirror to disk is Decision 2.

Tests: `vt-core/tests/replay.rs` — `replay_prepends_history_without_moving_the_frame`,
`modes_are_replayed`, `blocks_survive_reopen`; Go
`vtwasm/replay_test.go::TestReplayOrderIsModesFrameReadyHistory`,
`attach_replay_test.go::TestClientPaintsAtReadyBeforeHistory`;
`useTerminalSession` test — "paints at READY".

#### H. Flow control on the mux (survey §6.3, §3.13)

- The mux client acks every 5,000 bytes (`{ch:'terminal', type:'ack', bytes}`);
  the pty-host stops calling `pty.Read` at 100,000 unacknowledged bytes per
  slowest client and resumes at 5,000 (constants from VS Code
  `terminal.ts:876-896`). `client.go`'s per-client queue (`awaitCapacity`)
  stays for socket back-pressure; this adds end-to-end back-pressure to the
  child.

Tests: Go `host_test.go::TestReadPausesPastHighWatermarkAndResumesOnAck`;
`mux_client_test.dart` and `useTerminalSession` test — acks sent per 5,000 bytes.

### 1.4 Acceptance

- `feed()` for a 4 KiB chunk at row 200k costs within 20 % of the same chunk
  at row 1k.
- A paint under the spinner creates ≤ 2 DOM nodes per changed row and 0 for
  unchanged rows.
- Scroll bottom → row 0 at 200k rows: every stable row index rendered in
  order, no frame > 50 ms, the top-edge row unchanged across a trim.
- Width change at 200k rows: the viewport is correct within the debounce +
  one frame; older rows rewrap on scroll without a jump.
- Reopen after 200k rows: first paint < 200 ms on localhost; all rows
  reachable; blocks identical (ids, exit codes, commands) to the live pane.
- Renderer core and mirror each < 128 MiB at 200k rows.

## Part 2 — Frame fidelity: no tearing, no stalls

### 2.1 Synchronized output buffered in the parser (survey §2.1; replaces §1.1's renderer skip)

Today: `note_private_mode` (`vt-core/src/parser.rs:199-220`) handles 1006,
2004, 1004, 1000/1002/1003 and returns for everything else; 2026 is ignored;
`repaintOnFrame` paints whatever is parsed.

Design (port of `vte-0.15.0/src/ansi.rs:298-415`, the crate we already
compile — `~/.cargo/registry/src/index.crates.io-*/vte-0.15.0/src/ansi.rs`):

```rust
pub(crate) struct SyncBuffer {
    bytes: Vec<u8>,
    deadline_ms: Option<u64>,
}
const SYNC_TIMEOUT_MS: u64 = 150;
const SYNC_BUFFER_CAP: usize = 2 * 1024 * 1024;
const BSU: &[u8] = b"\x1b[?2026h";
const ESU: &[u8] = b"\x1b[?2026l";
```

- `TerminalCore::feed(bytes)` becomes `feed_at(bytes, now_ms: u64)`; `feed`
  keeps its signature and passes the last `now_ms` seen. While
  `sync.deadline_ms.is_some()`, bytes are appended to `sync.bytes`; only the
  tail (`len(new) + 7` bytes) is scanned with `memchr` for BSU (extend the
  deadline) or ESU (flush). Outside a sync block, the chunk is scanned for
  BSU; bytes before it are fed normally, bytes from it on are buffered.
  Flush = feed the buffered bytes through the normal path (marks decoded
  then, so block events stay in stream order with `lib.rs:77-83`), clear.
  Flush also on `bytes.len() >= SYNC_BUFFER_CAP`, on `tick(now_ms)` past the
  deadline, on `resize`, and on `process_boundary`.
- `TerminalCore::tick(now_ms)`; `synchronized_output() -> bool`.
- `vt-wasm`: `feed(bytes, now_ms: f64)`, `tick(now_ms: f64)`. `ts/core`:
  `feed(bytes)` passes `performance.now()`; the renderer's rAF loop calls
  `core.tick(timestamp)` before `snapshot()`.
- `vt-host`: `vt_feed(handle, ptr, len, now_ms: u64)` and `vt_tick(handle, now_ms)`;
  Go `Parser.Feed` passes `time.Now().UnixMilli()`; `pumpPTY` calls
  `parser.Tick` on its timer so a stalled child cannot hold the mirror.
- Pump hold (replaces the survey's §4.4 3 ms proposal — the pump already
  coalesces at `flushInterval = time.Second/60`): `deliver` asks the mirror
  `parser.InSync()` after feeding and, if true, holds the *next* flush until
  ESU or the 150 ms deadline, so a frame is not split across two mux
  messages. Bounded by `SYNC_TIMEOUT_MS`.

Tests: `vt-core/tests/synchronized_output.rs` —
`bytes_inside_a_sync_block_are_invisible_until_esu`,
`a_frame_split_across_three_feeds_snapshots_once`,
`a_mark_inside_a_sync_block_lands_after_the_rows_before_it`,
`overflow_flushes`, `tick_past_deadline_flushes`, `bsu_inside_a_block_extends_the_deadline`,
`resize_flushes`, `unknown_private_modes_still_ignored`;
`dom-block-renderer.test.ts` — "does not paint a half frame";
Go `host_test.go::TestDeliverHoldsAcrossASyncBlock`,
`vtwasm/replay_test.go::TestReplayNeverStartsInsideASyncBlock`.

### 2.2 Feed budget per animation frame (survey §2.10, §3.13)

Today: `BlockTerminal.feedToCore` calls `core.feed` synchronously per mux
message (`useTerminalSession.ts:579` → `BlockTerminal.tsx:141`); a 2 MB
message parses in one task.

- `ts/core`: `TerminalCore.enqueue(bytes)` appends to a backlog;
  `drain(deadlineMs = 12)` feeds slices (≤ 64 KiB each) until the deadline
  or empty, returns `{ remaining }`; the renderer's rAF loop calls `drain`
  first, then `tick`, then paints. `hasBacklog()` for the host. `feed`
  remains for synchronous callers (tests, replay).
- `onFeedParsed(listener)` fires after each drained slice (the hook the ack
  path in 1.H and find use).
- Keyboard input is never queued behind the backlog: `TerminalSurface` sends
  keys straight to the transport as today.
- `BlockTerminal.feedToCore` switches to `enqueue`.

Tests: `terminal-core.test.ts` — "a 1 MiB enqueue drains over several
frames in order", "drain stops at the deadline", "onFeedParsed fires per
slice"; `bench/agent-session` — long-task count for the 2 MB fixture.

### 2.3 Cached char metrics (survey §3.3)

Today: `measure()` (`dom-block-renderer.ts:139-151`) runs
`getBoundingClientRect()` on the hidden measure node every call; callers:
`repaint` (`:419`), `cellMetrics()` (selection), `jump-to-bottom`,
`blockContentInset`.

- Cache `{ cellWidth, cellHeight }`; invalidate on `setFont`/theme change,
  `devicePixelRatio` change (`matchMedia(\`(resolution: ${dpr}dppx)\`)` listener,
  xterm.js `DomRenderer.ts:330-334`), and a `ResizeObserver` on the measure
  host. Prefer `TextMetrics` (`measureText('W')` + `fontBoundingBoxAscent/Descent`)
  when supported, fall back to the DOM span (xterm.js `CharSizeService.ts:11-40,75-130`).

Tests: `dom-block-renderer.test.ts` — "measure() reads layout once until
the font changes" (spy on `getBoundingClientRect`).

### 2.4 Integrity checker and dispatch trace (survey §1.14, §5.10)

- `Parser::verify_integrity() -> Result<(), IntegrityError>`: every
  completed row's range lies inside `Content`; rows contiguous and ordered;
  `wrapped` rows are followed by a row; blocks tile the flat row space in
  order without overlap and end at or before the last row; `AttributeMap`
  keys inside `Content`; export prefix counters ≤ actual lengths. Called
  after every public mutation under `#[cfg(debug_assertions)]` and at the
  end of every integration test via a `common::check(&core)` helper.
- `feature = "trace"`: `Parser` records `(offset, action)` for every
  dispatched `vte` action into a ring the tests can read
  (`TerminalCore::trace() -> &[TraceEntry]`), so a captured artefact can be
  pinned to a sequence (Kitty `REPORT_COMMAND`).
- A `proptest` generator (dev-dependency) of print/SGR/CUP/ED/EL/IL/DL/
  resize/OSC 133 sequences asserting integrity after every step.

Tests: `vt-core/tests/integrity.rs` — the property test and one failing
fixture per invariant.

### 2.5 Recording and reference replay (survey §2.9, §7.6)

- Pty-host: `OPERATOR_PTY_RECORD=<dir>` env (read in `host_main.go` next to
  the other host env) tees every `deliver` batch to
  `<dir>/<session-id>.recording` and appends `{offset, cols, rows}` to
  `<dir>/<session-id>.size.json` on start and each resize. This is a
  subscriber of the same broadcast as `capture.go`, never in the hot path's
  lock.
- `packages/terminal/crates/vt-core/tests/ref/<name>/{recording, size.json, screen.txt, cursor.json}`
  and `tests/ref.rs` with a `ref_tests! { … }` macro (Alacritty
  `alacritty_terminal/tests/ref.rs:16-27,94-130`, Warp
  `app/src/terminal/ref_tests/mod.rs:1-2,25,94-160`): replay through
  `TerminalCore::new(cols, Limits::DEFAULT)` with resizes applied at the
  recorded offsets, compare `snapshot().row_text(i)` for the screen and
  cursor. Import Alacritty's 45 recordings (`alacritty_terminal/tests/ref/*`,
  Apache-2.0/MIT, attribution file beside them) with expectations regenerated
  as text; divergences triaged once as parser bug / model difference /
  upstream.

Tests: the corpus; `host_main_test.go::TestRecordEnvTeesOutputAndSizes`.

### 2.6 Acceptance

- `claude-spinner-10s` split at every byte boundary paints exactly one frame
  per ESU; no paint shows a mix of two frames (assert by hashing the
  rendered text per paint against the set of complete frames).
- The 2 MB fixture never blocks the main thread > 16 ms per frame.
- Feel gate diff is zero for every task in this part.

## Part 3 — Paint cost

Delivered by Part 1.B (one export per frame), 1.C, 1.E (row pool, dirty
rows) and the selection/cursor diff (survey §2.3). Acceptance: ten
`claude-spinner-10s` panes idle in one window keep the renderer process at
≤ 25 % of the baseline's CPU (number filled from the harness), and a mouse
move during streaming repaints one row.

## Part 4 — Text and glyph fidelity (all default-off, side-by-side first)

- **SGR attributes** (survey §2.8). Today `apply_sgr` (`parser.rs:309-360`)
  handles 0, 1, 2, 7, 22, 27, 30–37, 38, 39, 40–47, 48, 49, 90–97, 100–107;
  3, 4 (and `4:x`), 5, 8, 9, 23, 24, 25, 28, 29, 58, 59 fall to `_ => {}`.
  `StyleCode(u32)` (`style.rs`) packs colour + bold/dim/reverse. Design:
  `CellStyle` gains `attrs: u16` (bits: italic, underline, double, curly,
  dotted, dashed, strike, blink, hidden, overline) and an optional underline
  colour in `AttributeMap`; snapshot stride `STYLE_RUN_WORDS` grows by one
  word (checklist in `TERMINAL.md` §2: `GridSnapshot`, `append_row`,
  `append_screen_row`, `ExportBuffers`, `*_ptr/_len`, `terminal-core.ts`,
  `types.ts`, `vt-wasm/tests/exit_encoding.rs`); `style-code.ts` decodes;
  `row-builder.ts` emits `font-style`, `text-decoration(-style/-color)`,
  `visibility: hidden`, a `blink` class. Flag
  `theme.attributes: "plain" | "warp"`, default `"plain"` (today's look);
  Alacritty's `sgr`, `underline`, `colored_underline`, `clear_underline`
  recordings (2.5) are the parser tests.
- **Grapheme clusters** (survey §3.14, §5.9, §7.5). `screen.rs:363-410`
  widths per `char` via `unicode-width`; ZWJ/VS16/modifier sequences occupy
  one cell per part. Design: `unicode-segmentation` grapheme boundaries in
  `ScreenGrid::print`; continuation code points join the previous cell;
  `cell-width.ts` replaced by exported cell widths. Test corpus:
  `GraphemeBreakTest.json` from `kitty/kitty_tests/` (Unicode 17).
- **Width cache** (survey §3.2): per-glyph `letter-spacing` for fallback
  glyphs wider than the cell (xterm.js `WidthCache.ts`). Only if the
  baseline screenshot of an emoji/CJK row shows drift.
- **Box-drawing glyphs** (survey §1.17): only if the baseline shows hairline
  gaps between `│` rows at `lineHeight: 1.2` (`default-font.ts:7`); then
  CSS borders / inline SVG for U+2500–257F, U+2580–259F.
- **Cursor** (survey §2.12, §1.17): invert over a band whose colour equals
  the cursor's (contrast < 1.5, Alacritty `content.rs:21-22,124-134`);
  hollow when unfocused. Flag `theme.cursorContrast`.
- **IME in the alt-screen prompt** (survey §3.10): a composition view at
  `primaryCursorPlacement`, keydown swallowed while composing, one
  `onSendRaw` on `compositionend` after a `setTimeout(0)`
  (xterm.js `CompositionHelper.ts:73-95`). Needs a manual Japanese-IME test
  first; no flag (only affects composition).

## Part 5 — Act on what Claude Code prints (additive UI only)

- **Logical lines** (survey §4.5): `TerminalCore.logicalLines(range)` joins
  rows flagged `wrapped` (needs the per-row `wrapped` export; §2 checklist);
  `selection-text.ts` copies one line per logical line (closes
  `TERMINAL.md` §5 first gap).
- **Link grammar** (survey §6.4): port `vscode/src/vs/workbench/contrib/terminalContrib/links/browser/terminalLinkParsing.ts:44-214`
  (every `file:339`, `file:339:12`, `file(339,12)`, `"file", line 339`, …
  form, with its test table) to `ts/renderer-dom/src/link-parsing.ts`;
  candidates validated by the host (`HostCapabilities.resolvePath?`).
- **Linkifier** (survey §3.7): hover → per-logical-line providers (OSC 8,
  regex) → underline decoration → click with the platform modifier; pointer
  hand only over a link (`TERMINAL.md` §4.12).
- **Hint mode** (survey §2.7, §4.7, §5.5): a chord labels every visible match
  of the rule set (WezTerm `quickselect.rs:26-56` patterns minus IPFS, plus
  Kitty's `path:line` `default_linenum_regex` `marks.go:35-41`); typing a
  label emits `onHint({ ruleId, text, path?, line? })`; labels from
  WezTerm's `compute_labels_for_alphabet` (`quickselect.rs:57-100`).
- **OSC 8** (survey §1.15, §7.4): interned URIs with `MAX_DISTINCT_ENTRIES`
  and `MAX_URI_BYTES` caps, never reclaimed (Warp `hyperlink_registry.rs:1-15`).
- **Secret redaction** (survey §7.3): host-supplied patterns painted as
  masked highlights, honoured by copy and `readBlockOutput`. Default off.
- **Block timestamps** (survey §5.3, §6.2): `startedAt/finishedAt` per block
  from the host clock passed with `feed_at`; `onBlockFinished({ id, exitCode, durationMs, visible })`.

## Part 6 — Remote typing (after Part 1.G/H)

- **Predictive echo** (survey §4.3, §6.5): renderer-only dim overlay glyph at
  the cursor when measured RTT (input send → first byte) exceeds a host
  threshold; removed when real output advances the cursor; skipped when the
  previous keystroke produced no cursor advance.
- **Server-owned model** (survey §4.2): the mirror becomes the model of
  record and clients pull rows by `(stable row, generation)`; mobile drops
  its `xterm` fork. Its own design spec; Part 1.B/C/G are its prerequisites.

## Decisions needed

1. **Caps**: `Limits { rows: 200_000, bytes: 128 MiB }` per core, or other.
2. **Persist the mirror across app restarts**: yes → a follow-up serialises
   the mirror's export to `<data dir>/sessions/<id>/rows.bin` on shutdown and
   every 60 s (VS Code `serializeTerminalState`, survey §6.3); no → a
   restart starts at the respawn boundary as today.
3. **De-dup heuristic for the SIGWINCH duplicate row** (`TERMINAL.md` §4.8):
   in agent-TUI mode, when a repaint from home starts with a row whose text
   equals the last committed scrollback row, drop the duplicate. A genuinely
   repeated line would also be dropped once. Yes/no.
4. **SGR attributes default**: `"plain"` (today) or `"warp"` after the
   side-by-side.
5. **Lazy rewrap** (1.3.F) vs eager with a bigger budget. Proposed: lazy.

## Plans this spec produces

| Plan | Scope | Gate |
|---|---|---|
| A. Frame fidelity | baseline harness + feel gate; 2.5 recording; 2.1; 2.2; 2.3; 2.4 | none |
| B. Long sessions core | 1.3.A, B, C, D, E; Part 3 | A (harness) |
| C. Long sessions edges | 1.3.F; 1.3.G; 1.3.H | B |
| D. Text & glyphs | Part 4 | A; each item flag-gated |
| E. Act on output | Part 5 | B (stable rows, logical lines) |
| F. Remote typing | Part 6 predictive echo; §4.2 design spec | C |

Order: A → B → C → D and E in parallel → F.

### Plan A task outline (for the plan author; each becomes TDD tasks)

1. Harness: `bench/agent-session/{index.html,main.ts,run.mjs,feel-gate.mjs,scroll-gate.mjs}`
   on the existing Vite + Playwright pattern (`bench/selection-gate.mjs:1-30`);
   two fixtures; `npm run bench:agent` and `npm run bench:feel` in
   `packages/terminal/package.json`; fill the baseline table into this spec.
2. `OPERATOR_PTY_RECORD` in the pty-host (2.5) — needed to make fixture 2.
3. `tests/ref.rs` harness + Alacritty corpus import (2.5).
4. Integrity checker + property test (2.4).
5. Synchronized output in `vt-core` with `feed_at`/`tick` (2.1), then
   `vt-wasm`, `ts/core`, renderer tick; then `vt-host`/Go tick and the pump
   hold; rebuild both wasm artifacts and the daemon.
6. Feed budget in `ts/core` + `BlockTerminal` switch to `enqueue` (2.2).
7. Cached char metrics (2.3).
8. Feel gate + baseline re-run; CHANGELOG entries; `TERMINAL.md` §4 entry for
   the sync-output fix ("§4.16 Half-painted Ink frames") with its guards.

Verification for every task: `TERMINAL.md` §6 recipe (cargo fmt/clippy/test;
both wasm builds; Go tests; vitest in the three TS packages;
`npm run bench:selection`; `frontend` tsc; daemon build) plus
`npm run bench:feel`.

## References into the survey

Part 1: §1.2, §1.9, §1.13, §3.1, §3.5, §3.11, §4.1, §4.2, §5.8, §6.3.
Part 2: §1.14, §2.1, §2.9, §2.10, §3.3, §3.13, §4.4, §5.7, §5.10, §7.6.
Part 3: §2.3. Part 4: §1.17, §2.8, §2.12, §3.2, §3.10, §3.14, §5.9, §7.5.
Part 5: §1.15, §2.7, §3.7, §4.5, §4.7, §5.3, §5.5, §6.2, §6.4, §7.3, §7.4.
Part 6: §4.2, §4.3, §6.5.
