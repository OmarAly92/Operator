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
   ├─ persist.go         every 60 s (when changed) and on shutdown, writes the attach
   │                     replay (frame + newest 20 history chunks, ≤ 4 MiB) to
   │                     ~/.operator/pty-host-history/<id>.vt; a host created for a
   │                     relaunched session seeds its mirror from it (§4.29)
   ├─ vtwasm/            PASSIVE MIRROR: vt-core compiled to wasm (vt_host.wasm),
   │                     run by wazero. Feeds every byte, answers GetOutput /
   │                     text extraction, and produces the attach REPLAY.
   │                     Rows the mirror trims past its cap go, as styled text, to a
   │                     32 MiB cold ring (mirror_limits.go); MsgOlderReq answers
   │                     "Load older output" from it on the asking connection (§4.33)
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
   ├─ components/TerminalPane.tsx   picks the surface; agentTui={kind === "worker"}; the
   │                                 retained-terminal cache keeps one live terminal per
   │                                 split-view pane slot (`activeSlotsRef`, a Map keyed by
   │                                 pane slot), not one live terminal for the whole app —
   │                                 every other cached terminal for a tab shown elsewhere is
   │                                 parked, never torn down
   ├─ components/BlockTerminal.tsx  mounts the package, setAgentTuiMode, onGeometry;
   │                                 `recordsSpawnGrid` (default true) gates `onGeometry`'s
   │                                 `rememberPaneGrid` call so an unfocused split pane never
   │                                 overwrites the remembered spawn grid with its own size
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
    the frame into scrollback (`ClearPolicy::Scroll`). At a prompt (line editor
    `Owned`) a resize keeps the prompt rows instead and pulls scrollback back (§4.36).
  - `set_agent_tui_mode(true)` (Claude Code and every "worker" session): no reflow
    of the live frame (`resize_cells` truncates in place) and `ESC[2J` clears in
    place. Mirrors Warp's `FullGridClearBehavior::Clear` (`warp/crates/warp_terminal/src/model/grid/resize.rs:60`).
  - In BOTH modes scrollback is **rewrapped** on a width change (§4.2).
- **Snapshot** (`grid.rs` → vt-wasm `ExportBuffers` → TS `TerminalSnapshot`):
  `content`, `rows` (start,end pairs), `rowIndents` (u16 per row), `rowWrapped`
  (one byte per row, 1 when the next row continues this one — a printer
  soft-wrap or a rewrap cut), `runRanges`, `stylePairs` (stride
  `STYLE_RUN_WORDS = 6`: `end, fg, bg, attrs, underline, link`), `blocks`
  (stride `BLOCK_RECORD_WORDS`), cursor, alt screen, `spanRanges`/`cellSpans`
  (stride `CELL_SPAN_WORDS = 3`: `start, end, width` per cluster that is not a
  single width-1 scalar) — and `linkRanges`/`linkText` (the OSC 8 URI table,
  index `id - 1`: `linkRanges[(id-1)*2]`/`[(id-1)*2+1]` are the byte range
  into `linkText`). Adding a per-row field means: `GridSnapshot` +
  `append_row`/`append_screen_row` + `ExportBuffers` + `*_ptr/_len` +
  `terminal-core.ts` + `types.ts` + the Rust test fixture
  `vt-wasm/tests/exit_encoding.rs` — `row_wrapped` is the worked example
  beside `row_indents`, the second per-row field the buffers carry — and now,
  if the field is per-section, `ExportedRow`/`push_row` in `export.rs` and
  `history_rows`, and, for a per-cell field, `AltSnapshot` in
  `screen/snapshot.rs` and the dead-prefix accounting in `ExportBuffers`
  (`dead_*`/`history_*` counters, `drop_front`, `rewrite_history_from`,
  `truncate_screen`, `compact`).
- **Logical lines.** Two files own the join and neither duplicates the other:
  `ts/core/src/logical-lines.ts` joins flat snapshot rows behind
  `TerminalCore.logicalLines(range)`, the API any host can call over a plain
  snapshot; `ts/renderer-dom/src/logical-lines.ts` lifts that same join into
  the renderer's stable-row, per-block space and attaches link runs, because
  that is the space the linkifier, hint mode and redaction address. The
  renderer's `logicalLineAt` imports `joinLogicalLine` from
  `@operator/terminal-core` and derives its `text`/`rowOffsets` from that one
  function — it derives nothing of its own. A change to how pieces join
  belongs in the core's `joinLogicalLine` and lands in both by construction.
- **Hyperlinks.** `Parser::osc_dispatch` parses `OSC 8 ; params ; URI ST` and
  interns it in `HyperlinkRegistry` (`crates/vt-core/src/hyperlink.rs`) with
  Warp's caps (`MAX_DISTINCT_ENTRIES = 4096`, `MAX_URI_BYTES = 2083`) and no
  reclamation. The id rides in `CellStyle.link` (`u16`, 0 = none), so it
  splits, merges, rewraps, evicts and trims with the styles for free — no
  separate span buffer. The mirror re-emits the sequence per run in the
  attach replay and in every history chunk, because ids are per core, not
  shared across the two. **The table is not part of the byte budget:**
  `Parser::trim_to` weighs `content.resident_bytes() + styles.byte_len()`
  only (`parser/history.rs:91`), so the registry grows to its cap and stays —
  deliberate and bounded, not an oversight, and listed in §5.
- **BlockGrid clock.** A block missing the shell hook's `start_ms`/`end_ms` is
  stamped from the clock of the feed that started its command and the feed
  that closed it (`BlockGrid::set_clock`/`note_output`,
  `BlockRecord.started_at_ms`/`finished_at_ms`). The start is the command's
  output start (`OSC 133;C`, `BlockGrid::start_output`), not its prompt
  (`OSC 133;A`), so a block's duration never includes time spent typing at the
  prompt; a block whose command never started keeps its prompt's clock, and a
  hook `start_ms` always wins. Warp times a block the same way: `start_ts` is
  set when the command is submitted, or at preexec when that was not observed
  (`warp/app/src/terminal/model/block.rs` `Block::start`,
  `ensure_started_for_preexec`), and its long-running notification reads
  `completed_ts - start_ts` (`warp/app/src/terminal/view.rs` `block_duration`). The TS core feeds and the renderer ticks with
  `Date.now()`, not `performance.now()`, so these stamps are epoch
  milliseconds like the Go mirror's `time.Now().UnixMilli()` and the hook's
  own `start_ms`/`end_ms`.
- **`RendererFeatures`** (`ts/renderer-dom/src/features.ts`, set through
  `DomBlockRenderer.setFeatures` and the `features` prop of `TerminalSurface`)
  is the gate every Plan D behavior sits behind — SGR attributes, grapheme
  clusters, cursor contrast/hollow, and the width cache. `graphemes` and
  `widthCache` default on (2026-09-22, together — see §5 for why never one
  without the other); `attributes` defaults to `"warp"` (2026-09-23, §5);
  the cursor flags default off (see §5 for what each leaves unresolved). `TerminalSurface` puts the core in the resolved
  `graphemes` mode in a layout effect that runs before the geometry effect,
  and hosts `enqueue` bytes, which parse on the renderer's frame drain — so no
  byte reaches the parser before the mode is set.
- **Width mode.** `Parser::width_mode` (`WidthMode::Scalar` default,
  `WidthMode::Grapheme` via `TerminalCore::set_grapheme_clusters`) chooses
  whether a printed character occupies one cell per Unicode scalar or one
  cell-span per extended grapheme cluster. `ScreenGrid::join_previous` is
  where a soft-wrap join respects the active mode's cluster boundaries
  instead of splitting mid-cluster; `RowIndex` measures rewrap width with the
  same `clusters()` call the printer used, so a stale-run rewrap (§2's
  "Stale runs" bullet) and a live-frame rewrap agree on where a row breaks.
  The pty-host mirror is always `WidthMode::Scalar` — a deliberate Plan D
  deviation, not an oversight, since the mirror only needs byte-identical
  replay, not on-screen glyph placement. The renderer runs in grapheme mode
  by default, so the two disagree on emoji sequences; what that does to a
  reopen is measured in §5. The Unicode `GraphemeBreakTest`
  corpus (`crates/vt-core/tests/grapheme/`) runs against the splitter in both
  modes.
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
  The mirror also keeps a cold ring of trimmed rows (`Limits.ColdRingBytes`,
  32 MiB in `mirrorLimits`); the renderer core has none (§4.33).
- **Stable rows** give a row an identity that survives it migrating from the
  live screen into scrollback and back out again under trim. `trimmed_total`
  (`parser.rs:55,91`) counts rows evicted off the front since the session
  began; `stable_row(flat)` / `flat_row(stable)` (`lib.rs:340,344`) convert
  between a row's position in the current flat (scrollback + screen) space
  and this permanent counter. `BlockGrid::origin` (`block_grid.rs:29,45`) is
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
  integrity check rests on. `Parser::adopt_origin` (`parser/history.rs:9`) is what
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
  (`screen.rs:379`) marks both the row the cursor left and the row it
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
   Find cites two MIT/Apache references for behaviour only, no code adapted:
   Ghostty `src/terminal/search/active.zig:11-19` (re-search only what can
   change) and Alacritty `alacritty_terminal/src/term/search.rs:39-40` (smart
   case). Highlights (§4.31) cite Ghostty `src/terminal/highlight.zig:1-10`
   (one representation for selection, search and marks) for behaviour only, no
   code adapted; Kitty's marks are GPL-3.0 and were not read.
   Agent activity (§4.34) ports VS Code's `detectsHighConfidenceInputPattern`
   (MIT; `ts/core/src/input-patterns.ts`, `VSCODE-INPUT-PATTERNS-ATTRIBUTION.md`
   and `LICENSE-VSCODE-MIT` beside it) and follows VS Code's idle polling
   behaviour without copying code; the in-band agent events are our own wire
   format (`protocol/SPEC.md` §10), written from the survey's description of
   Warp's (§7.1; AGPL-3.0, no Warp file read).
3. **No comments in new code** (user's global instruction). Existing comments may
   be corrected when they become false; do not add new ones.
4. **Root cause before fix.** Every entry in §4 was mis-diagnosed first. Capture
   real bytes and reproduce in vt-core (or pyte) before changing the parser.
5. **Rebuild both wasm artifacts and the daemon** after any vt-core change, then
   tell the user to restart the daemon and the app. Old pty-host processes keep the
   old wasm for the life of the session.
6. **One place per terminal.** A split-view pane's retained terminal cache holds
   at most one live slot per cache key; the split layout tree
   (`frontend/src/renderer/lib/split-layout.ts`) separately guarantees a tab
   exists in at most one pane (`assertLayout`'s duplicate-tab check). Together
   these mean a session, shell or reviewer terminal is attached to exactly one
   DOM slot at a time. `TerminalPane.tsx`'s `activate` asserts this in dev
   builds (`console.error` when a cache key would activate in a second slot)
   rather than silently letting two panes fight over the same live vt-core.

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
  below the cursor first, then from the top (tmux `screen_resize_y`). At a shell
  prompt the prompt rows stay instead (§4.36); every other state, and the pty-host
  mirror, keeps this policy (`tests/resize_goldens.rs`).

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
- Plan E: the arrow is still the default everywhere else in the transcript;
  the pointing hand appears only while the `Linkifier` reports a link under
  the pointer (`.terminal-link-hover`), Warp's own rule
  (`app/src/terminal/view.rs` `set_cursor_shape`). How a link is found is
  §4.23. Guard:
  `styles-parity.test.ts` "shows the pointing hand only while a link is under
  the pointer".

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
- Plan E: the link underline, the hint labels and the redaction masks are
  overlays in `.terminal-decorations`, positioned from the same row geometry
  the selection fill uses — never edits to pooled row elements, for the same
  reason the selection isn't one.
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
  offset. `DomBlockRenderer.scrollAnchor()` (`dom-block-renderer.ts:252`, `scroll-tracker.ts:24`)
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
  to act once a row has already been drawn or trimmed (`parser/history.rs:9`) —
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
  ones. `Parser::apply_history_chunk` (`parser/history.rs:22`) prepends the rows,
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

### 4.22 Private `CSI … m` sequences reached the SGR path — Plan D review
- Symptom: none visible on `development` beyond a subtle one — every Claude
  Code banner and prompt band painted at 55 % opacity. On the Plan D branch,
  before the fix: every coloured run underlined once `attributes: "warp"`
  was on, the style map split into 87,023 entries (260 is right) and the
  renderer heap at 60k rows read 14 MiB, which the executor recorded as the
  cost of the new export.
- Cause: `Parser::csi_dispatch` (and the history receiver's `ScreenPerform`)
  handed every `m` to `apply_sgr`. Claude Code sends `CSI > 4;2 m`
  (XTMODKEYS, `modifyOtherKeys=2`) at startup; read as SGR that is `4` then
  `2` — underline (ignored before Plan D, recorded after it) and **dim**,
  which Claude Code never clears because it uses `39`/`22`, not `0`. vte
  itself dispatches by intermediates: `('m', [])` is SGR, `('m', [b'>'])`
  XTMODKEYS, `('m', [b'?'])` XTQMODKEYS (`vte-0.15.0/src/ansi.rs:1678-1694`).
- Now: SGR runs only when `intermediates.is_empty()` in both dispatchers.
  The `claude-spinner-10s` feel baseline was re-recorded in the same commit:
  its banner is now full colour, which is what Warp shows.
- Guards: `tests/sgr_attributes.rs::a_private_m_sequence_is_not_sgr`,
  `…::a_private_m_sequence_in_a_history_chunk_is_not_sgr_either`,
  `…::the_claude_code_recording_carries_no_attribute_bits` (feeds the real
  spinner recording and asserts no attribute bit on any run).

### 4.23 Hover file paths — Operator's own rules, VS Code's suffix grammar
- An exception to §3.2: this detector is written clean-room from the rules
  below and our own Claude Code captures. Do not port another terminal's
  file-path detector into it (licence), and cite only VS Code (MIT) here.
- What it does: hovering a cell looks for a link through that cell. An OSC 8
  hyperlink wins, then a URL (xterm.js's strict grammar), then a file path —
  providers in that order, earlier wins on overlap (`mergeLinks`); the path
  provider never asks the host about a cell inside a hyperlink or a URL.
- Candidates (`ts/renderer-dom/src/path-candidates.ts`, `pathCandidatesAt`):
  the hovered cell's segment runs between hard breaks — quotes, backtick,
  `()[]{}<>`, `|`, `;`, `,`, `=` and `PATH_BREAK_GLYPHS`. The glyphs are every
  non-letter, non-digit, non-space code point above ASCII in the two Claude
  Code recordings (`bench/agent-session/fixtures/*/recording`), plus the
  non-ASCII markers of vt-core's own `hanging_indent` table (`row_index.rs`,
  which adds `│ ├ └`, absent from both recordings). Whitespace only bounds a
  span: every span of up to `MAX_SPAN_WORDS = 4` whole words through the cell
  is a candidate, longest first, so `My Docs/a.md` links when it exists and
  `see a.md` never outranks `a.md` unless `see a.md` itself exists.
- Each span: trailing `. , : ; ! ?` is dropped unless the last component is
  `.` or `..`; a line/column suffix is stripped with VS Code's grammar
  (`link-parsing.ts`, a port of
  `vscode/src/vs/workbench/contrib/terminalContrib/links/browser/terminalLinkParsing.ts`):
  `getLinkSuffix` inside the span (`file:12`, `file:12:3`, `file#12`,
  `file 12`), `detectLinkSuffixes` right after it (`file(12,3)`,
  `"file", line 12`), plus GitHub's `#L12` / `#L12C3`, which VS Code's
  table does not have. A path starting `a/` or `b/` is also offered without
  the prefix. A directory may match only when the span has no line suffix
  and looks like a path (contains `/` or `\`, or starts with `~` or `.`),
  so `docs`, `src` or `backend` in prose never links.
- One batched host call: `HostCapabilities.resolveFirstPath(candidates, cwd)`
  gets every candidate at once and answers the first that exists, as
  `{ index, path }`. `MAX_PATH_CANDIDATES = 20` — 10 spans (the most four-word
  windows that can contain one word: 4 + 3 + 2 + 1) times the two readings of
  a diff path — is enforced by `pathCandidatesAt` and again by Operator's
  `resolve_first_path` (`frontend/src-tauri/src/native.rs`,
  `first_existing_path`), which also expands `~` and `~/…` and skips a
  directory a candidate does not allow. Operator passes the block's cwd,
  falling back to the session's workspace path.
- Caching: only a found path is remembered, keyed by cwd and the logical
  line's text (256 lines), so the spinner repainting other rows never drops
  it; "not found" is never cached, so a path hovered before the file exists
  links on the next hover once it does. The `Linkifier` reuses its answer
  for the same cell while the line's text is unchanged.
- Cost, measured 2026-09-23 on `claude-long-50k` (60,137 logical lines; the
  longest is 120 chars / 24 words, a prompt row): at most 10 candidates on
  any cell, mean 4.8 over the 109 cells that yield any; 0.01–0.02 ms to build
  them per hover; `first_existing_path` 0.10 ms for 10 misses and 0.19 ms
  for 20 (release build, this machine).
- Guards: `path-candidates.test.ts`, `link-providers.test.ts`
  ("createPathProvider", one test per rule), `linkifier.test.ts`,
  `TerminalSurface.mouse.test.tsx` "underlines the ~/ working directory
  Claude Code's startup banner prints beside its mascot" (real banner bytes
  from a `claude` v2.1.280 launch in a pty, `ts/react/src/__fixtures__/claude-code-banner`
  — the recorded fixtures print an elided `/…/` path instead), `native.rs`
  `first_existing_path_*`, `tauri-bridge.test.ts`, `BlockTerminal.test.tsx`.

### 4.24 A pane shown again kept the pty at its old grid — split view review
- Symptom: in split panes, typed text landed on the wrong row (over Claude
  Code's separator or a transcript line), long lines were cut at the pane edge,
  and Claude Code's banner repeated in overlapping copies.
- Cause: a layout change parks and re-shows the pane's retained terminal. The
  surface measured the new grid, parking cleared the queued publish
  (`useTerminalSession` visibility effect), and nothing re-sent it on return:
  `syncVisibleSize` only covers the xterm fallback (`surfaceGeometry !== null`
  returns), and the surface does not report again because its box did not change
  after it measured. The pty stayed at the old width (measured live: 98 columns
  behind a 47-column pane), so Claude Code drew frames the renderer rewrapped
  taller than Claude Code believed, and its relative repaints left copies.
- Now: when a pane becomes visible and its surface grid differs from the last
  published grid, that grid goes through the normal debounced publish, so a
  re-shown pane's settling sizes still collapse into one SIGWINCH (§4.6).
- Guards: `useTerminalSession.test.tsx` "publishes a surface grid that parking
  cancelled…", "…measured while parked…", "collapses a reshown pane's settling
  sizes…", "sends nothing when a pane is parked and shown at the grid it already
  published".

### 4.25 A hidden window drained nothing and notified nothing — `cb7b34b3b`
- Symptom: while Operator's window was minimised or app-hidden, no pane parsed
  its output and no "command finished" notification fired. On restore the
  pending blocks finished at once and reported `visible: true`, so
  `BlockTerminal` suppressed the notification for a command that finished while
  the user was away.
- Cause: `requestAnimationFrame` never fires in a hidden WKWebView (0 per
  second minimised or app-hidden, measured by
  `scripts/probe-wkwebview-hidden.swift`;
  `docs/superpowers/specs/2026-09-23-background-pane-cost-measurement.md`), and
  the renderer drained, ticked and detected finished blocks only from its
  animation frame. Every pane, the active one too, stopped.
- Now: while `document.visibilityState` is `"hidden"` the renderer schedules its
  frame on a `HIDDEN_TICK_MS` (100 ms) timer, which WebKit throttles to ~1/s;
  each tick drains up to `HIDDEN_DRAIN_MS` (250 ms), ticks the core and reports
  finished blocks with `visible: false`, painting nothing. When the document is
  shown the renderer goes back to animation frames and a pane that paints
  rebuilds in full on the first one (`catchUp`). The paint gate (`setVisible(false)`,
  `6f8e38973`) is the same non-painting frame for a parked pane while the
  window is shown, so a pane parked in a hidden window stays unpainted when the
  window returns.
- Guards: `dom-block-renderer.visibility.test.ts` "hidden document" and "paint
  gate" describes; `TerminalPane.test.tsx` "paints a retained terminal on
  screen and stops painting it while parked".

### 4.26 Layout containment — measured, no gain, not applied
- What was tried: `contain: layout` on `.terminal-row`, A/B in one session
  against a control (`bench/agent-session/run.mjs --panes-only --css …`).
  10-visible Layout: control 0.246–0.296, with containment 0.264–0.274 s —
  inside noise (2026-09-23,
  `docs/superpowers/specs/2026-09-23-layout-containment-measurement.md`
  "After"); WebKit repaint loop 1109–1170 ms control against 1075–1164 ms,
  discarded because the control ran first in every pair and drifted down
  through the session. `.terminal-block` was not tried: the plan tries it
  only on top of kept row containment. Nothing was changed.
- Why it cannot help much here: the scroller is already `contain: strict`
  (`renderer-chrome.ts:22`), so a frame's layout never leaves the pane,
  and each layout already has a median of 142 dirty objects out of 274–370
  (trace `beginData`), the same 142 with containment. What they are was not
  broken down; the rows rebuilt each frame are the likely bulk (inference,
  not measured), and new nodes need layout anyway. There is also no second
  layout to remove:
  0 render-step layouts per frame.
- Ruled out, do not add: `paint` (clips at the box and saves no layout);
  `size`, `strict`, `content`, `content-visibility: auto` (a row's height is
  not provably one line: text past its last run sits in the row's own line
  box, `row-builder.ts:116-119`; the virtualiser already mounts only visible
  rows); `style` (nothing to scope).
- Guard: `styles-parity.test.ts` "never uses a containment that clips paint
  or fixes size".

### 4.27 A paste that runs by itself — roadmap Plan 1
- Symptom: text copied from a web page with a hidden line break ran as a
  command the moment it was pasted into a pane whose program did not ask for
  bracketed paste, and inside bracketed paste a lone `ESC` or `^C` reached the
  program (`ts/editor/src/paste.ts` before this plan: only `ESC[201~` was
  removed).
- Now: one rule in `ts/editor/src/paste.ts` (`encodePaste`, `deliverPaste`),
  used by the line editor's passthrough (primary screen, where Claude Code
  runs) and by the alternate-screen handler in `TerminalSurface.tsx`.
  Bracketed: strip `ESC[201~`, `ESC` and `^C` and send. Unbracketed while the
  child owns the line: a newline, a C0 control other than tab, or `ESC[201~`
  makes the paste unsafe, and the host's `HostCapabilities.confirmPaste` is
  asked. No handler means send as before (product independence, §3.1). The
  editor-owned line never asks: nothing runs until Enter.
- Operator: `frontend/src/renderer/hooks/usePasteConfirm.tsx` shows the first
  5 lines (200 characters each) and a one-line reason in `ConfirmDialog`,
  wired in `BlockTerminal.tsx`. "Paste" or "Cancel", no "don't ask again".
- References, behaviour only (no code adapted, so no attribution file):
  Ghostty `src/input/paste.zig:160-190`, Alacritty
  `alacritty/src/event.rs:1369-1410`.
- Guards: `paste.test.ts` (verdict table, preview, delivery),
  `line-editor-paste.test.ts`, `TerminalSurface.paste.test.tsx`,
  `frontend/src/renderer/hooks/usePasteConfirm.test.tsx`,
  `BlockTerminal.test.tsx` "BlockTerminal paste confirm".

### 4.28 Find found nothing in Claude Code panes and never kept up — Plan 2
- Symptom: in a Claude Code pane the find bar said "No matches" for text on
  the screen; in a shell it found only commands whose output had scrolled
  entirely into scrollback; a match printed after the query was typed never
  appeared.
- Cause: `FindCursor` walked `BlockGrid` blocks and searched a block only when
  every row of it was completed history (`block_byte_range` returned `None`
  otherwise). A pane without OSC 133 marks — every Claude Code pane — has an
  empty `BlockGrid` (its one block is synthesised only at export,
  `grid.rs` `export_blocks`), so there was nothing to walk. Each query
  scanned once and stopped; the bar decoded every block and ran two
  `querySelector` calls per hit on every repaint.
- Now: `FindSession` (`crates/vt-core/src/find.rs`) searches rows, not
  blocks. Settled history — completed rows up to the last one that ends a
  line — is scanned once, oldest first, in `FIND_UPDATE_BUDGET_BYTES`
  (1 MiB) steps, then only from `scanned_to`. Hits are content byte ranges:
  a trim drops those below the first row, a rewrap only changes the rows
  they resolve to in `find_results`, a history prepend (attach replay)
  restarts the scan, a prompt resize that rewrites pulled-back rows drops
  only the hits from the cut's line on and rescans from there (§4.36). The
  unsettled tail (a soft-wrapped last history row) plus the live screen is
  re-searched when `generation()` changed, so a match across the
  scrollback/screen boundary is one hit. A soft-wrapped line is one line to
  the search; a hard break is a `\n` the query cannot
  cross (a match that would cross is searched again inside its own line).
  Literal queries use `memchr` when case-sensitive and an escaped regex
  (`regex-syntax`'s meta-character set) when not. The bar calls
  `findUpdate` after every paint while open, refetches results only when
  hits were added or removed, marks rendered rows from a set of hit rows,
  re-anchors the current hit by (stable row, byte), and scrolls to the
  hit's row with `DomBlockRenderer.scrollToRow`. Next/previous is an index
  step through sorted results, so Alacritty's directional DFAs
  (survey §2.6) were not needed.
- Guards: `crates/vt-core/tests/find_session.rs`, the `find.rs` unit tests,
  `ts/core/src/find.test.ts`, `ts/renderer-dom/src/find-bar.incremental.test.ts`,
  `dom-block-renderer.scroll.test.ts` "scrollToRow",
  `npm run bench:terminal -- --renderer dom --scenario find-500k`,
  `npm run bench:find-update`.

### 4.29 A hung pty-host froze its pane; a dead one lost its history — roadmap Plan 4
- Symptom: a pty-host that stopped answering (SIGSTOP, or wedged) left its pane
  frozen with no message, and nothing offered a way out short of restarting the
  daemon and the app. A pty-host that died took the terminal's history with it:
  the mirror and the ring live only in host memory.
- Cause: the reaper records a timed-out probe as `ProbeFailed`
  (`observe/reaper/reaper.go:205-215`) and lifecycle ignores it by design
  (`ports/runtime_observations.go:13-14`), so nothing ever concluded "hung";
  and nothing wrote the mirror anywhere.
- Now: `ptyhost.Runtime` counts consecutive failed `IsAlive` probes per host;
  at `hungAfterFailedProbes` (3, i.e. ~12-17 s at the reaper's 5 s tick) the
  host is hung, the terminal mux sends `{"type":"health","health":"hung"}` on
  `ch:"terminal"` to the panes viewing it (and to a pane that opens it later),
  and the pane shows "This terminal stopped responding." with **Restart
  terminal**. Restart is `POST /api/v1/sessions/{id}/restart-terminal`:
  `Runtime.Destroy` (SIGKILL after 500 ms, which reaches a stopped process)
  then the normal relaunch into a fresh host under the same handle id. It is
  never automatic. `respawn.go` cannot do this: it runs inside the hung host.
  Every host also saves its attach replay to `~/.operator/pty-host-history/`
  (`persist.go`); `Runtime.Create` deletes a session's file unless
  `RuntimeConfig.RestoreHistory` (set only by the session manager's relaunch
  path), and prunes files of gone hosts older than 7 days; the new host feeds
  the file and a process-boundary mark into its mirror before the child's
  first byte, so every attach replays the old history above the new process.
- Measured: `claude-long-50k` (60k rows) — frame 17 KB, newest 20 chunks
  180 KB in 491 ms; all 116 chunks would be 938 KB in 2.7 s, because every
  `vt_history_chunk` snapshots the whole core (`vt-host/src/lib.rs:470`).
  `docs/superpowers/specs/2026-09-24-crash-recovery-measurement.md`.
- Guards: `ptyhost/health_test.go` (hung after 3 not before, recovery, slow
  once, refused is gone, destroy clears), `terminal/health_test.go` (viewers
  only, new viewer told at once, client stays attached across a restart),
  `session_manager/restart_terminal_test.go`, controller `TestRestartTerminal`,
  `ptyhost/persist_test.go` (round trip after a crash, byte cap, write only on
  change, shutdown write, header, prune), `persist_runtime_test.go`,
  `TerminalPane.test.tsx` "terminal not responding",
  `useTerminalSession.test.tsx` health tests.

### 4.30 Messages from programs: title, notifications, size and colour replies — roadmap Plan 3
- Symptom: Claude Code sets its window title about ten times a second (`claude-long-50k`: 1,047 `OSC 0`) and Operator showed none of it; a program's own "done" notification (OSC 9/777/99) went nowhere; `CSI 16 t` (sent by Claude Code v2.1.280, `claude-markdown-reply`), `CSI 14/18 t`, mode 2048 and `OSC 10/11 ; ?` went unanswered; OSC 22 was ignored.
- Now: `vt-core` `program.rs` holds the title, a title stack capped at 4,096, up to 16 pending notifications and a pointer shape; both OSC dispatchers classify through `OscKind` and the history receiver handles only hyperlinks, so replayed history never changes the title or notifies. Replies use the same queue as the XTVERSION/DECRQM/DA1 answers (§4.16): only the mirror answers. The mirror learns the cell size (device pixels) and colours from the pane's `appearance` mux frame (last writer wins; nothing is answered for 14/16/2048/10/11 before one arrives). The pty-host strips a leading glyph+space (`domain.TerminalDisplayTitle`) and pushes only a changed stripped title, plus every notification, to **watcher** connections (`MsgWatchReq`, `MsgProgramEvent`); the daemon's runtime keeps one watch per live host in memory (opened by `Create`, `Attach` and each successful reaper probe; closed by `Destroy`) and the terminal mux relays on `ch:"programs"` with a snapshot on subscribe. The renderer's `ProgramRuntime` feeds `useTerminalTitle` (session card under the name, pane header) and shows a program notification as a desktop toast only when its terminal is not on screen in a focused window (agent-alerts rule D2); the pointer shape is the surface's `--terminal-pointer-shape`.
- Guards: `vt-core/tests/program_messages.rs`, `program_replies.rs`; `vt-wasm/tests/program_exports.rs`; `ts/core/src/program-messages.test.ts`; `ts/react/src/TerminalSurface.program.test.tsx`; `vtwasm/program_test.go`; `ptyhost/program_test.go`, `program_watch_test.go`; `domain/terminal_title_test.go`; `terminal/programs_test.go`; renderer `terminal-mux.programs.test.ts`, `terminal-titles.test.tsx`, `on-screen-terminals.test.ts`, `program-feed.test.ts`, `ProgramRuntime.test.tsx`, `SplitWorkspaceOnScreenTerminals.test.tsx`, `ShellTerminalsView.onscreen.test.tsx`, `terminal-appearance.test.ts`, and the new cases in `SessionsBoard.test.tsx`, `SplitPane.test.tsx`, `BlockTerminal.test.tsx`, `useTerminalSession.test.tsx`.
- Pointer shape on reattach (real-app run, 2026-09-26): the attach replay
  (`vt-host` `write_modes`) now carries `ESC ] 22 ; <css> ST` after the modes, so a
  pane attached after a program set a shape shows it; history chunks still ignore
  OSC 22 (`history.rs`). Guard: `vtwasm/replay_test.go`
  `TestReplayCarriesThePointerShapeTheChildSet`.
- References, behaviour only (no code adapted, so no attribution file): Ghostty `src/terminal/size_report.zig:5-80`, `stream_terminal.zig:256-280,1456-1476,1602-1605`, `osc/parsers/osc9.zig`, `rxvt_extension.zig`, `mouse.zig:100-150`; Alacritty `alacritty_terminal/src/term/mod.rs:42-48,2235-2248`; kitty's desktop-notification protocol description (no kitty code read).

### 4.31 One look for highlights; user marks — roadmap Plan 5
- Before: the selection painted its own `background-image` per row
  (`selection-view.ts` `selectionFills`), the find bar added and removed row
  classes itself on every repaint (`find-bar.ts` `applyHighlights`), and there
  were no user marks. Two paint paths for one idea, and nothing to put a third
  kind on.
- Now: `highlights.ts` is the model — `Highlight { kind, range, colour, rank }`,
  `range` in stable rows (§2), priority selection 3 > current find hit 2 > find
  hit 1 > mark 0, earlier mark rule above a later one. `highlight-painter.ts` is
  the only code that paints them: a row's layers, top first, as one
  `background-image` of `fillGradient` strings, the same layers clipped by
  `runFill` onto runs with their own background (the §4.11 rule, now for every
  kind), and the find classes. It diffs against what it painted, so an unchanged
  row gets no write. `renderer-highlights.ts` collects selection, find and
  marks and calls it from `finishPaint` and on every change; it never schedules
  a repaint, and it paints nothing while the pane is parked.
- Find keeps its old pixels on purpose: a hit row keeps
  `terminal-find-row-match` (a background colour) and the current hit keeps the
  `terminal-find-row-active` outline. A gradient layer of the same colour
  differs by up to 1 level per channel (measured while planning: 8,278 channel
  values in a 900×60 Chromium shot), so the colour stays a colour — except on a
  row that also has a mark, where the find tint becomes a layer above the mark
  so the priority holds. Find paints only transcript rows, never the alternate
  screen, as before.
- Marks: `setMarks(rules)` / `TerminalSurface` `marks`, `MarkRule { pattern,
  regex, colour }`. Literal = escaped, any case; regex = as written. Invalid
  regex, empty pattern, zero-length matches and colours `CSS.supports` rejects
  are dropped; touching matches of one rule merge. Each paint joins the logical
  lines of the rendered rows once (`visibleLogicalLines`), matches each line,
  and maps back with `rangeOf`; `MarkCache` keeps each line's spans while its
  text is unchanged. Nothing is stored in rows, so a trim or a rewrap cannot
  strand a mark. Marks read the masked text, so they never outline a redacted
  secret. Operator: Settings → Terminal highlights, five colours
  (`color-mix(in srgb, var(--terminal-ansi-N) 40%, transparent)` for yellow 3,
  red 1, green 2, cyan 6, magenta 5 — no blue, the selection's colour), at most
  10 rules, stored under `opr.terminal.marks`.
- Not moved onto the model: links, hints, redaction and prediction. They are
  overlays above the text (`.terminal-decorations { z-index: 2 }`); a redaction
  must cover glyphs. The model paints under the text.
- Cost (`run.mjs --panes-only`, `claude-spinner-10s`, alternated A/B, three
  pairs, 5 `BENCH_MARKS`, re-measured on the owner's Mac 2026-09-25 at review):
  10-visible TaskDuration control 0.846–0.877 s, marks 1.038–1.117 s;
  ScriptDuration 0.28 → 0.43–0.47 s; solo 0.207 → 0.244–0.254 s. That is a real
  cost, not noise (the planning-machine "overlap" came from a noisy control,
  1.088–1.277 s; the cloud sandbox ran 2.2–3.1 s overall). It is the cost of the
  feature on a worst case: `\d+` touches almost every row of the recording, and
  Claude Code's spinner rewrites those rows every frame, so they are rebuilt as
  new elements (`block-body.ts:74-77`) and must be painted again, one extra
  style recalc per pane per frame (RecalcStyleCount 2,256 → 3,237). About 1–2 %
  of one core across ten streaming panes, zero with no marks. The painter
  caches each row's paint by element, highlights and pane geometry and reuses
  it for a row whose element did not change, and measures one touched row per
  paint for the pane's left edge and width instead of every touched row
  (review fix; selection, find and marks screenshots byte-identical before and
  after, 11 of 11). A first
  build that measured every rendered row per paint doubled ScriptDuration.
- Regex marks run on vt-core's linear-time engine, not JavaScript's
  backtracking one (fixed at review 2026-09-25): `crates/vt-core/src/mark_regex.rs`
  (`regex-automata` meta regex, NFA size limit 1 MiB, empty matches skipped,
  offsets returned in UTF-16 units), exported as `WasmMarkRegex`
  (`crates/vt-wasm/src/mark.rs`) and wrapped by `compileMarkRegex` /
  `markRegexValid` in `ts/core/src/mark-regex.ts`. `(a+)+$` over 20,000
  characters returns at once instead of hanging the pane. The syntax is Rust's:
  lookaround and backreferences are rejected, and Operator's Settings validates
  with the same engine (`markRegexValid`, loaded when the section opens; a
  JavaScript syntax check is the fallback before the wasm is ready). Literal
  words stay a case-insensitive escaped JavaScript regex, which cannot
  backtrack. Compiled regexes live in wasm memory and are freed by
  `disposeMarks` when the rules change or the renderer resets. Guards:
  `crates/vt-core/tests/mark_regex.rs`, `ts/core/src/mark-regex.test.ts`,
  `marks.test.ts` "regex safety", `frontend/src/renderer/lib/terminal-marks.test.ts`.
- Guards: `highlights.test.ts`, `highlight-painter.test.ts`, `marks.test.ts`,
  `dom-block-renderer.highlights.test.ts` (overlap order, trim, rewrap, no
  repaint scheduled, no layout read when idle, parked, alternate screen,
  rejected colour, dispose), `find-bar.incremental.test.ts` "hands its hits…",
  `TerminalSurface.marks.test.tsx`, `terminal-selection.test.ts` (unchanged),
  `bench:affordances --action select|find --compare <Task 0 captures>` (byte
  identical), `bench:selection`, `bench:feel`; Operator:
  `terminal-marks.test.ts`, `ui-store.terminal-marks.test.ts`,
  `TerminalMarksSection.test.tsx`, `BlockTerminal.test.tsx` "hands Settings'
  highlights…".

### 4.32 Text typed during a command reached the shell, not the input box — roadmap Plan 6
- Symptom: in a zsh pane, keys typed while a command ran went to the pty
  (deliberate since `4b31952aa`, so a `y/n` prompt, a password or Claude Code
  gets them: `ts/editor/src/line-editor.ts` `passthrough`). When the prompt
  returned, zsh held the text in its own line buffer, invisible in the input
  box, and the next thing submitted from the box was appended to it: `echo hi`
  typed during `sleep`, then `ls` in the box, ran `echo hils`.
- Cause: a shell reads typeahead only after its prompt starts, and nothing
  told the line editor what it read. At `line-init`, zsh's `$BUFFER` is still
  empty; the text is waiting on the tty.
- Now: behaviour taken from the survey's description of Warp's shell-reported
  typeahead (§7.2; Warp is AGPL-3.0 — clean-room, no Warp file read).
  `shell/zsh.sh`'s `line-init` hook, once per finished command
  (`__operator_terminal_TYPEAHEAD_ARMED`, set in `precmd`) and only at a
  primary prompt (`$CONTEXT == start`), reads what is waiting
  (`read -t 0 -k 1`, at most 257 characters), pushes it straight back into zle
  (`zle -U`), and — when it is at most 256 characters with no control
  character — reports it right after `input-ready` as
  `OSC 7000;v=1;typeahead=<percent-encoded UTF-8>` (`protocol/SPEC.md` §4.5).
  vt-core keeps the report only while the line is owned
  (`LineEditorTracker::on_typeahead`; `input-released` and the alternate
  screen drop it) and `TerminalCore.takeTypeahead()` hands it over once.
  `LineEditor` takes it on every change, visible or not, and adopts it only if
  the user sent keys, IME text or a paste to the pty since the last report
  (`TypeaheadGate`, `ts/editor/src/typeahead.ts`): it appends the text to the
  buffer, never submits it, and sends `^U` (0x15) to clear zsh's copy. Keys are
  still never held back.
- Why the shell does not clear its own buffer (the first design did): the
  daemon's `SendMessage` writes text, pauses, then sends Enter as a separate
  frame (`backend/internal/adapters/runtime/ptyhost/client.go:38-70`). Text
  arriving while a command is finishing looks exactly like typeahead to the
  shell; a shell that cleared it lost the command and ran an empty line —
  `TestShellBlocksAlternateScreenAtCaptureStartExcludesRepaint` failed 3 of 3
  runs that way. Only the line editor knows the user typed the text, so only
  it clears the shell's copy. `^U` is `kill-whole-line` in zsh's emacs keymap
  and `vi-kill-line` in `viins`; both clear the pushed text.
- bash and fish are not covered, by decision. bash: `READLINE_LINE` is
  reachable only inside a `bind -x` binding, which the additive-only contract
  forbids (`docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`
  §8, line 872); a `PROMPT_COMMAND` drain (`read -r -s -n 1 -t …`) can read the
  text but cannot hand it back to readline, so it would lose the `SendMessage`
  case; macOS `/bin/bash` 3.2 also takes whole-second timeouts only (`-t 0`
  read nothing). fish: `commandline` is empty in a `fish_prompt` handler (fish
  reads the typeahead after drawing the prompt) and its `read` has no timeout.
  Both keep the old doubling.
- Limits: a line typed ahead with Enter runs as before and is not moved; the
  typed text also stays in the finished command's output, where the tty echoed
  it while the command ran (as in every terminal); keys that reach zsh after
  its report and before the `^U` (one pty round trip) are cleared with it; a
  client without a line editor (the phone) leaves the text in the shell, as
  before; a user who rebinds `^U` gets the old doubling.
- Also fixed: `__operator_terminal_pct_encode` in `zsh.sh` encoded a code
  point, not bytes (`é` → `%e9`, `€` → `%c`); it now encodes UTF-8 bytes under
  `no_multibyte`. `bash.sh`'s encoder had the same bug and also let `é` through
  unencoded (its `[A-Za-z]` range matches accented letters in a UTF-8 locale);
  it now walks bytes under `LC_ALL=C` and masks each to 0–255, because bash
  3.2 sign-extends bytes above 127 (`%ffffffffffffffc3`). Guard:
  `bash.test.mjs` "percent-encodes non-ASCII bytes as UTF-8".
- Guards: `shell/zsh.test.mjs` (reports and is cleared by Ctrl-U, kept when
  nothing clears it, UTF-8, Enter typed ahead runs, multi-line submission,
  over the cap, `read -s` password never surfaced, a program's own prompt
  still gets its keys, vi insert mode, byte encoding); `bash.test.mjs` and
  `fish.test.mjs` "reports no typeahead"; `crates/vt-core/tests/typeahead.rs`
  (incl. the Claude Code recording); `ts/core/src/typeahead.test.ts`;
  `ts/editor/src/line-editor-typeahead.test.ts` (incl. the Claude Code
  recording and a faked report); `protocol/vectors/typeahead.json`;
  `backend/internal/terminal/block_assembler_test.go`
  `TestAssemblerIgnoresATypeaheadMark`; `backend/internal/integration`
  `TestShellBlocks*`.

### 4.33 Output older than the row cap was dropped — roadmap Plan 7
- Symptom: past 200,000 rows (or 128 MiB) the oldest output was gone for good,
  in the pane and in the mirror (`Parser::trim_to` dropped it).
- Now: the pty-host mirror keeps trimmed rows as SGR text in a 32 MiB cold ring
  (`crates/vt-core/src/cold_ring.rs`, filled in `parser/history.rs` `trim_to`
  through `parser/cold.rs`). The mirror sends `OSC 7000;v=1;older=<floor>` after
  the attach history (or after the frame for a sized client without history) and
  at the end of every older answer. The pane shows **Load older output**
  (`ts/renderer-dom/src/load-older.ts`) when a floor below its first stable row is
  known and the host implements `HostCapabilities.loadOlderOutput`; a click sends
  mux `older{before}` → `MsgOlderReq` → one history chunk of ≤ 2,048 rows
  (`older_chunk`) plus the floor, in-band on that client's stream. The chunk
  carries `cols=` so a row wider than the pane lands whole and rewraps lazily.
  Loaded rows sit above the renderer's cap until the next live row trims them.
- Review fixes (branch `fix/plan-7-review`), each reproduced by a test first:
  (a) **labels match content.** `older_rows` (`parser/cold.rs:44-62`) used to
  clamp `before` to the mirror's own end and `older_chunk` still labelled the
  rows as ending at `before`, so after a respawn (a fresh mirror numbered from
  0, `ptyhost/respawn.go:63`) every click prepended the new process's rows, and
  a pane numbered ahead of the mirror got the same rows again under each new
  label. It now answers nothing when `before` is past the mirror's completed
  rows or outside the ring; the host then sends `older=<before>`
  (`ptyhost/older.go:27-41`) so the pane hides the button, and a process
  boundary clears the pane's floor (`OlderState::observe`, `older.rs:22`,
  called at `lib.rs:281`). (b) **answers stay out of the live parser.** The
  host queues older answers and attach-history chunks (`streamHistory`, off
  `h.mu`) between live PTY batches split at any byte, so a chunk could land
  inside a CSI or a UTF-8 character; its ESC reset vte and the live sequence
  printed as text (`1mRED`, `caf��`). `AnswerGate` (`answer_gate.rs`, used at
  `lib.rs:321`) holds `OSC 7000;v=1;history=` and `older=` back from vte across
  feeds (the rows already go to the history receiver), and the mark scanner
  restarts on an ESC inside a CSI or after an ESC (`marks/src/scanner.rs:72,86`)
  instead of dropping it and missing the chunk. Fixed in the core rather than
  by inserting at clean boundaries in the host because both insertion sites
  (`serveOlder` and Plan C's `streamHistory`) share it and vte exposes no
  state to test for a boundary. (c) **stale runs.** `rewrap_hot` rewrapped
  prepended wide rows inside the newest 2,000 rows but kept their stale runs
  (`StaleRunOutsideRows`); it now trims every run to the rows below the hot
  window (`row_index.rs:136`). (d) **ring heap.** Row lengths lived in a second
  `VecDeque` that doubled beside the text buffer reserved at the full cap, so
  blank rows took the heap to 2× the cap; each row's length and width now sit
  in the one buffer as a 6-byte header and a 4-byte trailer
  (`COLD_ROW_OVERHEAD_BYTES = 10`, `cold_ring.rs:4-7`), read from the nearer
  end (`offset_of`, `cold_ring.rs:127`). (e) **oversized rows.** A row whose
  serialised form alone passes the answer budget is sent blank
  (`older.rs:65-70`) instead of stopping every later click. Guards:
  `tests/older_seams.rs` (including a nine-step repro and 64 seeded
  feed/load/resize/touch sequences with `verify_integrity` after every step),
  `tests/injected_answers.rs`, `answer_gate.rs` unit tests,
  `cold_ring.rs` `the_heap_stays_within_the_cap_for_blank_and_long_rows`,
  scanner `an_escape_inside_a_csi_or_after_an_escape_still_opens_a_mark`,
  `ptyhost/older_test.go` `TestAnOlderRequestPastTheMirrorsRowsAnswersNothingOlder`,
  `ts/core/src/older-output.test.ts` "forgets the floor at a process boundary".
  (f) **a full older chunk landed 999 rows and 1,049 blanks** (real-app run,
  2026-09-26). `HistoryReceiver::begin` (`crates/vt-core/src/history.rs`) parsed
  a chunk into one `ScreenGrid` of `rows + 1` rows, and `ScreenGrid::new` clamps
  to `MAX_DIMENSION` (1,000, `screen.rs:14`). Attach-history chunks (512 rows)
  fit; a 2,048-row older answer scrolled its oldest 1,049 rows off that screen
  and prepended 999 real rows then 1,049 blank ones under the chunk's labels
  (`seq 1 400000`, one click: 198970..199968, about 1,000 empty rows, 199969).
  The receiver now saves each row when its `\n` arrives and resets a one-row
  screen (the `\n` never reaches vte), so it holds O(cols) cells whatever the
  row count. Guards: `tests/cold_ring.rs`
  `a_full_older_chunk_lands_every_row_with_its_text`, `vtwasm/older_test.go`
  `TestAFullOlderChunkLandsEveryRowInTheReceivingCore`,
  `ts/core/src/older-output.test.ts` "lands every row of a full 2,048-row chunk
  with its text".
- Not persisted: the saved history (§4.29) is 4 MiB and 20 chunks; cold rows are
  older than anything it can hold.
- Measured (`docs/superpowers/specs/2026-09-25-old-output-measurement.md`): a
  full 32 MiB ring costs the mirror wasm memory ≈1.2× its cap (77,594,624 bytes
  with a full ring vs 35,979,264 without); the ring's own payload never passes
  its cap (33,554,386 ≤ 33,554,432); a click's host side is under a few ms
  (1.382 ms newest, 0.610 ms oldest on a 520k-row synthetic mirror); the
  renderer side of a click is one full re-export of 200k rows (1,193.38 ms,
  the same order as the first full export, 1,158.68 ms), while feeding the
  2,048-row chunk itself costs 45.05 ms.
- Guards: `crates/vt-core/tests/cold_ring.rs`, `cold_ring.rs`/`content.rs` unit
  tests, marks `scanner.rs` older/cols tests, `vtwasm/older_test.go`,
  `ptyhost/older_test.go`, `terminal/manager_test.go` "Older", 
  `ts/core/src/older-output.test.ts`, `load-older.test.ts`,
  `dom-block-renderer.older.test.ts`, `TerminalSurface.older.test.tsx`,
  frontend `terminal-mux.test.ts`, `useTerminalSession.test.tsx`,
  `BlockTerminal.test.tsx` "load older output".

### 4.34 Agents could not tell the terminal what they were doing — roadmap Plan 8
- Before: agent state reached Operator only out of band (`opr` hooks over
  loopback HTTP, `opr mcp` `session_report`), so nothing worked for an agent
  whose hooks cannot reach the daemon (SSH, a container), and no host of the
  package could tell that an agent was idle or asking a question.
- In-band events: `OSC 777 ; agent-state ; v=1 ; state=… [; detail=…] ST`
  (`protocol/SPEC.md` §10). Plan 3's dispatcher (`program.rs` `osc777`) sends
  the `agent-state` extension to `AgentChannel` (`crates/vt-core/src/agent.rs`)
  before its `notify` check, so the two can never be confused. Parsing is
  strict (exact `v=1`, known state, no repeated key, strict percent-decoding);
  a payload of 1,024 bytes or more is ignored because vte's `no-std` OSC buffer
  (`MAX_OSC_RAW = 1024`) has already cut it. Identical consecutive events
  collapse; 16 wait at most; a process boundary forgets the last one; each
  queued event bumps the program generation, which `ts/core`'s `AgentEvents`
  polls after every feed and tick (`TerminalCore.onAgentEvent`).
- Never from loaded or replayed output — the Plan 3/7 rule: history chunk rows
  (attach history, older answers) go to the `HistoryReceiver`, whose
  `osc_dispatch` only interns hyperlinks, and their marks are held back by
  `AnswerGate`; the attach replay frame does reach vte, so `AgentChannel` is
  silenced from any `origin=` mark to `ready=`, adopted or not
  (`crates/vt-core/src/live_output.rs:2` `open_replay_window`, called from
  `lib.rs` `feed_raw`).
- Activity: `vt-core` counts bytes handed to vte outside the replay window
  (`live_output_bytes`, reset when a fresh core adopts a replay origin). The
  origin mark's own bytes are outside the count: the pre-mark bytes of the
  chunk are fed first, the mark after the window opens; a mark split across
  feeds takes back what the previous feed counted of it
  (`MarkDecoder::open_osc_bytes`, `crates/marks/src/scanner.rs:69`, less the
  answer gate's held bytes, `live_output.rs:21`).
  `AgentActivityMonitor` (`ts/core/src/agent-activity.ts`) turns it into
  `active` (output in the last 500 ms), `pollingForIdle`, `idle` (1,500 ms
  quiet) or `prompting` (quiet and the cursor line matches VS Code's
  high-confidence prompt patterns, `input-patterns.ts`) — VS Code's
  500 ms / two-idle-polls behaviour (`chatAgentTools/.../monitoring/types.ts`
  `PollingConsts`) as a clock. The timer runs only while someone listens and
  stops at `idle`; every output restarts it, so each threshold is timed from
  the latest output (`agent-activity.ts:81` `schedule`). The reported state
  changes only in `publish` (`agent-activity.ts:71`), which reaches every
  listener; a listener that subscribes when the state has moved on gets it
  through a 0 ms timer, so `onChange` never calls a listener or throws. The
  cursor line is padded to the cursor column in cells from the exported cell
  spans (`agent-activity.ts:127` `cellWidth`). `prompting` is not reported
  while the shell's line editor owns the line (`agent-activity.ts:67`): VS
  Code applies the patterns only while a command runs, and an idle
  `[~] $ ` prompt matches them. A pane without shell integration (Claude
  Code) has the line editor `unknown` and is checked as before.
- Listener failures: agent event and activity listeners each run isolated
  (`listener-failures.ts`); every listener gets every event, internal state
  settles first, and the failures are thrown together as an `AggregateError`
  afterwards, as `TerminalCore.notifyAll` already did. `feed()` and `tick()`
  run polling, activity and change notification whatever throws
  (`terminal-core.ts:200` `afterParse`).
- `readBlockOutput(id, { compact, maxLines })`: a block's logical lines;
  `compact` drops lines that are wholly a spinner frame (a spinner glyph,
  text, an ellipsis, an optional parenthesised status; `compact-output.ts:5`),
  blank runs, back-to-back repeats and a run of ≥ 3 non-blank lines that
  redraws the kept lines immediately before it, up to 256 lines
  (`compact-output.ts:49`). A run separated from its twin by a distinct line
  is kept (a later test's setup/run/teardown). Lossy by design and opt-in;
  redaction is not applied (renderer only). `maxLines` of 0 or less gives
  nothing, `Infinity` no cap, a fraction its floor (`compact-output.ts:64`).
- Measured (planning run, 2026-09-25): the Claude Code recordings replayed one
  frame per 100 ms (120, 157 and 1,048 frames) are `active` throughout and
  `idle` 1,500 ms after the last byte, `prompting` at none of 1,325 frame
  boundaries; compact keeps all 60,000 number lines of `claude-long-50k`
  (24.9–30.5 ms per call) and cuts `claude-markdown-reply` without agent-TUI
  mode from 101 to 88 lines. After the review fixes (2026-09-25) that cut is
  101 to 96 lines with 3 of the 4 banners kept: two of the banner frames are
  separated by the `⏵⏵ auto mode on` and `◐` lines, the same shape as a
  legitimate repeated run, so the redraw rule no longer drops them.
- Operator: nothing consumes these yet (user decision 2026-09-25). The mirror
  parses the events into its capped queue and drops them;
  `publishProgramLocked` (`ptyhost/program.go`) publishes only titles and
  notifications.
- References: VS Code (MIT) — `detectsHighConfidenceInputPattern` ported
  verbatim (`VSCODE-INPUT-PATTERNS-ATTRIBUTION.md`), polling behaviour
  followed. Warp (AGPL-3.0) — not read; the survey's description (§7.1) only.
- Guards: `crates/vt-core/tests/agent_events.rs` (vectors whole and byte by
  byte, history chunk, older answer byte by byte and inside a live event,
  replay frame, flood, boundary, sync block, live byte counter, recordings),
  `agent.rs` unit tests, `vt-wasm/tests/program_exports.rs`,
  `vtwasm/program_test.go` `TestAnAgentEventIsNeitherATitleNorANotificationInTheMirror`,
  `ts/core/src/agent-events.test.ts`, `agent-activity.test.ts` (incl. the three
  recordings and a hidden window's one-second drains), `compact-output.test.ts`,
  `block-output.test.ts`. Review fixes: `agent_events.rs`
  `a_replay_into_a_reused_core_is_neither_live_output_nor_an_event`,
  `a_replay_split_byte_by_byte_into_a_reused_core_is_not_live_output`,
  `an_origin_mark_after_rows_exist_silences_events_until_ready`; `scanner.rs`
  `open_osc_bytes_counts_the_sequence_in_flight`; `agent-activity.test.ts`
  (reconnect replay, late joiner, threshold timing, throwing listener, line
  editor ownership, wide-character padding, idle shell prompt);
  `agent-events.test.ts` "AgentEvents listener failures";
  `compact-output.test.ts` (whole-line spinner, separated runs, `maxLines`).

### 4.35 The parser rework — roadmap Plan 9
- **Part A: `vte::ansi::Handler` measured, not adopted (2026-09-26).** A
  scratch crate fed vte 0.15's `ansi::Processor` the sequences vt-core relies
  on. XTVERSION (`CSI > 0 q`), `CSI 16 t`, OSC 9/99/777/1/133/7000 and a bare
  `OSC 8 ;` reach no `Handler` method; SGR 53/55 are dropped, SGR 21 becomes
  cancel-bold, `38;5;300` is rejected, `4:6` becomes an underline; DECRQM
  passes one mode; `CSI b` (REP), `ESC Z` (DA1) and `ESC # 8` (DECALN) would
  start doing something, which changes `tests/ref/csi_rep` and
  `decaln_reset`; and `Processor::new` allocates a 2 MiB sync buffer per core
  (`vte-0.15.0/src/ansi.rs:39,261-264`). The `Processor` owns its parser and
  its `Performer` is private (`ansi.rs:425`), so nothing can be handled half
  by `Handler` and half by us. Dispatch stays on `vte::Perform`
  (`crates/vt-core/src/parser/perform.rs`). The `ansi` feature does not need
  `std` (vte's `Cargo.toml`: `ansi = ["log", "cursor-icon", "bitflags"]`), and
  vt-core must keep vte without `std`: the 1,024-byte OSC cap of §4.34 is the
  no-std buffer (`vte-0.15.0/src/lib.rs:46`).
- Guard for the whole plan: `crates/vt-core/tests/parser_goldens.rs` replays
  the 46 `tests/ref` recordings, the 3 Claude Code fixtures and 4 synthetic
  streams (`tests/golden_support/synthetic.rs`) in four configurations
  (renderer: grapheme mode, 4 KiB feeds; renderer with feeds of 1, 3, 7, 64,
  509 and 4,093 bytes in turn; mirror: scalar, no reflow, 20,000 rows /
  256 KiB, cold ring; agent-TUI mode with the odd feeds) and compares a
  digest of rows, styles, cell spans, wrapped flags, blocks, links, cursor,
  alternate screen, modes, title, notifications, agent events, query replies
  and every per-feed `Delta` with `tests/goldens/*.golden`, generated on the
  tree before the rework (`UPDATE_GOLDENS=1`). Regenerate only for a
  deliberate behaviour change, and name it in the commit.
- **Part B: printable runs and unknown sequences.** The parser buffers
  printable ASCII between control sequences (`Parser.run`, flushed before
  every other callback and at the end of every `advance_vte`, so a mark, an
  alternate-screen switch or a sync flush never sees bytes pending) and
  `ScreenGrid::print_ascii_run` (`crates/vt-core/src/screen/print.rs`) writes
  it a row segment at a time; `ScreenGrid::print` skips the width lookup and
  the grapheme join for ASCII after an ASCII cell (an ASCII scalar joins a
  cluster only after a `Prepend`, UAX #29 GB9b); `joins_previous` no longer
  allocates (`width.rs`). Ghostty's run decode (`src/terminal/stream.zig:599-720`)
  is the idea, not the code: vte owns the byte loop, so the batching happens
  on its `print` callbacks. `TerminalCore::unknown_sequences()` keeps the
  newest 64 distinct CSI/ESC/DCS/OSC that nothing handled
  (`parser/unknown.rs`; an OSC by its number only, never its payload; text
  ≤ 48 bytes; debugging only, also `WasmTerminalCore.unknown_sequences()`).
  The three Claude Code recordings leave `CSI <0u`, `CSI >4;2m`, `CSI >4m`,
  `CSI >5u`, `CSI ?0u`, `CSI ?2031h/l` and `ESC (B` in it.
- Review fixes (2026-09-26, after a differential fuzz of about 700k streams
  against the pre-Plan-9 core found no screen difference):
  the run buffer flushes at `RUN_FLUSH_BYTES` = 4 KiB and gives its memory
  back after an oversized flush (`parser/perform.rs`), so one 8 MiB line no
  longer pins 8 MiB per core (live heap 3,280 KiB against the old core's
  3,276 KiB, was 11,468 KiB); an OSC is recorded by its number only when it
  is 1–5 ASCII digits and as `OSC ?` otherwise, so `ESC ] L title` and other
  payload-first OSCs no longer leak their text; the ring formats into one
  reusable buffer, checks the newest entry first, and records at most
  `UNKNOWN_FEED_BUDGET` = 128 sequences per feed, so a flood of unknown
  sequences costs at most 0.59× (was 0.23×) of the pre-Plan-9 throughput and
  repeats no longer allocate; an ESC with intermediates (`ESC # 8` DECALN,
  `ESC ( 0`) is no longer dispatched to the screen: before, the screen
  ignored the intermediate and `ESC # 8` ran DECRC. Guards:
  `tests/unknown_sequences.rs` (payload, `ESC # 8`, flood budget),
  `parser/perform.rs` `run_tests`.
- Hazard for future work: charsets (`ESC ( 0`, SO/SI), insert mode
  (`CSI 4 h`), autowrap off (`CSI ? 7 l`) and origin mode are not implemented
  by the old or the new core. Whoever adds them must also gate the ASCII fast
  path (`Parser::print` buffering and `ScreenGrid::print_ascii_run`), or those
  modes will silently not apply to printable runs.
- Part B measured (`examples/parse_throughput.rs` and
  `bench/parse-throughput.mjs`, 3 alternated pairs, medians of 7, MB/s):
  - ascii-heavy grapheme: control 16.69-17.33 partB 31.91-32.50 (86.3% median) faster
  - ascii-heavy scalar: control 26.79-27.86 partB 32.59-33.97 (22.4% median) faster
  - claude-long-50k grapheme: control 22.94-23.12 partB 27.42-28.39 (19.9% median) faster
  - claude-long-50k scalar: control 45.54-46.08 partB 44.38-46.21 (-0.5% median) noise
  - edit-heavy grapheme: control 23.21-24.76 partB 45.80-47.46 (101.4% median) faster
  - edit-heavy scalar: control 37.96-41.60 partB 47.05-49.36 (20.9% median) faster
  - wasm claude-long-50k grapheme: control 15.96-16.58 partB 19.79-20.40 (23.2% median) faster
  - wasm claude-long-50k scalar: control 34.22-34.89 partB 33.61-35.00 (-0.5% median) noise
  - Environment: Linux x86_64, Intel(R) Xeon(R) Processor @ 2.10GHz
- Guards (Part B): `tests/print_run.rs` (a 512-case proptest against
  one-character-at-a-time printing, the `Prepend` join, runs split at every
  byte, a run before a boundary mark and before the alternate screen,
  invalid UTF-8, DEL), `tests/unknown_sequences.rs`, `vt-wasm`
  `program_exports.rs` `the_wasm_core_lists_unknown_sequences_with_their_counts`,
  and the goldens.
- **Part C: erase and insert on a row.** `screen/edit.rs` erases with one
  slice `fill` of the erase cell and inserts/deletes characters with one
  `rotate_right`/`rotate_left` of the row slice (`fill_cells`,
  `shift_cells`); `wrapped` is cleared exactly when the per-cell `set` used
  to clear it (an edit that reaches the last column, every ICH/DCH), and an
  empty span marks nothing dirty. Claude Code sends no ICH/DCH/ECH
  (`claude-long-50k`: 0 `@`, 0 `P`, 0 `X`, 32,808 `K`), so the gain is for
  shells and full-screen programs. **Row flags** after Ghostty
  (`src/terminal/page.zig:2020-2058`, behaviour only): a per-row
  `styled`/`grapheme` flag and a plain-row commit path in
  `scrollback::commit_row` were built and measured — no line faster beyond
  noise (numbers below) — so they are not applied.
  `hyperlink` would need no flag (the link id rides in `CellStyle.link`) and
  `wrapped` stays its own vector. The prototype's one bug (a prepended
  history chunk longer than `CHUNK_SIZE` underflowed a subtraction) was
  caught by `tests/older_seams.rs`.
- Part C measured (same method as Part B; bulk edits against Part B, then
  row flags against bulk edits):
  - claude-long-50k grapheme: partB 27.48-28.25 partC 27.28-30.75 (2.6% median) noise
  - claude-long-50k scalar: partB 44.02-45.42 partC 47.84-52.81 (8.9% median) faster
  - ascii-heavy grapheme: partB 30.15-32.89 partC 30.17-32.81 (2.5% median) noise
  - ascii-heavy scalar: partB 32.90-33.66 partC 31.08-32.25 (-5.3% median) noise
  - edit-heavy grapheme: partB 46.62-50.02 partC 62.26-65.12 (35.1% median) faster
  - edit-heavy scalar: partB 47.21-48.52 partC 63.00-67.46 (36.3% median) faster
  - wasm claude-long-50k grapheme: partB 20.15-21.10 partC 21.28-21.84 (5.2% median) faster
  - wasm claude-long-50k scalar: partB 34.92-35.90 partC 35.54-37.38 (1.4% median) noise
  - claude-long-50k grapheme: partC 28.27-30.29 flags 29.78-30.26 (4.9% median) noise
  - claude-long-50k scalar: partC 50.41-51.73 flags 50.75-52.42 (0.1% median) noise
  - ascii-heavy grapheme: partC 32.07-33.06 flags 31.59-32.40 (-3.2% median) noise
  - ascii-heavy scalar: partC 32.51-33.01 flags 30.96-32.46 (-2.4% median) noise
  - edit-heavy grapheme: partC 61.19-64.32 flags 62.68-64.73 (1.3% median) noise
  - edit-heavy scalar: partC 62.58-65.61 flags 63.13-64.54 (-1.9% median) noise
  - wasm claude-long-50k grapheme: partC 20.73-21.76 flags 20.78-21.33 (1.9% median) noise
  - wasm claude-long-50k scalar: partC 35.07-37.07 flags 34.06-36.83 (-2.6% median) noise
  - Environment: Linux x86_64, Intel(R) Xeon(R) Processor @ 2.10GHz
- Guards (Part C): `tests/bulk_edits.rs` (passes on the tree before Part C
  too), `synthetic-edits-styled` in the goldens.

### 4.36 A shell prompt copied into scrollback on every resize — roadmap Plan 10
- Symptom: with a visible prompt, every resize at the prompt left one stale copy
  of it in scrollback, and a prompt taller than one row left its upper rows too.
  Replaying 15 captured zsh 5.9 / bash 3.2 / bash 5.3 sessions with four resizes
  each ended with 5 copies of the prompt. Operator's own shell panes suppress the
  prompt (`backend/internal/service/shellterm/service.go:439`
  `SuppressPrompt: true`), so there the row is empty and nothing showed.
- Cause: the shell-mode resize evicted the whole frame, prompt included, and
  restarted the screen with the cursor at (0,0). The shells redraw relative to
  where they drew: measured 2026-09-26, zsh moves up by the rows its prompt and
  buffer took at the **old** width minus one, clears (`ESC[J`) and redraws; bash
  redraws only its last prompt line (moving up only within it); fish 4.8.1
  writes nothing on a width change and, on the next key, moves up by its old
  prompt height and repaints. Clamped at row 0, the redraw drew a second prompt.
- Now: while the line editor is `Owned`, on the primary screen, in a core that
  reflows on resize, `Parser::resize_for` (`crates/vt-core/src/parser/resize.rs:28`)
  keeps the prompt: the rows above the open block's first row go to scrollback
  and rewrap there like any evicted row (§4.2–4.4); the rows from the prompt
  start to the cursor's last row stay unrewrapped — cut at the new width (a wide
  character cut in half becomes a blank) or padded — with the cursor at the same
  row offset and column (`ScreenGrid::resize_keeping_prompt`,
  `crates/vt-core/src/screen/prompt.rs:4`). Kitty's "keep the current prompt from
  rewrapping" (survey §5.4; GPL-3.0, clean-room from the survey's description,
  not read), chosen over Ghostty's reflow-then-clear (`Screen.zig:2232-2290`,
  behaviour only): a reflowed prompt changes its row count, so the shells'
  old-width up-moves land mid-prompt (narrower) or in the output above it
  (wider — zsh's `ESC[J` then erases output rows), and fish would show a blank
  prompt until the next key. Then `Parser::pull_back` (`parser/resize.rs:76`)
  moves the newest scrollback rows back onto the top of the screen so the
  prompt keeps its distance from the bottom (Alacritty `grow_lines`/`shrink_lines`,
  Ghostty `pull_scrollback`; behaviour only), but only rows that commit back to
  the same bytes and style runs (`Parser::row_cells`, `parser/resize.rs:116`,
  commits them into a scratch buffer and compares; `Content::truncate_to`
  `content.rs:143`, `AttributeMap::truncate_to` `attribute_map.rs:72`,
  `RowIndex::pop_completed` `row_index.rs:434`). When no style key is left
  below the cut, `AttributeMap::truncate_to` takes the content's first byte
  as the start of its last run (`attribute_map.rs:77`): the map's base would
  let the next style change restyle an older-output chunk still resident
  below it, and 0 added a key that covers no byte. Flat and stable row numbers
  never change, so blocks, the scroll anchor and the older-output floor are
  untouched.
- The prompt is kept only when that loses nothing the shell will not redraw
  (review fix, branch `fix/plan-10-review`). Before, the kept region ran from
  the prompt start to the lowest row the cursor reached and every row in it
  was cut at the new width, so output printed below an owned prompt (a
  background job) was cut for good: at 10×5, `$ ` then `line0-abcd` resized to
  5 and back came back as `line0`. And when the open block's first row had
  scrolled into scrollback the prompt start became row 0, so the whole screen
  was kept and cut. A line soft-wrapped into the prompt row
  (`0123456789abc` then the prompt at 10 columns) went to scrollback as a
  wrapped row, which the rewrap ends as a line, so it lost its join after a
  width change. Now the resize takes the old path (evict the frame, rewrap)
  when the open block's first row is in scrollback
  (`parser/resize.rs:51-53`), when the row above the prompt start soft-wraps
  into it (`screen/prompt.rs:22`), or when a kept row below the shell's own
  rows would lose a non-blank cell or a wide character at the cut
  (`screen/prompt.rs:25-31`, `row_loses_cells` `:77`). The shell's own rows
  are the prompt start down to the row where `input-ready` arrived
  (`Parser::note_input_ready`, `parser/blocks.rs:68`, stored as an offset from
  the open block's first row with the block's id, read at
  `parser/resize.rs:57-60`) and that row's soft-wrapped continuations (the
  typed line); zsh redraws all of them and bash its last line, so those may
  still be cut (the bash case below). The literal rule — every kept row
  lossless — was tried first and broke four Plan 10 tests
  (`a_narrower_window_keeps_a_two_line_prompt_where_zsh_redraws_it`,
  `bash_redraws_only_the_last_prompt_line_and_the_first_stays_in_place`,
  `a_wide_character_cut_by_a_narrower_prompt_row_is_blanked_whole`,
  `the_cursor_keeps_its_place_in_the_prompt`): it gives back a stale prompt
  copy whenever a prompt line is wider than the new window. The two cell
  copies in `screen/prompt.rs` are element loops, not `clone_from_slice`: a
  second caller of the slice clone stopped it inlining into `blank_row` and
  `fill_cells` and cost the native parser 7–16 % (claude-long-50k scalar
  68.22–69.01 → 73.98–74.42 MB/s, edit-heavy scalar 70.12–70.36 →
  83.63–83.68 MB/s against `bef8a00ec`, 3 alternated pairs, medians of 7,
  Apple M1 Max; against the pre-Plan-10 tree `1763df9e8` the rows are within
  −3.9 % to +3.4 %).
- Content byte offsets are reusable. Before this plan they were reused in one
  place only: `Parser::apply_history_chunk` trims the content front to the
  first row and prepends below it (`parser/history.rs:43-44`), so an older
  chunk loaded after a front trim lands on offsets that trimmed rows used.
  A find session whose scanned range covered them treated the loaded rows as
  already searched (row cap 10, 20 lines, a finished find, 3 more lines, a
  2-row chunk: 0 hits against 2 for a fresh session); `Content` now counts
  prepends (`content.rs:60`, `prepends()` `:183`) and `FindSession::update`
  rescans history when the count moved (`find.rs:195-207`), the same full
  rescan a prepend below the scanned range always caused.
  `Content::truncate_to` lets the next push reuse offsets of pulled-back
  rows. Two things relied on offsets not being reused and were fixed (review fix 75baad0):
  `AttributeMap::prepend_runs` raises `run_start` past the runs it prepends
  (`crates/vt-core/src/attribute_map.rs:31-33`) — without it an older-output
  chunk loaded after a full pull-back lost the style of its last run at the
  next style change; and `Content` counts reuses and keeps, for each count,
  the lowest cut made since it (`Content::note_reuse` `content.rs:158` keeps
  `(count, cut)` pairs with rising cuts, dropping any older pair a new lower
  cut covers, and merging the pairs whose cut a front trim has passed into
  one with the oldest cut and the newest count, `content.rs:164-170`; every
  count answered by a merged pair still gets a cut below all resident bytes,
  so a find session rescans all of history as before; `lowest_cut_since`
  `content.rs:178`, `truncations()` `content.rs:187`). Those rules alone did
  not bound the list: every counted pull-back at a higher offset than the last
  adds a pair, and 20,000 command-and-grow cycles at the default limits left
  26,661 pairs, still growing. Past `MAX_CUTS` = 1,024 pairs
  (`content.rs:4`, `:171-175`) the list collapses to one pair with the newest
  count and the lowest cut, so a session older than the collapse rescans from
  that cut — a longer rescan, never a wrong hit. When the count moved since its last update,
  `FindSession::update` drops only the history hits that end after the start
  of the line holding that cut, and rescans from there
  (`crates/vt-core/src/find.rs:187-193`, `line_start` `find.rs:343`; the
  line start, not the cut, because a pulled row can be the continuation of a
  soft-wrapped line and a match must not start mid-line; the row holding the
  cut is the first whose end is past it, because a later rewrap can leave a
  cut mid-row, and taking the first row starting at or after it skipped the
  rest of that row) — without it pulled
  rows rewritten before the next find update left hits pointing at the new
  text. Review fix 75baad0 dropped and rescanned all history instead, so
  dragging the window taller with the find bar open reset a long history on
  every step and it never finished scanning. Only a pull-back that cuts below
  the content end from before the resize counts (`parser/resize.rs:48`,
  `:101-104`): every resize
  at a prompt evicts the rows above it and usually pulls those same
  just-appended bytes back, and counting that reset an open find session on
  every width change (dragging the window with the find bar open made the hit
  count flicker and a long history never finished scanning). A find session
  only ever scanned bytes that existed before the resize, so a cut at or above
  that end reuses nothing it saw. Growing the window pulls pre-existing
  scrollback rows back, so it counts; the session keeps every hit above the
  pulled rows and scans nothing new (the pulled rows are screen rows now,
  searched with the screen). Whether any other
  reader keys state by content offset across a pull-back is not known.
- Unchanged: a command running, the alternate screen, no shell integration
  (every Claude Code pane), agent-TUI mode, and the pty-host mirror (reflow off,
  `crates/vt-host/src/lib.rs:39`) take the old path — `tests/resize_goldens.rs`
  (12 streams generated before this change) and `tests/parser_goldens.rs` are
  unchanged and `bench:feel` has zero diff.
- Not covered: bash's upper prompt lines stay cut at a narrower width (bash
  redraws only its last line; xterm behaves the same); a prompt region taller
  than the new screen takes the old path, and so do a prompt whose start
  scrolled into scrollback, a line soft-wrapped into the prompt row and output
  below the prompt that the new width would cut (each leaves a stale prompt
  copy in scrollback, as before Plan 10); the pull-back stops at the first row
  that would not restore exactly (a word-cut continuation, a hanging indent, a
  trailing blank), so the prompt can sit higher on the screen than before (not
  visible in the pane); Windows ConPTY repaints its own viewport after a resize
  — whether a Git Bash pane there looks better or worse is not known. The
  pre-existing blank before a wide character that the printer wrapped still
  commits as a space (`abcd中` printed at 5 columns rewraps as `abcd 中`).
- Guards: `crates/vt-core/tests/prompt_resize.rs` (20 tests, built from the
  shells' captured bytes, including
  `an_older_output_chunk_keeps_its_styles_after_a_prompt_resize_pulled_every_row_back`),
  `tests/prompt_resize_find.rs` (5 tests:
  `find_hits_stay_on_their_text_when_pulled_rows_are_rewritten_before_the_next_update`,
  `a_prompt_resize_keeps_a_finished_find_session_without_rescanning`,
  `a_taller_prompt_resize_keeps_the_find_hits_below_the_pulled_rows` and
  `find_hits_after_a_cut_that_a_rewrap_moved_mid_row_are_rescanned`),
  `tests/prompt_resize_fallback.rs`
  (`output_below_an_owned_prompt_survives_a_narrower_resize`, its
  background-output variant, `a_line_soft_wrapped_into_the_prompt_row_stays_joined`
  and `a_typed_command_soft_wrapped_below_the_prompt_is_still_kept_in_place`;
  the first three pass on `1763df9e8`), `tests/find_history_seams.rs`
  (`a_history_chunk_prepended_after_a_front_trim_is_searched`,
  `a_find_session_stays_exact_after_more_prompt_resizes_than_the_cut_list_holds`),
  `tests/prompt_resize_integrity.rs` (32 seeds × 300 steps, `verify_integrity`
  and cell spans after every step, ≥ 200 resizes at a prompt),
  `tests/resize_goldens.rs`, `content.rs`/`attribute_map.rs`/`row_index` unit
  tests (among them
  `runs_prepended_after_a_full_truncation_survive_a_style_change_at_the_seam`,
  `the_lowest_cut_since_a_count_covers_every_later_reuse_only`,
  `the_cut_list_stays_bounded_over_alternating_cuts_and_front_trims`,
  `the_cut_list_never_holds_more_than_its_cap_and_never_answers_too_high`,
  `a_full_truncation_to_the_first_byte_adds_no_key_at_the_next_style_change`
  and `a_full_truncation_above_prepended_bytes_keeps_their_style`), the
  `find.rs` unit test `a_cut_inside_a_soft_wrapped_line_rescans_from_the_line_start`,
  `block_grid` `open_block_ref_is_the_open_block_and_nothing_after_it_closes`,
  `shell/{zsh,bash,fish}.test.mjs` "after a width change …". Those shell tests
  pass on macOS (planning: zsh 5.9, bash 3.2 and 5.3, fish 4.8.1, tmux 3.6b)
  and on Linux (zsh 5.9, bash 5.2.21, fish 4.8.1, tmux 3.4); the redraw bytes
  above were captured on macOS only.

### 4.37 A wide character cut in half by an overwrite or an edit
- **Symptom (before 2026-09-26):** a character printed over one half of a
  wide character left the other half behind. At 4 columns `日日\x1b[1;2H日`
  left the cells `日 日 \0 \0`, and `row_cell_spans` reported a span 3 cells
  wide. A narrow character over a lead kept the orphaned continuation, and a
  narrow character over a continuation kept a one-cell lead that the next
  cell overlapped. Found by a review fuzz of Plan 10; it predates Plan 10.
  The edit commands did the same: at 6 columns `日日` then `CUP(1;3)` and
  `DCH` left a span 3 cells wide, `a日日` then `CUP(1;2)` and `ECH` left a
  space 2 cells wide, `a日b` then `CUP(1;3)` and `ICH` moved a continuation
  away from its lead, and `EL`/`ED` from or up to a continuation did too.
- **Now:** no span is wider than two cells. `ScreenGrid::clear_split_wide`
  (`crates/vt-core/src/screen/print.rs:93`) runs before every write that can
  split a wide character: `print` (`:31`), `print_ascii_run` (`:58`),
  `put_ascii` (`:80`) and the grapheme widening in `join_previous` (`:161`).
  It only reads the two cells at the edges of the write; the blanking and
  the erase cell are built in the cold `blank_split_wide` (`:102`) only when
  one of them is a continuation.
  A lead whose continuation is overwritten, and every continuation after the
  written cells, become erased cells with the current background (xterm and
  Ghostty behaviour; no code taken). The row's wrapped flag is kept.
  The edit commands run it on the cells they remove, before they move or
  fill anything (`crates/vt-core/src/screen/edit.rs`): `EL` 0/1, `ED` 0/1 on
  the cursor row and `ECH` through `erase_cells` (`:17`, called at `:42`,
  `:51`, `:90`, `:91`, `:125`), `DCH` on the deleted cells (`:116`), and `ICH`
  at the cursor and at the first cell pushed off the right edge (`:103-104`).
  A wide character any of them cuts in half becomes blanks with the current
  erase background (xterm and Ghostty behaviour; no code taken).
- **Goldens re-recorded deliberately** (the one change of that kind on the
  Plan 10 branch): for the print paths, `synthetic-unicode-mix`,
  `synthetic-edits-styled` and `resize-running-3` had recorded the split
  halves (spans up to 4 cells wide in the first two when fed in 64-byte
  chunks). For the edit commands, `synthetic-edits-styled`,
  `resize-no-integration-1` and `resize-running-1`: replayed with the edit
  blanking switched off they match the old goldens exactly, and they are the
  only streams in which an edit cut a wide character (63 edits in
  `synthetic-edits-styled`: 28 `EL`, 18 `ECH`, 9 `ICH`, 8 `ED`; 6 `EL` in
  each of the other two; none in the other 62 streams). No other golden
  changed.
- **A resize that truncates rows** (review fix, branch `fix/plan-10-review`):
  `resize_cells` — the pty-host mirror, agent-TUI mode, the alternate screen
  and any resize with a scroll region set (`record_eviction` records nothing
  then, `crates/vt-core/src/screen.rs:179`) — cut each row at the new width
  and kept a wide lead whose continuation fell past it. The row then measured
  one cell wider than the pane, and the scrollback rewrap split the half
  character onto a row of its own. It is now blanked like the prompt path's
  cut (`crates/vt-core/src/screen/resize.rs:66-71`, a default blank as in
  `screen/prompt.rs:48-53`). Synthetic goldens re-recorded deliberately:
  `resize-no-integration-1`/`-2`/`-3`, `resize-running-1`/`-2`/`-3`,
  `resize-alt-screen-1`/`-2`/`-3` and `resize-at-prompt-mirror-agent-1` (24
  `mirror` and 24 `agent-odd` digest lines, the `renderer` and
  `renderer-odd` lines of `resize-alt-screen-1`). Replayed with the blanking
  switched off they match the old goldens exactly, and they are the only
  streams in which a resize cut a wide character (2 to 10 cuts each; none in
  `resize-at-prompt-mirror-agent-2`/`-3` or in any of the 53 parser golden
  streams — the 46 `tests/ref` recordings and the 3 Claude Code fixtures
  among them — which are unchanged). In `resize-running-2` the mirror's whole
  text differs in one place: `link👍` no longer wraps onto a row holding only
  the half-cut `🏽` (2,502 → 2,501 rows). Guard: `tests/resize_wide_edge.rs`
  (mirror in both width modes, agent-TUI, scroll region, alternate screen).
- Guards: `crates/vt-core/tests/cell_spans.rs:114-189` (seven print tests)
  and `:191-334` (five edit tests and
  `no_mix_of_prints_moves_and_edits_leaves_a_span_wider_than_two_cells`,
  300 seeds of prints, cursor moves, `ICH`/`DCH`/`ECH`/`EL`/`ED`/`IL`/`DL`),
  both width modes, each through `common::check`.

### 4.38 A killed pty-host blocked Restore with a 500 (real-app run, 2026-09-26)
- Symptom: after a session's pty-host was killed (`kill -KILL`),
  `POST /api/v1/sessions/{id}/restore` answered 500 `INTERNAL_ERROR`.
- Cause: the reaper sees a refused dial (`client.go:297`), and the session is
  terminated, but nothing called `Destroy`, so the dead `hostSession` stayed in
  `Runtime.sessions` and the relaunch's `Runtime.Create`
  (`session_manager/manager.go:1510`) was refused as "already exists"; the plain
  error had no `toAPIError` mapping.
- Now: `Create` first checks an existing entry; if its pid is gone or its address
  refuses connections it drops the entry and its registry row (`forgetHost`,
  shared with `Destroy`) and starts a fresh host. The history file is kept, so the
  new host replays it (§4.29). A live, hung or in-flight duplicate still fails,
  wrapping `ports.ErrRuntimeSessionExists` (409 `TERMINAL_HOST_RUNNING`).
- Guards: `ptyhost/runtime_dead_host_test.go`,
  `session_manager/restore_dead_host_integration_test.go` (real pty-host, SIGKILL,
  then Restore), `service/session` `TestToAPIErrorMapsWorkspaceBranchSentinels`.

### 4.39 A reopened shell pane showed every finished command twice (real-app run, 2026-09-26)
- Symptom: a shell pane opened in a second window or after a reload drew the
  durable blocks, then one header-less block repeating the same history as raw
  text, then the live prompt. A shell with no finished command was fine.
- Cause: `TerminalPane` holds the attach until `useShellTerminalBlocks` loads and
  `BlockTerminal.feedHistory` writes the durable blocks into the core. The attach
  replay is the mirror's grid of up to 1,000 rows (`vt_replay`) with no block
  marks; `Parser::adopt_origin` refuses its origin on a core that already has rows,
  so it lands below the durable blocks as one synthetic block.
- Now: `vt_replay` brackets the settled rows (up to the end of the last finished,
  non-synthetic block, never the last row) with `OSC 7000;v=1;settled=begin ST` /
  `settled=end ST`; `BlockTerminal` drops the bracketed rows through
  `lib/settled-replay-filter.ts` only when it fed durable history. The filter
  survives any transport split and stops dropping at the next `origin=`/`ready=`
  if a frame was cut. Other clients ignore the key.
- Limits: a command that finishes between the blocks fetch and the attach shows
  on the next reload, not this one; output before the first prompt is not
  replayed on a seeded attach.
- Guards: `vtwasm/settled_test.go`; `lib/settled-replay-filter.test.ts`
  (including a real-core case with the host's replay bytes); `BlockTerminal.test.tsx`
  "drops the replay's settled rows after durable history…" and "keeps every
  replayed row when there was no durable history…".

### 4.40 Find bar: Ctrl+F typed ^F, clicks left the find field, no reveal (real-app run, 2026-09-26)
- Ctrl+F opened the find bar **and** sent `\x06`: the next command ran as
  `^Fsleep`. A bubbling `document` keydown matched `metaKey || ctrlKey` after the
  line editor had sent the key. Now `isFindChord` (`ts/react/src/selection-gesture.ts`)
  is Cmd+F on macOS and Ctrl+Shift+F elsewhere, caught in the capture phase with
  `preventDefault` + `stopPropagation`; plain Ctrl+F reaches the shell.
- Clicking the find input or its `.*` toggle moved focus to the line editor: the
  find bar is mounted in the host, whose `onClick` focused the editor. Now the
  host ignores clicks inside `OWNS_FOCUS` (the find bar and editable controls,
  `surface-geometry.ts`); presses on host chrome are not mouse-reported, and keys
  or pastes in the find input never reach a full-screen program.
- Typing a query showed "1 of N" without scrolling to it. `find-bar.ts` now
  reveals the current hit when a query first finds something (typed, or the first
  match arriving later); later streaming hits never move the view (§4.28).
- Guards: `ts/react/src/TerminalSurface.find.test.tsx` ("find shortcut", "find bar
  focus"); `find-bar.incremental.test.ts` "reveals the current match as the query
  is typed…" and "reveals the first match that arrives after the query…".

## 5. Known gaps (not bugs, decisions pending)

- **A prompt resize that would cut output falls back to the stale-copy
  path.** Since the Plan 10 review (§4.36), a resize at an owned prompt keeps
  the prompt only when no row below the shell's own rows loses a cell; output
  printed below the prompt that the new width would cut, a prompt start in
  scrollback, or a line soft-wrapped into the prompt row send the frame to
  scrollback as before Plan 10, and the shell's redraw leaves one stale prompt
  copy there. The shell's own rows end at the row where `input-ready` arrived;
  fish sends `input-ready` before its `133;A` (`docs/superpowers/plans/2026-09-26-terminal-plan-10-shell-resize.md:36`), so for fish only the first prompt row and its soft wraps
  count, and a two-line fish prompt whose second line is wider than the new
  window falls back. Rewrapping only the output rows while keeping the prompt
  in place would avoid both; not built.
- **Find exports every hit on every change.** `findResults` copies all hits
  out of wasm whenever an update adds or removes one; while Claude streams, a
  query with hundreds of thousands of hits (a single letter) pays that per
  paint. Hits paint through the highlight model since Plan 5 (§4.31) but still
  as whole rows, not the hit's cells, and there is no host `onResultsChanged`
  (survey §3.12).
- **SGR attributes render by default since 2026-09-23.**
  `RendererFeatures.attributes` defaults to `"warp"` (italic, underline in 5
  styles, SGR 58 colour, strike, overline, hidden, blink); `"plain"` keeps
  only bold and dim (`row-builder.ts:75-80`) and is what
  `baselines/*/feature-attributes_plain/` shows. Evidence
  (`bench/agent-session/fixtures/claude-markdown-reply`, a markdown reply, a
  diff and a Bash call from Claude Code v2.1.280): italic 5 emissions, bold
  18, dim 6, and no underline, strike, inverse, blink, hidden, overline or
  SGR 58; the older two recordings carry none of the new set. On every
  Claude Code recording the flip changes exactly two words, both italic
  (`claude-markdown-reply` offset-0). The underline, strike, overline and
  hidden paths are exercised only by `glyph-probe` and unit tests. An
  underlined trailing blank is still trimmed from the export. The cursor
  flags stayed off: `cursorContrast` changes 0 px on every Claude Code
  recording (the input cursor sits on the default background), and
  `cursorHollowUnfocused` was not chosen.
  `styles.json` covers no blink/overline case because Alacritty's reference
  cell flags have none to record. In both width modes a zero-width scalar
  after a space now rewraps with the space instead of starting a new row
  (Task 5).
- **Renderer and mirror wasm memory grew with the five-word style run.** At
  the 60k-row fixture the renderer core heap reads ~11.4 MiB against ~8.9 MiB
  on the pre-Plan-D tree measured the same way (mirror at `mirrorLimits`
  ~11.25 MiB against ~9.19 MiB). The style-run *count* is identical (260
  `AttributeMap` entries); the cost is the 5/3 stride on 60k exported runs,
  `Vec` growth, the 16-byte `CellStyle`, and the Unicode 17 segmentation
  tables in `vt_host.wasm` (250 → 306 KB). Far under the 128 MiB budget. A
  larger jump than this is a fragmentation bug — see §4.22 for the one that
  put it at 14 MiB.
- **`widthCache` corrects toward the core's cell widths, so it needs
  `graphemes`; both default on since 2026-09-22.** With `graphemes` off the
  core lays an emoji sequence out in scalar-mode cells (`❤️` one cell, a ZWJ
  family three two-cell clusters) and `widthCache` faithfully squeezes the
  glyphs into those cells (`letter-spacing: -10px` on the heart; the glyph
  probe's `seq:` row goes from -37.92 to -50.89 px). With both on the row
  lands at +0.27 px
  (`bench/agent-session/baselines/glyph-probe/EVIDENCE-graphemes_widthCache.json`).
  Chromium shapes a ZWJ sequence across the per-cluster spans (the follow-on
  spans measure 0 px), so the split is not the cause; the target widths are.
  The gap is now only a host that passes `widthCache: true` with
  `graphemes: false` explicitly — never do that. On the Claude Code
  recordings the flip moves exactly two kinds of row: text after `⎿` 6 px
  left onto the grid, and the `⏵⏵ auto mode on` row 2 px right
  (`baselines/*/feature-graphemes_false_widthCache_false/diff-offset-*.png`). The cost
  is one `[data-terminal-width]` span per corrected cluster: spinner DOM
  nodes per paint 73.11 → 75.98, row nodes per paint unchanged.
- **The pty-host mirror stays in scalar width mode while the renderer runs
  in grapheme mode.** Its `clip_row` clips by `char`, not by grapheme
  cluster, and its cursor column is a scalar-mode column. The attach replay
  (`vt_replay`) re-sends every row as text, so the receiving core re-lays the
  text out in its own mode and the rows come out right; only two things
  carry a scalar-mode column across: the cursor, placed with `\r` + `CSI n
  C` from the mirror's column, and text a child placed with a cursor move
  after a mode-dependent cluster (VS16, ZWJ, emoji modifier, flag pair —
  single-scalar emoji like `🚀` and every CJK character are the same width
  in both modes). Measured 2026-09-22 by feeding the Go mirror, replaying it
  into a fresh grapheme-mode core and comparing with the same bytes fed
  directly: `claude-spinner-10s` and `claude-long-50k` — 0 differing rows
  (27 and 40 compared) and the same cursor, because Claude Code's output
  carries no mode-dependent cluster; a prompt the child positions with
  `CSI C` after `❤️` — identical; a line printed with `❤️`, a ZWJ family,
  `👋🏽` and `🇪🇬` and the cursor left where printing put it — rows
  identical, cursor 5 columns right of where it should be (46 vs 41);
  `> ❤️ ab` then `\r CSI 7 C X` — the replay shows `> ❤️ ab X` where the
  live pane showed `> ❤️ abX`. Both last until the child next rewrites that
  line or moves the cursor, which Claude Code does on every Ink frame. So:
  invisible for Claude Code as recorded; visible, one reopen at a time, for
  a shell prompt that ends in an emoji sequence. The fix, if it ever
  matters, is the mirror in grapheme mode, not a renderer-side correction.
- **The pending manual Japanese-IME check.** Task 9's IME composition work
  (the underlined marked-text view, the settled-value single-send fix) has
  not yet been manually verified with a real macOS Japanese IME by a human;
  this must be done before the feature is considered fully verified.
- A DEC 2026 block that grows to `SYNC_BUFFER_CAP` (2 MiB) is flushed and
  parsed in one `feed` inside whatever frame receives it, bypassing the 12 ms
  `drain` budget: a burst of ~60 ms on this machine. Claude Code frames are
  kilobytes, so it needs a misbehaving program; lowering the cap or splitting
  the flush across frames is the fix if it ever shows.

- **Closed by Plan E Task 1:** the renderer's copy path now joins a
  soft-wrapped line into one line (`selectedText`, via `TextRows.rowWrapped`
  and `logicalLineAt`). `readBlockOutput`/`vt_render` on the HOST side still
  join with `\n` — that path reads the block-output buffer directly, not
  through the renderer's stable-row `TextRows`, so Task 1's join does not
  reach it; a soft-wrapped line in a slash-output or an agent-handoff tail
  still shows as several lines.
- **The OSC 8 registry sits outside `Limits { bytes }` and is never
  reclaimed.** `Parser::trim_to` weighs `content.resident_bytes() +
  styles.byte_len()` only (`parser/history.rs:91`) and `memory_stats` reports the
  same two, so `HyperlinkRegistry` is neither counted nor trimmed.
  `HyperlinkRegistry` stores each interned URI twice (the `by_link:
  HashMap<Hyperlink, LinkId>` key and the `by_id: Vec<Hyperlink>` element), so
  the caps (`MAX_DISTINCT_ENTRIES = 4096`, `MAX_URI_BYTES = 2083`) permit a
  core to hold up to ~17 MB of interned URIs (2 × 4096 × 2083 B) above its 128
  MiB budget for its lifetime, before `HashMap` overhead — reachable only by
  a program printing 4096 distinct maximal URIs. Measured on
  `claude-long-50k` (no OSC 8): empty. Warp's own trade
  (`hyperlink_registry.rs:11-15`), not an oversight here.
- **The hint rule set is the package's constant; a host cannot replace it
  yet.** `DomBlockRenderer.hintBegin(rules?)` accepts one rule list per call,
  but nothing plumbs a host-supplied list through `TerminalSurface` — Operator
  always gets `DEFAULT_HINT_RULES`. Revisit if a host ever needs its own
  patterns (a `HostCapabilities.hintRules?` seam, most likely).
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
  (`parser/history.rs:48`), so a later width change cannot rejoin a logical line the
  mirror had soft-wrapped — those rows rewrap as independent lines. Rows the
  pane produces *after* the reopen are unaffected. Carrying the flag would
  mean emitting wrapped rows without `\r\n` and sizing the receiver's scratch
  screen to the mirror's width (a `cols=<n>` field on the chunk mark), which
  would make the chunk's row count depend on the receiver's own wrapping
  instead of on the mark's `count` — the invariant `HistoryReceiver::consume`
  ends a chunk on. Revisit with a second anchor for that invariant; do not
  "fix" it by loosening the row count.
- **A masked secret (Task 8) is unmasked to assistive tech.** `maskedTextRows`
  only changes what `TextRows.rowText` returns to the copy path, the
  linkifier, hint mode and the block-output source; the row DOM itself is
  never rewritten, so a screen reader or the accessibility tree still reads
  the original token. The mask is a paint (`.terminal-redaction`) plus a read
  transform, not a redaction of the rendered cells.
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
- **A second frame-count wait lived in `feedAll`/`feedUntilRows` — fixed
  2026-09-23.** `bench:agent:scroll` failed 2 of 20 runs with `scrolling
  reached 59908 of 60134 rows` (2235 steps against 2245). Headless Chromium
  fires animation frames every ~8.3 ms, so the renderer paints every other
  frame; `feedAll` waited one frame after the last feed and then
  `DomBenchmarkRenderer.waitForPaint`, which resolves one frame after *any*
  paint since it last looked (`bench/adapters/dom.ts:123-127`) — an earlier
  chunk's paint. When both frames fell under 16.42 ms of the previous paint
  (15.1, 15.8, 16.0 ms in the failing traces) the last chunk was unpainted:
  the DOM's last row 59852 of 60133 and `scrollHeight` 4720 px short, so the
  walk started ten steps low and never saw the tail. Probe: 5 of 50 short
  before, 0 of 30 after. `feedWhile` now waits on the paint counter from
  before the last feed (`paintSince`), like `paintAfter`.
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
  `write_block_open`/`write_block_close` (`crates/vt-host/src/block_marks.rs`) emit a
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
    `Parser::esc_dispatch` (`crates/vt-core/src/parser/perform.rs:78`) discards
    `intermediates`, and `ScreenGrid::esc` (`crates/vt-core/src/screen/dispatch.rs:73`)
    has no `#`/`8` arm. Corpus: `decaln_reset`, `vttest_cursor_movement_1`.
  - `ESC ( 0` / `ESC ( B` (G0 charset designation, DEC Special Graphics line
    drawing) is never dispatched, for the same reason — intermediates are
    discarded before `esc()` sees them. Corpus: `saved_cursor`, `saved_cursor_alt`.
  - `CSI ?3h`/`?3l` (DECCOLM, 80/132-column switch) is not in
    `Parser::note_private_mode` (`crates/vt-core/src/parser.rs:312`), so the
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
- **The phone has no predictive local echo.** Survey §4.2's server-owned model
  was the only route to one and is not being pursued (dropped 2026-09-22,
  `docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md`
  "Why not pursued"). Part 6's predictive echo is a renderer-only dim overlay in
  `ts/renderer-dom`; the Flutter client draws with its own vendored fork
  (`packages/mobile/packages/xterm`) and never loads that renderer. It also
  would not help the case it was proposed for: the mobile composer is already
  local echo (text sits in a Flutter field and goes as one payload on send,
  `packages/mobile/lib/feature/terminal/logic/send_route.dart:20-21`), and the
  wait after send is Claude's turn — measured 2026-09-22 at 1.07–1.57 s
  (median 1.24 s) for the cheapest possible prompt against a 111.7 ms median
  keystroke round trip (146.8 ms p95) over the daemon's public tunnel and
  6.7 ms on loopback
  (`docs/superpowers/specs/2026-09-22-remote-typing-latency-measurement.md`,
  reproduce with `scripts/measure-remote-typing-latency.mjs`). Per-keystroke
  lag on mobile is real only in the raw terminal pane and the key row
  (`terminal_cubit.dart:99`, `:281-283`). The desktop renderer **does** have a
  predictive echo as of Plan F (default off, armed only above a host RTT
  threshold — the desktop-against-remote-daemon case the user confirmed they
  use). Operator switches it on from Settings → General, "Show typing
  instantly on slow connections" (`terminalPredictiveEcho` in `ui-store.ts`,
  off by default, stored under `opr.terminal.predictiveEcho`), which makes
  `BlockTerminal` pass a 30 ms threshold
  (`frontend/src/renderer/lib/terminal-predictive-echo.ts`). Once on it
  gates itself: a loopback daemon measures ~7 ms and never arms. The route to the same thing on the phone is the shared renderer
  that `docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md`
  designs. **Do not build a second prediction implementation in the Dart
  fork** — that is the fork §4.2 exists to delete.
- **Claude Code runs on the primary screen, not the alternate screen.** Both
  real recordings (`bench/agent-session/fixtures/claude-spinner-10s`,
  `claude-long-50k`) contain zero `ESC[?1049h`/`?47h`/`?1047h`; its prompt is
  an inline Ink frame, which is also why §4.8 and §4.10 exist. Plan F was
  specced on the opposite premise and its first build hooked predictive echo
  only into the alternate screen's key handler, so it never fired for Claude
  Code while every test (all of which mounted an alt surface) passed. Keys
  for a child that owns the line on the primary screen go
  `LineEditor.passthrough` → `EditorHost.sendRaw`; anything that must see a
  Claude Code keystroke hooks there (`EditorHost.beforePassthrough`). Guard:
  `TerminalSurface.test.tsx` "keeps Claude Code on the primary screen…" feeds
  the recording and asserts `altScreen` stays null.

- **Hung detection covers session terminals only, and the board shows
  nothing.** The reaper probes session rows (`reaper.go:143-166`), so a
  standalone shell or a reviewer terminal is never marked hung; the hung state
  lives in daemon memory and reaches only the pane (`ch:"terminal"` health
  frames). A board badge needs a read-time runtime join in `SessionView` and a
  push trigger; not built (roadmap Plan 4, decision D6).
- **Every liveness probe renders a full attach replay.** A status probe is a
  new connection, and `handleConn` renders `replayFrameLocked` under `h.mu`
  for it before answering (`host.go:862`), ~24 ms at 60k rows. The reaper
  pays it every 5 s per session. Skipping the replay for a connection whose
  first frame is not a resize is the fix if it ever shows.
- **After Restart terminal the pane keeps its renderer core.** A worker pane's
  cache key is its handle id (`TerminalPane.tsx:156`), which a restart keeps,
  so the new host's replay lands on the existing core — the same path as
  Restore. Check for duplicated rows in the real app; a fix belongs with the
  Restore path.
- **Saved history is bounded.** Frame plus the newest 10,240 history rows,
  ≤ 4 MiB, written at most once a minute: a crash loses up to the last minute,
  and older rows of a very long session are not saved. An in-place respawn
  ("Relaunch in a cleared session") replaces the mirror, so the next save
  holds only the new process. Files of hosts that are gone are deleted after
  7 days, the next time any terminal is created.
- **A Load older output click re-exports the whole scrollback once.**
  `apply_history_chunk` marks the export full (`parser/history.rs`), so a click
  at 200k rows costs 1,193.38 ms of renderer time (the 2,048-row feed itself
  45.05 ms). Every attach-history chunk pays the same. The fix is an
  incremental front prepend in `ExportBuffers` (`vt-wasm/src/export.rs`, 599
  lines: split first).
- **Loaded rows do not survive new output.** The renderer keeps its cap; the next
  committed live row trims the loaded rows first and the button returns. A load
  whose answer arrives after live rows made the pane trim is rejected silently
  (the chunk no longer abuts) and the button returns.
- **The seam between loaded rows and the pane is exact only at one width.** Rows
  are addressed by stable row; pane and mirror count the same rows only when they
  ran at the same width and saw the same resizes. Otherwise a few rows can repeat
  or be skipped at the seam; a chunk's label always matches the mirror rows it
  carries, and a pane numbered past everything the mirror holds (a respawn, a
  pane far ahead) is told nothing is older rather than sent mismatched rows.
  Loaded rows carry no block marks and no `wrapped` flag.
- **A cold row larger than the 1 MiB answer buffer** (a very long row of heavily
  styled or linked text) loads as a blank row, so the rows older than it stay
  reachable; its text is lost.
- **Only `history=` and `older=` marks are kept out of the live parser.**
  `origin=`, `ready=` and `boundary=` still reach vte: the first two are
  written with the attach frame before any live byte, and the boundary is
  preceded by its own resets. An answer that lands inside a live OSC (a title
  split across two PTY reads) makes the mark scanner drop that OSC's payload;
  vte keeps it.
- **What a parked pane still costs.** Measured 2026-09-23 on
  `terminal-background-pane` `1b76f26fd` (`run.mjs --panes-only`, three runs,
  `claude-spinner-10s`, 100 frames over 10 s): 1 visible + 9 parked
  0.518–0.528 s against a solo row of 0.419–0.458 s and 10 visible
  1.296–1.326 s, i.e. 7.6–12.1 ms per parked pane per 10 s (65–88 ms before
  the gate); parked panes add no layouts, no style recalcs and no DOM
  mutations (`parkedMutations` 0). What remains: every change still builds one
  snapshot per parked pane for block detection (`settleHidden` →
  `detectFinishedBlocks`, 55.4 ms of the 1+9 profile, mostly
  `export_screen_row`) and decodes its blocks, and in the app
  `TerminalSurface`'s alt-screen listener reads another
  (`TerminalSurface.tsx:298`, not mounted by the bench), and the line editor
  still ingests history per change from that same snapshot so a command that
  scrolls out while the pane is hidden stays in Up-arrow recall; the parse itself is
  small (`drain` 5.9 ms). A hidden window drains up to `HIDDEN_DRAIN_MS`
  (250 ms) of parse per timer tick, and WebKit throttles that timer to ~1/s,
  so only a producer that needs more than ~250 ms of parse per second grows
  the backlog while the window is hidden. The budget is larger than
  `FEED_BUDGET_MS` (12 ms) there because nothing paints, so there is no frame
  to protect; with 12 ms a busy session's closing mark stayed in the backlog
  until restore, where the block was reported `visible: true` and its
  notification suppressed. Animation-frame drains keep 12 ms. `rendererVisible`
  remains only the fallback for `onBlockFinished`'s `visible` when a host
  never calls `setVisible`; it is never a paint gate. The forced layout per
  paint (now `dom-block-renderer.ts:546`, the pinned-header
  `getBoundingClientRect`) is still paid by every **visible** pane
  (measurement note, "Follow-ups"). Numbers and profile:
  `docs/superpowers/specs/2026-09-23-background-pane-cost-measurement.md`
  "After".
  A pane parked longer than `RETAINED_TERMINAL_UNLOAD_MS` (30 minutes,
  `frontend/src/renderer/lib/retained-terminal.ts`) is unloaded by Operator's
  retained-terminal cache (`TerminalPane.tsx` `scheduleUnload`), not by the
  package: its renderer, core and mux attachment go away, the pty-host keeps
  the session, and showing it again reopens it through attach + history
  replay (§4.19). A shell pane whose line editor holds an unsent draft is not
  unloaded (its timer re-arms until the draft is gone). All cores share one
  `WebAssembly.Memory`, which never
  shrinks, so an unload frees space for the next core to reuse; it does not
  lower the resident size already reached. What switching back costs was not
  measured in the app (the real-app check could not run: dev ports busy); the
  only numbers are the bench's, ~40 ms to first paint and ~100–130 ms for 60k
  history rows (spec table "reopen" row). Worker panes lose no notifications
  by unloading, since Claude Code emits no block marks (0 `OSC 133`, 0
  `OSC 7000` in `claude-spinner-10s` and `claude-long-50k`) and "needs input"
  comes from the daemon's SSE stream; an unloaded shell pane is notified of
  finished commands from the daemon's `terminal_block` mux frames
  (`TerminalMux.onTerminalBlock`, `lib/shell-block-notifications.ts`). The
  shell hooks send no `start_ms`, so the daemon's `BlockAssembler` stamps a
  block's start when its output begins (`OSC 133;C`) and a frame with no usable
  start never notifies; before that fix every frame carried
  `startedAt: 0001-01-01` and would have notified every command. The loaded
  renderer times a block from its prompt (`OSC 133;A`, vt-core
  `BlockGrid::open_block`), so its duration includes time spent typing at the
  prompt — pre-existing, and why a short command after a long pause at the
  prompt can still notify from a loaded pane. Long
  run: the 30-minute bench soak (1 visible + 9 parked, 64 KiB/s each) holds
  about 25 MiB of wasm per core at the 200k-row cap from minute 7, flat to
  minute 30, and ~1.9 s of main thread a minute, byte-for-byte repeatable
  across two runs; the bench has no cache, so it cannot show the unload. The
  2-hour real-app soak (WebContent RSS and CPU, a minimised stretch, and
  2 visible split panes + parked) is not verified: dev ports busy.
  Measurement note "Memory and long run" and "Long run after unload".
- **Program notifications are desktop toasts only.** They are not notification rows: those need a session and project and a type the table's `CHECK` allows (`migrations/0117_notification_alerts.sql:8-9`), which standalone shells cannot give. So no bell entry and no phone alert (ntfy) for OSC 9/777/99, and nothing is shown while Operator's window is closed. A notification the child sends before the daemon's watch connects (the first milliseconds of a host) is dropped.
- **Size and colour answers wait for a pane.** The mirror answers `CSI 14/16 t`, mode 2048 and `OSC 10/11` only after a pane has sent its cell size and colours; a Claude Code session started while no pane is open gets no answer to its startup `CSI 16 t`. With several panes on one terminal, the last to send wins.
- **The title is not in the attach replay.** A renderer core that reattaches has an empty `title()` until the program sets it again; Operator reads the title from the daemon, so nothing visible depends on it.
- **Typing ahead covers zsh only.** bash and fish panes keep the old
  behaviour: text typed during a command lands in the shell's own line and
  is doubled by the next submission from the input box. The reasons and the
  evidence are in §4.32; `bash.sh`'s percent-encoder still encodes code
  points, not UTF-8 bytes, so a non-ASCII `cmd=`/`cwd=` from bash is wrong.
- **Nothing emits or consumes agent events yet** (§4.34). Operator keeps its
  local hooks; the in-band channel waits for remote agents. A sender must keep
  each sequence under 1,024 bytes and 14 fields (vte limits).
- **A replay that never sends `ready=` silences agent events** and live
  output on that core until a later `ready=`: the window opens at any
  `origin=` mark. The pty-host always sends both
  (`crates/vt-host/src/lib.rs:378-380` and `:438`). The pty-host does not
  filter marks out of the child's output, so a child that prints an
  `origin=` mark (`cat` of a recorded session) silences agent events and the
  activity counter until something prints `ready=`; before the review fix
  this happened only on a core with no rows.
- **An agent event pending in an open DEC 2026 sync block at attach is
  dropped as replayed.** `vt_replay` appends the mirror's pending sync bytes
  (`crates/vt-host/src/lib.rs:434`) before the `ready=` mark (`:438`), so the
  event reaches the renderer core inside the replay window. The mirror never
  delivers it either (Operator drops mirror events, §4.34).
- **Agent activity flickers in a hidden window.** WebKit throttles the drain
  and the monitor's timer to about once a second (§4.25), so a streaming agent
  reads `active` → `pollingForIdle` between bursts; it never reaches `idle`
  while bursts keep coming (1,500 ms threshold).
- **`prompting` is not known to detect Claude Code's own permission
  dialog** (its numbered choice list). No recording under
  `bench/agent-session/fixtures` contains one, so whether any of VS Code's
  high-confidence patterns matches its cursor line is not known. Add a
  pattern only once a real recording of the dialog exists.
- **`readBlockOutput` ignores redaction** (`secretPatterns` is applied by the
  renderer's text sources only) and `compact` is lossy: a run of three or
  more lines that exactly repeats the lines just before it is dropped even
  when the program printed it twice, and a repainted frame with a distinct
  line between the copies is kept (`claude-markdown-reply`, §4.34).
- **Unknown sequences are recorded, not reported** (§4.35). Only code reads
  the ring (`TerminalCore::unknown_sequences()`, or
  `WasmTerminalCore.unknown_sequences()` from a devtools console); the
  pty-host mirror's ring is never read, and SOS/PM/APC strings reach no vte
  callback, so they are not recorded at all.
- **The history receiver prints one character at a time.** History chunks and
  older answers go through `crates/vt-core/src/history.rs`'s own `Perform`,
  which gets `ScreenGrid::print`'s ASCII fast path but not the run buffer.

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
npm run bench:glyphs         # Playwright: evidence for the glyph probe (box-drawing gap, width-cache drift), writes baselines/glyph-probe/EVIDENCE*.json
npm run bench:feel -- --feature <list>  # Playwright: side-by-side screenshots for a flag, e.g. attributes=plain — never diffed, only recorded
npm run bench:agent:gate     # Playwright: no torn paint under the spinner, queued 2 MiB never blocks > 16 ms
npm run bench:agent:scroll   # Playwright: full scroll coverage, trim anchor holds, width-change gate (top-edge row and lazy rewrap)
npm run bench:affordances -- --action <hover|hint|redact>  # Playwright: side-by-side screenshots of one affordance on act-probe — never diffed

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
