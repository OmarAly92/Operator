# TERMINAL.md — read this before touching anything terminal-related

This file is the memory of the terminal work. A fresh session has none of the
context that produced the current design, and most of the bugs listed here were
"fixed" wrongly at least once before the real cause was found. Read the whole
file before editing `packages/terminal`, the pty-host, `BlockTerminal`,
`TerminalPane`, `useTerminalSession`, or any resize/attach/replay code.

The reference implementation for every rendering decision is Warp's source at
`/Users/omaraly/development/AI/warp` (Rust). When in doubt, find what Warp does
and match it; the user's stated goal is "typical like Warp".

---

## 1. The pipeline, end to end

```
agent / shell process
   │  bytes over a pty (born at the pane's grid, see §4.5)
   ▼
opr pty-host  (backend/internal/adapters/runtime/ptyhost, one subprocess per session)
   ├─ ring.go            raw output ring for late attachers
   ├─ vtwasm/            PASSIVE MIRROR: vt-core compiled to wasm (vt_host.wasm),
   │                     run by wazero. Feeds every byte, answers GetOutput /
   │                     text extraction, and produces the attach REPLAY.
   ├─ attach.go          handshake: client states its grid (and whether it can
   │                     read history), host replays origin + modes + the
   │                     mirror's screen + READY, returns, then — for a client
   │                     that asked — streams history newest→oldest in 512-row
   │                     chunks, then live bytes
   └─ host.go            openingGridWait (250ms): a new connection must state its
                         grid before the replay is sent
   │  loopback TCP protocol (proto.go)
   ▼
daemon (session_manager → httpd mux channels)
   │
   ▼
renderer  frontend/src/renderer
   ├─ hooks/useTerminalSession.ts   transport, grid publisher, RESIZE_DEBOUNCE_MS
   ├─ components/TerminalPane.tsx   picks the surface; agentTui={kind === "worker"}
   ├─ components/BlockTerminal.tsx  mounts the package, setAgentTuiMode, onGeometry
   └─ lib/pane-grid.ts              last measured grid, spread into create/restore bodies
   │
   ▼
packages/terminal  (product-independent, see §3)
   ├─ crates/vt-core     the terminal model (Rust). Everything below is here.
   ├─ crates/vt-wasm     wasm-bindgen export for the renderer (snapshot buffers)
   ├─ crates/vt-host     C-ABI wasm for the Go mirror (vt_feed, vt_render, vt_replay)
   ├─ ts/core            TerminalCore wrapper over vt-wasm, snapshot views
   ├─ ts/renderer-dom    DomBlockRenderer: blocks, rows, virtualiser, selection
   │                     (`selection-model.ts` owns it as grid points, not DOM ranges)
   └─ ts/react           TerminalSurface: grid measurement, wheel, mouse, editor,
                         selection gestures and the copy chord (selection-gesture.ts)
```

There is no tmux in the interactive path any more. The old "janky scroll"
finding (tmux attach repaint) is history; do not re-add tmux.

Two copies of vt-core run for every session: the host mirror (reflow off, tmux
`capture-pane` semantics, `vt-host/src/lib.rs` calls `set_reflow_on_resize(false)`)
and the renderer core. A fix in vt-core is not live until BOTH wasm artifacts are
rebuilt (§6).

---

## 2. vt-core model in one page

- **ScreenGrid** (`screen.rs`) — the live rows×cols cells, a ring (`first`) so a
  full-screen scroll is O(cols). Each row also carries a `wrapped` flag set when
  the printer soft-wraps off it (Warp's `WRAPLINE`). Rows that scroll off the top
  are **evicted** (`record_eviction` → `EvictedRow { cells, wrapped }`).
- **Scrollback** = `Content` (append-only UTF-8 byte stream, chunked) +
  `RowIndex` (`RowRange { start, end, wrapped, indent }` byte ranges into it) +
  `AttributeMap<CellStyle>` (styles keyed by content offset). `scrollback::commit_row`
  turns an evicted row into content bytes and a row range. Every evicted row is
  committed, blank or not.
- **BlockGrid** (`block_grid.rs`) — OSC 133 / OSC 7000 blocks as `(first_row,
  row_count)` in the flat row space (scrollback rows, then screen rows). It never
  owns bytes; it is renumbered by `trim_to_first_row` and `remap_rows`.
- **Modes** (`parser.rs`):
  - default ("shell"): `reflow_on_resize = true` → a resize evicts the frame up to
    its last non-blank row into scrollback and restarts the screen; `ESC[2J` scrolls
    the frame into scrollback (`ClearPolicy::Scroll`).
  - `set_agent_tui_mode(true)` (Claude Code and every "worker" session): no reflow
    of the live frame (`resize_cells` truncates in place) and `ESC[2J` clears in
    place. Mirrors Warp's `FullGridClearBehavior::Clear` (`warp/crates/warp_terminal/src/model/grid/resize.rs:60`).
  - In BOTH modes scrollback is **rewrapped** on a width change (§4.2).
- **Snapshot** (`grid.rs` → vt-wasm `ExportBuffers` → TS `TerminalSnapshot`):
  `content`, `rows` (start,end pairs), `rowIndents` (u16 per row), `runRanges`,
  `stylePairs` (stride `STYLE_RUN_WORDS`), `blocks` (stride `BLOCK_RECORD_WORDS`),
  cursor, alt screen. Adding a per-row field means: `GridSnapshot` + `append_row`/
  `append_screen_row` + `ExportBuffers` + `*_ptr/_len` + `terminal-core.ts` +
  `types.ts` + the Rust test fixture `vt-wasm/tests/exit_encoding.rs` — and now,
  if the field is per-section, `ExportedRow`/`push_row` in `export.rs` and
  `history_rows`.
- **Limits** (`Limits { rows, bytes }`, `crates/vt-core/src/limits.rs`) caps
  both cores from the product, not a hardcoded scrollback count:
  `TerminalCore::memory_stats()` (`lib.rs:102`) reports `MemoryStats` against
  the same cap. The renderer core takes its limit from `BlockTerminal.tsx`
  `DEFAULT_LIMITS` (`frontend/src/renderer/components/BlockTerminal.tsx:66`,
  `{ rows: 200_000, bytes: 128 * 1024 * 1024 }`); the Go mirror takes its from
  `mirrorLimits` (`backend/internal/adapters/runtime/ptyhost/mirror_limits.go:5`,
  the same 200k rows / 128 MiB), which `vtwasm/agent_session_test.go`'s
  `productMirrorLimits` repeats so its memory report measures the real cap
  (the package that owns `mirrorLimits` imports `vtwasm`, so the test
  cannot read it). These are set independently and must be kept in sync by
  hand — there is no shared source of truth across the Rust/Go boundary.
- **Stable rows** give a row an identity that survives it migrating from the
  live screen into scrollback and back out again under trim. `trimmed_total`
  (`parser.rs:34,95`) counts rows evicted off the front since the session
  began; `stable_row(flat)` / `flat_row(stable)` (`lib.rs:340,344`) convert
  between a row's position in the current flat (scrollback + screen) space
  and this permanent counter. `BlockGrid::origin` (`block_grid.rs:27,45`) is
  the stable row of flat row 0 — equal to `Parser::trimmed_total`, advanced
  on every trim. Blocks hold **stable** rows in `Block.first_row` and
  convert down to flat rows at the grid's public boundary (`flat_extent`).
  `first_stable_row` is exported per snapshot (`vt-wasm/src/export.rs:370`,
  wired through `first_stable_row_lo`/`_hi`, `lib.rs:288-293`) so the
  renderer can convert without asking the core. The DOM's
  `data-terminal-row` attribute (`ts/renderer-dom/src/row-builder.ts:37`) is
  this stable row number, not a flat index — it is stable across a trim even
  though the row's screen position moves.
- **Prepended history.** `Content` allocates downward from `CONTENT_BASE`
  (`content.rs`) so prepended bytes never move already-committed offsets;
  rows stay offset-ordered, which is what every trim, style lookup and
  integrity check rests on. `Parser::adopt_origin` (`parser.rs:529`) is what
  puts a fresh core into the replaying host's stable row space before any
  history lands — it only succeeds on a core that has trimmed nothing and
  drawn nothing yet, and without it the two cores' stable-row spaces never
  meet and every history chunk is silently dropped
  (`Parser::apply_history_chunk` requires `first_stable_row + rows.len() ==
  trimmed_total`).
- **Stale runs.** `HOT_ROWS = 2_000`: a width change rewraps the screen and
  the newest 2,000 completed rows eagerly; everything older is marked stale.
  `rows_for(range)` rewraps a stale range on first access and corrects the
  row-count estimate above the viewport as ranges are touched. A run
  boundary — where eager rewrap stops and stale begins — is always a line
  start, never mid-row, so a partially-rewrapped logical line can't exist.
- **Delta / incremental export** avoid re-decoding scrollback that has not
  changed. `generation()` (`lib.rs:291`) bumps on every mutation;
  `take_delta()` (`lib.rs:295`) drains a `Delta` of the rows the `ScreenGrid`
  marked dirty since the last call. The dirty bits are set by the cell
  writers in `ScreenGrid` and by cursor movement: `ScreenGrid::move_to`
  (`screen.rs:371`) marks both the row the cursor left and the row it
  arrived on, so a bare cursor move repaints those two rows and nothing else.
  `ExportBuffers::apply` (`vt-wasm/src/export.rs:141`) applies a `Delta`
  against the exporter's own buffers rather than rebuilding them, dropping a
  dead prefix and compacting when it grows past the live content. TS
  `TerminalCore.sync()` (`terminal-core.ts:209`, calling `inner.sync()` at
  `vt-wasm/src/lib.rs:119`) reconciles the wasm side; `snapshot()`
  (`terminal-core.ts:205`) caches one `TerminalSnapshot` keyed on
  `{ generation, memory.buffer }` and rebuilds only when either has
  changed. The `buffer` term is load-bearing: a snapshot's typed arrays are
  views into wasm memory, and growing that memory reallocates it and
  detaches every view, so comparing buffer identity is what makes a stale
  view impossible instead of something each caller has to remember. This
  cache has nothing to do with `lastNotifiedGeneration`
  (`terminal-core.ts:65,179`), which only dedupes `onChange` notifications. `takeDirty()` (`terminal-core.ts:297`) and
  `onRowEvents()` (`terminal-core.ts:308`) are how `DomBlockRenderer` learns
  which rows to repaint without diffing the whole snapshot.

---

## 3. Hard rules

1. **`packages/terminal` is product-independent.** No Operator import, concept,
   path or default inside it. Operator wiring lives in `backend/` and
   `frontend/`; the package only sees `HostCapabilities`, `PtyTransport`,
   `SpawnRecipe`, theme input. Gate: "could a second, non-Operator host use this?"
   The one exemption is measurement tooling under `bench/`: `bench/agent-session/run.mjs`
   runs a Go test in `backend/` for the reopen row of the baseline table. Nothing
   under `crates/` or `ts/` may reference the host repository.
2. **Match Warp, cite Warp.** Rendering/behaviour decisions quote the Warp file
   and line they mirror (see the comments already in `styles.css`, `screen.rs`).
3. **No comments in new code** (user's global instruction). Existing comments may
   be corrected when they become false; do not add new ones.
4. **Root cause before fix.** Every entry in §4 was mis-diagnosed first. Capture
   real bytes and reproduce in vt-core (or pyte) before changing the parser.
5. **Rebuild both wasm artifacts and the daemon** after any vt-core change, then
   tell the user to restart the daemon and the app. Old pty-host processes keep the
   old wasm for the life of the session.

---

## 4. Bugs already solved — do not reintroduce

Each entry: symptom → real cause → what guards it now. The commits are in the
history of `master`.

### 4.1 "No blank lines between messages above the screen" — `3a850c24d`
- Symptom: rows still on screen kept their spacing, everything scrolled off read
  as one gap-less run. Previously blamed on resize/SIGWINCH. It was not resize.
- Cause: `RowIndex::complete_row` only recorded a row when it had bytes, and
  `BlockGrid::remove_row` rebased blocks as if the row never existed.
- Now: every evicted row is committed (`complete_row` always pushes);
  `remove_row` is gone. `frame_rows()` (last non-blank row + 1) bounds what a
  reflow resize / scrolling `ESC[2J` evicts, so a cursor parked below the frame
  does not leave blank rows behind.
- Guards: `tests/blank_rows.rs`, `scrollback::an_all_blank_row_commits_as_an_empty_row`,
  `tests/screen_normal.rs::blank_rows_scrolled_off_the_screen_keep_an_open_block_anchored`.

### 4.2 Horizontal scrollbar / rows wider than the pane — `a8bb24ad1`
- Symptom: at the bottom the pane looked fine; scrolled up it panned sideways and
  clipped the left edge (`overflow: auto` container + `white-space: pre` rows).
- Cause: scrollback rows kept the width they were written at; only the live frame
  was resized.
- Now: `RowIndex::rewrap(content, cols)` runs on every width change in both modes
  (`Parser::commit_evicted` when `rewrap_pending`). Rows an earlier cut split
  (`wrapped == true`) are joined back into their logical line first, then any
  line wider than `cols` is cut again. Content and style offsets never move; only
  row boundaries do, and `BlockGrid::remap_rows(map)` moves blocks with them.
  The screen's `wrapped` flag makes a line the printer soft-wrapped rejoin on
  widening. `DomBlockRenderer` sets `overflow-x: hidden; overflow-y: auto` on the
  container (helper `applyScrollOverflow`) as a guard.
- This is Warp's flat-storage strategy (`warp/crates/warp_terminal/src/model/grid/flat_storage/index.rs:100-146`),
  which also rewraps agent-TUI scrollback while leaving the live frame to the app.
- Guards: `tests/rewrap.rs`, `row_index.rs` unit tests, `host-styling.test.ts`,
  Go `vtwasm/replay_test.go::TestReplayAfterAShrinkFitsTheGridAndKeepsEveryCell`.

### 4.3 Words cut in half by the rewrap ("vari|able") — `c9498e499`
- Cause: the first rewrap cut at the exact column.
- Now: `push_line` breaks at the last space before the edge, inside a word only
  when the word alone is wider than the pane, never after a leading space. The
  break space hangs past the edge (browser `pre-wrap` semantics) so visible text
  never exceeds the grid. Widening still rejoins.
- Guards: `row_index.rs::rewrap_breaks_at_the_last_space_before_the_edge`,
  `..._cuts_inside_a_word_only_when_the_word_alone_is_too_wide`,
  `..._never_breaks_after_a_leading_space`, `tests/rewrap.rs::a_rewrapped_line_breaks_between_words`.

### 4.4 Continuation rows flush left under a bullet — `36c791390`
- Now: `hanging_indent(text, cols)` reads leading spaces + a marker (`-`, `*`,
  `+`, `>`, `•`, `●`, `○`, `◦`, `▪`, `▸`, `▹`, `►`, `·`, `⎿`, `└`, `├`, `│`, or
  `1.` / `3)`) + the gap after it, capped at half the pane. Continuation pieces
  carry `RowRange.indent` and are cut to `cols - indent`. The snapshot exports
  `rowIndents`; `row-builder.ts` pads the row by `indent * cellWidth` px;
  `vt_render`/`vt_render_styled`/`vt_replay` write the indent as spaces (replay
  clips the text to `cols - indent`).
- Guards: `row_index.rs::a_bullet_line_hangs_its_continuation_under_the_text`,
  `hanging_indent_recognises_markers_and_caps_at_half_the_pane`,
  `tests/rewrap.rs::a_bullet_line_hangs_its_continuation_under_the_text`,
  `ts/renderer-dom/src/row-indent.test.ts`.

### 4.5 One SIGWINCH per session at birth — `64994379d`, `f938e8fb2`
- Symptom: every new or restored session opened with a duplicated banner /
  transcript row.
- Cause: the pty was born 80x24 and resized on first attach; Claude Code repaints
  its whole frame from home on SIGWINCH (§4.8).
- Now: `SpawnSessionRequest`, `DelegateTaskRequest`, `OpenShellTerminalRequest`
  and `RestoreSessionRequest` take optional `cols`/`rows` (1..1000).
  `ports.SpawnConfig`/`RuntimeConfig`/`PaneGrid` carry them to the spawner, which
  passes `--grid CxR` to `opr pty-host` (`host_main.go::hostArgs/parseHostArgs`;
  pty via `pty.StartWithSize`, ConPTY via `Resize`). Respawn reuses the live grid.
  The renderer remembers the last grid a pane reported (`lib/pane-grid.ts`,
  fed by `BlockTerminal.onGeometry`) and spreads `paneGridBody()` into spawn,
  delegate, shell-terminal and restore bodies. Empty body → old default.
- Still at the default grid (known, deliberate): `ResumeAgent`, `RestoreAll`
  on daemon start, the CLI, and the mobile client (it may send the same
  fields later).
- Guards: `ptyhost/host_main_test.go`, `host_pty_unix_test.go::TestNewPTYIsBornAtTheRequestedGrid`,
  `runtime_test.go::TestCreate_ForwardsThePaneGridToTheSpawner`,
  `controllers/sessions_test.go::TestCreateSessionForwardsThePaneGrid / TestRestoreSessionForwardsThePaneGrid / TestRestoreSessionAcceptsAnEmptyBody`,
  `lib/pane-grid.test.ts`.

### 4.6 A dozen transcript copies after a window drag — `c3bc565de`
- Cause: the grid publisher's trailing edge fired on a schedule, not on quiet,
  so a drag sent a SIGWINCH every 100ms; each one is a full repaint that leaves
  the previous frame in scrollback.
- Now: `useTerminalSession.ts` restarts the `RESIZE_DEBOUNCE_MS` (100) window
  on every frame so a drag collapses into one resize at the size the user let go
  at. The leading edge is kept only for the attachment's first published grid,
  because the pty-host holds the replay until a grid arrives (`openingGridWait`).
- Do not "fix" resize responsiveness by re-adding a leading edge or a max-wait.

### 4.7 Replayed transcript doubled and gap-less on reattach — `884ab7e85`
- Cause: `vt_replay` emitted rows wider than the client grid; each wrapped into
  two rows on the client and shifted everything below.
- Now: `clip_row` clips every replayed row (and the cursor column) to the grid.
  After §4.2 a wider row should not exist; the clip stays as the guard.
- Guard: `vtwasm/replay_test.go`.

### 4.8 One duplicated row per width change under Claude Code — UPSTREAM, unfixable here
- After a SIGWINCH Claude Code repaints "the last N lines of its layout" from
  `ESC[H`, but its live rendering had already scrolled the frame one row up
  (trailing `\r\r\n` on the bottom row), so the top row of the repaint duplicates
  the last scrollback row. The same captured bytes through **pyte** give the
  identical result. Upstream: anthropics/claude-code #40555, #49086, #46981,
  #57145; #55762 (force full repaint) closed as not planned. Warp has the same
  artefact (warp #9838 / PR #9877 is about not pushing the OLD frame into scrollback,
  which we already match).
- Do not re-investigate vt-core eviction for this symptom. The only Operator-side
  levers are fewer SIGWINCHes (§4.5, §4.6, both done) or a text de-dup heuristic
  in agent TUI mode (not built; would be a heuristic, decide with the user).

### 4.9 Grid sized to the whole host, not the space inside the block padding — `2c700136f`
- `.terminal-block` reserves 16px each side (Warp `PADDING_LEFT`) and 1.1 / 1
  lines top/bottom. `TerminalSurface` computes columns from
  `(host.clientWidth - renderer.blockContentInset().x) / cellWidth`. Measuring
  against the full host width tells the shell it has more columns than a row can
  show → every full-width line overflows. Guard: `TerminalSurface.test.tsx`
  "sizes the grid to the space inside the block padding".

### 4.10 Agent TUI resize policy — `resize_policy.rs`
- Resizing an agent TUI must not push the pre-resize frame into scrollback
  (`resizing_an_agent_tui_appends_no_frame_to_scrollback`); a shell resize moves
  the frame to scrollback exactly once, never copies it. Height shrink drops rows
  below the cursor first, then from the top (tmux `screen_resize_y`).

### 4.11 Selection hidden under Claude Code's user-message band — `559ba747b`
- Symptom: a selection dragged over the grey user-message band stayed grey,
  with blue hairlines between its rows.
- Cause: the band's run paints its own `background-color`, which sits above the
  row's selection fill (`paintSelectionFill` paints the row's `background-image`).
  The hairlines were the half-leading: an inline span's background covers only
  the glyph box, and rows are `line-height` tall.
- Now: runs with a background get the selection as a `background-image` clipped
  to the row's fill (`selection-fill.ts::runFill`), which paints above the run's
  colour and below its text -- Warp's order (`grid_renderer.rs::render_selection`
  blends the rect over cell backgrounds, glyphs drawn last). `.terminal-run` is
  `inline-block` at `--terminal-line-height` so backgrounds tile seamlessly.
- Guards: `terminal-selection.test.ts` "tints a painted run's background",
  `selection-fill.test.ts::runFill`, `styles-parity.test.ts` "fills a painted run
  to the full line height".

### 4.12 I-beam pointer over the transcript — `b687426fd`
- Selectable text gets a browser I-beam by default. Warp keeps the platform arrow
  over its grid and uses the pointing hand only for links (`app/src/util/link_detection.rs`).
  `.terminal-block, .terminal-alt-surface { cursor: default }`. Guard:
  `styles-parity.test.ts` "keeps the arrow over the transcript".

### 4.13 Selection destroyed by repaints — model-owned selection
- Symptom: a selection survived only while the terminal was idle. Measured in
  the bench harness: 1356 selected characters idle, dropping to 0 with Claude
  Code's spinner writing every 100ms.
- Cause: the transcript's selection was the browser's, anchored in text nodes
  that every repaint rebuilt from scratch, so new output collapsed it and a
  drag lurched back to the block start.
- Now: the selection lives in `renderer-dom` as grid points (block, row,
  column, half-cell side) in `selection-model.ts`, painted from geometry
  (`selection-geometry.ts`) and copied from the snapshot (`selection-text.ts`),
  the way Warp's `BlockListSelection` works. Gestures are a pure state machine
  in `selection-gesture.ts`: a drag threshold before a selection starts,
  click-count word/line selection (double-click a word with Warp's boundary
  set, triple-click a line), a drag past the edge auto-scrolling with Warp's
  polynomial curve, and the platform copy chord (Cmd+C on macOS, Ctrl+Shift+C
  elsewhere).
- Guards: `cell-width.test.ts`, `words.test.ts`, `selection-model.test.ts`,
  `selection-geometry.test.ts`, `selection-text.test.ts`,
  `terminal-selection.test.ts`, `selection-gesture.test.ts`,
  `TerminalSurface.mouse.test.tsx`, and the `bench:selection` Playwright gate
  (`bench/selection-gate.mjs`).
- A pointer press on chrome is ignored on purpose (`SELECTION_CHROME` in
  `TerminalSurface.tsx` covers the block header, the pinned header, the
  jump-to-bottom button, the find bar and the palette). The gate therefore
  locates a transcript row on screen and starts its drag there; it used to
  hard-code `(120, 120)`, which the two-line block header turned into header
  chrome, and the gate then failed on a selection that worked. If the gate
  fails, check where the drag starts before suspecting the selection.

### 4.14 Typing after opening a session went nowhere until a click
- Symptom: click a session in the sidebar, the terminal opens, the first
  keystrokes are dropped; a click in the pane was needed before typing worked.
- Cause: nothing focused the terminal's input when a pane was shown. The old
  xterm pane focused itself on `focusRequested`; `f72cdffa0` deleted xterm and
  left `focusRequested` accepted by `TerminalPane` but read by nothing. The
  retained-terminal cache blurs a pane on park (`blurTerminal`) and marks it
  `inert`, and on show it only flipped `inert` back -- focus stayed on the
  sidebar button the user had clicked.
- Now: `TerminalSurface` takes a `focusToken`; each new value focuses the
  editor (or the alt-screen composition target). `AttachedTerminal` bumps it
  when `isVisible` becomes true and whenever `focusRequested` changes while
  visible, and passes it through `BlockTerminal`. A parked pane never gets a
  token. Warp: `pane_group/mod.rs::focus_pane` focuses the pane contents on
  activation and `terminal/view.rs::on_focus` moves focus into the input box.
- Guards: `TerminalSurface.test.tsx` "puts focus in the editor when the host
  hands it a focus token", "sends a focus token to the alternate screen's
  input", `BlockTerminal.test.tsx` "hands the host's focus token to the
  surface", `TerminalPane.test.tsx` "TerminalPane focus" (on screen, human
  input requested, retained pane shown again but never while parked).

---

### 4.15 Relaunched agent drawn over the previous frame
- Symptom: after "Relaunch in a cleared session" (or a Claude-account switch,
  which is the same respawn) the new Claude Code banner was painted on top of
  the old one, rows overlapping.
- Cause: `handleRespawn` resets the host's ring and mirror but attached
  renderers keep their own vt-core, and the daemon stream forwards only
  `MsgTerminalData`, so the new child's first bytes landed on the stale screen.
- Now: `respawn.go` broadcasts a process-boundary mark
  (`ESC[?1049l ESC[0m OSC 7000;v=1;boundary=<exit> BEL`) to every attached
  client before the new pump starts. `vt-core` (`Parser::process_boundary`)
  closes the open block, or the markless frame as a finished synthetic block,
  then evicts the whole frame into scrollback and homes the cursor regardless
  of clear policy (`ScreenGrid::evict_frame`); the new process's output forms a
  new running synthetic block (`grid.rs` trailing block). The user asked for
  "close the old, relaunch in a new block" over a plain clear.
- Guards: `vt-core/tests/process_boundary.rs`;
  `respawn_test.go::TestRestartResetsRingAndKeepsClientAttached` (the mark
  must precede the new child's output on a pre-restart connection).

### 4.16 Half-painted Ink frames
- Symptom: under Claude Code's 100 ms spinner the pane tore — a paint could
  show the top of one frame and the bottom of the previous one, and a pane
  reopened mid-frame replayed half a frame.
- Cause: Claude Code brackets every Ink frame with DEC 2026
  (`ESC[?2026h` … `ESC[?2026l`); `note_private_mode` ignored the mode, so the
  renderer painted whatever had been parsed when its animation frame fired,
  and the pty-host mirror rendered the attach replay from the same half-parsed
  state.
- Now: `vt-core` buffers the bytes of an open sync block in front of the
  parser (`sync.rs`, the port of `vte-0.15.0/src/ansi.rs` `advance_sync`) and
  parses the whole frame on the terminator, a 2 MiB cap, a 150 ms deadline
  (`TerminalCore::tick(now_ms)`), a resize or a process-boundary mark. The
  renderer ticks the core at the top of every animation frame
  (`DomBlockRenderer.repaintOnFrame`) and keeps scheduling frames while a
  block is open; the Go mirror is fed with the wall clock and ticked from the
  pump timer and before every attach replay; `vt_replay` paints the last
  complete frame and appends the still-buffered bytes so the client completes
  the frame from the live stream. The pump holds the flush after a batch that
  ended inside a block until the terminator or the deadline, so a frame is
  split across two mux messages at most once.
- The part the fixtures hid: Claude Code only uses DEC 2026 when it *knows*
  the terminal supports it. With an unknown `TERM_PROGRAM` (ours is
  `Operator`) it sends `CSI > 0 q` (XTVERSION), `CSI ? u` and `CSI c` (DA1),
  and only if XTVERSION was answered does it probe `CSI ? 2026 $ p` and accept
  a DECRPM status of 1/2/3; DA1 is the terminator that ends each probe round.
  Under Warp (which answers) the recordings had 2026; under Operator nothing
  answered and Claude never emitted it, so the first real-app run showed zero
  sync frames. The mirror now answers, because it is the only party present
  from the child's first byte (a renderer would answer once per attached
  client): `Parser::set_answers_queries(true)` + `set_terminal_identity`
  (`vt_new` enables it, Go passes `vtwasm.TerminalIdentity` = `Operator`),
  replies queued by `take_query_replies` and written to the pty by `deliver`
  after it releases `h.mu`. Answers: XTVERSION → `DCS > | Operator ST`, DA1 →
  `CSI ? 62 ; 22 c`, DECRQM → `CSI ? Pm ; {1|2|0} $ y` from the tracked mode
  state (2026 reports 2). `CSI ? u` is deliberately unanswered (kitty keyboard
  is not implemented). The renderer core never answers.
- Guards: `vt-core/tests/synchronized_output.rs` (`bytes_inside_a_sync_block_are_invisible_until_esu`,
  `a_frame_split_across_three_feeds_snapshots_once`, `a_mark_inside_a_sync_block_lands_after_the_rows_before_it`,
  `overflow_flushes`, `tick_past_deadline_flushes`, `bsu_inside_a_block_extends_the_deadline`,
  `resize_flushes`, `unknown_private_modes_still_ignored`, `a_bsu_split_byte_by_byte_still_buffers`,
  `a_boundary_mark_inside_a_sync_block_flushes`); `ts/core/src/terminal-core.test.ts`
  "notifies a pending sync block without exposing it…", "tick past the deadline flushes and notifies";
  `dom-block-renderer.test.ts` "does not paint a half frame", "paints a buffered frame once the
  deadline passes…"; Go `vtwasm_test.go::TestFeedAtBuffersASyncBlockUntilItsTerminator`,
  `TestTickPastTheDeadlineFlushesTheSyncBlock`, `replay_test.go::TestReplayNeverStartsInsideASyncBlock`,
  `host_test.go::TestDeliverHoldsAcrossASyncBlock`, `TestSyncHoldEndsAtTheDeadlineAndTicksTheMirror`,
  `TestAStalledSyncBlockReachesTheMirrorAtTheDeadline`,
  `TestDeliverAnswersADecrqmProbeOnThePty`, `TestDeliverAnswersXtversionWithTheHostIdentity`;
  `vt-core/tests/query_replies.rs`; `bench/agent-session/run.mjs --gate` (zero torn paints, Task 8).
  Real-app evidence (2026-09-20, dev daemon + `/mux`): 41 sync frames in a
  30 s window, the `?2026$p` probe answered, 2 of 56 mux messages ending
  inside a block, 12 mid-output reattaches with a clean replay each.

### 4.17 Blocks pinned past the end of the row space — found by the integrity proptest
- Symptom: none visible yet; found by `tests/integrity.rs::every_operation_leaves_the_model_consistent`
  (Plan A). Two bookkeeping gaps in `BlockGrid`:
  a block opened by `OSC 133;A` after a cursor move below the frame and closed
  by a process boundary kept a `first_row` above its own end (a zero-row block
  pinned to a screen row a later shrink drops); and `trim_to_first_row` did
  `block.first_row -= shift` for every block after the front one, which
  underflows when a block starts above the cut (a prompt mark after a
  cursor-up) — a wrapping subtraction in release wasm, so the snapshot's
  `checked_u32` would have failed and the renderer thrown on the next paint.
- Now: `close_block` / the abandon path clamp `first_row` to `next_row`;
  `Parser::resize` ends with `BlockGrid::clamp_to_rows(completed + screen rows)`;
  the trim shift is saturating. `verify_integrity` reads the open block's
  extent as `first_row` alone (its `row_count` is only meaningful once closed).
- Guards: `tests/integrity.rs` — the proptest (256 cases per run, 12,000 run
  clean when it landed), `a_boundary_closed_empty_block_survives_a_shrinking_resize`,
  `a_block_opened_on_the_screen_survives_a_rewrap_and_a_trim`,
  `a_trim_past_a_block_that_starts_above_the_cut_does_not_underflow`.

### 4.18 Viewport jump when scrollback trims — `2dd61c47b`
- Symptom: scrolled up into history, then the fixture kept streaming past the
  scrollback cap. On every trim, the text sitting under the viewport's top
  edge shifted down by roughly the trimmed height, as if the pane had jumped
  — the same rows were still rendered, but not where the eye left them.
- Cause: `repaint()` restored a pixel `scrollTop` saved before the trim. A
  trim shrinks scrollback from the front (`Parser::trim_to`, §1.2) and
  renumbers every block and row below the cut, so the same pixel offset now
  points at different content — the save/restore pair assumed row positions
  were stable across a repaint, which stopped being true once trimming a
  200k-row session became routine instead of a one-time edge case.
- Now: the viewport anchors to a **stable row** (§2) instead of a pixel
  offset. `DomBlockRenderer.scrollAnchor()` (`dom-block-renderer.ts:230`)
  captures the stable row under the top edge and its sub-row pixel offset
  before a repaint; `rowTop()`/`anchorAt()` (`viewport.ts:53,75`) convert
  between a stable row and a pixel position using the current block layout,
  so the anchor is re-resolved against post-trim geometry instead of being
  replayed verbatim. The same anchor is re-resolved on a rewrap (§4.2), not
  only a trim, since a width change also renumbers rows.
- Guards: `viewport.test.ts` describe block `"rowTop and anchorAt"`
  (round-trip conversion, including "round-trips through rowTop for every
  row"); `dom-block-renderer.test.ts` describe block `"scroll anchor"`
  (survives a trim, survives a rewrap); `bench:agent:scroll`'s trim phase
  (`bench/agent-session/scroll-gate.mjs`) feeds past the cap mid-scroll and
  asserts the row under the top edge is identical before and after.

### 4.19 Reopening a long session recovered only the mirror's last screen
- Symptom: a pane reopened (app restart, reattach) after producing more than
  the mirror's `Replay(MaxOutputLines)` cap (1,000 lines) lost everything
  older than that — the whole point of Plan C's byte-budget caps (§2 Limits)
  was defeated the moment a client reattached, because `Replay(MaxOutputLines)`
  was the entire attach path.
- Cause: two traps, both live defects in the first draft of this plan, not
  hypothetical:
  (a) the mirror and the reopened core number rows in different stable
  spaces (§2 Stable rows). Sending history chunks without first telling the
  receiving core what stable row its own fresh, empty state should be
  planted at means `Parser::apply_history_chunk`'s row-space check
  (`first_stable_row + rows.len() == trimmed_total`) never lines up, so
  every chunk is dropped. The fix states the origin **first**, before any
  row exists on the receiving core, because `Parser::adopt_origin` refuses
  to act once a row has already been drawn or trimmed (`parser.rs:529`) —
  reordering the replay after a row exists silently reintroduces the bug.
  (b) a chunk's closing `exit=` mark must sit **inside** its last row,
  before that row's CR-LF terminator, not as a separate line after it — a
  byte written after the chunk's own final CR-LF falls through to the live
  parser and closes whatever block the *live* agent currently has open,
  corrupting the live pane's block state for an unrelated reason (reopening
  a different, unrelated session).
- Now: `attach.go` streams five parts in order — origin mark, modes, the live
  frame, `OSC 7000;v=1;ready=1` (the client paints here), and then, for a
  client that opted in, history chunks newest→oldest, each framed by
  `OSC 7000;v=1;history=<first_stable_row>,<count>` with `id=`/`cmd=`/`exit=`
  marks re-emitted so the reopened pane has the same blocks, not re-derived
  ones. `Parser::apply_history_chunk` (`parser.rs:542`) prepends the rows,
  retreats the block grid's origin, and rejects a chunk whose row space
  doesn't land exactly at the receiver's current `trimmed_total`.
- Guards: `TestReplayOpensWithTheOriginMark`, `TestReplayOrderIsModesFrameReadyHistory`,
  `TestAHistoryChunkEndsAtARowTerminator`, `TestClientPaintsAtReadyBeforeHistory`,
  `TestAClientWithoutHistoryOptInGetsNoChunks`, `TestAFreshSessionAttachIsUnchanged`,
  `vt-core/tests/replay.rs`, the useTerminalSession "paints at READY" test.

### 4.20 Lazy rewrap silently truncated a reopened session's history
- Symptom: after a width change on a session with more than `HOT_ROWS`
  (2,000) completed rows, closing and reopening the pane delivered every cold
  row with its tail cut off at the CURRENT grid width. Silent: no error, no
  log, just missing text — in the one feature (§4.19) that exists to recover
  the whole session.
- Cause: a seam between two independently built pieces. Lazy rewrap
  (`RowIndex::rewrap_hot`) leaves everything below the hot window cut at the
  OLD, wider width and waits for someone to call `touch_rows`. The renderer
  does that from its own export (`WasmTerminalCore::sync`,
  `crates/vt-wasm/src/lib.rs:134`); the mirror in `vt-host` has no export and
  called it from nowhere. `vt_history_chunk` then handed those still-wide rows
  to `clip_row`, whose job is to truncate anything wider than the grid. Before
  lazy rewrap every row was rewrapped eagerly, so `clip_row` was a guard that
  could never fire — and its comment said so. Lazy rewrap made that comment
  false without touching the file.
- Why the obvious fix is wrong: touching the chunk's own row range inside
  `vt_history_chunk` does NOT work, and fails silently in the same way.
  Rewrapping a range changes how many rows it holds, while `before`/`bound`
  address rows by a stable number the client has already anchored to the
  frame's `origin=`. Rewrapping mid-stream moves the rows out from under that
  anchor: the counts still abut, so nothing is rejected, and the rows the
  rewrap created past the chunk's bound are simply never sent. Verified by
  experiment during the fix — the test below still failed, on a different row.
- Now: `vt_touch_history` rewraps ALL stale history in one pass, and
  `handleConn` calls it for a history-opted-in client BEFORE
  `replayFrameLocked` renders the origin the client adopts. One rewrap, then a
  fixed row space for the whole stream. It costs a full-history rewrap on a
  reopen after a resize — a one-shot cost on a path that is already streaming
  the whole session — and it runs off `h.mu` so it does not stall other panes.
- Guards: `TestHistoryChunksRewrapColdRowsAfterANarrowingResize` (vtwasm),
  which also asserts every chunk abuts the frame's origin.

### 4.21 The replay origin and the first history chunk were snapshotted apart
- Symptom: a reopened pane occasionally got NO history at all, falling back to
  pre-Plan-C behaviour, with nothing logged.
- Cause: `replayFrameLocked` computed the origin from a `TerminalCore`
  snapshot under `h.mu`; `streamHistory` then started from the
  `vtwasm.HistoryBefore` sentinel and let the mirror re-derive the bound from
  a FRESH snapshot, off the lock, moments later. Any row the child completed
  in between put the two apart. `Parser::apply_history_chunk` requires the
  chunk to abut EXACTLY, and chunks step down in units of 512, so a drift of
  even one row rejects the first chunk and every chunk after it — returning
  `false`, with no error and no log.
- Now: the origin is read back out of the frame that was just rendered
  (`replayOrigin`) and passed to `streamHistory` as its starting bound. One
  render, one number, used both to tell the client where it stands and to cut
  the first chunk.
- Guards: `TestHistoryStartsAtTheOriginTheFrameDeclared` (ptyhost).

## 5. Known gaps (not bugs, decisions pending)

- A DEC 2026 block that grows to `SYNC_BUFFER_CAP` (2 MiB) is flushed and
  parsed in one `feed` inside whatever frame receives it, bypassing the 12 ms
  `drain` budget: a burst of ~60 ms on this machine. Claude Code frames are
  kilobytes, so it needs a misbehaving program; lowering the cap or splitting
  the flush across frames is the fix if it ever shows.

- Copying a rewrapped block (`readBlockOutput`, `vt_render`) joins rows with
  `\n`, so a soft-wrapped line copies as several lines. Warp copies the logical
  line. Fix would export `wrapped` per row and join on copy.
- The screen's `wrapped` flag is cleared on any width change (`resize_cells`)
  because truncated cells can no longer be rejoined faithfully.
- The hot region (the screen plus the newest `HOT_ROWS = 2_000` completed
  rows, §2) is still walked eagerly on every width change. A cold run below
  that is walked once, lazily, on first access (a scroll into it), not on
  the resize itself; the row count above the viewport is an estimate until
  a stale range is touched and corrects. This replaces the old "rewrap walks
  all scrollback on every width change" entry — that was true before Plan C
  1.3.F, it no longer is.
- **A reopened pane's prepended rows lose their `wrapped` flag.**
  `vt_history_chunk` emits every history row CR-LF terminated and
  `Parser::apply_history_chunk` prepends them with `wrapped: false`
  (`parser.rs:568`), so a later width change cannot rejoin a logical line the
  mirror had soft-wrapped — those rows rewrap as independent lines. Rows the
  pane produces *after* the reopen are unaffected. Carrying the flag would
  mean emitting wrapped rows without `\r\n` and sizing the receiver's scratch
  screen to the mirror's width (a `cols=<n>` field on the chunk mark), which
  would make the chunk's row count depend on the receiver's own wrapping
  instead of on the mark's `count` — the invariant `HistoryReceiver::consume`
  ends a chunk on. Revisit with a second anchor for that invariant; do not
  "fix" it by loosening the row count.
- **The `bench:agent:scroll` flake was the harness counting frames while the
  renderer paces paints by time — fixed 2026-09-22.** `repaintOnFrame` defers
  a paint that would land within `PAINT_INTERVAL_MS` of the previous one, so a
  `setScrollTop` that waited two animation frames (~15 ms after a feed's
  paint) could read `visibleRows()` before the scroll had painted: `[0]`
  `undefined` after the trim, `-1` before the width change, and a scroll walk
  that missed rows (`covered < total`). Probe evidence: in the failing run 0
  paints landed inside the two frames and 1 landed within the next 200 ms.
  `bench/agent-session/main.ts` now has `paintAfter(action)` — level-triggered
  on the `onPaint` counter, bounded at 600 frames — and `setScrollTop`,
  `widthChange` and the gate's trim phase use it. 6/6 clean runs after the
  fix against 1/4 before. Do not reintroduce a frame-count wait in the
  harness; wait for the paint the action causes.
- **`run.mjs`'s `widthChange` row reads the top-edge row 5 rows apart before
  and after (60081 → 60086) — that is the sticky-bottom contract, not a
  bug.** That probe resizes with no prior scroll, so the pane is pinned to
  the bottom; a 40-column rewrap of the hot region adds rows, and a pane
  pinned to the bottom is *meant* to keep the newest row visible, moving its
  top edge. The gated measurement (`scroll-gate.mjs`'s width phase) scrolls
  to a stable position first and reads the same row before and after.
- **Ack accounting is per pty-host CONNECTION, not per mux client.** `MsgAck`
  folds every ack into one `clientState`, and `unackedLocked` reports the
  worst connection. The daemon may fan a single attachment out to several mux
  clients (desktop and mobile on the same session) through
  `connState.handleTerminal`, which forwards each client's ack onto that one
  connection: a fast client's ack races ahead of a slow one, `acked` follows
  the fast one, and the slow client throttles nothing — flow control (Plan C
  1.3.H) is effectively off in exactly the multi-client case it was meant to
  help. Separately, `attachment.run`'s reattach loop opens a FRESH pty-host
  connection with `delivered` reset to 0 while the renderer's
  `r.consumedBytes` keeps counting from before the reconnect, so post-reconnect
  acks clamp `acked` to the new connection's `delivered` and the watermark
  gate stays open for that pane from then on. Both fail OPEN — no stall, no
  corruption, just no back-pressure — which is why this ships documented
  rather than fixed; a real fix needs per-mux-client accounting at the
  pty-host connection layer, which does not exist today.
- **A block that straddles a 512-row chunk boundary loses its tail.**
  `write_block_open`/`write_block_close` (`crates/vt-host/src/lib.rs`) emit a
  block's `id=`/`cmd=` mark on its first row and its `exit=` mark on its last.
  When those rows fall in different chunks, the receiver sees an opening mark
  with no close (or a close with no open) and the block ends at the chunk
  boundary instead of at its real last row. Low severity — the rows
  themselves all arrive, only the block grouping around them is approximate —
  and it sits next to the `wrapped`-flag loss above for the same reason: a
  real fix means carrying block state across chunk boundaries in the mark,
  which changes the chunk's self-contained invariant.
- **`vt_touch_history` runs off `h.mu`, just before the frame is rendered** — a
  full-history rewrap under the host's global lock would stall every pane. A
  resize landing between the rewrap and the render re-marks rows stale and
  §4.20's truncation returns, so `handleConn` settles the grid FIRST
  (`applyLargestLocked` counts the attaching connection before it is
  registered) and then re-checks the grid under the same lock that renders the
  replay, redoing both if another client moved it meanwhile
  (`TestAttachWithHistoryRewrapsAfterTheAttachResize`). The attach's own resize
  used to land in that window on every reopen at a new width, which was not a
  race but a certainty; nothing now resizes the parser between the rewrap and
  the frame it is numbered against.
- `TestProcessEnvironmentLetsOverridesWin` in `ptyhost` fails on master before
  any of this work (TERM override appended twice). Pre-existing, unrelated.
- Found triaging the Alacritty reference corpus (`crates/vt-core/tests/ref/TRIAGE.md`),
  not fixed there:
  - `ESC # 8` (DECALN, fill screen with `E`) is never dispatched —
    `Parser::esc_dispatch` (`crates/vt-core/src/parser.rs:475`) discards
    `intermediates`, and `ScreenGrid::esc` (`crates/vt-core/src/screen/dispatch.rs:73`)
    has no `#`/`8` arm. Corpus: `decaln_reset`, `vttest_cursor_movement_1`.
  - `ESC ( 0` / `ESC ( B` (G0 charset designation, DEC Special Graphics line
    drawing) is never dispatched, for the same reason — intermediates are
    discarded before `esc()` sees them. Corpus: `saved_cursor`, `saved_cursor_alt`.
  - `CSI ?3h`/`?3l` (DECCOLM, 80/132-column switch) is not in
    `Parser::note_private_mode` (`crates/vt-core/src/parser.rs:199`), so the
    screen clear real terminals perform on a column-mode switch never happens
    and stale content bleeds through. Corpus: `deccolm_reset`, `vttest_insert`,
    `vttest_origin_mode_1`, `vttest_origin_mode_2`, `vttest_tab_clear_set`.
  - `CSI ?6h`/`?6l` (DECOM, origin mode) is not in `note_private_mode` either —
    no case in the corpus currently depends on it, but it is a silent no-op.
    Corpus: `origin_goto` (sets it, no visible effect there).
  - `EL 0` does not model the deferred-autowrap "pending wrap" cursor state:
    a character printed in the last column keeps the cursor logically past
    the column until the next printable character, so `EL 0` immediately
    after should not erase it. vt-core erases it. Corpus: `erase_in_line`.

---

## 6. Verify and ship — the exact recipe

Run from the paths shown; **use absolute paths in every command**. In this
harness parallel Bash calls share and change the working directory, and zsh
globbing / `cd` into a directory you are already in fail silently — several
"no-op" runs in the past came from exactly that.

```bash
# Rust (vt-core, vt-wasm, vt-host)
cd /Users/omaraly/development/AI/Operator/packages/terminal
cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test

# Host mirror wasm -> backend asset (committed binary)
cargo build --release -p vt-host --target wasm32-unknown-unknown
cp target/wasm32-unknown-unknown/release/vt_host.wasm \
   ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd /Users/omaraly/development/AI/Operator/backend
go test ./internal/adapters/runtime/ptyhost/...      # vtwasm must pass

# Renderer wasm + TS (ts/core/wasm and dist are gitignored, rebuilt locally)
cd /Users/omaraly/development/AI/Operator/packages/terminal
npm run build:wasm -- --force && npm run build:ts
for p in core renderer-dom react; do (cd ts/$p && npx vitest run); done
npm run bench:selection      # Playwright: a selection must survive 20 repaints
npm run bench:feel           # Playwright: zero pixel diff vs bench/agent-session/baselines (record with -- --record)
npm run bench:agent:gate     # Playwright: no torn paint under the spinner, queued 2 MiB never blocks > 16 ms
npm run bench:agent:scroll   # Playwright: full scroll coverage, trim anchor holds, width-change gate (top-edge row and lazy rewrap)

# Frontend + daemon
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
# -> frontend/daemon/opr ; the user must restart the daemon AND the app
```

Backend API changes: `cd backend/internal/httpd/apispec && go generate ./...`
then `npm run api:ts` in `frontend/` (regenerates `src/api/schema.ts`).

Changelog: `packages/terminal/CHANGELOG.md`, "Unreleased" section, one entry per
behaviour change. Commits go straight to `development`, message ends with the
`Co-Authored-By` trailer the harness gives you.

---

## 7. How to debug terminal rendering (what actually worked)

1. **Capture real bytes**, not guesses. Drive the real agent through a pty
   (`script`, or a small Python `pty.fork` capture), resize it with `TIOCSWINSZ`,
   and save the raw stream. Earlier scratch tools: `cap_tall.py`, `pyte_replay.py`
   (a pyte venv) under the session scratchpad — trivial to recreate.
2. **Feed the capture to vt-core in a test** (`TerminalCore::new(cols, 1000)`,
   `resize`, `feed`, `snapshot().row_text(i)`), and to **pyte** as a second
   opinion. If pyte shows the same artefact, the bug is the application's, not
   ours (§4.8).
3. **Check which copy is stale.** The renderer core and the host mirror are
   different wasm builds; the pty-host keeps its wasm for the session's life.
4. **Compare with Warp** by reading its code, not by guessing: grep
   `/Users/omaraly/development/AI/warp/crates/warp_terminal/src/model/grid/` and
   `app/src/terminal/`. The Explore agent is good at this.
5. **Screenshots lie about the cause.** "Missing blank lines" was eviction, not
   resize. "Horizontal scroll" was scrollback width, not the renderer. Find the
   layer that owns the bytes before touching CSS.

---

## 8. Advice for a cleared-session agent

- Start by reading this file, then `packages/terminal/CHANGELOG.md` (Unreleased),
  then `git log --oneline -15 -- packages/terminal backend/internal/adapters/runtime/ptyhost`.
- The user judges results by side-by-side screenshots against Warp. Ask for one
  when the symptom is visual; reproduce it in a vt-core test before fixing.
- The user says "fix it" and expects the whole chain: engine → both wasm
  builds → tests → daemon rebuild → commit → "restart the daemon and app". Do not
  stop at the engine.
- Write the failing test first (TDD is the house style; every §4 entry has one).
- Keep the package generic (§3.1). If a change needs an Operator concept, it goes
  in `frontend/` or `backend/`.
- When the user asks "does X have no solution?", answer honestly and point at
  the upstream issue if it is upstream (§4.8). Do not chase it again.
- If a Go test in `ptyhost` fails, check whether it is the pre-existing
  `TestProcessEnvironmentLetsOverridesWin` before assuming your change broke it.
- A visual change must re-record the feel baselines (`npm run bench:feel -- --record`)
  in the same commit and say why in the CHANGELOG.
