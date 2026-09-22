# Changelog

## Unreleased

- vt-core: `TerminalCore::set_grapheme_clusters(true)` (TS `setGraphemeClusters`, `RendererFeatures.graphemes`) prints by extended grapheme cluster: ZWJ sequences, emoji modifier sequences and regional-indicator pairs occupy two cells, VS16 widens a text-presentation base, and the rewrap measures the same clusters (`unicode-segmentation` 1.13.3 + `unicode-width` 0.2.2, both Unicode 17). Default off: scalar widths as before. The Unicode `GraphemeBreakTest` corpus (`tests/grapheme/`, via kitty) runs against the splitter. In both modes a zero-width scalar after a space now rewraps with the space instead of starting a row. Evidence: glyph probe `seqDriftPx` -46.36 → -4.22 px (`baselines/glyph-probe/EVIDENCE-graphemes.json`); still 1.14px shy of `wideDriftPx` (-5.36px), consistent with per-glyph browser font-metric variance rather than a cell-count error (verified against the Unicode corpus and the `vt-core` cursor/rewrap tests).
- vt-core: SGR 3, 4 and `4:0-5`, 5/6, 8, 9, 21, 23, 24, 25, 28, 29, 53, 55, 58 and 59 are parsed into `CellStyle.attrs` (`Attrs`, ten bits after `alacritty_terminal/src/term/cell.rs` `Flags`) and `CellStyle.underline`; the style run grows to five words `(end, fg, bg, attrs, underline)` — `STYLE_RUN_WORDS = 5` in `vt-wasm` and `@operator/terminal-core`. The renderer still paints words 0–2 only, so nothing is drawn differently until `RendererFeatures.attributes` is `"warp"`. The mirror re-emits the attributes in the attach replay, and the Alacritty `sgr`, `underline`, `colored_underline` and `clear_underline` recordings now assert a `styles.json` derived from Alacritty's own grid.
- renderer-dom: `RendererFeatures.attributes: "warp"` paints italic, underline (single/double/curly/dotted/dashed with SGR 58 colour), strikethrough, overline and hidden from the style word's attribute bits, and tags blink with `terminal-blink` without animating it (Warp ignores SGR 5). Default `"plain"` paints exactly as before. Side-by-side: `bench/agent-session/baselines/*/feature-attributes_warp/`. In the two Claude Code fixtures the attributes present are: single underline, used extensively (the header block's version/model/cwd lines, the numbered-list body in `claude-long-50k`, and the status line's `auto mode on`, `esc to interrupt`, `for agents`, `currentVersion`, `Update available!`, `brew upgrade claude-code@latest` in `claude-spinner-10s`); none of italic, double/curly/dotted/dashed underline, a non-default underline colour, strikethrough, overline, hidden or blink appear in either fixture.
- renderer-dom: the transcript scroller sets `overscroll-behavior-y: none`, so it stops hard at both edges like Warp's block list (`app/src/terminal/block_list_viewport.rs`, `scroll_position_for_delta` clamps the new top to `[0, max_scroll_top]` and there is no elastic region) instead of rubber-banding past the bottom.
- renderer-dom: an elastic overscroll past the top or bottom edge (WebKit rubber-band, where `scrollTop` overshoots its range) no longer has the sticky-bottom and scroll-anchor writes snapping the position back every frame, which vibrated the pane at the end of the scroll.
- vt-core/vt-wasm/core: the snapshot exports `spanRanges`/`cellSpans` (`CELL_SPAN_WORDS = 3`: row-relative byte `start`, `end`, cell `width`) for every cluster that is not a single width-1 scalar, on the primary and the alternate screen, through the incremental export like the style runs. Nothing reads them yet.
- renderer-dom: selection and copy place cells from the snapshot's exported cell spans instead of a hand-written width table (`cell-width.ts`, deleted). Copying across a code point the table misclassified (`🚀` U+1F680 was one cell in the table and is two in the core) now yields the characters under the selection. With `graphemes` on, a ZWJ sequence or a flag is one two-cell cluster to the selection too.
- renderer-dom: `RendererFeatures.cursorContrast` inverts the cursor (foreground box, background-coloured glyph) when the cell's background is within contrast 1.5 of the cursor colour (Alacritty `MIN_CURSOR_CONTRAST`); `cursorHollowUnfocused` draws a hollow block while the surface has no focus (Ghostty `cursor.zig`), reported by `TerminalSurface` through `DomBlockRenderer.setFocused`. Both default off. Side-by-side: `baselines/glyph-probe/feature-cursorContrast/`, `feature-cursorHollowUnfocused/`.
- core/editor/react: IME composition draws its in-progress text at the cursor cell (`.terminal-composition-view`, underlined like Warp's marked text) in both the transcript editor and the alternate screen, and the composed text is sent once from the textarea's settled value a tick after `compositionend` (xterm.js `CompositionHelper`), so Chromium's early `compositionend` no longer sends a partial string. Manual Japanese-IME check: pending — not yet performed by the user.
- renderer-dom: `RendererFeatures.widthCache` measures each non-ASCII cluster once per font variant (xterm.js `WidthCache`) and applies `letter-spacing` so a fallback glyph wider or narrower than its cells no longer shifts the rest of the row; the baseline showed -5.36 / -28.38 px of drift on the probe's emoji / CJK rows, now -8.36 / -7.34 px (`EVIDENCE-widthCache.json`). Default off. **Concern, reported not fixed:** `glyph-probe.mjs`'s marker column is one cell short of its own `MARKER_COLUMN` (all three marker rows place `|` at 39 cells, not 40), so the raw drift numbers above are biased by a constant ~+1 cell and both still read "needed" against the 1px gate. Re-deriving the target from the rows' actual cell count (39, not 40) shows the correction working as designed on the `wide`/`cjk` rows (+3.08 → +0.08 px, -19.94 → +1.09 px) but regressing the `seq` row's ZWJ/skin-tone/flag sequences (-37.92 → -50.89 px). The root cause of that regression has not been conclusively isolated: direct Chromium testing rules out per-code-point letter-spacing insertion inside a grapheme cluster as the mechanism (a `letter-spacing` correction applied to a single span wrapping a full ZWJ/skin-tone/regional-indicator/VS16 cluster moves the whole ligated glyph by exactly the requested amount, with no internal splitting), so this remains an open question rather than a diagnosed defect; implemented as specified against the brief's reference (xterm.js `WidthCache`/`DomRendererRowFactory`) rather than patched around.

Rows are patched, not rebuilt.

- `populateBlock` keeps row nodes keyed by stable row on the block element,
  rebuilds only rows the core reports dirty or new, reuses the block header
  until its fields change, and moves one cursor element instead of creating
  one per paint (xterm.js `DomRenderer.ts` row pool and `renderRows`). Block
  elements that leave the window wait in an LRU pool (3× the window) and come
  back with their nodes.

- The selection fill is diffed against the previous paint: extending a
  selection by one row writes one row's background (Alacritty
  `display/damage.rs` `damage_selection`).

- `pointAt`/`rowOrigin` interpret the painted rows against the stable-row
  origin of the paint that built them, not the core's current one, so a
  mouse press between a trim and the repaint that follows it resolves to the
  row under the pointer instead of one shifted by the trimmed count.

Scrolling stays put when scrollback is trimmed or rewrapped.

- While not stuck to the bottom, `DomBlockRenderer` anchors the viewport to
  the stable row under its top edge plus a pixel offset and recomputes
  `scrollTop` from it after every paint (`scrollAnchor()`), following a rewrap
  through the remap row event. A trimmed anchor clamps to the first row.

- `TerminalCore.feed` only parses; `snapshot()` syncs the export lazily and
  returns the same object while the generation is unchanged, so a paint, a
  mouse move and a find share one export per frame; `decodeBlocks` is memoised
  per snapshot. `takeDirty()` and `onRowEvents()` expose the delta to the renderer.

The export is incremental.

- `WasmTerminalCore::feed`/`tick`/`resize` no longer rebuild the export;
  `sync()` applies the pending delta (appended history rows, the rewritten
  screen section, trimmed rows as a dead prefix compacted past 25 %) and
  returns the generation it reflects. A rewrap, a resize, the alternate
  screen and a process boundary rebuild in full. A property test pins that
  the incremental buffers equal a full rebuild after any chunking, resize
  and trim. Dirty stable rows accumulate until `ack_dirty`; row events
  (`row_events_trimmed`, `remap`) until `clear_row_events`. A partial delta's
  screen row count can shrink without every removed row appearing in the dirty
  set (a full reset is one), so a consumer must re-derive the current screen row
  count from `history_rows()` and the exported row count on every sync and drop
  the rows past it, rather than relying on the dirty list alone to know what to
  remove.

The model reports what changed.

- `TerminalCore::generation()` counts mutations; `take_delta()` returns the
  history rows appended, the screen rows written, the exported rows trimmed
  and the rewrap remap since the last call (Ghostty
  `src/terminal/render.zig` `Dirty`; WezTerm line `seqno`). Every
  `ScreenGrid` write marks its row. `export_history_rows` /
  `export_screen_rows` / `export_blocks` / `export_cursor` are the pieces
  `build_snapshot` is made of. A cursor move marks the row it left and the row
  it reached, and a visibility toggle marks the cursor's row, so everything a
  consumer must repaint is in `screen_rows`.

Rows have stable ids.

- `TerminalCore::stable_row(flat)` / `flat_row(stable)` / `first_stable_row()`
  (WezTerm `term/src/screen.rs` `stable_row_index_offset`): a row keeps its id
  when older rows are trimmed. `BlockGrid` stores stable rows and is no longer
  renumbered by a trim; the snapshot exports `first_stable_row`; find hits
  report stable rows.
- `data-terminal-row` carries the stable row; selection points, find hits and
  `paintedRowOrigin` address rows by stable id, so a selection no longer drifts
  when scrollback is trimmed above it.

Scrollback is capped by bytes as well as rows.

- `TerminalCore::with_limits(columns, Limits { rows, bytes })` trims whole rows
  from the front while either budget is exceeded (Ghostty
  `src/terminal/PageList.zig` `Limits`, `setMaxBytes`); `new(columns, rows)`
  stays as `Limits::rows_only(rows)`. `memory_stats()` reports resident content
  bytes, style entries, scrollback rows and blocks.
- `TerminalCoreOptions.limits { rows, bytes }` replaces `scrollback` (kept as
  an alias for one release: `scrollback: n` is `{ rows: n, bytes: unbounded }`);
  `TerminalCore.memoryStats()`. `vt_new` takes a byte budget and
  `vt_memory_stats` reports it; the Go mirror takes `vtwasm.Limits`.

The model can answer terminal queries.

- `TerminalCore::set_answers_queries(true)` plus `set_terminal_identity(name)`
  make the parser queue replies for XTVERSION (`CSI > 0 q` → `DCS > | name ST`),
  DA1 (`CSI c` → `CSI ? 62 ; 22 c`) and DECRQM (`CSI ? Pm $ p` → DECRPM with the
  tracked mode state; 2026 reports supported), read back with
  `take_query_replies`. `vt-host` enables it and exports `vt_take_query_replies`
  / `vt_set_terminal_identity`; the renderer core stays silent. Programs that
  probe before using synchronized output (Claude Code) now get the answer they
  need from the host mirror.

Blocks can no longer point past the end of the row space.

- A block opened after a cursor move below the frame and closed by a process
  boundary kept a start row above its own end, and trimming scrollback past a
  block that started above the cut underflowed its start row. Both were found
  by the new integrity proptest; `BlockGrid` now clamps a block to its end on
  close, clamps every block to the row space after a resize, and trims with a
  saturating shift (`TERMINAL.md` §4.17).
- A `?2026h` that straddles two feeds is preferred over a later one in the
  same chunk, so the frame it opens is buffered too.

Cell metrics are measured once per font change.

- `DomBlockRenderer.measure()` caches the cell width and height and
  invalidates on `setFont`, `setTheme`, a `devicePixelRatio` change
  (`matchMedia` resolution query, xterm.js `DomRenderer.ts`
  `handleDevicePixelRatioChange`), instead
  of forcing a layout read on every paint, every selection update and every
  jump-to-bottom check (xterm.js `CharSizeService.ts`).

Bytes are parsed under a per-frame budget.

- `TerminalCore.enqueue(bytes)` queues output and `drain(deadlineMs = 12)`
  parses it in 64 KiB slices from the renderer's animation-frame loop until
  the budget is spent (xterm.js `WriteBuffer.ts` `WRITE_TIMEOUT_MS`), so a
  multi-megabyte tool result no longer blocks the main thread for the whole
  parse. `hasBacklog()` and `onFeedParsed(listener)` expose progress; `feed`
  stays synchronous for callers that need it.

Synchronized output (DEC private mode 2026) is buffered in the parser.

- `vt-core` holds every byte between `ESC[?2026h` and `ESC[?2026l` back from
  the model and parses the whole frame at once when the terminator, a 2 MiB
  cap, a 150 ms deadline (`TerminalCore::tick(now_ms)`, the host's clock), a
  resize or a process-boundary mark arrives — the `vte::ansi::Processor`
  mechanism (`vte-0.15.0/src/ansi.rs`, `advance_sync`), so neither the
  renderer core nor the pty-host mirror ever contains half of an Ink frame.
  `feed_at(bytes, now_ms)` carries the clock; `feed` keeps the last one.
- The renderer ticks the core's sync deadline at the top of every animation
  frame and keeps painting frames while a block is open, so a stalled
  application is shown after 150 ms at the latest; `TerminalCore.feed` and
  `resize` notify `onChange` when the model changed or a sync block is
  pending, never for a feed that changed nothing.
- The host mirror (`vt-host`) takes the clock on `vt_feed`, exposes `vt_tick`
  and `vt_in_sync`, and `vt_replay` appends the bytes of an open sync block
  after the last complete frame so an attach never paints half a frame and
  never loses the half either.

A process boundary mark ends the current block and starts a fresh one.

- `OSC 7000 ; v=1 ; boundary=<exit>` tells `vt-core` the process that owned
  the pty has been replaced in place (tmux `respawn-pane`). It closes the open
  block with that exit code, or turns the markless rows so far into a finished
  synthetic block, then moves the whole frame into scrollback and homes the
  cursor, even when clears are in place (agent TUI mode). Output after it lands
  in a new running synthetic block, so a relaunched agent gets its own block
  instead of painting over the previous frame.
- Markless rows before the first `OSC 133 ; A` are now their own abandoned
  synthetic block rather than rows no block owns, and markless rows after the
  last closed block are a running synthetic block. Both keep every row in the
  snapshot renderable.

A host can put keyboard focus in the terminal.

- `TerminalSurface` takes a `focusToken`. Each new value moves focus into the
  input the surface is currently using -- the line editor, or the alternate
  screen's composition target while a full-screen program owns the grid. The
  surface still never takes focus on its own: which pane owns the keyboard is
  the host's call, the way Warp's pane group focuses a pane's contents when it
  activates it (`app/src/pane_group/mod.rs`, `focus_pane`) and the terminal view
  then focuses its input box (`app/src/terminal/view.rs`, `on_focus`). Before
  this the only way into the editor was a click, so a pane that had just
  opened dropped the first keystrokes.

Scrollback rewraps to the pane width.

- `vt-core` kept every scrollback row at the width it was written at, so after
  a pane shrank the rows above the screen ran past its right edge and the
  renderer grew a horizontal scrollbar to reach them. A resize now re-cuts the
  scrollback to the new column count the way Warp's flat storage does: rows an
  earlier cut had split are joined back into their line first, lines wider
  than the pane are cut again at the last space before the edge (inside a
  word only when the word alone is wider than the pane, and never after a
  leading space) with wide characters kept whole, and the screen records
  which of its rows the printer soft-wrapped so a widened pane rejoins them.
  The space a line breaks at hangs past the edge the way a browser's
  `pre-wrap` hangs it, so the visible text of a row never exceeds the grid.
- A continuation row hangs under the text of its first row: a line that
  starts with spaces, a bullet (`-`, `*`, `•`, `●`, `⎿`, a numbered `1.`
  and the like) and a gap gives its continuations that width as an indent,
  capped at half the pane. `GridSnapshot::row_indents` carries it per row,
  the wasm export exposes it as `rowIndents`, `renderer-dom` pads the row by
  that many cells, and `vt_render`/`vt_replay` write it as spaces. Content, style offsets and block ownership are
  unchanged; only the row boundaries move. Agent TUIs get the same treatment
  for their scrollback while their live frame is still left for them to
  repaint.
- `renderer-dom` clips the block list horizontally. A row can no longer be
  wider than the grid, and a glyph that renders a hair wider than its cell must
  not grow a scrollbar either.

Selecting a painted band shows the selection.

- A run with its own background colour (Claude Code's user-message band) sat
  above the row's selection fill and hid it, so the band stayed grey inside a
  selection. `renderer-dom` now tints such runs with the same selection
  colour, clipped to the row's fill, the way Warp blends its selection rect
  over the cell backgrounds with the glyphs drawn on top
  (`grid_renderer.rs` `render_selection`).
- A run's background covered only its glyph box, so a band spanning several
  rows showed a seam of half-leading between every row. Runs now fill the
  full line height, as Warp fills the whole cell.
- The mouse pointer stays an arrow over the transcript. Selectable text gets
  a browser I-beam by default; Warp shows the platform arrow over its grid
  and reserves the pointing hand for links.

The selection lives in the renderer, not the browser.

- The transcript's selection was the browser's, anchored in text nodes that
  every repaint rebuilt, so new output collapsed it and a drag lurched to the
  block start. `renderer-dom` now owns the selection as grid points
  (block, row, column, half-cell side), paints it from geometry and copies it
  from the snapshot, the way Warp's `BlockListSelection` works. Double-click
  selects a word with Warp's boundary set, triple-click a line, a drag past
  the edge auto-scrolls with Warp's curve, and Cmd+C (Ctrl+Shift+C off macOS)
  copies. Typing, a plain click, a resize, or the block leaving scrollback
  clears it; output and scrolling do not.

Blank rows survive scrolling off the screen.

- `vt-core` dropped any all-blank row the moment it left the screen: the row
  index only recorded a completed row when it carried bytes, and the block grid
  rebased every block past it as though the row had never existed. An agent's
  transcript separates its messages with blank lines, so everything above the
  screen read as one gap-less run while the rows still on screen kept their
  spacing. Every evicted row is now a scrollback row, empty or not, and
  `BlockGrid::remove_row` is gone with the case it served.
- A reflowing resize and a scrolling `ESC[2J` evict the frame up to its last
  row with content rather than up to the cursor, so a cursor parked below the
  frame no longer leaves blank rows behind in scrollback.

`vt_replay` serializes the terminal for attach replay.

- New `vt-host` export `vt_replay(handle, lines, out, cap)` returns the bytes
  that reproduce the terminal's current state on a freshly attached client:
  CR-LF terminated styled rows, the alternate-screen mode set when the child is
  in it, and a final cursor placement. The existing `vt_render*` exports answer
  "what does the screen say" for text extraction and stay unchanged.
- A replay needs all three of those. Without CR-LF the receiving terminal
  stair-steps every row (LNM is off); without the cursor placement the child's
  next in-place redraw counts rows from the wrong origin and paints a second
  copy of its UI below the first.
- `vt_replay` clips every row to the grid's current width. A resize does not
  reflow, so scrollback keeps rows at the width they were written at; replaying
  one verbatim into a grid that is now narrower wraps it into two rows and
  pushes everything below it down by one, which is what made a reattached
  transcript come back doubled and without the blank lines between an agent's
  messages.
- New `vt-core` accessor `TerminalCore::columns()`.

Background colours reach the renderer.

- `vt-core` keeps a cell's background alongside its foreground (`CellStyle`)
  instead of parsing SGR `48`/`40-47`/`100-107`/`49` only to discard them, and
  handles reverse video (`7`/`27`) by swapping the pair when a cell is written.
- Erase, scroll, and insert/delete now paint the current background rather than
  a hard-coded blank, matching Warp's `cursor.template.bg` behaviour, and a
  trailing run of spaces that carries a background is no longer trimmed off the
  row.
- **Wire format change:** the exported `style_pairs` buffer is now triples of
  `(runEnd, foreground, background)` rather than `(runEnd, style)` pairs.
  `STYLE_RUN_WORDS` names the stride. Code 255 is the theme foreground and 254
  the theme background.
- The DOM renderer paints `background-color` per run, leaving the default
  background unset so the terminal's own ground shows through.
- Block elements (`U+2580..U+259F`) are drawn as cell-filling rectangles rather
  than from the font. A font glyph fills one em while the row box is
  `line-height`, and CSS spends the difference as half-leading, so stacked
  blocks showed a seam on every row -- visible as a sliced-up Claude Code logo.
  Warp draws its own box-drawing range procedurally for the same reason
  (`grid_renderer/box_drawing.rs`). The character stays in the DOM, transparent,
  so selection and copy are unchanged.

Blocks carry Warp's two-line header.

- A block header is now the metadata line -- status dot, cwd, git branch,
  duration -- above the command itself, which sits on its own row in the
  terminal foreground at full weight, the way Warp puts the command on the
  line it was typed on rather than in a caption. The header is two line
  heights tall and drops the rule under it; the block's own padding already
  separates it from the output. The command and cwd carry their untruncated
  text as a `title`, so an elided one is still readable.
- The pinned header appears only once a block's own header has scrolled out
  of view. It used to be painted from the viewport-center block, so the
  command at the top of the pane was named twice -- once in place and once in
  the sticky strip over it. It overlays the transcript with a negative margin
  instead of taking a row of its own.
- The hover actions over a block (copy, rerun, bookmark) are no longer
  rendered. `renderBlockActions` and its events stay exported for a host that
  wants them, but the renderer no longer needs `HostCapabilities`, so
  `DomBlockRenderer.setHostCapabilities` is gone.

A marked command's block starts at its output.

- `OSC 133;C` now re-anchors an open block's first row to the row output
  begins on, so the shell's prompt and the echoed command line are no longer
  the first two rows of the block that also renders the command in its
  header. This only applies when the command text is known from
  `OSC 7000;cmd=`; an unmarked command keeps its prompt in the transcript,
  because dropping those rows would lose the only copy of what was typed.
- The renderer hides the trailing empty shell prompt while the line editor
  owns the input, so the editor's own prompt row is not shadowed by a
  zero-command block above it. A trailing block that has written output is
  kept -- a background job's text stays visible while the prompt is free.

Editor chrome matches the transcript.

- `--terminal-line-height` was set from `FontConfig.lineHeight` directly, but
  that field is a multiplier, so the editor laid its rows out at 1.3px and
  every derived metric was wrong. It is now `lineHeight * sizePx`, as
  `renderer-dom` already computed it.
- The editor sits under a hairline rule at the transcript's own inset, wraps a
  long line instead of clipping it, and shows cwd and branch as bordered
  chips.

Shell terminals no longer inherit the launcher's `NO_COLOR`.

- A desktop app started with `NO_COLOR` set passed it to every pty child, so
  an interactive shell and the agents under it came up without colour. It is
  stripped from the inherited environment; an explicit override still wins.
- A shell terminal on a shell with a bootstrap recipe asks for prompt
  suppression, so the package's prompt row is not stacked under the shell's
  own.

- The `bench:selection` gate starts its drag from a transcript row it finds on
  screen rather than a fixed pixel. It hard-coded a point that a taller block
  header turned into chrome, where a pointer press is ignored by design, and
  reported a live regression in a selection that was working.

- Plan B measured (see the spec's baseline table, "After Plan B"): feed+sync
  at row 50k is 0.20ms vs 0.20ms at row 1k (inside the 20% + 0.2ms budget);
  a one-row selection extend repaints 1 row (was 2); `bench:agent:scroll`
  reports full coverage (60,134/60,134) and the top-edge row unchanged across
  a 5,098-row trim. Two Part 1.4 targets are missed and reported: a spinner
  paint creates 7.21 DOM nodes per changed row (a `div` plus a `span` and a
  text node per style run; target ≤ 2) and ten idle panes cost 1.30s of
  main-thread task time over 10s against a 0.44s target (25 % of the 1.759s
  pre-Plan-B baseline). The harness's `addedNodes` counter now counts every
  node of an inserted subtree, not only its root, so nodes-per-paint figures
  before this entry are not comparable. `bench:agent:gate` asserts
  `feedSyncCost` flatness from 1k to 50k rows and the one-row selection
  repaint, prints the two missed rows, and fails when a `feedSyncCost`
  sample was not collected.

A reopened pane recovers the whole session.

- terminal: the wasm export rewraps the rows the renderer is about to paint (its window plus overscan) before handing back a snapshot, and applies a rewrap by re-reading history from the first row that moved instead of rebuilding the whole export. The scroll anchor keeps the viewport still while the row count above it corrects.
- vt-core: a width change rewraps the screen and the newest 2,000 completed rows immediately and marks older rows stale at the width they are cut at; a stale run is rewrapped once, on first access through `touch_rows`, and emits the same stable-row remap an eager rewrap does. The integrity checker pins that stale runs stay non-overlapping and inside the row space.
- vt-core: an `origin=` mark puts a fresh core into the replaying host's stable row space; a `history=` mark routes the bytes that follow it into a chunk receiver that prepends them as scrollback rows and blocks instead of printing them at the cursor, and no chunk byte — including a block's closing `exit=` — reaches the live block grid; a `ready=1` mark is recorded as `TerminalCore::replay_ready()`.
- vt-core: scrollback content is allocated from a base offset so a reopened pane can prepend history rows below the rows it already holds; `Parser::adopt_origin` puts a fresh core into the replaying host's stable row space and `Parser::apply_history_chunk` prepends rows, styles and blocks, moving `trimmed_total`/`BlockGrid::origin` together.
- vt-host: the attach replay opens with an `OSC 7000;v=1;origin=` mark naming the stable row of its first row, then the DEC modes the child set (`?1049`, each bit of the mouse-tracking mask as `?1000/1002/1003`, `?1006`, `?2004`, `?1004`, `?1`), and closes with an `OSC 7000;v=1;ready=1` mark, so a reattaching client shares the host's row space and paints the complete frame at a known point.
- vt-host: `vt_history_chunk` serialises scrollback newest→oldest in 512-row chunks, each framed by an `OSC 7000;v=1;history=<first_stable_row>,<count>` mark with its blocks re-emitted as `id=`/`cmd=`/`exit=` inside the rows they span, so a reattaching client recovers the whole session instead of the mirror's last screen and no chunk byte reaches its live block grid.
- pty-host: an attach now streams five parts — the origin mark, the child's modes, the live frame, the READY mark, then scrollback newest→oldest — and the handshake returns at READY so the pane paints while history is still arriving. History is sent only to a client that asks for it on its opening resize, so a client that cannot read history chunks is unaffected.
- pty-host: a client may acknowledge the terminal bytes it has consumed (`MsgAck`); the host counts every payload it sends that client — replay frame, history chunks and live batches alike — stops reading the pty once its slowest acking client is 100,000 bytes behind, and resumes at 5,000, so a slow link throttles the child instead of queueing the session. Streaming history paces on the same watermark, and a client that never acks is unlimited.
- renderer: the initial-replay cover lifts when the core reports the replay's READY mark parsed, instead of after the whole replay goes quiet, so a reopened pane paints its live frame while its scrollback is still streaming in behind it. A host that sends no READY mark still uncovers on the existing quiet and cap timers.
- terminal mux: a client may send `{ch:'terminal', type:'ack', bytes}` and the daemon forwards it to the attach stream, and may declare `history: true` when it opens a pane to receive the session's scrollback behind its replay; the desktop renderer does both and acks every 5,000 bytes it consumes.
- ts/core: `TerminalCore.staleRowCount()` forwards to the wasm core's stale-run count, so a bench or a caller can see how much of a width change's rewrap was deferred instead of walked eagerly.
- bench/agent-session: `main.ts` gains `reopenFromReplay` (feeds a replay frame then every history chunk, timing first paint and the paint after the last chunk) and `widthChange` (times a column resize to its settled paint and reports the top-edge row and stale-row count before and after); `run.mjs`'s reopen row now reports the whole reopen, not just the frame, and `scroll-gate.mjs` gates a width-change phase on the top-edge row holding still and lazy rewrap engaging. `TestAgentSessionReplayReport` streams the mirror's history and adds a block-list reconstruction check: the frame plus every history chunk fed into a second parser must recover the same `id=`/`cmd=`/`exit=` marks as the source mirror.
- vt-host: `vt_touch_history` rewraps every history row lazy rewrap left cut at an older width, and the pty-host runs it before it renders the frame a history-opted-in client attaches to, so a reopened pane's cold rows arrive whole instead of truncated to the new grid.
- pty-host: a history stream starts at the origin the replay frame just declared, instead of re-deriving its own bound from a later snapshot — a row completed in between rejected the first chunk and, silently, every chunk after it. A history stream also stops when its own client disconnects rather than parking on the ack watermark for the life of the process.
- vt-core: a second width change re-marks the band a `touch_rows` left hot between the head and tail of a stale run; it used to be skipped forever and stay cut at whatever intermediate width the touch used. History rows also carry the SGR background into their erase colour, as the live path does.
- renderer: `history: true` is sent on the first open of a terminal core only. A core that has already painted refuses a replay's origin, and with it every chunk behind it, so a reconnect used to stream the whole session's scrollback, ack-paced, just to discard it.


## 0.3.0 - 2026-08-30

Phase 2 replaces shell line editing with the package-owned editor and prompt row.

- Explicit `input-ready` and `input-released` marks drive `Unknown`, `Owned`, and
  `Released` states without an ownership timer.
- The DOM editor provides multi-line editing, syntax highlighting, mark-derived
  history, ghost text, Ctrl-R reverse search, and edit-and-rerun.
- Prompt suppression lands with the prompt row and remains reversible through the
  show-shell-prompt option.
- Additive zsh, bash, and fish bootstraps emit ownership marks; fish keeps its own
  OSC 133 enabled.
- Operator mounts the editor below the block list, sends submitted text with one
  newline, preserves raw passthrough outside `Owned`, and hides the editor in the
  alternate screen.
- The Phase 2 perf gate passes against the xterm baseline: large-output median
  49,063,386 B/s, vtebench median 4.801 workloads/s, input p95 8.60 ms, and the
  50,000-block scroll p95 13.40 ms with 20 live blocks.

## 0.2.0 - 2026-08-29

Phase 1a: the block-aware core, the mark protocol, and the slice of
features that proves the package can hold blocks through a real session.

- **Block-aware core over the row index.** `vt-core` now layers a
  `BlockGrid` and a `BlockTree` (a leaf-with-summary tree, the "sum
  tree") on top of the append-and-wrap parser. Every `feed` reopens
  the same block the row index was already tracking, so blocks are
  never a second source of truth for terminal state.
- **Mark protocol with two decoders against shared vectors.** The
  `terminal-marks` crate owns the Tier 1 (OSC 133) and Tier 2 (OSC
  7000) grammars, with a tolerant recovery table for the OSC 133
  sequence states. A Go decoder at `go/marks/` decodes the same
  feed-only Tier 1 grammar for the daemon side, and both decoders
  pass the same 16 JSON vectors under
  `protocol/vectors/`. The closed event vocabulary and tolerant
  recovery rules are pinned in `protocol/SPEC.md`.
- **Blocks formed from marks and tracked through the alt screen.**
  The block formation logic reads OSC 133 (and the OSC 7000
  extension) and surfaces the block list through the existing
  `CoreSnapshot`. The alt screen is a tracked state: marks
  observed between enter and leave do not change the block list,
  and leaving the alt screen resumes from the last block seen
  outside it.
- **Block-coordinate selection.** Selections are now
  `(block_id, anchor, head)` instead of raw `(row, col)` pairs,
  so a selection that straddles a block boundary resolves
  cleanly after the grid is trimmed.
- **Incremental find engine.** The find engine indexes blocks as
  they are produced and serves the next match in O(log n) per
  step. A small "block i owns row i" fallback covers the case
  where a block is observed before its rows are flushed, which
  is a known timing workaround (see "Known costs" below).
- **Additive-only zsh bootstrap.** The `shell/zsh.sh` bootstrap
  installs precmd / preexec hooks and the OSC 7000 extension
  emission. It sources on top of any user config, never rebinds
  any key, is idempotent under a second source, and never touches
  the user's prompt string. The `spawn-recipe` runtime rejects
  `suppressPrompt: true` so a future caller cannot take prompt
  suppression by accident.
- **Package-level guardrails stay green.** `check:boundaries`
  still rejects any import that escapes `packages/terminal/`,
  the forbidden package edges, any source file over 600 lines,
  and any Cargo or Go replacement that resolves outside the
  package. The CI matrix now runs the Go tests, `go vet`, and
  the zsh bootstrap tests in addition to the existing Rust,
  Vitest, and smoke gates.

### Known costs (carried into Phase 1b, not regressions)

- `BlockGrid::trim_to_first_row` renumbers every surviving block
  in O(n) per trim. A root-level offset on the tree would make
  this O(log n) but the current cost is small: trim runs once
  per `feed`, only after the row cap is reached, and is well
  under the §9.4 perf gate on the workloads Phase 1a measures.
  The decision is recorded here so a later reader does not
  mistake the O(n) for an oversight; it is a deliberate trade
  for a simpler tree shape.
- The find engine's `block_byte_range` falls back to "block i
  owns row i" when `block.row_count == 0`. This is a workaround
  for a Task 7 timing race where a block is observed before its
  first row has been flushed into the row index. The fallback
  only fires for the first match in a fresh block and does not
  change the result, only the byte range the engine reports.
- `BlockTree::push` and `BlockTree::pop_front` each walk the path
  from the affected leaf to the root twice — once via
  `propagate_summary_up` and once via
  `propagate_from_last_leaf_to_root` /
  `propagate_from_first_leaf_to_root`. Both walks do the same
  work, so the second is redundant. A later task can collapse
  the two into one without changing the public API.

## 0.1.0 - 2026-08-29

Phase 0 workspace skeleton.

- Workspace skeleton: independent npm workspace and Cargo workspace at
  `packages/terminal/`, with `@operator/terminal-core`,
  `@operator/terminal-renderer-dom`, and `@operator/terminal-react`
  npm packages and `vt-core`, `vt-wasm`, and `terminal-marks` Cargo
  crates, all at 0.1.0.
- Explicit WASM loading through `init(wasmBytes)` instead of the
  `wasm-bindgen` auto-fetch form, so the same bytes load in Vitest,
  Vite, and an optimized Tauri binary.
- One-block DOM slice painted from a real VT parse, exposed through the
  React mount.
- Boundary enforcement: `check:boundaries` rejects any import that
  escapes `packages/terminal/`, the forbidden package edges
  (`renderer-dom` -> `editor`, `editor` -> `completions`), any source
  file over 600 lines, and any Cargo or Go replacement that resolves
  outside the package.
- xterm 5.5.0 baseline recorded for later phases to beat.

### Fixes found in Phase 0 review

- `RowIndex::trim_to` released the open row's start instead of the first
  retained row's start, so `Content::drop_before` discarded bytes that
  retained rows still referenced. Any output ending in a newline blanked
  the whole scrollback once the row limit was reached.
- Zero-width scalars never advanced the column, so the open row was never
  completed and never trimmed; a stream of combining marks grew the core
  without bound. A cell now accepts at most eight of them.
- `checked_u32_from_u64` was reachable only from its own test while the
  live conversions in `grid.rs` were unchecked `as u32` casts. Snapshot
  offsets are now checked and surface `CoreError::OffsetOverflow`.
- SGR sub-parameters were read as top-level codes, so `48;5;31` -- a
  256-colour background -- repainted the foreground ANSI red. The
  extended-colour introducers now consume their own parameters, and the
  colon form stays self-contained.
- A throwing `onChange` listener escaped `feed` and starved the listeners
  registered after it; failures are now collected and reported together.
- `wasm-bindgen-cli` is cached in CI instead of being compiled from
  source in all four jobs on every run.
