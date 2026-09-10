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
   ├─ attach.go          handshake: client states its grid, host replays the
   │                     mirror's screen (vt_replay), then streams live bytes
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
   └─ ts/react           TerminalSurface: grid measurement, wheel, mouse, editor
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
  `types.ts` + the Rust test fixture `vt-wasm/tests/exit_encoding.rs`.

---

## 3. Hard rules

1. **`packages/terminal` is product-independent.** No Operator import, concept,
   path or default inside it. Operator wiring lives in `backend/` and
   `frontend/`; the package only sees `HostCapabilities`, `PtyTransport`,
   `SpawnRecipe`, theme input. Gate: "could a second, non-Operator host use this?"
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

Each entry: symptom → real cause → what guards it now. Commits are on master
(local, unpushed at the time of writing).

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
- Still at the default grid (known, deliberate): `POST /api/v1/orchestrators`
  (`SpawnOrchestrator`), `ResumeAgent`, `RestoreAll` on daemon start, the CLI,
  and the mobile client (it may send the same fields later).
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

---

## 5. Known gaps (not bugs, decisions pending)

- Copying a rewrapped block (`readBlockOutput`, `vt_render`) joins rows with
  `\n`, so a soft-wrapped line copies as several lines. Warp copies the logical
  line. Fix would export `wrapped` per row and join on copy.
- The screen's `wrapped` flag is cleared on any width change (`resize_cells`)
  because truncated cells can no longer be rejoined faithfully.
- Rewrap walks all scrollback rows on every width change (one `copy_range`
  per row). Fine at 1k–10k rows with the debounce; revisit if scrollback caps grow.
- `TestProcessEnvironmentLetsOverridesWin` in `ptyhost` fails on master before
  any of this work (TERM override appended twice). Pre-existing, unrelated.

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

# Frontend + daemon
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
# -> frontend/daemon/opr ; the user must restart the daemon AND the app
```

Backend API changes: `cd backend/internal/httpd/apispec && go generate ./...`
then `npm run api:ts` in `frontend/` (regenerates `src/api/schema.ts`).

Changelog: `packages/terminal/CHANGELOG.md`, "Unreleased" section, one entry per
behaviour change. Commits go straight to master, message ends with the
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
