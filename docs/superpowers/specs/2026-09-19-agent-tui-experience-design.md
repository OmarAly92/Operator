# Agent-TUI experience: Claude Code fidelity and long-session performance

**Date:** 2026-09-19
**Decision owner:** Omar Aly
**Status:** approved direction, plans not yet written
**Derived from:** [`2026-09-19-terminal-reference-survey.md`](2026-09-19-terminal-reference-survey.md)
(the survey). Section numbers written `§N.M` refer to that document; this spec
only restates what it needs and adds the long-session requirements the survey
did not cover.

## Why

Operator is used mainly to run Claude Code, and the terminal "feels perfect"
today for a fresh session. Two things erode that: (1) small fidelity faults an
agent TUI exposes that a shell does not — tearing under the 100 ms spinner,
stalls when a big tool result lands, dropped text attributes, drifting emoji
rows, no way to act on the file paths it prints; (2) long sessions. A Claude
session runs for hours and produces tens of thousands of rows. Today the
renderer keeps 5,000 rows and the pty-host mirror 1,000, every 100 ms repaint
re-exports the whole scrollback, and reopening a pane replays only the mirror's
1,000 rows. So "scroll up and every message is there" is not true past 5,000
rows, is never true after a reopen, and the pane gets heavier the longer the
session runs.

The user's stated requirements, verbatim in intent:

1. Improve the experience with agent TUIs, Claude Code above all.
2. Performance on long Claude sessions: scrolling up shows *all* messages, and
   nothing breaks (no jumps, no missing rows, no freezes, no re-flowed mess).
3. The current feel is the baseline. Anything that changes what a Claude Code
   pane looks like ships default-off behind a flag and is shown side-by-side
   first.

## Non-goals

- Shell-mode behaviour: OSC 133 options, prompt redraw on resize, quick
  fixes, run-recent, vi mode (survey §1.5, §1.6, §2.13, §6.6, §6.8, §6.11).
- The `vte::ansi` refactor (§2.2) — valuable, not agent-specific; it stays in
  the survey's plan 2.
- Accessibility (§3.9) — product timing.
- Remote agents / OSC 777 (§7.1, §7.7, §7.8).
- Anything Claude Code does *to itself*: the duplicated row after a resize is
  its own SIGWINCH repaint (`TERMINAL.md` §4.8, upstream). One heuristic is
  offered under Decisions; nothing else chases it.

## What a Claude Code pane is, in our terms

- Spawned with `agentTui = true` (`frontend/src/renderer/components/TerminalPane.tsx`,
  `kind === "worker"`), so `vt-core` runs in agent-TUI mode: no reflow of the
  live frame, `ESC[2J` clears in place, scrollback still rewraps on width
  change (`TERMINAL.md` §2, §4.2, §4.10).
- Emits DEC 2026 around every Ink frame, SGR mouse (1000/1006), 1049 for some
  views; no Kitty keyboard, no 2048 (verified with `strings` on the installed
  binary, survey Appendix B).
- Repaints on a ~100 ms timer while thinking (`TERMINAL.md` §4.13 measured it).
- Prints box drawing (`│ ⎿ ├ ─ ╭ ╮ ╰ ╯`), braille spinners, emoji status
  glyphs, `path:line` references and URLs in every tool result; uses bold,
  dim, colour bands; italic/underline/strikethrough: not measured (see
  Baseline).
- Two `vt-core` copies see every byte: the renderer core (wasm in the window)
  and the pty-host mirror (wasm in the daemon's subprocess) that produces the
  attach replay (`TERMINAL.md` §1).

## Baseline — measured before any change, kept as the gate

A `bench/agent-session` harness in `packages/terminal` records, for a
captured Claude Code stream (`OPERATOR_PTY_RECORD`, §2.9) of ≥ 50,000 rows:

| Metric | How | Today (not known — the first plan fills this table) |
|---|---|---|
| `feed()` cost at 1k / 5k / 50k rows | `performance.now()` around `core.feed` | |
| paints per second, DOM nodes created per paint under the spinner | `MutationObserver` count | |
| main-thread block time when a 2 MB tool result arrives | long-task API | |
| scroll-up to row 0 at 50k rows: jank frames, dropped rows | Playwright | |
| attach/reopen time and rows recovered at 1k / 5k / 50k rows | daemon API + `/mux` | |
| memory of the renderer core and the mirror at 50k rows | wasm `memory.buffer.byteLength` | |
| pixel diff of the rendered transcript vs the pre-change screenshot | `bench/` screenshot | must be zero unless the item declares otherwise |

The last row is the "feel gate": every task in every plan below runs it.

## Part 1 — Long sessions: every message stays, scrolling never breaks

### 1.1 Requirement

A session of any length (target: 200,000 rows, ~8 hours of dense agent
output) keeps every row reachable by scrolling, in the live pane and after a
reopen of the pane or a restart of the app, with no per-frame cost that grows
with the session length and no visible jump when older rows are trimmed or
rewrapped.

### 1.2 Today, with citations

- Renderer cap: `DEFAULT_SCROLLBACK = 5000` rows
  (`frontend/src/renderer/components/BlockTerminal.tsx:66`) →
  `TerminalCore.create({ scrollback })` (`packages/terminal/ts/core/src/terminal-core.ts:57`)
  → `Parser::trim_to(max_total)` drops rows, content bytes and styles from the
  front and rebases blocks (`packages/terminal/crates/vt-core/src/parser.rs:296-307`).
- Mirror cap: `vtwasm.New(…, MaxOutputLines)` with `MaxOutputLines = 1000`
  (`backend/internal/adapters/runtime/ptyhost/host_main.go:152`,
  `ring.go:8-9`); `vt_replay` renders that mirror
  (`packages/terminal/crates/vt-host/src/lib.rs:160-200`), so a reattach
  recovers at most 1,000 rows. The raw `Ring` is also 1,000 lines.
- Per-feed cost: `WasmTerminalCore::feed` calls `core.snapshot()` and
  `export.refresh` after *every* chunk (`packages/terminal/crates/vt-wasm/src/lib.rs:44-49`);
  `snapshot` walks every completed scrollback row and copies all content and
  style pairs into new vectors (`packages/terminal/crates/vt-core/src/grid.rs:80-101`).
  The renderer then calls `core.snapshot()` again per paint
  (`packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:371`) and
  `decodeBlocks(snapshot)` over every block (`:400`), and the selection path
  decodes once more per mouse move (`TERMINAL.md` §5).
- Width change: `RowIndex::rewrap` walks all scrollback rows
  (`TERMINAL.md` §5: "fine at 1k–10k rows with the debounce; revisit if
  scrollback caps grow") — this spec grows them.
- Virtualiser: `computeWindow` with `OVERSCAN_ROWS = 6`
  (`dom-block-renderer.ts:45,426-433`) renders only visible blocks and
  windows rows inside big blocks; block elements outside the window are
  dropped (`:465-470`) and rebuilt when scrolled back into view.
- Scroll anchoring while scrolled up: `repaint` restores `scrollTop` to the
  pre-paint value (`:474-476`); when `trim_to` removes rows above the
  viewport the content under that `scrollTop` shifts by the trimmed height —
  a visible jump. Not verified with a test; the plan writes one.
- Reopen: worker sessions get no `historyBlocks`
  (`frontend/src/renderer/components/TerminalPane.tsx:1043`, shell targets
  only), so a reopened Claude pane is the mirror replay plus live bytes.

### 1.3 Design

**A. Caps become byte budgets, large, and equal in both cores** (survey §1.13)
- `TerminalCore::new(columns, Limits { rows: 200_000, bytes: 128 MiB })`;
  `trim_to` trims whole rows while either limit is exceeded. Content is UTF-8
  and styles are run-encoded (`attribute_map.rs`), so 200k rows of agent
  output is on the order of 20–40 MB; the wasm heap can hold it twice.
- The mirror gets the same limits (`host_main.go:152`, `respawn.go:63`);
  `MaxOutputLines` stays for the raw `Ring` only. `memory_stats()` exported
  from both cores feeds the daemon's session info.

**B. Incremental export: the snapshot stops being O(session)** (survey §1.2, §4.2's seqno)
- `Content` offsets never move (`TERMINAL.md` §4.2), so the scrollback part
  of `ExportBuffers` is append-only between width changes. `GridSnapshot`
  becomes two parts: `history` (completed rows: appended to since the last
  export, never rewritten except by trim from the front and rewrap) and
  `screen` (rewritten every export, bounded by rows×cols).
- `vt-wasm` keeps the previous export and applies a delta:
  `{ trimmedRows, appendedRows[], screen, blocks, generation }`; rewrap or
  trim-past-viewport produce a `full` delta. `feed()` no longer calls
  `snapshot()`; it records dirtiness (screen rows written, rows evicted) and
  the export is built lazily on `snapshot()` from the renderer's rAF —
  one export per painted frame, not per chunk.
- `ts/core` exposes `snapshot()` (unchanged shape for callers) backed by the
  cached buffers plus the delta, and `generation`. `decodeBlocks` memoises
  per generation (`TERMINAL.md` §5 gap closed). The selection view reuses
  the cached snapshot instead of re-exporting per mouse move.
- Row events (survey §3.5) ride the same delta: `Trim { amount }`,
  `Remap { map }` after rewrap, `ScreenDirty { rows }`.

**C. Stable row ids** (survey §4.1)
- `stable_row = flat_row + trimmed_rows` on the core; the snapshot exports
  `firstStableRow`. Blocks, selection anchors, find hits, the scroll anchor
  and the pinned header all hold stable rows, so trimming from the front is
  a subtraction nobody has to observe.

**D. Scroll position is anchored to a stable row, not to `scrollTop`**
- `DomBlockRenderer` keeps `anchor = { stableRow, offsetPx }` for the row at
  the top of the viewport whenever `stickToBottom` is false. After each
  paint it recomputes `scrollTop` from the anchor through `row-geometry.ts`.
  A trim above the viewport, a rewrap that changes row heights above, or a
  block header appearing above all leave the same text under the same pixel.
- When `stickToBottom` is true the existing behaviour stays (`:503-518`).
- Test: at 50k rows, scroll to the middle, feed 10k more rows so a trim
  happens, assert the text under the viewport's top edge is unchanged.

**E. Bounded element pool instead of drop-and-rebuild** (survey §3.1)
- Block elements and row nodes leaving the window go to an LRU pool
  (cap: 3× the window), reused on the way back; a block returning to the
  window whose generation is unchanged reattaches its nodes without a
  rebuild. Rows inside the window repaint only when marked dirty (B).

**F. Rewrap cost: lazy for cold history** (survey §5.8, Ghostty's deferred
reflow TODO in `PageList.zig:1263-1265`)
- On a width change the core rewraps the screen and the last `HOT_ROWS`
  (e.g. 2,000) of history eagerly, records the new width, and marks older
  rows `stale_width`. `rows(range)` rewraps a stale range on first access
  (the virtualiser only asks for the window plus overscan). Row counts above
  the viewport are unknown until rewrapped, so the scrollbar's total height
  is an estimate (`rows × 1` until touched, corrected as ranges are
  rewrapped — the anchor in D keeps the viewport still while the estimate
  changes). Selection and find hold content offsets, which rewrap does not
  move, so they survive the lazy pass.
- Debounce stays 100 ms trailing (`TERMINAL.md` §4.6).

**G. Reopen and reattach recover everything** (survey §1.9, §3.11, §6.3)
- The mirror holds the same 200k/128 MiB as the renderer (A), so
  `vt_replay` can reproduce the whole session. Replay order becomes: modes
  (1049/1000/1006/2004/2026 state, `TERMINAL.md` §4.7 clip retained), the
  live frame, a `READY` mark (`OSC 7000;v=1;ready=1`), then history newest→
  oldest in chunks the client prepends behind the frame. The client paints
  at `READY`; the user can scroll into history as it arrives. Block records
  travel with it (`OSC 7000 id/exit/cmd` re-emitted per block) so the
  reopened pane has the same blocks, not re-derived ones.
- `RowIndex` gains `prepend` (row records only; bytes append to `Content`
  and the row's byte range points at them), so history arriving after the
  frame does not shift the frame.
- App restart: the daemon's `RestoreAll` respawns processes; the *previous*
  session's rows are gone with the old pty-host. Persisting the mirror's
  rows to disk on shutdown (VS Code `serializeTerminalState`, survey §6.3)
  is the follow-up; listed under Decisions, not in scope for the first plan.

**H. Flow control on the mux** (survey §6.3, §3.13)
- The client acks bytes every 5,000 chars; the pty-host stops reading the
  pty at 100,000 unacknowledged and resumes at 5,000. A phone on Tailscale
  no longer receives a 20 MB burst it cannot parse.

### 1.4 Acceptance

- 200k-row captured session: `feed()` at row 200k costs the same as at row
  1k (± noise); paint at the bottom creates ≤ 2 DOM nodes per changed row.
- Scroll from bottom to row 0 at 200k rows: no dropped rows, no frame >
  50 ms, text under the top edge stable across trims.
- Width change at 200k rows completes within the debounce plus one frame
  for the viewport; older rows rewrap on scroll without a visible jump.
- Reopen the pane after 200k rows: frame visible in < 200 ms on localhost;
  every row reachable within seconds; blocks identical to the live pane.
- Memory at 200k rows: renderer core < 128 MiB, mirror < 128 MiB.

## Part 2 — Frame fidelity: no tearing, no stalls

- **Synchronized output in the parser** (survey §2.1, replacing §1.1's
  renderer skip): bytes inside `?2026h … ?2026l` are buffered before `vte`,
  flushed on ESU, at 2 MiB, or when the host's `tick(now_ms)` passes 150 ms;
  `resize` and `process_boundary` flush; marks are decoded at flush so
  blocks stay in stream order (`lib.rs:77-83`). The mirror ticks from the Go
  read loop, so `vt_replay` never starts inside a frame.
- **Pump coalescing** (survey §4.4, §5.7): the pty-host waits up to 3 ms for
  more bytes after a short read before broadcasting, so a frame written in
  several `write()`s arrives as one mux message even without 2026.
- **Feed budget** (survey §2.10, §3.13): `TerminalCore.enqueue(bytes)`
  drains ≤ 12 ms per animation frame; keyboard input is never queued behind
  the backlog; `onFeedParsed` fires per chunk (the hook find and flow
  control use).
- **Cached char metrics** (survey §3.3): `measure()` reads layout once per
  font/zoom/DPR change instead of per paint and per mouse move.
- **Integrity checker and dispatch trace** (survey §1.14, §5.10):
  `Parser::verify_integrity()` after every mutation in debug builds; a
  `trace` feature records dispatched actions so a captured artefact can be
  pinned to a sequence.

Acceptance: a captured Ink frame split at every byte boundary paints once;
a 2 MB tool result never blocks the main thread > 16 ms per frame; the feel
gate diff is zero.

## Part 3 — Paint cost

Covered by Part 1.B/C/E (incremental export, stable rows, element pool) plus
survey §2.3: selection and cursor repaints are computed by diffing the
previous and current renderer state — a mouse move that extends the
selection by one row touches one row; a cursor move touches two.

Acceptance: ten Claude Code panes idle with spinners keep the renderer
process under a measured CPU budget (number set from the baseline; target:
≤ 25 % of today's).

## Part 4 — Text and glyph fidelity (all default-off, side-by-side first)

- **SGR attributes** (survey §2.8): italic, underline (4 and `4:x`),
  strikethrough, blink, hidden, underline colour, rendered through
  `row-builder.ts`; snapshot stride `STYLE_RUN_WORDS` grows by one word.
  Flag `theme.attributes = "warp" | "plain"`; default `plain` (today's look)
  until the side-by-side is approved.
- **Grapheme clusters** (survey §3.14, §5.9, §7.5): ZWJ/VS16/modifier
  sequences occupy the cells the font draws; `GraphemeBreakTest` corpus as
  the test; one width table shared with the renderer.
- **Width cache** (survey §3.2): per-glyph `letter-spacing` for fallback
  glyphs wider than the cell — only if the baseline screenshot shows drift.
- **Box-drawing glyphs** (survey §1.17): only if the screenshot shows
  hairline gaps between `│` rows at line-height 1.2; then CSS-border/inline
  SVG for U+2500–257F, U+2580–259F.
- **Cursor** (survey §2.12, §1.17): invert over a band whose colour equals
  the cursor's; hollow when unfocused. Flag.
- **IME in the alt-screen prompt** (survey §3.10): composition view at the
  cursor, one send on `compositionend`. Needs a manual Japanese-IME test
  first; no flag needed (only affects composition).

## Part 5 — Act on what Claude Code prints (additive UI only)

- **Logical lines** (survey §4.5): `logicalLines(range)` joins soft-wrapped
  rows; copy yields one line per logical line (closes `TERMINAL.md` §5's
  first gap).
- **Link grammar** (survey §6.4): the ported VS Code suffix table
  (`file:339`, `file:339:12`, `file(339,12)`, `"file", line 339`, …) plus
  URL regex; candidates validated by the host against the workspace.
- **Linkifier** (survey §3.7): hover → per-logical-line providers → underline
  decoration → click with the platform modifier; pointer hand only over a
  link (`TERMINAL.md` §4.12 already reserves it).
- **Hint mode** (survey §2.7, §4.7, §5.5): a chord labels every visible
  match of the rule set (path, `path:line`, URL, sha, UUID, diff header);
  typing a label emits `onHint({ ruleId, text, path?, line? })`; Operator
  opens the file at the line or copies. Nothing is drawn until the chord.
- **OSC 8** (survey §1.15, §7.4): interned URIs with caps; underline on
  hover like detected links.
- **Secret redaction** (survey §7.3): host-supplied patterns painted as
  masked highlights, honoured on copy and in block text sent to mobile or
  summaries. Default off.
- **Block timestamps** (survey §5.3, §6.2): `startedAt/finishedAt` per
  block from the host clock; `onBlockFinished` with duration and visibility
  so Operator can notify on a long tool run finishing while the pane is
  hidden.

## Part 6 — Remote typing (after Part 1.G/H)

- **Predictive echo in the alt-screen prompt** (survey §4.3, §6.5): only when
  measured RTT exceeds a threshold, a dim overlay glyph at the cursor that
  disappears when real output advances the cursor; renderer-only, no model
  change; skipped when the previous keystroke produced no cursor advance
  (password-style prompts).
- **Server-owned model** (survey §4.2): the mirror becomes the model of
  record and clients pull rows by `(stable row, seqno)`; mobile drops its
  `xterm` fork. Its own design spec; Part 1.B/C/G are its prerequisites and
  are designed so that adopting §4.2 later replaces the transport, not the
  core.

## Decisions needed

1. **Caps**: 200,000 rows / 128 MiB per core as proposed, or another pair.
2. **Persist the mirror across app restarts** (Part 1.G last bullet): yes →
   a follow-up plan serialises `ExportBuffers` to
   `~/.operator/sessions/<id>/rows.bin` on shutdown and on a timer; no →
   a restart starts the transcript at the respawn boundary as today.
3. **De-dup heuristic for the SIGWINCH duplicate row** (`TERMINAL.md` §4.8):
   in agent-TUI mode, when a repaint from home starts with a row whose text
   equals the last scrollback row, drop the duplicate. It is a heuristic
   (a genuinely repeated line would also be dropped once). Yes/no.
4. **SGR attributes default**: `plain` (today) or `warp` after the
   side-by-side.
5. **Lazy rewrap** (Part 1.F) vs eager with a higher budget: eager is
   simpler; at 200k rows it is a visible pause on every width change.
   Proposed: lazy.

## Plans this spec produces

| Plan | Scope | Gate |
|---|---|---|
| A. Frame fidelity | Part 2 + baseline harness + feel gate | none |
| B. Long sessions core | Part 1.A, 1.B, 1.C, 1.D, 1.E; Part 3 | A (harness) |
| C. Long sessions edges | Part 1.F lazy rewrap, 1.G replay, 1.H flow control | B |
| D. Text & glyphs | Part 4 | A; each item flag-gated |
| E. Act on output | Part 5 | B (stable rows, logical lines) |
| F. Remote typing | Part 6 predictive echo; §4.2 design spec | C |

Order: A → B → C → D and E in parallel → F. Each plan follows
`TERMINAL.md` §6 for verification (both wasm builds, daemon rebuild, the
Playwright selection gate) plus the baseline table and the feel gate.

## References into the survey

Part 1: §1.2, §1.9, §1.13, §3.1, §3.5, §3.11, §4.1, §4.2, §5.8, §6.3.
Part 2: §1.14, §2.1, §2.10, §3.3, §3.13, §4.4, §5.7, §5.10.
Part 3: §2.3. Part 4: §1.17, §2.8, §2.12, §3.2, §3.10, §3.14, §5.9, §7.5.
Part 5: §1.15, §2.7, §3.7, §4.5, §4.7, §5.3, §5.5, §6.2, §6.4, §7.3, §7.4.
Part 6: §4.2, §4.3, §6.5.
