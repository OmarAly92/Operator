# Terminal reference survey: what other terminals do better, and what we take

**Date:** 2026-09-19
**Decision owner:** Omar Aly
**Status:** survey, input to implementation plans. One section per reference
terminal; sections are appended as each project is surveyed.

## Why

`packages/terminal` was built by cloning Warp's decisions (`TERMINAL.md` §3.2:
"Match Warp, cite Warp"). Warp is one terminal. Other mature terminals solved the
same problems differently, and some of their answers are better for the way
Operator uses a terminal: an agent TUI (Claude Code) repainting every 100ms into a
DOM renderer, with a block list on top, attached late over a daemon.

This document is the evidence base for the next terminal plans. Every approach is
recorded with the reference project's file and line, what our package does today
with our file and line, the gap, and a concrete proposal. A plan written from this
document should not need to re-read the reference project.

Rules carried over from `TERMINAL.md` that every proposal below obeys:

- `packages/terminal` stays product-independent (§3.1). Nothing below adds an
  Operator concept to the package.
- A `vt-core` change is live only after both wasm artifacts are rebuilt (§3.5).
- Every §4 bug in `TERMINAL.md` has a guard test; every proposal here names the
  tests it adds.
- Reference decisions are cited. Adopting a section below adds that project to
  `TERMINAL.md` §3.2 as a second citable reference next to Warp; a comment in
  code cites the reference file the same way `styles.css` cites Warp today.

## How to read an entry

Each approach has the same shape:

| Field | Meaning |
|---|---|
| **Reference** | file:line in the reference project, what the code does |
| **Ours today** | file:line in `packages/terminal` (or `backend/`, `frontend/`), what it does |
| **Gap** | the observable difference, and why it matters for Operator |
| **Proposal** | the change, split by layer: `vt-core`, `vt-wasm`/`vt-host`, `ts/core`, `ts/renderer-dom`, `ts/react`, host |
| **Tests** | the guard tests the plan must add |
| **Priority** | P1 fixes something visible now; P2 correctness under load; P3 hygiene; P4 needs a product decision first |
| **Decision** | only when the proposal departs from a Warp decision already in `TERMINAL.md` |

Absent evidence is written as "not known", never guessed.

## Implementation status (updated 2026-09-25)

Every entry below carries a **Status** line under its heading, checked against the tree on 2026-09-24 (`development`): 45 done, 19 partial, 14 not done, 8 not pursued, 1 not needed, 1 n/a. "Plan A–F" are the agent-TUI spec's plans (`docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`); "Plan 4" is the background-pane plan (`docs/superpowers/plans/2026-09-23-terminal-background-pane-cost.md`). Entries marked non-goal were excluded by the agent-TUI spec, not rejected. "Roadmap Plan 1" is the paste-safety plan (`docs/superpowers/plans/2026-09-24-terminal-plan-1-paste-safety.md`); "Roadmap Plan 3" is the program-messages plan (docs/superpowers/plans/2026-09-25-terminal-plan-3-program-messages.md); "Roadmap Plan 5" is the highlights plan (`docs/superpowers/plans/2026-09-25-terminal-plan-5-highlights-marks.md`); "Roadmap Plan 7" is the very-old-output plan (`docs/superpowers/plans/2026-09-25-terminal-plan-7-old-output.md`). "Roadmap Plan 8" is the agent-awareness plan (`docs/superpowers/plans/2026-09-25-terminal-plan-8-agent-awareness.md`). "Roadmap Plan 9" is the parser-rework plan (`docs/superpowers/plans/2026-09-26-terminal-plan-9-parser-rework.md`).

| Entry | Status | What landed / what is missing |
|---|---|---|
| §1.1 | Done | Plan A, done the §2.1 way — DEC 2026 buffered in `vt-core` (`SyncBuffer`, 150 ms / 2 MiB), flushed on ESU, the deadline or a resize. The renderer-side skip and watchdog were not needed. |
| §1.2 | Done | Plan B — per-row dirty tracking, `Delta`/`take_delta`, incremental `ExportBuffers`, snapshot memoised per generation. Since Plan 4 (2026-09-23) a parked pane does not paint. |
| §1.3 | Partial | Plan B — selection and find hits are keyed by stable row ids, so they survive a trim. Not done: the rewrap `remap` reaches only the viewport anchor, not the selection; no `PinSet`; the cursor is not carried through a reflow. |
| §1.4 | Partial | Plan E — copy joins a soft-wrapped line. Not done: rectangle (Alt-drag), Shift+click / Shift+arrow adjust, the select-block-output gesture, configurable click behaviours. |
| §1.5 | Not done | Shell resize still evicts the frame once (Warp model). A non-goal of the agent-TUI spec. |
| §1.6 | Not done | `decode_osc133` still reads only `A`/`B`/`C`/`D` and `D;<exit>`. A non-goal of the agent-TUI spec. |
| §1.7 | Done | Plan 2 — `FindSession` on the core: settled history scanned once from `scanned_to` and never again; the unsettled tail and the live screen re-searched only when the generation changes; hits re-resolve through the row index after a trim or rewrap. Also fixed: panes without OSC 133 marks (Claude Code) and rows still on the screen were never searched. |
| §1.8 | Done | Roadmap Plan 5 — `highlights.ts` (ranges in stable rows, a kind, a priority) painted only by `highlight-painter.ts`; selection, find hits and user marks all go through it (`renderer-highlights.ts`). Links, hints, redaction and prediction stay overlays in `decorations.ts` because they paint above the text. Find hits keep their whole-row look. |
| §1.9 | Done | Plan C — `vt_replay` sends origin, modes, the frame, `READY`, then history in 512-row chunks; the pane paints at `READY`. |
| §1.10 | Done | Roadmap Plan 1 — `encodePaste` returns the bytes and a verdict; outside bracketed paste a newline, a C0 control other than tab, or `ESC[201~` is unsafe and goes to `HostCapabilities.confirmPaste` (Operator: a dialog with the first five lines); no handler sends as before. The editor-owned line never asks. The confirm is a host seam, not surface chrome as the entry proposed. |
| §1.11 | Not done | `print` is still per character with a style resolve each; no `print_run`, no unknown-sequence ring (Plan A's `trace` feature is a debug build, not the ring). |
| §1.12 | Not done | No `RowFlags`; `ScreenGrid` keeps separate `wrapped` and `dirty` vectors. |
| §1.13 | Done | Plan B — `Limits { rows: 200_000, bytes: 128 MiB }` in both cores, plus `memory_stats`. Compression was excluded by the proposal itself. Open: the OSC 8 registry sits outside the byte budget (`TERMINAL.md` §5). |
| §1.14 | Partial | Plan A — `verify_integrity`, the proptest generator and the `trace` feature. Not done: failure injection, pyte agreement in the proptest. |
| §1.15 | Done | Plan E — OSC 8 and hover links. Roadmap Plan 3 — OSC 0/2 title (card and pane header in Operator), OSC 9/777/99 notifications (toast when the pane is not on screen), OSC 10/11 replies from the pane's colours, OSC 22 pointer shape. |
| §1.16 | Done | Roadmap Plan 3 — the mirror answers XTWINOPS 14/16/18 `t` and mode 2048 from the grid and the pane's cell size (device pixels). Coalescing was already adequate (`RESIZE_DEBOUNCE_MS` = 100). |
| §1.17 | Partial | Plan D — contrast-inverted and hollow-unfocused cursor behind flags (both off); box drawing measured and ruled out (`boxGapPx` = 0). Not done: the `minContrast` theme option, dropped by the Plan D spec without a recorded decision. |
| §1.18 | Not done | The shell scripts still emit bare `133;A/B/C/D`; no `redraw=`, `k=s` or `133;P`. Folded into §1.6. |
| §2.1 | Done | Plan A — DEC 2026 buffered in `vt-core` (`SyncBuffer`, 150 ms / 2 MiB), pump holds across a block. |
| §2.2 | Not pursued | Roadmap Plan 9 (2026-09-26) measured `vte::ansi::Handler`: XTVERSION, `CSI 16 t`, OSC 9/99/777/133/7000 and raw parameters reach no method, SGR 21/53/`38;5;300`/`4:6` decode differently, REP/`ESC Z`/`ESC # 8` start doing something, and `Processor::new` allocates 2 MiB per core; there is no partial adoption (`TERMINAL.md` §4.35). The `ansi` feature does not need `std`. |
| §2.3 | Done | Plan B — selection damage diffed against the previous paint (one row repainted per selection step) and one moved cursor element. Column bounds were ruled out by the entry itself for a DOM renderer. |
| §2.4 | Not done | No pull-back on height growth and no cursor-carrying reflow; waits on §1.5. The wide-character-at-the-cut case was already covered. |
| §2.5 | Partial | Plan B — `onRowEvents` (trim and rewrap `remap`) and stable rows make trims harmless. Not done: the selection does not apply `remap`, so a width change moves it. |
| §2.6 | Partial | Plan 2 — smart case (Alacritty `search.rs:39-40`) for literals and regexes, and a regex toggle in the find bar. Next/previous is an index step through the session's sorted results, so directional DFAs were not needed. Not done: `bracket_search`, `semantic_search_*`. |
| §2.7 | Done | Plan E — hint mode on Ctrl+Shift+Space with labels and `onHint`. Not done: host-supplied rules (package constant only) and Alacritty's bracket post-processing. |
| §2.8 | Done | Plan D — ten attribute bits and underline colour in the style word; painted with `attributes: "warp"`, the default since 2026-09-23 (`534ef20fe`). |
| §2.9 | Done | Plan A — `tests/ref` with Alacritty's recordings plus our own. |
| §2.10 | Done | Plan A — `enqueue`/`drain` with a 12 ms budget per animation frame. Plan 4 added a 250 ms drain per timer tick while the window is hidden (`cb7b34b3b`). |
| §2.11 | Done | Roadmap Plan 1 — inside bracketed paste `ESC[201~`, every `ESC` and every `^C` are removed and the paste is sent without asking; outside, `\r\n`/`\n` still become `\r`. |
| §2.12 | Done | Plan D — `cursorContrast` and `cursorHollowUnfocused` flags, both still off: `cursorContrast` changes 0 px on the Claude Code recordings (`TERMINAL.md` §5). |
| §2.13 | Not pursued | The entry itself says not recommended, and the agent-TUI spec lists it under non-goals. |
| §2.14 | Done | Roadmap Plan 3 — title stack capped at 4,096 (oldest dropped), pending notifications at 16, titles at 1,024 bytes. There is no keyboard-mode stack to cap. The grapheme byte cap (256) was already in place. |
| §3.1 | Done | Plan B — row-element pool with dirty-row patching. The ≤ 2 nodes per changed row target was missed (≈7 per styled row). Since Plan 4 a parked pane does not paint; row layout containment was measured with no gain (`TERMINAL.md` §4.26). |
| §3.2 | Done | Plan D — per-cluster letter-spacing from a width cache, on by default together with `graphemes` since 2026-09-22 (`7395b910c`); ZWJ and flag clusters are measured as one span. The ligature joiner is not adopted (Hack has no ligatures). |
| §3.3 | Done | Plan A — char metrics cached, invalidated by `setFont`, `setTheme` and the DPR query. No `ResizeObserver` on the measure host and no `TextMetrics` path, both by decision (Plan A deviations). |
| §3.4 | Done | Covered by §2.1: `vt-core` buffers DEC 2026, so a sync frame lands as one dirty set and one paint; no renderer timeout needed. |
| §3.5 | Done | Plan B — done as stable row ids plus `onRowEvents` (trim and remap) rather than xterm.js markers. |
| §3.6 | Partial | Plan E — an internal overlay layer positioned from geometry (link underline, hints, redaction masks, echo prediction). Not done: host `registerDecoration`/`onRender`, the overview ruler; find hits are not decorations. |
| §3.7 | Done | Plan E — linkifier: OSC 8 provider first, URL and path providers second, per hovered logical line. Path detection rebuilt from Operator's own rules 2026-09-23 (`b17acd63c`). |
| §3.8 | Partial | Plan E — copy joins a soft-wrapped line; Plan B — selection on stable rows with a per-row damage diff. Not done: the overlay container (the fill is still per row) and column (Alt) selection. |
| §3.9 | Not done | No screen-reader mode, row roles or live region for output; the only `aria-live` is the find-bar counter. |
| §3.10 | Done | Plan D — composition view at the cursor and one send a tick after `compositionend`. Manual Japanese-IME check still pending. |
| §3.11 | Done | Plan C — the replay re-emits the child's modes before the frame. Soft-wrapped history rows are still replayed unjoined (`TERMINAL.md` §5). |
| §3.12 | Partial | Plan 2 — the find bar updates on every paint through `findUpdate` (new matches appear without retyping; history is not rescanned) and keeps the current hit anchored by stable row. Plan 5 — hits paint through the highlight model (§1.8), still whole rows. Not done: a host `onResultsChanged`. |
| §3.13 | Partial | Plan A (12 ms budget) and Plan C (ack every 5,000 bytes, pause at 100,000); a hidden window drains 250 ms per tick (Plan 4). No 50 MB discard watermark. |
| §3.14 | Done | Plan D — grapheme-cluster widths, on by default since 2026-09-22 (`7395b910c`); the renderer reads exported cell spans. The pty-host mirror stays in scalar mode (`TERMINAL.md` §5). |
| §3.15 | Partial | Plan A — `onFeedParsed`. Not done: the Windows wrapped-line heuristic, OSC 9;4 progress, the Kitty keyboard encoder. |
| §4.1 | Done | Plan B — stable rows (`trimmed_total`, `first_stable_row`, `BlockGrid::origin`). |
| §4.2 | Not pursued | Design spec written in Plan F (`2026-09-22-server-owned-terminal-model-design.md`); implementation dropped 2026-09-22 — Claude Code lays out its own rows, so there are no logical lines a phone could rewrap. |
| §4.3 | Done | Plan F — desktop-only overlay above a 30 ms host RTT threshold, off by default (Settings). The phone has none. |
| §4.4 | Partial | Plan A — the pump holds across a DEC 2026 block. The 3 ms poll was not added: the pump already coalesces at 1/60 s. |
| §4.5 | Done | Plan E — per-row `wrapped` export, `logicalLines`, copy joins a soft-wrapped line. History prepended on reopen stays single rows. |
| §4.6 | Not done | No per-row semantic tag and no `semanticZones` query. |
| §4.7 | Done | Plan E — hint rules are WezTerm's minus IPFS, with Kitty's `path:line` first; WezTerm's label algorithm. No host seam to replace the rule set. |
| §4.8 | Not done | No `hasUnseenOutput` and no OSC 9;4 progress. Alt-screen and mouse-tracking state were already on the snapshot. |
| §4.9 | Not pursued | The entry counts it as equal: a finished session keeps its blocks and a relaunch adds a process-boundary block (`TERMINAL.md` §4.15). |
| §4.10 | Partial | Plan A — a shared `tests/common` (integrity and cell-span check) and the `tests/ref` harness. No `TestTerm` helpers. |
| §5.1 | Done | Covered by §2.1 (`vt-core` buffers DEC 2026; the pump holds across a block). |
| §5.2 | Not done | `zsh.sh` still emits bare `133;A/B/C/D`; no `k=s`, no `cmdline`, no cursor shape by keymap. A non-goal of the agent-TUI spec. |
| §5.3 | Partial | Plan E — `onBlockFinished` with duration and visibility. Plan 4 — a hidden window still drains and reports (`cb7b34b3b`); unloaded shell panes notify from the daemon (`13ad4994d`). macOS toasts `59624c9a9`. Not done: `lastVisitedBlockId` and `readBlockOutput` defaulting to it. |
| §5.4 | Not done | Shell resize still evicts the frame; Kitty's exempt-the-prompt option was not taken up. A non-goal of the agent-TUI spec. |
| §5.5 | Done | Plan E — `path:line` hints and links open through the host; since `fdc202778` the editor chosen in Settings (VS Code, Cursor, Zed) opens at the line and column. The default "system" opener opens the file without the line. |
| §5.6 | Done | Roadmap Plan 5 — `DomBlockRenderer.setMarks` / `TerminalSurface` `marks` (`MarkRule { pattern, regex, colour }`), matched per painted logical line; Operator Settings → Terminal highlights. Not built: next/previous-mark navigation. |
| §5.7 | Not pursued | Replaced by the pump hold (1/60 s coalescing, held across a DEC 2026 block) and the 12 ms drain budget (agent-TUI spec). |
| §5.8 | Done | Roadmap Plan 7 (2026-09-25) — the pty-host mirror keeps rows trimmed past the cap as SGR text in a 32 MiB cold ring; the pane's Load older output fetches ≤ 2,048 rows as a history chunk. Plan C — lazy rewrap for cold scrollback (`HOT_ROWS = 2_000`). Fixed segments were already ours (`Content` is chunked). |
| §5.9 | Done | Plan D — `unicode-width`/`unicode-segmentation` on Unicode 17, tested against `GraphemeBreakTest.json`; `graphemes` on by default since `7395b910c`. |
| §5.10 | Done | Plan A — `vt-core` `feature = "trace"` records every dispatched action with its stream offset (Kitty's `REPORT_COMMAND`), which was the whole proposal. |
| §6.1 | Not done | No nonce, `trusted` flag or continuation property. The rerun action fills the line editor and does not execute. |
| §6.2 | Partial | Plan E — block timestamps from the feed clock, timed from output start (`288cb4770`); links resolve against the hovered block's cwd. Not done: confidence, invalidation, serialisation, PS2/right-prompt stripping, core `blockForRow`/`cwdForRow`. |
| §6.3 | Partial | Plan C — replay with block marks and flow-control acks. Roadmap Plan 4 (2026-09-24) — a pty-host that fails 3 reaper probes in a row is marked hung and its pane offers Restart terminal; the mirror's attach replay is saved every 60 s and replayed into the next host for a relaunched session. Not done: resize-aware ring. |
| §6.4 | Done | Hover tries the spans through the hovered cell, longest first, in one capped `resolveFirstPath` host call; VS Code's suffix grammar (ported with its test table) strips the line/column; VS Code's per-line caps. Multi-line and word links not done. |
| §6.5 | Done | Plan F — renderer-only overlay armed above a 30 ms host RTT, off by default; behavioural exclusions (no-echo, row jump, alt screen, paste, control keys, open 2026 block, TTL). Overlay-only is the proposal's own choice, so no timeline. Phone not pursued. |
| §6.6 | Not done | No quick-fix matcher or `onQuickFix`. A non-goal of the agent-TUI spec. |
| §6.7 | Not pursued | Not adopted by the entry itself; `pinned-header.ts` pins the block header, not the prompt. |
| §6.8 | Not done | Line-editor history reads only this session's blocks. A non-goal of the agent-TUI spec. |
| §6.9 | Partial | Roadmap Plan 8 (2026-09-25) — `ts/core` has `agentActivity()`/`onAgentActivity` (active / pollingForIdle / idle / prompting from live output, 500 ms / 1,500 ms, VS Code's high-confidence prompt patterns) and `readBlockOutput(id, { compact, maxLines })` (spinner lines and redrawn frames dropped). Not done: Operator does not consume either; no tool surface (run/get-output/send), no user-input tracking while prompting, no per-command compressors. |
| §6.10 | Done | Already before the survey: block headers show duration (`fa6cec10b`); block actions include copy, share, bookmark, filter, jump and rerun; `block-nav`. Nonce gating is §6.1. |
| §6.11 | Done | A parked pane sends no resize; on show its grid goes through the normal debounced publish (`be9d35222`, `TERMINAL.md` §4.24). Plan 4 added the visibility seam, paint gate and 30-minute unload. Rows-immediate not adopted (`TERMINAL.md` §4.6). |
| §7.1 | Partial | Roadmap Plan 8 (2026-09-25) — `vt-core` parses `OSC 777 ; agent-state ; v=1 ; state=… [; detail=…]` (our format, `protocol/SPEC.md` §10) into `onAgentEvent`, never from history, older answers or the replay frame; Plan 3 already parses OSC 777 `notify` and OSC 9. Not done: nothing emits it (Operator's hooks stay out of band, loopback HTTP) and Operator consumes none; remote/SSH agents are future work. |
| §7.2 | Partial | Background output after the last block is kept as a running synthetic block (`e7684bed8`). Typeahead done for zsh (roadmap Plan 6): the shell reports text typed during a command at its next prompt, the line editor adopts it only if the user typed it and clears the shell's copy with `^U` (`TERMINAL.md` §4.32). bash and fish keep the old behaviour. |
| §7.3 | Done | Plan E — the daemon's patterns masked in copy, selection, links, hints and block text; default off. The phone view is not masked, and a masked token stays readable by assistive tech (`TERMINAL.md` §5). |
| §7.4 | Done | Plan E — capped, never-reclaimed registry; the link id is the sixth style word. |
| §7.5 | Done | Plan D — cells, word boundaries and selection step by exported cell spans. The cursor covers a whole cluster only with `cursorContrast` (off); the line editor steps by code point. |
| §7.6 | Done | Plan A — `OPERATOR_PTY_RECORD` plus the Alacritty-derived ref tests. |
| §7.7 | Not pursued | With §4.2. The phone already co-views as a secondary mux client; replay covers reattach. No browser share links. |
| §7.8 | Not pursued | The package design forbids reading ssh arguments or running commands in the user's session (`2026-08-29-warp-terminal-package-design.md`); OSC 133 from a remote shell works without setup. |
| §7.9 | Not needed | `LineEditorState` (`Unknown`/`Owned`/`Released`) and `altScreen` on the snapshot already match Warp. |
| §7.10 | N/A | A do-not-clone list, not a proposal. |

## Our package in one paragraph (for the reader who has not opened it)

`crates/vt-core` is the model: `ScreenGrid` (`screen.rs`) for the live
rows×cols ring, `Content` + `RowIndex` + `AttributeMap` (`scrollback.rs`,
`content.rs`, `row_index.rs`, `attribute_map.rs`) for append-only scrollback,
`BlockGrid` (`block_grid.rs`) for OSC 133 / OSC 7000 blocks over the flat row
space, `Parser` (`parser.rs`, on the `vte` crate 0.15) for the byte stream, and
`GridSnapshot` (`grid.rs`) as the only read API. `crates/vt-wasm` exports the
snapshot as flat buffers for the browser; `crates/vt-host` is the C-ABI wasm the
Go pty-host runs as a passive mirror for attach replay. `ts/core` wraps the wasm
(`terminal-core.ts`), `ts/renderer-dom` paints blocks into the DOM
(`dom-block-renderer.ts`) and owns the selection (`selection-model.ts`),
`ts/react` is the `TerminalSurface` (grid measurement, keys, mouse, paste).
`shell/` holds our zsh/bash/fish integration emitting OSC 133 + OSC 7000.

---

## 1. Ghostty

**Repository:** `/Users/omaraly/development/AI/ghostty` at commit `b32f20f3e`
(2026-09-18, "terminal: add option to disable scrollback pull on resize").
**Language:** Zig. **Relevant tree:** `src/terminal/` (the VT model, ~97k lines,
also shipped as libghostty-vt), `src/renderer/` (Metal/OpenGL/WebGL cell
renderer), `src/termio/` (pty I/O thread), `src/font/sprite/` (procedural
glyphs), `src/shell-integration/`.

**Why Ghostty is worth mirroring:** its terminal model is the most heavily
tested of the open-source terminals (tests live beside the code: `Terminal.zig`
is 16.5k lines, most of it tests), it is designed to be embedded (libghostty-vt,
the `snapshot/` format, `RenderState`), and several of its choices were made
after measuring exactly the problem we have: a renderer that re-reads the whole
screen every frame.

The survey covers everything in `src/terminal`, the renderer's terminal-facing
decisions, and `termio`. GPU rendering, font shaping, Kitty graphics, the
inspector UI and the platform apprts are listed under "not adopted" with a
reason.

### 1.1 Synchronized output (DEC private mode 2026)

> **Status: Done.** Plan A, done the §2.1 way — DEC 2026 buffered in `vt-core` (`SyncBuffer`, 150 ms / 2 MiB), flushed on ESU, the deadline or a resize. The renderer-side skip and watchdog were not needed.

**Reference**
- Mode table: `src/terminal/modes.zig:340` —
  `.{ .name = "synchronized_output", .value = 2026, .default_configurable = false }`.
- On `?2026h` the IO thread arms a reset timer:
  `src/termio/stream_handler.zig:713-714` sends `start_synchronized_output`;
  `src/termio/Thread.zig:378-388` (`startSynchronizedOutput`) starts a
  `sync_reset_ms = 1000` timer (`Thread.zig:38`); `Thread.zig:409`
  (`syncResetCallback`) → `src/termio/Termio.zig:567`
  (`resetSynchronizedOutput`) clears the mode if the application never sends
  `?2026l`.
- The renderer skips the frame while the mode is set:
  `src/renderer/generic.zig:1366-1369` (`if (state.terminal.modes.get(.synchronized_output)) return;`
  inside `updateFrame`, `generic.zig:1313`).
- A resize forces the mode off: `src/terminal/Terminal.zig:4071`
  (`self.modes.set(.synchronized_output, false)`), with rollback on failure at
  `Terminal.zig:4049-4053`.

**Ours today**
- `crates/vt-core/src/parser.rs:462-470` handles `CSI ? … h/l`: mode 1 is
  application cursor keys, everything else goes to `note_private_mode`
  (`parser.rs:199-220`: 1006, 2004, 1004, 1000/1002/1003; any other mode
  returns without effect). 1049 is handled by the screen's `csi`. 2026 is not
  among them (`grep -rn 2026 crates/vt-core/src` → no match).
- `ts/renderer-dom/src/dom-block-renderer.ts:306-324` schedules `repaint` on
  `requestAnimationFrame` after every `feed`; `repaint` (`:362`) reads whatever
  bytes have been parsed so far.
- The installed Claude Code (`/opt/homebrew/Caskroom/claude-code@latest/2.1.273/claude`)
  contains `\x1b[?2026h` and `\x1b[?2026l` (verified with `strings`), alongside
  1000/1006/1049. It brackets every Ink frame with them.

**Gap**
A frame Claude Code writes in several `write()` calls can be painted half-drawn:
the top of the new frame over the bottom of the old one for one animation
frame. That is the flicker under the spinner. Every terminal that honours 2026
(Ghostty, Kitty, WezTerm, Alacritty, Warp since 2024) avoids it; we ignore the
mode entirely.

**Proposal**
- `vt-core`: `Parser` gains `synchronized: bool` set by `?2026h`, cleared by
  `?2026l`, by `resize()` (Ghostty `Terminal.zig:4071`), and by `process_boundary`.
  Expose `TerminalCore::synchronized_output()`; `GridSnapshot` does not need it.
- `vt-wasm`: export the getter. `vt-host`: nothing (the mirror only needs the
  final state).
- `ts/core`: `TerminalCore.synchronizedOutput(): boolean`.
- `ts/renderer-dom`: `repaintOnFrame` returns early while
  `core.synchronizedOutput()` is true, keeping the rAF chain alive; a 1000ms
  watchdog (Ghostty's `sync_reset_ms`) started on the first skipped frame
  forces a repaint and asks the core to clear the flag (`clearSynchronizedOutput()`
  on the wasm API) so a crashed app cannot freeze the pane.
- Nothing changes in the pty-host or the daemon.

**Tests**
- `vt-core/tests/synchronized_output.rs`: `?2026h` sets, `?2026l` clears, resize
  clears, boundary clears, unknown modes still ignored.
- `dom-block-renderer.test.ts`: "does not paint while synchronized output is set",
  "paints the final frame after ?2026l", "watchdog paints after 1000ms".
- `bench/` fidelity: feed a captured Ink frame split at an arbitrary byte and
  assert a single paint.

**Priority:** P1. See §2.1 for the parser-buffered variant (`vte::ansi`),
which supersedes the renderer-side skip and watchdog proposed here.

### 1.2 Dirty tracking and a stateful render view instead of a full rebuild per frame

> **Status: Done.** Plan B — per-row dirty tracking, `Delta`/`take_delta`, incremental `ExportBuffers`, snapshot memoised per generation. Since Plan 4 (2026-09-23) a parked pane does not paint.

**Reference**
- Per-row dirty bit: `src/terminal/page.zig:2067-2078` (`Row.dirty`, "set to true
  by any operation that modifies the row's contents or position, and consumers
  of the page are expected to clear it when they redraw"); per-page dirty at
  `page.zig:184-190`; `Page.isDirty` at `page.zig:1719-1723`.
- PageList level: `src/terminal/PageList.zig:6893` (`clearDirty`), `:6905`
  (`isDirty`), `:6910` (`markDirty`), and `Pin.markDirty` at `:7172`.
- `RenderState`, `src/terminal/render.zig:72`. Header comment `render.zig:26-40`:
  the renderer used to `clone` the viewport each frame, "the clone time was
  repeatedly a bottleneck blocking IO", replaced by a stateful `update` that
  touches only dirty rows. `Dirty` enum `render.zig:280-295`: `false` (skip the
  frame), `partial` (some rows), `full` (dimensions or colours changed). Per-row
  `dirty` for the renderer's own bookkeeping `render.zig:228-231`; per-row
  `applied_styles` so a row whose text changed but styling did not skips the
  style fill (`render.zig:238-252`).
- Two-phase update so the terminal lock is held briefly: `render.zig:44-60`
  (`beginUpdate` under the mutex, `endUpdate` on memory the render state owns).
- Comment on placement: `render.zig:20-23` — it lives in `src/terminal`, not
  `src/renderer`, so it stays generic to any renderer (libghostty-vt).

**Ours today**
- `ts/renderer-dom/src/dom-block-renderer.ts:362-480` (`repaint`): every frame
  calls `core.snapshot()` (a full export of every row's content, styles, blocks),
  `decodeBlocks(snapshot)`, then for every visible block `populateBlock`.
- `ts/renderer-dom/src/block-body.ts:19-44` (`populateBlock`): builds a fresh
  `DocumentFragment`, `buildRowNode` for every row in the window (new `div` and
  `span`s, `row-builder.ts:36-116`), and `section.replaceChildren(fragment)`.
  No row element survives a repaint.
- `TERMINAL.md` §4.13 records the cost already paid for this: the browser
  selection was destroyed by the rebuild and had to move into the model.
- `TERMINAL.md` §5: every selection operation takes a fresh `core.snapshot()`
  and `decodeBlocks()` because the `Uint8Array` view goes stale when wasm
  memory grows.

**Gap**
Under Claude Code's 100ms spinner the whole visible window (up to
`OVERSCAN_ROWS` + viewport rows, `dom-block-renderer.ts:45`) is exported,
decoded and rebuilt ten times a second while a single row changed. It is the
main CPU cost of an idle Operator window with a few panes open, and it is why
the selection had to be re-architected. Ghostty measured the same class of
cost and removed it.

**Proposal**
- `vt-core`: a `generation: u64` on `ScreenGrid` incremented per mutation, a
  per-screen-row `dirty` bitset set by every write path (`print`, erase,
  scroll, insert/delete lines, resize, `evict_frame`) and cleared by a
  `take_dirty()` call; a `scrollback_len_at_last_snapshot` so appended
  scrollback rows are known to be new; a `full` flag set by resize, rewrap,
  `trim_to`, alt-screen switch, palette/theme change. Mirrors Ghostty's
  `Dirty { false, partial, full }`.
- `vt-wasm`: export `dirty_kind()`, `dirty_rows_ptr/len` (screen rows), and the
  scrollback row range appended since the last snapshot. Snapshot export
  itself stays whole for now (the flat buffers are cheap; the DOM is not).
- `ts/renderer-dom`: `populateBlock` keys row nodes by absolute snapshot row
  (`data-terminal-row`), keeps them in a `Map` on the block element, and
  patches only rows in the dirty set (text runs rebuilt for that row only),
  moves/creates nodes for new rows, and drops nodes that left the window. On
  `full`, today's rebuild path runs. The cursor element moves instead of being
  recreated.
- `TERMINAL.md` §5 memoisation: cache `decodeBlocks(snapshot)` per generation
  so a mouse move during selection no longer decodes.

**Tests**
- `vt-core/tests/dirty.rs`: printing marks one row; scroll marks the ring
  rows that moved; resize/rewrap/trim/alt switch set `full`; `take_dirty`
  clears; the host mirror never calls it and is unaffected.
- `dom-block-renderer.test.ts`: "keeps the row elements that did not change"
  (identity check on `HTMLElement`s across a repaint), "rebuilds all rows on a
  full dirty", "moves the cursor element instead of recreating it".
- `bench/selection-gate.mjs` keeps passing (the selection is already
  model-owned; this removes the reason it had to be).
- A bench number: paints per second and DOM nodes created per paint under the
  captured Claude Code spinner stream, before and after.

**Priority:** P2 (P1 if the idle CPU of a multi-pane window is on the table).

### 1.3 Tracked pins: positions that survive scroll, eviction and reflow

> **Status: Partial.** Plan B — selection and find hits are keyed by stable row ids, so they survive a trim. Not done: the rewrap `remap` reaches only the viewport anchor, not the selection; no `PinSet`; the cursor is not carried through a reflow.

**Reference**
- `Pin` type: `src/terminal/PageList.zig:7113` — `(page node, row y, x)`.
- Tracking: `PageList.zig:5672` (`trackPin`), `:5688` (`untrackPin`), `:5708`
  (`pinIsValid`); the set of tracked pins `PageList.zig:460`. Every operation
  that moves rows (scroll-off, erase, reflow, page split/compact) walks the
  tracked pins and rewrites them (`PageList.zig:879`, and throughout
  `resizeCols` `:1343` via `ReflowCursor` `:1588`).
- Consumers: the viewport (`pin_preheat` comment `PageList.zig:44-46`), the
  cursor and saved cursor through a reflow (`src/terminal/Screen.zig:2037-2049`
  and `:2153-2161`), selection bounds (`src/terminal/Selection.zig:41-52`,
  `tracked` vs `untracked`, `Selection.track` `:131`), the press point of a
  drag gesture (`src/terminal/SelectionGesture.zig:41-49`), search highlights
  (`src/terminal/highlight.zig:62`, `Tracked`).
- `Resize.Cursor.pin` (`PageList.zig:1249-1256`): "preserves right-side blank
  cells up to the cursor during reflow", so a prompt with the cursor after
  trailing spaces keeps its column.

**Ours today**
- Selection anchors are `(blockId, row, column, side)` in
  `ts/renderer-dom/src/selection-model.ts`; `repaint`
  (`dom-block-renderer.ts:404-407`) drops the selection only when a block id
  disappears. A rewrap (`row_index.rs::rewrap`, `TERMINAL.md` §4.2) moves row
  boundaries under the anchors, so after a width change the selection covers
  different text. `trim_to` (`lib.rs:116,175`) evicts the head block and the
  selection is dropped.
- Find results are recomputed from `Content` per query (`crates/vt-core/src/find.rs`)
  and expressed as byte ranges; there is no anchored "current match".
- The cursor after a shell-mode resize is repositioned by `resize_cells`
  (`screen.rs:506-508`: clamp row and column), not carried through a reflow;
  §4.10 policy evicts the frame instead.
- `RowIndex::rewrap` already produces an old-row → new-row `map` used by
  `BlockGrid::remap_rows` (`TERMINAL.md` §4.2).

**Gap**
Nothing in our model can hold "this position" across a mutation except a block
id. Ghostty's pins are the single mechanism behind a selection that survives a
resize, a find match that stays highlighted while output streams, and a cursor
that lands on the same text after reflow.

**Proposal**
- `vt-core`: a `PinSet` on `Parser` holding `Pin { row: usize (flat row space), col: u16 }`
  entries with handles. Every row-moving operation already goes through three
  places: `commit_evicted`/`trim_to` (rows shift up by the evicted count),
  `RowIndex::rewrap` (the `map`), and `evict_frame`/`process_boundary`. Each
  applies the same transform it applies to `BlockGrid`. Because `Content`
  offsets never move, a scrollback pin can be stored as a byte offset and
  resolved to a row through `RowIndex` on read, which makes rewrap free for
  scrollback pins; only screen-row pins need the map. Expose `track_pin`,
  `untrack_pin`, `pin_position(handle) -> Option<(row, col)>`.
- `vt-wasm`/`ts/core`: the three calls.
- `ts/renderer-dom`: `selection-model.ts` stores pin handles for head and tail
  and resolves them per paint; a pin that resolves to `None` (evicted) clamps to
  the first row. Find keeps a pin per match while the find bar is open.
- `ts/react`: `selection-gesture.ts` pins the press point (Ghostty
  `SelectionGesture.zig:41-49`) so a drag during streaming output extends from
  the text the user pressed on, not from a row number.

**Tests**
- `vt-core/tests/pins.rs`: a pin on a scrollback row survives eviction of rows
  above it, a rewrap that splits/joins its line, and `trim_to` (resolves to
  `None` when its row is trimmed); a pin on a screen row moves with scroll and
  with `evict_frame`.
- `selection-model.test.ts`: "a selection survives a width change and still
  covers the same text", "a selection whose head was trimmed clamps".
- `selection-gesture.test.ts`: "a drag anchored on a row that scrolled up keeps
  the anchor".

**Priority:** P2. Prerequisite for 1.4 (selection extras) and 1.7 (search).
See §2.5 for the lighter rotate-based alternative and §3.5 for the
event-driven marker variant, which is the recommended one.

### 1.4 Selection model and gesture

> **Status: Partial.** Plan E — copy joins a soft-wrapped line. Not done: rectangle (Alt-drag), Shift+click / Shift+arrow adjust, the select-block-output gesture, configurable click behaviours.

**Reference**
- `src/terminal/Selection.zig`: `rectangle: bool` (`:30`) for column/block
  selection; `Bounds` tracked or untracked (`:42`); `adjust`
  (`:414`) with `Adjustment` (`:399-410`: left/right/up/down/home/end/
  page_up/page_down/beginning_of_line/end_of_line) for keyboard-driven
  selection growth; `containedRowCached` (`:319`) to answer "is this cell
  selected" per row without re-ordering the pins.
- `src/terminal/Screen.zig`: `selectLine` (`:3017`), `selectAll` (`:3181`),
  `selectWordBetween` (`:3243`), `selectWord` (`:3274`), `selectOutput`
  (`:3365`, select the whole output of the command under the pointer using
  OSC 133 row marks), `selectionString` (`:2942`) and `selectionStringMap`
  (`:2954`, string plus a per-character map back to cells, used by search and
  link detection).
- `src/terminal/SelectionGesture.zig`: one type owns press/drag/release/
  autoscroll (`:278`, `:352`, `:558`, `:456`); click count with
  `repeat_interval` and `max_distance` (`:246-256`); behaviours per click count
  default `.{ .cell, .word, .line }` (`:152`); `reset` for cancellation when
  mouse reporting turns on or the screen changes (`:193`, doc `:29-39`); the
  press pin is tracked so output scrolling does not invalidate the drag
  (`:41-49`); `deepPress` for macOS force click → word selection (`:493-520`);
  the type is deliberately not concurrency safe and says so (`:52-61`).

**Ours today**
- `ts/renderer-dom/src/selection-model.ts` (head/tail grid points, half-cell
  side), `selection-geometry.ts`, `selection-text.ts`, `selection-fill.ts`;
  `ts/react/src/selection-gesture.ts` is the pure state machine (drag
  threshold, click-count word/line, autoscroll curve, copy chord) —
  `TERMINAL.md` §4.13.
- No rectangle selection, no keyboard adjustment, no "select this block's
  output" gesture (block actions exist in `block-actions.ts`; copying a block's
  output goes through `readBlockOutput`, §5 known gap: soft-wrapped lines copy
  as several lines).
- Word boundaries: `words.ts` with Warp's boundary set.

**Gap**
Feature parity is close for mouse selection. Missing: rectangle (Alt-drag)
selection, Shift+arrow extension, select-output of a block by triple-click on
its body, and — from 1.3 — anchors that survive mutation. `selectionStringMap`
is the piece that makes "copy the logical line, not the visual rows" and
"search hit → cells" cheap.

**Proposal**
- `ts/renderer-dom`: `selection-model.ts` gains `rectangle: boolean`; geometry
  and text honour it (Ghostty `Selection.zig:30` semantics: pins are the
  rectangle's corners in either order). `adjust(kind)` with Ghostty's
  `Adjustment` set. `selectOutput(blockId)` returns the block's output rows.
- `ts/react`: Alt (Option) held at press → rectangle; Shift+click extends;
  Shift+arrows call `adjust`; triple-click behaviour becomes configurable per
  click count the way `default_behaviors` is (host passes a
  `[cell, word, line]` array; Operator keeps Warp's defaults).
- `selection-text.ts`: copying joins rows whose `wrapped` flag is set (closes
  `TERMINAL.md` §5 first gap). Needs `wrapped` per row in the snapshot; add it
  through the §2 checklist (`GridSnapshot` + `append_row` + `ExportBuffers` +
  `types.ts` + `exit_encoding.rs`).

**Tests**
- `selection-model.test.ts`: rectangle bounds in both drag directions;
  `adjust` for every kind at the edges of the buffer.
- `selection-text.test.ts`: "a soft-wrapped line copies as one line",
  "a rectangle copies one slice per row".
- `TerminalSurface.mouse.test.tsx`: Alt-drag, Shift-click extend,
  Shift+arrow grow.

**Priority:** P3 (P2 for the wrapped-copy fix, which is a known gap).

### 1.5 Resize: redraw the prompt in place instead of pushing the frame into scrollback; pull scrollback back on growth

> **Status: Not done.** Shell resize still evicts the frame once (Warp model). A non-goal of the agent-TUI spec.

**Reference**
- `src/terminal/Terminal.zig:4092-4099`: the primary screen resizes with
  `reflow = modes.wraparound`, `prompt_redraw = flags.shell_redraws_prompt`,
  `pull_scrollback = flags.resize_pull_scrollback`; the alternate screen with
  `reflow = false` (`:4108-4114`), and if the alternate resize fails it is
  replaced by an empty screen rather than failing the resize (`:4116-4130`).
- `src/terminal/Screen.zig:2232-2290` (`clearPromptForRedraw`): after the
  reflow, if the cursor's row is prompt or input (`cursor.semantic_content != .output`),
  clear from the last `OSC 133 A` row to the cursor (`.true`) or only the
  cursor's row (`.last`, a Ghostty extension), so the shell's own SIGWINCH
  redraw lands on blank rows instead of over the old prompt. The comment at
  `:2240-2246` explains why it checks `semantic_content` and not the row flag
  (Nushell marks `B` but not `k=s` continuations).
- The flag comes from the shell: `Terminal.zig:2110-2115` reads
  `redraw=` off `OSC 133 ; A` (`osc/parsers/semantic_prompt.zig:86-88`,
  `Redraw` enum `:307`); default `.true` (`Terminal.zig:105`).
- `pull_scrollback` (commit `b32f20f3e`, 2026-09-18): `PageList.zig:1233-1247`
  doc — when growing rows, pull lines back out of scrollback into the active
  area (xterm.js, wezterm and Windows Terminal do the same, refs in the
  commit message); `false` for ptys that keep their own screen buffer without
  scrollback (ConPTY), which would otherwise disagree with the terminal about
  what is on screen. Implemented at `PageList.zig:1355` and `:2897`.
- Height shrink keeps the cursor's row (`PageList.zig:3167-3202`
  `trailingBlankLines` / `trimTrailingBlankRows`: blank rows below the cursor
  are dropped first).

**Ours today**
- `TERMINAL.md` §2 and §4.10 (`resize_policy` tests): shell mode evicts the
  frame up to `frame_rows()` into scrollback and restarts the screen, "a shell
  resize moves the frame to scrollback exactly once"; agent TUI mode truncates
  in place (`screen.rs:486` `resize_cells`). Both modes rewrap scrollback
  (§4.2). This mirrors Warp `resize.rs:60`.
- Height growth never pulls rows back: `resize_cells` builds a blank grid and
  copies the surviving rows in (`screen.rs:491-500`); new rows are blank.
- The renderer hides trailing blank rows of a block (`trimTrailingBlankRows`,
  `dom-block-renderer.ts:418`), which is why the blank-bottom gap is rarely seen.
- Our `shell/zsh.sh:103` emits `OSC 133 ; A` with no options.

**Gap**
After every shell-mode width change the old prompt (and whatever the shell
had drawn) is a finished row in scrollback and the shell draws a new one
below — one stale prompt per resize, the same class of artefact §4.8 describes
for Claude Code but self-inflicted in shell mode. Ghostty's model reflows the
active rows in place and blanks the prompt for the shell to redraw; nothing is
pushed into history. For agent TUI mode the comparison is a wash (Ghostty has
no such mode; Claude Code's own repaint is the §4.8 upstream problem either
way).

**Proposal** (shell mode only; agent TUI mode is untouched)
- `vt-core`: `Parser::resize` in shell mode reflows the live frame in place
  instead of evicting: rows above the cursor's block are rewrapped through
  `RowIndex::rewrap` semantics applied to `ScreenGrid` rows (the screen's
  `wrapped` flags already exist, §4.2), the cursor rides a pin (1.3), and if
  the cursor's row is inside an open prompt (the block whose `A` has been
  seen and whose `C` has not — `BlockGrid` knows this), the rows from that
  block's first row to the cursor are cleared. `frame_rows()`-bounded eviction
  is kept only for the height-shrink case where rows cannot fit.
- Honour `redraw=0` on `OSC 133 A` (`crates/marks/src/osc.rs`, currently
  `decode_osc133` reads only `A/B/C/D` and `D;<exit>`): a shell that says it
  will not redraw keeps today's behaviour.
- Height growth pulls the newest scrollback rows back into the frame when the
  frame's last row is the cursor row (Ghostty `pull_scrollback = true`), with a
  `set_pull_scrollback(false)` for the ConPTY host (our pty-host has a Windows
  build, `host_main.go` ConPTY path, `TERMINAL.md` §4.5).
- Host: `vt-host` mirror gets the same policy so replay matches.

**Tests**
- `vt-core/tests/resize_policy.rs`: "a shell resize does not add a row to
  scrollback", "the prompt rows are cleared for redraw when the cursor is in an
  open prompt", "redraw=0 keeps the frame", "growing rows pulls the last
  scrollback rows back", "pull disabled appends blank rows".
- Go: `vtwasm/replay_test.go` — replay after a shell resize shows one prompt.
- The §4.10 test `resizing_an_agent_tui_appends_no_frame_to_scrollback` stays.

**Priority:** P4 — it replaces a Warp decision recorded in `TERMINAL.md` §4.10.

**Decision:** shell-mode resize: keep Warp's evict-once, or adopt Ghostty's
reflow-in-place + prompt clear. Side-by-side screenshot of a zsh prompt
through three width changes decides it. §2.4 has the shortest reference
implementation of the cursor bookkeeping if approved.

### 1.6 OSC 133 semantic prompt options

> **Status: Not done.** `decode_osc133` still reads only `A`/`B`/`C`/`D` and `D;<exit>`. A non-goal of the agent-TUI spec.

**Reference**
- Parser: `src/terminal/osc/parsers/semantic_prompt.zig`. Actions `:23-32`
  (`L` fresh line, `A`, `N` new command, `P` prompt start with `k=` kind, `B`,
  `I`, `C`, `D`). Options `:78-109`: `aid`, `cl`, `cmdline`, `cmdline_url`,
  `redraw`, `special_key`, `click_events`, `exit_code`; `prompt_kind` `k=`
  (`:130`) with values initial/right/continuation/secondary.
- Terminal handling: `Terminal.zig:2100-2135` — `A` records the prompt kind on
  the cursor's semantic content, reads `redraw`, and `click_events`/`cl` (for
  click-to-move-cursor in the prompt, Kitty's protocol). `Terminal.zig:1791`
  marks continuation rows `prompt_continuation` on `k=s`.
- The fish heuristic `Terminal.zig:2185-2200`: a newline at column 0 on a
  prompt row un-marks the row, because fish emits no `k=s` continuations.
- Prompt navigation uses the row flag: `PageList.zig:3505` (`scrollPrompt`),
  `:6345` (`promptIterator`); `Row.semantic_prompt` is a false-positive-safe
  row flag `page.zig:2049-2058`.
- Shell side: `src/shell-integration/zsh/ghostty-integration:124`
  (`133;A;cl=line`), `:159` (`133;B`), `:229` (`133;C`), `:116-120`
  (`133;D;<status>`), `:272-277` (use `133;P` for the right prompt to avoid
  fresh-line behaviour, and `133;B` is required for click-to-move).

**Ours today**
- `crates/marks/src/osc.rs:27-55` (`decode_osc133`): `A`, `B`, `C`, `D`,
  `D;<exit>`; any option after the letter is ignored; unknown letters return
  `None` (`:116`). `OSC 7` path is parsed (`:57`).
- Our own tier-2 extension carries what Ghostty's `cmdline` and `aid` carry:
  `shell/zsh.sh:80` (`7000;v=1;id=…;cmd=…`), `:94` (`exit=`), `:102`
  (`cwd=…;branch=…`), `:15/:20` (`input-ready` / `input-released` for the line
  editor state, `line_editor.rs`).
- Multi-line prompts / continuation rows: not tracked; a `PS2` continuation
  row is an ordinary row of the block.
- Click in the prompt to move the cursor: not supported (the line editor is
  the browser's composition target, `composition-target.ts`).

**Gap**
Our OSC 7000 already covers `cmdline`, `aid` and `exit` more richly. What we
lack from Ghostty's `133` handling: `k=s`/`k=c` continuation marks (so a
multi-line prompt is known to be prompt, which 1.5 needs), `redraw=` (1.5),
`P`/`I`/`N`/`L` actions (right prompts, "fresh line" on `A`), and the fish
heuristic. `cl=`/`click_events` is only useful once we let the child own the
prompt, which we do not (the line editor owns it), so it is listed as not
adopted.

**Proposal**
- `crates/marks`: parse the option list on every `133` subcommand into a small
  `Vec<(key, value)>`; surface `k=`, `redraw=`, `cl=`; accept `P`, `I`, `N`,
  `L` (`L` = fresh line: if the cursor is not at column 0, emit a newline before
  the prompt, Ghostty `Terminal.zig:2212` `semanticPromptFreshLine`, called
  at `:2100`).
- `vt-core`: rows get a `semantic: none | prompt | prompt_continuation | input | output`
  tag in `ScreenGrid` and `RowRange` (one byte per row; exported as a `u8` per
  row through the §2 checklist); `BlockGrid` uses it for the header/command
  rows; the fish heuristic is applied on line feed at column 0.
- `shell/zsh.sh`, `bash.sh`, `fish.fish`: emit `133;A;redraw=1` and `k=s` on
  continuation prompts (`PS2`); keep OSC 7000.
- `ts/renderer-dom`: block header reads the command from `7000 cmd=` as now;
  `block-rows.ts` can style continuation rows like the prompt row.

**Tests**
- `crates/marks/src/osc.rs`: options parse in either order, unknown keys are
  skipped, `D;<exit>;k=v` still yields the exit code.
- `vt-core/tests/semantic_rows.rs`: rows tagged from `A/P/B/C/D`, `k=s`
  continuations, fish heuristic, tags survive eviction and rewrap.
- `shell/zsh.test.mjs` etc.: the emitted sequences.

**Priority:** P3 alone; P2 if 1.5 is adopted (it depends on this).

### 1.7 Search: incremental, scoped to what can change

> **Status: Done.** Plan 2 — `FindSession` on the core: settled history scanned once from `scanned_to`, the unsettled tail and the live screen re-searched only when the generation changes, hits re-resolved through the row index. Also fixed: markless (Claude Code) panes and on-screen rows were never searched.

**Reference**
- `src/terminal/search.zig`: `Active`, `PageList`, `Screen`, `Terminal`,
  `Viewport` searches, plus a `Thread` for the app build (`search.zig:5-17`).
- `src/terminal/search/sliding_window.zig:30-60`: a circular byte buffer of
  encoded page text plus a parallel metadata ring mapping bytes back to
  page/row/cell, so a needle spanning a page boundary is found without
  flattening the whole scrollback.
- `src/terminal/search/active.zig:11-19`: "the active area is the only part of
  a PageList that is mutable, therefore the only part that needs to be
  repeatedly searched as the contents change".
- `src/terminal/search/viewport.zig:12-22`: re-search only the viewport, and
  only when a `Fingerprint` of the viewport changes.
- `src/terminal/search/Thread.zig:1-6`: search runs on its own thread and
  admits it still takes the terminal lock.
- Results are `highlight.zig` ranges (1.8), tracked so they move with the text.

**Ours today**
- `crates/vt-core/src/find.rs`: `FindQuery::{Literal, Regex}` over `Content`
  with `memchr::memmem` / `regex_automata`; `TerminalCore::find` and
  `find_with_state` (`lib.rs:131-157`); a `FindCursor` iterates matches as
  byte ranges mapped to blocks/rows. Every call scans from scratch.
- `ts/renderer-dom/src/find-bar.ts` drives it per keystroke and per repaint
  while the bar is open (exact re-search cadence: not known without reading
  `find-bar.ts` end to end; the plan should measure it).

**Gap**
Scrollback is immutable in our model except through rewrap, so re-searching
it on every repaint while Claude Code streams is wasted work that scales with
scrollback size. Ghostty's split — history searched once and cached, the
active area re-searched on change, the viewport by fingerprint — maps directly
onto our `Content` (append-only) + `ScreenGrid` (mutable) split.

**Proposal**
- `vt-core`: `FindSession { query, history_hits: Vec<ByteRange>, history_scanned_to: usize, screen_hits: Vec<(row, col_range)> }`
  kept on the core: history hits are extended from `history_scanned_to` when
  `Content` grows (eviction appends bytes; never rescans); screen hits are
  recomputed only when the screen generation (1.2) changed; a rewrap
  invalidates nothing because byte ranges do not move (they re-resolve to
  rows through `RowIndex`). Expose `find_update() -> (added, removed)`.
- `ts/renderer-dom`: the find bar paints hits from the session and keeps the
  current hit as a pin (1.3) so "next/previous" stays anchored while output
  streams.

**Tests**
- `vt-core/tests/find_session.rs`: hits in history are not rescanned after
  new output; a hit in the live frame updates when the frame changes; a match
  that spans the scrollback/screen boundary is found; a rewrap keeps the hit.
- `find-bar.test.ts`: "does not rescan history on repaint".

**Priority:** P3.

### 1.8 Highlights as one representation for selection, search and future marks

> **Status: Done.** Roadmap Plan 5 — one model (`highlights.ts`), one painter (`highlight-painter.ts`) for selection, find hits and user marks; links, hints, redaction and prediction stay overlays in `decorations.ts` (above the text). See `TERMINAL.md` §4.31.

**Reference**
- `src/terminal/highlight.zig:1-10`: "Highlights are any contiguous sequences
  of cells that should be called out in some way, most commonly for text
  selection but also search results or any other purpose." Note at `:8-10`:
  the plan is for highlights to replace `Selection` entirely.
- `Untracked` (`:31`) and `Tracked` (`:62`) forms, mirroring pins.
- `RenderState.Row.highlights` (`render.zig:233-236`) with an opaque `tag: u8`
  (`render.zig:255-262`) so the renderer paints selection, search hits and
  anything else with one code path.

**Ours today**
- Selection fill: `selection-fill.ts` paints `background-image` per row.
- Find hits: painted separately by `find-bar.ts` (mechanism: not known; the
  plan should read it). Two paint paths for the same "range of cells" concept.

**Proposal**
- `ts/renderer-dom`: a `Highlight { start: Pin, end: Pin, tag }` list on the
  renderer; `selection-fill.ts` becomes `highlight-fill.ts` taking a tag → CSS
  variable map (selection colour, find colour, current-find colour). The
  selection is the highlight with tag `selection`. 1.7's hits are highlights.
- No `vt-core` change beyond pins (1.3).

**Tests**
- `highlight-fill.test.ts`: two overlapping highlights paint in tag order;
  the existing `selection-fill.test.ts` cases carry over unchanged.

**Priority:** P3, bundled with 1.7.

### 1.9 Attach snapshot: active screen first, `READY`, then history

> **Status: Done.** Plan C — `vt_replay` sends origin, modes, the frame, `READY`, then history in 512-row chunks; the pane paints at `READY`.

**Reference**
- `src/terminal/snapshot/main.zig:1-17`: a documented binary snapshot of
  terminal state whose layout "prioritizes making a terminal functional as
  quickly as possible": envelope, active screen state, a `READY` record ("enough
  state has been sent down to render the terminal and reconstruct its
  unfinished VT stream state"), then history pages, then `FINISH`.
- Format spec as Kaitai Struct: `src/terminal/snapshot/snapshot.ksy`, verified
  by `verify-kaitai.py`; records in `record.zig`, `screen.zig`, `history.zig`,
  `continuation.zig` (the parser's mid-sequence state, so a stream cut inside
  an escape resumes correctly), `checkpoint.zig`.

**Ours today**
- Attach (`TERMINAL.md` §1, §4.7): the pty-host's mirror renders the screen
  into VT bytes (`vt_replay`), the client re-parses them; late attachers get
  the ring (`ring.go`) after that. The replay is clipped per row (§4.7) and
  emitted top-to-bottom; scrollback and the live frame arrive in one stream.
- The host mirror runs vt-core with reflow off (`vt-host/src/lib.rs`), so
  the client's rewrap does the width fitting on arrival.

**Gap**
For a session with a long scrollback the client parses the whole history
before the live frame is on screen. Ghostty's order puts the frame up first
and streams history behind it. We also lose parser continuation state at the
cut (an attach in the middle of an OSC 7000 payload re-parses from a clean
state; whether that has ever produced a visible artefact: not known).

**Proposal**
- `vt-host`: `vt_replay` emits two parts: the live frame (with cursor and
  modes, including 1049/2026/2004/mouse modes so `TerminalSurface` starts with
  the right key encoding), then a `READY` mark (an OSC 7000 `v=1;ready=1` the
  client understands), then the scrollback rows oldest→newest. The client
  paints on `READY`, and inserts history rows above the frame as they arrive
  (`RowIndex` prepend — new code; `Content` is append-only, so history bytes
  are appended to `Content` and `RowIndex` gains a prepend that only moves
  row records, offsets untouched).
- Alternative with less new code: send the `ExportBuffers` snapshot bytes
  directly over the mux instead of VT, since the renderer core already decodes
  that format; `vt-host` would need `ExportBuffers` (today only in `vt-wasm`).
  The plan picks after measuring attach time on a 10k-row scrollback.
- Go: `attach.go` orders the two parts; `replay_test.go` guards.

**Tests**
- `vtwasm/replay_test.go`: frame precedes history; `READY` precedes history;
  the cursor and modes are correct before any history arrives.
- `vt-core/tests/replay_prepend.rs`: prepending history under a frame keeps
  blocks and pins correct.

**Priority:** P3 (P2 for users who reattach to long sessions over Tailscale).

### 1.10 Paste safety as one rule in one place

> **Status: Done (roadmap Plan 1, 2026-09-24).** `encodePaste` gives a verdict; an unsafe unbracketed paste goes to the host's `confirmPaste` (Operator shows a dialog). Deviation from the proposal below: the confirm is a host seam rather than surface chrome, and `ESC[201~` is still stripped inside brackets (with every `ESC` and `^C`, §2.11) instead of refused.

**Reference**
- `src/terminal/paste.zig:1-17`: the single function that turns "the user
  pasted" into pty bytes: Kitty 5522 paste events, else 2004 bracketing, else
  `\n → \r`; "the safety rule lives only here so every embedder shares one
  implementation".
- The rule: `src/input/paste.zig:160-190`: `isSafe` — unsafe if the data
  contains `\n` or `\x1b[201~` regardless of mode ("the existence of these
  bytes should raise suspicion that the producer of the paste data is acting
  strangely"); `isSafeWith` — bracketed: unsafe only if it contains the bracket
  terminator; unbracketed: unsafe if it contains a newline. The app asks the
  user to confirm an unsafe paste (`allow_unsafe`, `paste.zig:58`, error
  `paste.zig:146`).
- Nothing reaches the pty until the whole paste is read and passed the rule
  (`paste.zig:163-166`).

**Ours today**
- `ts/editor/src/paste.ts:17-27` (`planPaste`): when the line editor owns the
  line, insert; otherwise `\r\n|\n → \r`, and if bracketed, wrap in
  `PASTE_START/END` with any embedded `PASTE_END` silently removed.
- An unbracketed multi-line paste is sent as several `\r`, i.e. executed line
  by line, with no confirmation. Whether the daemon/host applies any further
  rule: not known (the pty-host forwards bytes).

**Gap**
Silently stripping `\x1b[201~` hides a hostile clipboard instead of refusing
it, and an unbracketed multi-line paste into a shell runs every line. Ghostty
refuses (or asks) in both cases.

**Proposal**
- `ts/editor/src/paste.ts`: `planPaste` returns `{ kind: "unsafe", reason }`
  for the `isSafeWith` cases; `TerminalSurface` shows a one-line confirm in
  the surface chrome (no Operator concept; the host passes strings) with
  "Paste anyway". The `PASTE_END` strip is removed in favour of the refusal.
- Nothing in `vt-core`.

**Tests**
- `paste.test.ts`: bracketed with `201~` → unsafe; unbracketed with `\n` →
  unsafe; bracketed multi-line → send; confirm → send verbatim.
- `TerminalSurface.paste.test.tsx`: the confirm appears and the second
  action sends.

**Priority:** P2 (security-adjacent, small). §2.11 adds Alacritty's
bracketed-mode byte filter to the same change.

### 1.11 Stream: chunk-safe parsing, a bulk printable fast path, and unknown-sequence reporting

> **Status: Not done.** `print` is still per character with a style resolve each; no `print_run`, no unknown-sequence ring (Plan A's `trace` feature is a debug build, not the ring).

**Reference**
- `src/terminal/stream.zig:599-720`: `nextSlice` consumes a chunk; in ground
  state it calls `simd.vt.utf8DecodeUntilControlSeq` (`:712`) to decode a run
  of printable codepoints in one go (`src/simd/vt.zig:1-60`, SIMD in C++ with
  a scalar fallback that does "U+FFFD substitution of maximal subparts"),
  then prints the run; `nextSliceUntilGround` (`:622`) stops at the end of a
  sequence so a caller can interleave work.
- `src/terminal/stream_continuation.zig`: the parser's mid-sequence state is
  a value that can be saved and restored (used by `snapshot/continuation.zig`),
  so a chunk boundary inside an escape is not special.
- `src/terminal/stream_terminal.zig:98,227-235,350`: an `unknown_sequence`
  callback receives every APC/OSC/DCS the terminal did not handle, with the
  raw content and a `truncated` flag; the inspector shows them.

**Ours today**
- `Parser` is built on `vte` 0.15 (`Cargo.toml:17`), byte-at-a-time state
  machine; chunk boundaries are safe by construction (vte keeps state).
- `print` is per `char` (`parser.rs:441-444` → `ScreenGrid::print`), which
  resolves the pending style per character.
- Unhandled OSC/CSI are dropped silently (`osc.rs:21` returns `None`; no log).

**Gap**
Per-character printing with a style resolve each is the parser-side cost
under Claude Code's repaint; Ghostty's run decode amortises the style and the
width lookup per run. Silent drops mean a new Claude Code sequence (as
happened with 2026) is invisible until someone `strings` the binary.

**Proposal**
- `vt-core`: `Parser::feed` pre-scans each chunk in ground state with
  `memchr` for the next `0x1b`/C0 byte, validates that slice as UTF-8 once
  (`std::str::from_utf8` with the maximal-subpart replacement for the tail),
  and calls a new `ScreenGrid::print_run(&str, style)` that resolves the
  style once and walks chars for width. `vte` stays for everything else.
- `Parser` counts unhandled sequences by kind (`unknown_csi`, `unknown_osc`
  prefix, `unknown_dcs`) into a small ring exposed as
  `TerminalCore::unknown_sequences()`; `ts/core` logs them at debug level
  once per distinct prefix. No UI.

**Tests**
- `vt-core/tests/print_run.rs`: a run split across two `feed` calls inside a
  multibyte char; a run containing invalid UTF-8; a run interrupted by SGR
  mid-way; wide characters; same snapshot as the per-char path (fixture from
  the existing `exit_encoding.rs` corpus).
- `parser.rs` unit: unknown OSC is recorded once with its prefix.
- Bench: bytes/second on the captured Claude Code stream before/after.

**Priority:** P3 (measure first; the DOM cost in 1.2 dominates).

### 1.12 Row-level flags that make erase/insert fast when nothing fancy is on the row

> **Status: Not done.** No `RowFlags`; `ScreenGrid` keeps separate `wrapped` and `dirty` vectors.

**Reference**
- `src/terminal/page.zig:2020-2058`: `Row.wrap`, `wrap_continuation`,
  `grapheme`, `styled` ("can have false positives but never a false
  negative … erase operations MUCH MUCH faster in the case that the row was
  never styled … around 4x"), `hyperlink`, `semantic_prompt`.

**Ours today**
- `ScreenGrid` has `wrapped: Vec<bool>` per row (§4.2) and cells carry a
  `CellStyle` each; erase/insert/delete walk every cell and its style.
- Graphemes are accumulated per cell up to a byte cap (`screen.rs:20`).

**Gap**
Minor today. It becomes relevant when 1.6 adds a per-row semantic tag and
1.15 adds hyperlinks: keeping "does this row have any X" as a false-positive
flag is what lets those features cost nothing on plain rows.

**Proposal**
- `vt-core`: a `RowFlags` bitset per screen row (`wrapped`, `styled`,
  `has_grapheme`, `has_hyperlink`, `semantic`) maintained on write, with the
  false-positive contract from Ghostty; erase paths take the fast branch when
  `styled` is clear. `wrapped` moves into it.

**Tests**
- `screen.rs` units: a row written with default style clears fast; a styled
  cell sets the flag; the flag is never cleared by an erase that leaves a
  styled cell.

**Priority:** P3, folded into whichever of 1.6 / 1.15 lands first.

### 1.13 Memory limits by bytes as well as rows; cold-history compression

> **Status: Done.** Plan B — `Limits { rows: 200_000, bytes: 128 MiB }` in both cores, plus `memory_stats`. Compression was excluded by the proposal itself. Open: the OSC 8 registry sits outside the byte budget (`TERMINAL.md` §5).

**Reference**
- `src/terminal/PageList.zig:6915` (`Limits`), `:611` (`max_lines`),
  `:625-626` ("the maximum number of physical rows retained as scrollback"),
  `setMaxBytes` `:3969`, `setMaxLines` `:3983`; `limits.enforce` after
  resize (`:1287`, `:1339`).
- Cold pages are compressed and their memory decommitted while their virtual
  mapping is kept so restore is infallible: `PageList.zig:74-91`
  (`Node.Data = resident | compressed`), `compress` `:4842`,
  `compressIncremental` `:4873` driven by an activity timer
  (`page_compression`, `:441`), `src/terminal/compress.zig:1-5`.
- `memoryStats` `:6852` for the inspector.

**Ours today**
- `TerminalCore::new(columns, scrollback_rows)` (`lib.rs:58`); `trim_to`
  (`lib.rs:116,175`) enforces a row count only. `Content` is UTF-8 bytes in
  chunks; `AttributeMap` holds styles keyed by offset. Byte usage is
  unbounded for wide rows or heavy styling; a `memory_stats()` does not exist.
- Two cores per session (renderer + host mirror), so any cap is paid twice.

**Gap**
A row cap does not bound memory when rows are wide or every cell is styled
(Claude Code paints wide coloured bands). Compression is not worth it for us
(our bytes are already compact and the wasm heap cannot decommit), but a
byte cap and a stats call are cheap and would have made the "how big is this
session" question answerable.

**Proposal**
- `vt-core`: `TerminalCore::new` takes `Limits { rows, bytes: Option<usize> }`;
  `trim_to` also trims oldest rows while `Content.len() + AttributeMap.len()`
  exceeds `bytes`; `memory_stats() -> { content_bytes, style_entries, rows, blocks }`
  exported to `ts/core`.
- No compression.

**Tests**
- `vt-core/tests/limits.rs`: byte cap trims whole rows and keeps blocks and
  pins consistent; stats match after trims.

**Priority:** P3.

### 1.14 Testing techniques: integrity checks, failure injection, synthetic streams

> **Status: Partial.** Plan A — `verify_integrity`, the proptest generator and the `trace` feature. Not done: failure injection, pyte agreement in the proptest.

**Reference**
- `src/terminal/PageList.zig:796-930` (`assertIntegrity` / `verifyIntegrity`,
  `IntegrityError` at `:817`): every mutating operation ends with a structural
  check in debug builds (page serials, tracked pins valid, row counts).
- `src/tripwire.zig:1-9`: a failure-injection library — named checkpoints
  (`Terminal.zig:4008` `resize_tw = tripwire.module(enum {...})`, checked at
  `:4092` `tw.check(.primary_screen)`) that tests can trip to exercise every
  error path of `resize` (the alternate-screen fallback at `:4116-4130` is
  tested this way).
- `src/synthetic/`: generators for random VT streams, cells, styles; used by
  `src/benchmark/` and fuzz-style tests.

**Ours today**
- 23 integration test files under `crates/vt-core/tests` plus unit tests, all
  example-based; the fixture corpus in `vt-wasm/tests/exit_encoding.rs`.
- No invariant checker: `RowIndex` ↔ `BlockGrid` ↔ `Content` consistency is
  asserted per test, not after every operation. §4.1 and §4.4 were exactly
  invariant violations (a row unrecorded; blocks rebased wrongly).
- `snapshot()` returns `Result` (`lib.rs:119`) but no test drives the error
  path (wasm memory growth failure, `TERMINAL.md` §5 last item).

**Proposal**
- `vt-core`: `Parser::verify_integrity() -> Result<(), IntegrityError>`
  checking: every scrollback row's range lies inside `Content`; rows are
  contiguous and ordered; `wrapped` rows are followed by a row; blocks tile
  the flat row space in order without overlap and end at or before the last
  row; every pin resolves or is marked dead; `AttributeMap` keys lie inside
  `Content`. Called after every public mutation under `#[cfg(debug_assertions)]`
  and at the end of every integration test.
- A `proptest`-style generator (dev-dependency) producing random sequences
  of print/SGR/CUP/ED/EL/IL/DL/resize/OSC 133 and asserting integrity plus
  agreement with pyte on the visible screen (the §7 second-opinion tool, made
  automatic).
- A failure-injection hook around `snapshot()` export growth, so the
  renderer's stale-view handling has a test.

**Tests**
- Themselves.

**Priority:** P2 — cheapest insurance against the §4 class of regressions.

### 1.15 OSC coverage: hyperlinks, working directory, notifications, pointer shape, colours, title

> **Status: Done.** Plan E — OSC 8 and hover links. Roadmap Plan 3 — OSC 0/2 title (card and pane header in Operator), OSC 9/777/99 notifications (toast when the pane is not on screen), OSC 10/11 replies from the pane's colours, OSC 22 pointer shape.

**Reference** (`src/terminal/osc/parsers/`)
- `hyperlink.zig:8` — OSC 8 with `id=` (tests `:59-86`); storage in
  `src/terminal/hyperlink.zig:29-90` (a ref-counted set per page, `implicit`
  ids for links without one). Regex link detection in the renderer:
  `src/renderer/link.zig:14-60` (`Link { regex, highlight: always | always_mods | hover | hover_mods }`),
  default URL regex `src/config/url.zig:109` with the scheme list at `:27`;
  the app resolves OSC 8 first, regex second (`src/Surface.zig:4369`
  `linkAtPin`, `:4437` `processLinks`, `:4487` OSC 8 URI lookup).
- `report_pwd.zig:6` — OSC 7 (we have it).
- `osc9.zig:6,272-288` — OSC 9 iTerm2 / ConEmu notification; `kitty_desktop_notification.zig:1-2`
  — OSC 99 with metadata (title, body, urgency, `done`).
- `mouse_shape.zig:8` — OSC 22 pointer shape.
- `color.zig:159` (OSC 4/5 palette), `:219` (104/105 reset), `:281` (OSC
  10–19 dynamic fg/bg/cursor query and set).
- `change_window_title.zig:6` — OSC 0/2 (with a length cap, test `:36`).
- `kitty_text_sizing.zig:1-2` — OSC 66 (multi-cell text sizing).

**Ours today**
- `crates/marks/src/osc.rs`: 133 and 7 only; everything else is dropped
  (`osc.rs:21`). No hyperlink storage, no link detection in `row-builder.ts`
  (`grep -rn "https\?://" ts/renderer-dom/src` → no non-test match), no
  notifications, no title, no palette/OSC 10/11 query answers. Whether Claude
  Code queries OSC 10/11 for its theme detection: not known (its binary was
  checked for modes, not OSC).

**Gap**
The user-visible ones: clickable URLs (both OSC 8 and detected) — Warp has
this and TERMINAL.md §4.12 already reserves the pointing hand for links; OSC
9/99 notifications, which for an agent terminal is "the agent finished" without
Operator having to infer it from block state; OSC 10/11 replies so a TUI can
detect light/dark (Claude Code's theme auto-detect, if it uses it: not
known — capture and check).

**Proposal**
- `vt-core`: OSC 8 stored like styles (`AttributeMap<LinkId>` keyed by content
  offset, a `Vec<String>` of URIs with dedup, `implicit` ids as in Ghostty);
  snapshot exports link runs (stride like `stylePairs`). OSC 0/2 title, OSC
  10/11 (query → the host answers with the theme's colours through a
  `HostCapabilities` callback; set is ignored), OSC 9 / 99 → an event on the
  existing `event_bridge.rs` with `{ title, body }`, OSC 22 → a pointer shape
  event. Handled sequences never reach the "unknown" ring (1.11).
- `ts/renderer-dom`: `row-builder.ts` wraps link runs in `<a>` with the
  pointer hand; a detected-link pass runs on rows in the window using one
  regex (Ghostty's `url.zig:109` as the default; the host can override), on
  hover only, so the common paint path is untouched.
- `ts/react`: click with the platform modifier opens through
  `HostCapabilities.openUrl`; notifications go to `HostCapabilities.notify`.
  Operator wires those in `frontend/`.

**Tests**
- `vt-core/tests/osc8.rs`: link runs across a wrap, across eviction, across
  rewrap (offsets do not move), implicit ids.
- `row-builder.test.ts`: link runs render as anchors; regex detection finds
  the Ghostty test URLs (`url.zig` tests) and not the negatives.
- `event_bridge` unit: OSC 9/99 events carry title/body; OSC 10/11 queries
  produce the right reply bytes.

**Priority:** P2 for OSC 8 + detection and OSC 9/99; P3 for the rest.
§2.2 delivers all of these sequences pre-parsed; §2.7 turns detection into
keyboard-addressable hints.

### 1.16 Resize coalescing and in-band size reports

> **Status: Done.** Roadmap Plan 3 — the mirror answers XTWINOPS 14/16/18 `t` and mode 2048 from the grid and the pane's cell size (device pixels). Coalescing was already adequate (`RESIZE_DEBOUNCE_MS` = 100).

**Reference**
- `src/termio/Thread.zig:28-31` (`Coalesce.min_ms = 25`), `:390-405`
  (`handleResize`: a resize while the timer is active is stored, not applied;
  the timer applies the last one), `:428` (`coalesceCallback`).
- `src/terminal/stream_terminal.zig:249-260`: the stream handler's `resize`
  also emits the mode 2048 in-band size report when the app enabled it;
  `src/terminal/size_report.zig:5-40` encodes 2048 and XTWINOPS 14/16/18 t
  (cell and text-area pixel sizes).

**Ours today**
- `useTerminalSession.ts` `RESIZE_DEBOUNCE_MS = 100`, trailing edge restarted
  per frame, leading edge only for the first grid (`TERMINAL.md` §4.6). The
  reasoning there ("do not re-add a leading edge or a max-wait") stands;
  Ghostty's 25ms is a trailing debounce too.
- Mode 2048 / XTWINOPS: not handled (`grep -rn "2048\|XTWINOPS"` → nothing).
  Claude Code's binary does not contain `2048` (checked).

**Gap**
None on coalescing. 2048 is unused by our only TUI; XTWINOPS `18t` (report
size in cells) is what some scripts use to size output. Low value.

**Proposal**
- `vt-core`: answer `CSI 18 t` and `CSI 14/16 t` (pixel sizes from the
  `cellWidth/cellHeight` the surface already measures — pass them in
  `resize`), and mode 2048 if set. Replies go through the existing reply path
  used for DA/CPR (exact location: not known; the plan should find it in
  `parser.rs` / `event_bridge.rs`).

**Tests**
- `vt-core/tests/size_report.rs`.

**Priority:** P4 (only if a tool asks for it).

### 1.17 Renderer-side decisions that transfer to a DOM renderer

> **Status: Partial.** Plan D — contrast-inverted and hollow-unfocused cursor behind flags (both off); box drawing measured and ruled out (`boxGapPx` = 0). Not done: the `minContrast` theme option, dropped by the Plan D spec without a recorded decision.

**Reference**
- Scroll-to-bottom on output by comparing the bottom-right pin between
  frames, not by inspecting scroll position: `src/renderer/generic.zig:1372-1384`
  (`last_bottom_node`, `last_bottom_y`).
- Minimum contrast between foreground and background, enforced at paint
  (`generic.zig:586,653`, `min_contrast`; math in `src/renderer/cell.zig`).
- Unfocused cursor is a hollow block regardless of the requested style:
  `src/renderer/cursor.zig:58-60`.
- Procedurally drawn glyphs for box drawing, block elements, braille,
  powerline and legacy computing symbols so they join seamlessly at any font
  or line height: `src/font/sprite/Face.zig:1-12`, drawers in
  `src/font/sprite/draw/` (`box.zig`, `block.zig`, `braille.zig`, `branch.zig`,
  `powerline.zig`, `geometric_shapes.zig`, `symbols_for_legacy_computing*.zig`),
  registry convention in `draw/README.md`.

**Ours today**
- Stickiness: `dom-block-renderer.ts:503-518` (`updateStickiness`, distance to
  bottom ≤ `STICK_THRESHOLD_PX = 4`), with the clientHeight guard for layout
  scrolls. It answers "was the user at the bottom", which is the right
  question for a DOM scroller; Ghostty's pin comparison answers "did output
  arrive", used to force a scroll when `scroll-to-bottom=output` is on. We
  have no "jump on new output even if scrolled up" option; the jump-to-bottom
  button (`jump-to-bottom.ts`) covers it.
- No minimum-contrast pass; the theme (`theme-warp.ts`) is Warp's palette.
- Cursor: `cursor.ts`, `terminal-cursor.test.ts`; unfocused rendering: not
  known without reading `cursor.ts`.
- Box drawing comes from the font (`fonts/hack-*.woff2`) at
  `lineHeight: 1.2` (`default-font.ts:7`). Whether vertical bars show hairline
  gaps between rows at this line height on the shipped font: not known —
  screenshot needed. Claude Code draws `│ ─ ╭ ╮ ╰ ╯ ⎿ ├` on every tool call.

**Proposal**
- Hollow cursor when the surface is unfocused (Ghostty `cursor.zig:58-60`;
  Warp does the same — cite both).
- A `minContrast` option on the theme input (default off; Operator may turn
  it on for the agent TUI whose colour bands are fixed by Ink).
- Box-drawing: measure first. If gaps exist, a `.terminal-run[data-box]` class
  rendered with CSS borders / inline SVG for U+2500–257F, U+2580–259F and
  U+E0B0–E0BF (the Ghostty drawer set), computed from the measured cell size,
  the way `Face.zig` sizes sprites from `font.Metrics`.

**Tests**
- `cursor.test.ts`: unfocused → hollow.
- `styles-parity.test.ts`: box glyphs fill the full cell height (if adopted).

**Priority:** P3; the box-drawing part is P2 if the screenshot shows gaps.

### 1.18 Shell integration scripts

> **Status: Not done.** The shell scripts still emit bare `133;A/B/C/D`; no `redraw=`, `k=s` or `133;P`. Folded into §1.6.

**Reference**
- `src/shell-integration/{bash,zsh,fish,elvish,nushell}/`. Zsh: `133;A;cl=line`
  in the prompt (`:124`), `133;B` after (`:159`), `133;C` before exec
  (`:229`), `133;D;<status>` (`:116-120`), `133;P` for right prompts (`:272-277`).
  Also emits OSC 7 cwd and sets the title; `README.md` documents injection by
  env var (`GHOSTTY_RESOURCES_DIR`) without touching rc files, and the
  `no-cursor`/`no-title`/`sudo` feature switches.

**Ours today**
- `packages/terminal/shell/{zsh.sh,bash.sh,fish.fish}` with tests
  (`*.test.mjs`) driven through a real pty (`pty.mjs`). Emits 133 A/B/C/D and
  the 7000 extension (1.6 lists the lines). Elvish/nushell: none. Injection
  mechanism: not known from this survey (see `shell/README.md`).

**Gap**
Covered by 1.6 (options) and nothing else material; our tests drive a real
shell, which Ghostty's do not.

**Proposal**
- Folded into 1.6: `redraw=1`, `k=s`, `133;P` for right prompts. No new
  shells unless a user asks.

**Priority:** with 1.6.

### Not adopted from Ghostty, and why

| Area | Files | Reason |
|---|---|---|
| GPU cell renderer, glyph atlas, shaders | `src/renderer/{Metal,OpenGL,WebGL}.zig`, `shaders/` | We render DOM by design (`DESIGN.md`); nothing transfers except 1.17. |
| Font discovery, shaping, fallback | `src/font/` (except `sprite/`) | Browser text stack. |
| Kitty graphics protocol | `src/terminal/kitty/graphics*.zig`, `apc.zig` | No Operator TUI emits images; large surface. Revisit only for a user request. |
| Kitty keyboard protocol (CSI u) | `src/input/`, `Terminal.zig` kitty keyboard flags | Claude Code's binary contains no `CSI > … u` / `CSI ? u`; our `encodeKey` is xterm-style; adopt only when a TUI needs it. |
| Kitty clipboard 5522, `MimeReader` | `src/terminal/clipboard.zig`, `kitty/clipboard.zig` | Browser clipboard API is the boundary; no TUI asks. |
| Click-to-move cursor in prompt (`cl=`, `click_events`, `special_key`) | `semantic_prompt.zig:86-104`, `Terminal.zig:2117-2131` | Our line editor owns the prompt row; the child never sees the click. |
| tmux control mode | `src/terminal/tmux.zig`, `tmux/` | tmux was removed from the interactive path (`TERMINAL.md` §1). |
| Page memory pool, mmap preheat, page compaction/split | `PageList.zig:36-46`, `:3650`, `:3726`, `page.zig` | wasm heap; our `Content` chunks already avoid per-row allocation. |
| Cold-page zstd compression | `compress.zig`, `PageList.zig:4842-5050` | Cannot decommit inside wasm; bytes are already compact (1.13 takes the byte cap only). |
| Terminal inspector UI | `src/inspector/` | Operator's dev tooling is the daemon API + `/mux` (memory: verify via daemon API). 1.11's unknown-sequence ring and 1.13's stats are the parts worth having. |
| Search thread | `search/Thread.zig` | The core runs on the main thread in the browser; 1.7's incremental session gives the same effect without a thread. |
| Alternate-screen resize failure fallback | `Terminal.zig:4116-4130` | Our alt grid resize cannot fail (no allocator errors surfaced); noted, no action. |
| DECSET 1004-style focus reporting, 1016 pixel mouse, X10 | `modes.zig` | 1004 we have; 1016 unused by our TUIs. |

### Ghostty section: suggested plan order

1. **1.1** synchronized output — one day, visible today.
2. **1.14** integrity checker + property test — insurance before the model
   changes below.
3. **1.2** dirty rows + patch-in-place DOM.
4. **1.3** pins → **1.4** wrapped-line copy and selection extras → **1.7/1.8**
   incremental find on highlights.
5. **1.10** paste safety; **1.15** OSC 8 + notifications.
6. **1.6** OSC 133 options, then the **1.5** decision with a screenshot.
7. **1.9** READY-first attach when reattach time is measured to matter.
8. **1.11**, **1.12**, **1.13**, **1.16**, **1.17** as their triggers appear.

---

## 2. Alacritty

**Repository:** `/Users/omaraly/development/AI/alacritty` at commit `d692748d`
(2026-08-31, "Remove unnecessary Row column count limit").
**Language:** Rust. **Relevant tree:** `alacritty_terminal/src/` (the model,
~10.7k lines: `grid/`, `term/`, `selection.rs`, `vi_mode.rs`, `event_loop.rs`),
`alacritty_terminal/tests/ref/` (recorded-session reference tests),
`alacritty/src/display/` (damage, hints, renderable content),
`alacritty/src/input/` and `event.rs` (mouse, paste).

**Why Alacritty is worth mirroring:** it is the same language as `vt-core`
and, decisively, it is built on the same parser crate we already depend on —
`vte` 0.15 (`alacritty_terminal/Cargo.toml:28`, ours `packages/terminal/Cargo.toml:17`).
Alacritty enables `vte`'s `ansi` feature, which we do not; that feature is where
Alacritty's synchronized-update handling, typed CSI/OSC/SGR dispatch, mode
enum, hyperlinks and title handling live. Several "Alacritty approaches" below
are therefore available to us as a Cargo feature flag plus a trait
implementation, not a port. The model is also small enough to read end to end
and its 45 reference recordings are a ready-made conformance corpus.

Alacritty deliberately has no blocks, no shell integration, no tabs and no
scrollback search UI beyond regex; where it is thinner than Ghostty the entry
says so and points back to §1.

### 2.1 Synchronized updates buffered in the parser (`vte::ansi::Processor`)

> **Status: Done.** Plan A — DEC 2026 buffered in `vt-core` (`SyncBuffer`, 150 ms / 2 MiB), pump holds across a block.

**Reference**
- `~/.cargo/registry/src/index.crates.io-*/vte-0.15.0/src/ansi.rs` (the
  crate Alacritty and we both compile):
  `SYNC_UPDATE_TIMEOUT = 150ms` (`:36`), `SYNC_BUFFER_SIZE = 2 MiB` (`:39`),
  `BSU_CSI`/`ESU_CSI` byte patterns (`:45`, `:48`).
  `Processor::advance` (`:298-311`): while a sync timeout is pending the bytes
  go to `advance_sync` (`:370-388`), which appends them to a buffer and scans
  only the newly added tail for `?2026h`/`?2026l` with `memchr`
  (`advance_sync_csi`, `:390-415`); on `?2026l`, buffer overflow, or timeout
  (`stop_sync`, `:315`) the whole buffer is parsed in one go. The handler —
  the terminal model — never sees a partial frame. `Timeout` trait `:478-490`
  is the embedder's clock; `sync_bytes_count` `:362`.
- Alacritty's use: `alacritty_terminal/src/event_loop.rs:165-168` wakes the
  renderer only if some processed bytes were *not* inside a sync block;
  `:228-246` arms an event-loop timer from `parser.sync_timeout()` and calls
  `stop_sync` when it fires. `term/mod.rs:1992,2041,2084` — the model's
  `set/unset/report_private_mode` treat `SyncUpdate` as a no-op because the
  parser already handled it.

**Ours today**
- `parser.rs:199-220` `note_private_mode`: 2026 falls through `_ => return`.
- `TerminalCore::feed` (`lib.rs:76-100`) drives `vte::Parser` (the `Perform`
  trait, no `ansi` feature) byte-exact and interleaves our own mark decoder
  (`crates/marks`) by byte offset.
- The renderer paints on rAF whatever has been parsed (`dom-block-renderer.ts:306-324`).
- The host mirror (`vt-host`) parses the same bytes for attach replay, so a
  late attacher can be handed a half-drawn frame if the replay is cut inside
  a sync block.

**Gap**
Same symptom as §1.1 (Claude Code brackets every Ink frame with 2026; we tear).
Alacritty's mechanism is different from Ghostty's and better for our two-copy
architecture: buffering in the parser means neither the renderer core nor the
host mirror ever contains a partial frame, so §1.1's renderer-side skip and
its watchdog become unnecessary, and `vt_replay` is automatically frame-aligned.

**Proposal** (this supersedes the renderer-side part of §1.1; the parser flag
and tests there still apply)
- `vt-core`, option B (recommended first): port the ~120 lines of
  `advance_sync`/`advance_sync_csi`/`stop_sync` into `Parser` as a
  `SyncBuffer { bytes: Vec<u8>, deadline: Option<Instant-like u64> }` in front
  of `vte::Parser`: `feed` appends while active, scans the tail for
  `?2026h`/`?2026l`, and flushes on ESU, on 2 MiB, or when the host reports
  the 150 ms deadline passed (`TerminalCore::tick(now_ms)` — the package has
  no clock; `ts/core` calls it from the rAF loop, the Go host from its read
  loop). The mark decoder (`crates/marks`) is fed at flush time so block
  events stay in stream order with the rows they own (`lib.rs:77-83`).
  `resize` and `process_boundary` flush.
- Option A (larger, §2.2): enable `vte`'s `ansi` feature and get the same
  code for free by implementing `vte::ansi::Handler`.
- `vt-host`: `vt_feed` gains the tick; `attach.go` calls it before `vt_replay`
  so a replay never starts inside a sync block.
- `ts/renderer-dom`: no skip logic needed; a paint during an open sync block
  simply sees the previous complete frame.

**Tests**
- `vt-core/tests/synchronized_output.rs` (from §1.1) plus: bytes inside a
  sync block are not visible in `snapshot()` until ESU; a frame split across
  three `feed` calls paints once; a block mark inside a sync block lands after
  the rows before it; overflow at 2 MiB flushes; `tick` past the deadline
  flushes; `?2026h` inside an open block extends the deadline.
- Go `vtwasm/replay_test.go`: replay after bytes ending inside a sync block
  shows the previous frame, not a half frame.

**Priority:** P1 (replaces §1.1's renderer skip with a smaller, more complete change).

### 2.2 Typed VT dispatch through `vte::ansi::Handler` instead of hand-rolled CSI/OSC/SGR

> **Status: Not pursued.** Roadmap Plan 9 (2026-09-26) — measured with a scratch crate: vte 0.15's `ansi::Processor` cannot express XTVERSION, `CSI 16 t`, OSC 9/99/777/133/7000, a bare `OSC 8 ;`, multi-mode DECRQM or raw parameters (the `trace` feature, the unknown-sequence ring), decodes SGR 21/53/`38;5;300`/`4:6` differently, would start executing REP, `ESC Z` and `ESC # 8` (changing two `tests/ref` screens), and allocates a 2 MiB sync buffer per core (`vte-0.15.0/src/ansi.rs:39,261-264`); its `Performer` is private (`:425`), so no sequence can be handed back. Dispatch stays on `vte::Perform` (`TERMINAL.md` §4.35). The proposal's "`std` is required by `ansi`" is wrong: `ansi = ["log", "cursor-icon", "bitflags"]` builds without `std`.

**Reference**
- `vte-0.15.0/src/ansi.rs:495` `pub trait Handler` — one method per
  terminal action, all with default no-op impls: `input`, `goto`, `insert_blank`,
  `scroll_up/down`, `erase_chars`, `clear_line/screen`, `terminal_attribute`
  (SGR fully decoded into `Attr` `:1136`, including underline styles and
  SGR 58 underline colour), `set_mode/unset_mode/report_mode`,
  `set_private_mode/unset_private_mode/report_private_mode` with the
  `NamedPrivateMode` enum (`:939-967`: 1, 3, 6, 7, 12, 25, 1000, 1002, 1003,
  1004, 1006, 1007, 1042, 1049, 2004, 2026), `set_scrolling_region`,
  `set_color/dynamic_color_sequence/reset_color` (OSC 4/10/11/104…),
  `set_hyperlink` (OSC 8), `set_title/push_title/pop_title`,
  `text_area_size_pixels/text_area_size_chars` (XTWINOPS 14/18 t),
  `set_mouse_cursor_icon` (OSC 22), `clipboard_store/load` (OSC 52),
  `report_keyboard_mode/push_keyboard_mode/pop_keyboard_modes/set_keyboard_mode`
  (Kitty keyboard), `set_modify_other_keys`, `decaln`, `identify_terminal`,
  `device_status`.
- Alacritty's `Term<T>` implements it: `alacritty_terminal/src/term/mod.rs`
  (`impl<T: EventListener> Handler for Term<T>` at `:1059`, ~1,200 lines
  covering every method; e.g. `push_title` `:2235`, `push_keyboard_mode`
  `:1288`, `set_private_mode` `:1934`, `report_private_mode` `:2046`).

**Ours today**
- `parser.rs` implements `vte::Perform` and decodes CSI/SGR/OSC itself:
  `csi_dispatch` `:445-472` (SGR `m`, private modes, the rest forwarded to
  `ScreenGrid::csi` in `screen/dispatch.rs`), `apply_sgr` `:315-360`
  (0, 1, 2, 7, 22, 27, 30–37, 38, 39, 40–47, 48, 49, 90–97, 100–107; every
  other code falls to `_ => {}`), `note_private_mode` `:199-220`.
- OSC: only 133 and 7 via `crates/marks/src/osc.rs`.

**Gap**
Everything §1.15 and §1.16 propose adding by hand (OSC 8, title, OSC 10/11,
OSC 22, XTWINOPS, Kitty keyboard modes) arrives already parsed if we implement
`ansi::Handler`; so do the SGR attributes we drop today (§2.8). It also
removes `apply_sgr` and half of `csi_dispatch` from our code. The cost: the
`Perform`-based `Parser` becomes an `ansi::Handler` implementation on a new
`Terminal` struct. `crates/marks` must keep its independent byte scanner:
`ansi.rs:1329-1523` `Performer::osc_dispatch` handles OSC 0/2, 4, 8, 10–12,
22, 52, 104, 110–112 and sends every other OSC — including 133 and 7000 — to
a local `unhandled` that only logs at `debug!` (`:1332-1341`, `:1523`); the
`Handler` trait has no unknown-OSC method. The interleaving-by-offset logic
in `lib.rs:77-83` therefore stays as is; §1.11's unknown-sequence ring cannot
come from `vte::ansi` either.

**Proposal**
- `vt-core`: `Cargo.toml` `vte = { features = ["ansi"] }` (keep
  `default-features = false`; `std` is required by `ansi`). New
  `impl vte::ansi::Handler for Parser` mapping onto the existing
  `ScreenGrid` operations; `feed` uses `ansi::Processor<NoopTimeout>` (or the
  §2.1 timeout type). Delete `apply_sgr`, the private-mode match and
  `csi_dispatch`'s manual param parsing once the fixture tests
  (`vt-wasm/tests/exit_encoding.rs`, `crates/vt-core/tests/*`) pass unchanged.
- Sequence: land §2.1 option B first (small, independent), then this refactor
  behind the full test suite, then §2.8/§1.15 on top of the typed handler.

**Tests**
- Every existing `vt-core` and `vt-wasm` test must pass byte-for-byte on the
  same fixtures; the Alacritty reference corpus (§2.9) is the added gate.

**Priority:** P2 refactor; it is the cheapest route to §1.15, §1.16 and §2.8.

### 2.3 Line damage with column bounds, and diffing selection/cursor damage outside the model

> **Status: Done.** Plan B — selection damage diffed against the previous paint (one row repainted per selection step) and one moved cursor element. Column bounds were ruled out by the entry itself for a DOM renderer.

**Reference**
- Model: `alacritty_terminal/src/term/mod.rs:137-146` `LineDamageBounds { line, left, right }`;
  `:176-184` `TermDamage::{Full, Partial(iter)}`; `:186-213`
  `TermDamageIterator` filters damage above the viewport by `display_offset`;
  `:216-262` `TermDamageState` with `damage_point`/`damage_line` expanding
  the per-line column span; `Term::damage()` `:458-486` adds the old and new
  cursor cells so cursor movement alone is a two-cell repaint, and notes that
  selection and vi cursor are *not* model damage ("could easily be tracked by
  comparing their old and new value between adjacent frames", `:450-452`);
  `reset_damage` `:489`; insert mode forces full damage `:461-464`.
- Display: `alacritty/src/display/damage.rs:16-30` `DamageTracker` keeps
  `old_selection`/`old_vi_cursor`, two `FrameDamage`s (`:140-147`) swapped
  per frame (`swap_damage` `:58`) for double-buffered presentation,
  `damage_selection` (`:106`) damages the union of old and new selection
  rectangles.

**Ours today**
- No damage; `repaint` rebuilds every visible row (`block-body.ts:19-44`,
  §1.2 "Ours today").
- Selection fill: `paintSelectionFill` (`dom-block-renderer.ts:482`)
  clears `backgroundImage` on every previously filled row and refills from a
  fresh `selectionView()` (a full `core.snapshot()` + `decodeBlocks()`,
  `TERMINAL.md` §5) on every repaint and every mouse move.

**Gap**
§1.2 covers row dirtiness. Alacritty adds two things worth keeping separate:
(a) column bounds per damaged line — for a DOM renderer a row is the unit,
so bounds are not needed; (b) the principle that selection and cursor
repaints are computed by diffing the previous and current *renderer* state,
not by asking the model — which is exactly the missing piece in
`paintSelectionFill`.

**Proposal**
- `ts/renderer-dom`: keep `lastSelectionRange` (block/row/col bounds);
  on repaint or mouse move compute the symmetric difference of old and new
  row sets and touch only those rows' `backgroundImage`; the cursor element
  moves between its old and new row nodes instead of being recreated
  (already in §1.2's list). `selectionView()` is called at most once per
  snapshot generation (§1.2 memoisation).
- No model change beyond §1.2.

**Tests**
- `dom-block-renderer.test.ts`: "a mouse move that extends the selection by
  one row repaints exactly one row"; "moving the cursor touches two rows".

**Priority:** with §1.2.

### 2.4 Reflow across the whole buffer with the cursor carried through it

> **Status: Not done.** No pull-back on height growth and no cursor-carrying reflow; waits on §1.5. The wide-character-at-the-cut case was already covered.

**Reference**
- `alacritty_terminal/src/grid/resize.rs:14-35` — order of operations: lines
  first, then columns; the cursor template cell is preserved across the
  resize.
- `grow_lines` `:43-69`: "keeps the cursor at the bottom as long as there is
  scrollback available" — new rows are pulled from history first, and only
  the remainder are blank rows; the cursor and saved cursor move down by the
  pulled count (`:62-66`).
- `shrink_lines` `:78-99`: history is pushed "out the top" (Terminal.app /
  iTerm behaviour), the cursor stays on its content; blank rows below the
  cursor go first (`required_scrolling` `:84`).
- `grow_columns` `:101-243` and `shrink_columns` `:245-389`: the grid
  (scrollback and screen alike) is rebuilt row by row; a row whose last cell
  carries `Flags::WRAPLINE` (`term/cell.rs:28`) is joined with the next; wide
  characters at the edge get `WIDE_CHAR_SPACER`/`LEADING_WIDE_CHAR_SPACER`
  (`cell.rs:30,35`, `resize.rs:170-190`); the cursor's own row is reflowed
  with `input_needs_wrap` (our `pending_wrap`) temporarily materialised as a
  column (`:129-132`, `:144-147`, `:157-165`); after the pass, rows are pulled
  down or the cursor moved up so it lands on the same text (`:100-108`).

**Ours today**
- `TERMINAL.md` §4.2–4.4 and §4.10: scrollback rows rewrap through
  `RowIndex::rewrap` (word-aware, hanging indents — richer than Alacritty's
  exact-column cut); the live frame is either evicted (shell mode) or
  truncated in place (agent TUI mode); height growth appends blank rows
  (`screen.rs:486-511`); `pending_wrap` exists (`screen.rs:99`).
- The screen's `wrapped` flag is cleared on any width change (`TERMINAL.md`
  §5 second gap: "truncated cells can no longer be rejoined faithfully").

**Gap**
Alacritty and Ghostty (§1.5) agree on the two behaviours we lack in shell
mode: growing rows pulls history back so the prompt stays anchored, and the
cursor is carried through a column reflow rather than the frame being evicted.
Alacritty's `resize.rs` is the shortest correct reference implementation of
the cursor bookkeeping (390 lines, Rust), and is the one to port if §1.5 is
approved; Ghostty's adds the prompt-clear on top.

**Proposal**
- Folded into §1.5's decision. If approved: port `grow_lines`/`shrink_lines`
  semantics (`:43-99`) to `ScreenGrid::resize` for shell mode, and the cursor
  reflow rules (`:100-108`, `:144-165`) into the in-place reflow. Keep our
  word-aware cut for scrollback; Alacritty cuts at the column.
- Independent of the decision: adopt the wide-character-at-edge spacer rule
  (`resize.rs:170-190`) in `RowIndex::rewrap` if a test shows we split a wide
  char across the cut ("wide characters kept whole" is claimed in the
  CHANGELOG; the plan verifies with a CJK fixture).

**Tests**
- `vt-core/tests/resize_policy.rs` additions listed in §1.5; plus
  `tests/rewrap.rs::a_wide_character_at_the_cut_moves_whole`.

**Priority:** with §1.5 (P4 decision); the wide-char check is P3 on its own.

### 2.5 Selection that rotates with the grid instead of tracked pins

> **Status: Partial.** Plan B — `onRowEvents` (trim and rewrap `remap`) and stable rows make trims harmless. Not done: the selection does not apply `remap`, so a width change moves it.

**Reference**
- `alacritty_terminal/src/selection.rs:93-99` `SelectionType::{Simple, Block, Semantic, Lines}`;
  `:100-118` doc: `Semantic` and `Lines` keep expanding as the end point
  moves, so a double-click drag stays word-aligned.
- `rotate` `:137-190`: when the grid scrolls `delta` rows inside a region, the
  terminal calls `selection.rotate(dims, range, delta)`; the selection moves
  with the content, is clipped to the region, and becomes `None` when it
  leaves the buffer. Call sites: `term/mod.rs:689` (scroll on resize), `:752`
  (`scroll_down`), `:778` (`scroll_up`, i.e. every line fed while a selection
  exists).
- `to_range` `:271` resolves the selection into an ordered `SelectionRange`
  (`:33-40`) at query time, expanding semantic/line kinds against the current
  grid; `contains_cell` `:60-90` excludes the block cursor's cell at the
  selection edges so the cursor stays visible; `include_all` `:252` for
  select-all; `intersects_range` `:228` lets the model clear a selection when
  a mutation overlaps it.

**Ours today**
- §1.3 "Ours today": `(blockId, row, column, side)` anchors, dropped only when
  a block id vanishes; rewrap moves rows under them.

**Gap**
Ghostty's pins (§1.3) are the general mechanism; Alacritty's rotate is the
minimal one: the model tells the selection how many rows moved and in which
range. Our model has exactly two row-moving operations — eviction (`trim_to`,
frame eviction) and rewrap (which already produces a row map). Rotating
anchors through those two paths gives 90% of §1.3 at a fraction of the code,
and can be done entirely in `ts/renderer-dom` if the snapshot reports "rows
evicted since last snapshot" and the rewrap map.

**Proposal**
- If §1.3's pins are not adopted: `GridSnapshot` exports
  `rowsTrimmedSinceLast: u32` and, after a width change, the old→new row map
  (`RowIndex::rewrap`'s `map`, currently internal); `selection-model.ts`
  applies both on each repaint (`rotate` semantics: subtract, remap, drop when
  out of range). Find hits (§1.7) use the same two hooks.
- Adopt `Semantic`/`Lines` re-expansion on drag (`selection.rs:100-118`):
  `selection-gesture.ts` already tracks click count; the expansion must be
  recomputed from the current snapshot at every drag update rather than
  frozen at press time. Whether ours re-expands or freezes: not known — the
  plan reads `selection-gesture.ts::drag`.

**Tests**
- `selection-model.test.ts`: "anchors shift up by the trimmed row count",
  "anchors follow the rewrap map", "a selection whose rows were all trimmed
  is dropped", "a word selection dragged onto a new row re-expands to the word".

**Priority:** P2 as the lightweight alternative to §1.3; §3.5 (markers fed
by row events) is the recommended synthesis of the two.

### 2.6 Directional, bounded regex search with lazy DFAs and smart case

> **Status: Partial.** Plan 2 — smart case and a regex toggle; next/previous walks sorted results, so no directional DFAs. Not done: `bracket_search`, `semantic_search_*`.

**Reference**
- `alacritty_terminal/src/term/search.rs:25-31` `RegexSearch` holds four
  lazy DFAs (forward/reverse × left/right) built with `regex_automata::hybrid`
  (`:34-60`, `:110-118`) so a search from a point in either direction is
  streaming, with cache limits (`minimum_cache_clear_count`,
  `nfa_size_limit`, `:41-44`).
- Smart case: `:39-40` — case-insensitive unless the pattern has an
  uppercase letter.
- `search_next(regex, origin, direction, side, max_lines)` `:121-137`:
  next match from a point, bounded by `max_lines` so the viewport search
  cannot walk the whole history (`alacritty/src/display/hint.rs:20`
  `MAX_SEARCH_LINES = 100`, used at `:326-327`).
- Helpers on `Term`: `bracket_search` `:472` (`BRACKET_PAIRS` `:19`),
  `semantic_search_left/right` `:517/:533` (word boundaries from
  `semantic_escape_chars`), `inline_search_left/right` `:541/:565`
  (vi `f`/`t`), `line_search_left/right` `:593/:606`; `RegexIter` `:620`
  iterates all matches in a range (used for highlighting every visible hit).
- Wide-character aware origins: `expand_wide` `:129`.

**Ours today**
- `find.rs`: `FindQuery::{Literal, Regex}` with `regex_automata::meta`
  over `Content` bytes, forward only, whole-buffer per query; case handling:
  not known (the plan reads `find.rs`). No "next/previous from here", no
  bounded viewport pass; `words.ts` (renderer) has Warp's boundary set for
  double-click.

**Gap**
Ghostty §1.7 covers caching by region. Alacritty adds: search *from a point
in a direction*, bounded, which is what a find bar's Enter/Shift+Enter needs,
and smart case, which users expect.

**Proposal**
- `vt-core`: `find_next(query, from: (row, col), direction, max_rows) -> Option<Match>`
  on top of the §1.7 session, implemented with `regex_automata::hybrid`
  forward and reverse DFAs (Alacritty `search.rs:34-118`); smart case in
  `FindQuery::literal/regex`. `bracket_search` and `semantic_search_*` are
  cheap once `Content` has a char iterator around a point; add them for the
  renderer's double-click and future keyboard selection (§1.4).
- `ts/renderer-dom` find bar: Enter/Shift+Enter call `find_next` from the
  current hit; the highlight pass uses `max_rows = viewport + 100`.

**Tests**
- `find.rs` units: direction and bound honoured; smart case; a match that
  crosses a soft-wrap; bracket search on nested pairs; word boundaries match
  `words.ts` (`selection-text.test.ts` fixtures reused).

**Priority:** P3, with §1.7.

### 2.7 Hints: regex/hyperlink matches with keyboard labels and actions

> **Status: Done.** Plan E — hint mode on Ctrl+Shift+Space with labels and `onHint`. Not done: host-supplied rules (package constant only) and Alacritty's bracket post-processing.

**Reference**
- `alacritty/src/display/hint.rs:26-40` `HintState { hint, alphabet, matches, labels, keys }`;
  `start` `:61`, `update_matches` `:74` (visible matches only, bounded by
  `MAX_SEARCH_LINES`), `keyboard_input` `:132` narrows by typed label
  characters, `labels` `:176`; label generation splits the alphabet so the
  last character differs (`HINT_SPLIT_PERCENTAGE` `:23`).
- `HintMatch` `:196-240`: bounds, optional OSC 8 hyperlink, the hint rule,
  `text()` resolves the matched string.
- `visible_regex_match_iter` `:318`, `visible_unique_hyperlinks_iter` `:335`.
- Hover: `highlighted_at(term, config, point, mods)` `:389-425` — OSC 8
  hyperlink under the pointer first (`hyperlink_at` `:428-453`, contiguous
  cells only), regex second, gated by the rule's required modifiers and by
  mouse-reporting mode (Shift overrides, `:400-402`).
- Post-processing `:455-520`: a match is trimmed of unbalanced closing
  brackets and trailing punctuation (`:501` "Truncate uneven number of
  brackets").
- Rules: `alacritty/src/config/ui_config.rs:354-392` `Hint { content: {regex, hyperlinks}, action, persist, post_processing, mouse, binding }`;
  actions `:329-352` `Copy | Paste | Select | MoveViModeCursor | Command(program)`;
  default URL rule `:250-275` with `URL_REGEX` `:40-41`
  (schemes list, then any run of non-control, non-bracket characters),
  bound to `Ctrl+Shift+O` for keyboard mode and to plain mouse hover/click.

**Ours today**
- No link detection or OSC 8 (§1.15 "Ours today"). Block actions exist
  (`block-actions.ts`) but nothing addresses a span *inside* a block.
- Agents print file paths and URLs constantly; opening one means selecting
  it by mouse and pasting elsewhere.

**Gap**
§1.15 proposes OSC 8 + hover-detected URLs (Ghostty's model). Alacritty's
hints generalise that into a rule table with actions and a keyboard path,
which fits an agent terminal better: "copy this file path", "open this URL",
"select this hash" without leaving the keyboard. The package stays
product-independent because the rules and actions come from the host.

**Proposal**
- `ts/renderer-dom`: `HintRule { id, regex, hyperlinks: boolean, postProcess: boolean }`
  list from the host via `TerminalSurface` props; a `hint-mode.ts` that on
  activation collects visible matches (`find_next` bounded to the window,
  §2.6, plus OSC 8 runs from §1.15), draws label overlays positioned by
  `row-geometry.ts`, narrows on typed characters (Alacritty `keyboard_input`
  `:132`), and emits `onHint({ ruleId, text, uri? })` for the host to act on
  (Operator maps rule ids to open/copy/insert-into-composer in `frontend/`).
  Hover path: `highlighted_at` semantics on pointer move with the rule's
  modifier, underline via the §1.8 highlight tag `hint`.
- Post-processing port (`:455-520`) as a pure function with Alacritty's tests.
- Default rule set shipped by the package as a constant the host may
  replace: Alacritty's `URL_REGEX` (`ui_config.rs:40-41`) plus a file-path
  rule (Operator-specific — lives in `frontend/`).

**Tests**
- `hint-mode.test.ts`: labels are unique and prefix-free; typing narrows;
  Escape exits; OSC 8 run beats regex at the same cell; post-processing trims
  `https://x.y/a)` to `https://x.y/a` but keeps `(https://x.y/(a))` balanced.
- `TerminalSurface.test.tsx`: the chord enters hint mode; `onHint` fires with
  the matched text.

**Priority:** P2 (highest-value new capability in this section for agent use).

### 2.8 Full SGR attribute set as a cell flag bitset, with rare data out of line

> **Status: Done.** Plan D — ten attribute bits and underline colour in the style word; painted with `attributes: "warp"`, the default since 2026-09-23 (`534ef20fe`).

**Reference**
- `alacritty_terminal/src/term/cell.rs:22-40` `Flags: u16` —
  `INVERSE, BOLD, ITALIC, UNDERLINE, WRAPLINE, WIDE_CHAR, WIDE_CHAR_SPACER, DIM, HIDDEN, STRIKEOUT, LEADING_WIDE_CHAR_SPACER, DOUBLE_UNDERLINE, UNDERCURL, DOTTED_UNDERLINE, DASHED_UNDERLINE`
  (`ALL_UNDERLINES` mask `:40`).
- `CellExtra` `:132-136` (zero-width chars up to `MAX_ZEROWIDTH_CHARS = 9`
  `:17`, underline colour for SGR 58, OSC 8 hyperlink) boxed off the cell so
  a plain cell is `char + fg + bg + flags`.
- SGR decoding is `vte::ansi::Attr` (all of 1–9, 21–29, 38/48/58 with 2/5
  sub-parameters, 90–107) delivered through `Handler::terminal_attribute`.

**Ours today**
- `parser.rs:315-360` `apply_sgr`: bold (1), dim (2), reverse (7), their
  resets, and colours. Italic (3), underline (4 and `4:x`), blink (5), hidden
  (8), strikethrough (9), underline colour (58/59) are `_ => {}`.
- `style.rs` `StyleCode(u32)` packs colour + bold/dim/reverse bits;
  `STYLE_RUN_WORDS` stride in the snapshot; `style-code.ts` decodes in the
  renderer; `row-builder.ts` sets classes/inline colours.
- Zero-width accumulation exists with a byte cap (`screen.rs:20`).

**Gap**
Claude Code and other Ink/TUI output using italic (tool names, hints),
underline (links, emphasis) or strikethrough (removed lines in diffs)
renders as plain text in Operator. This is visible and cheap to fix, and the
typed handler in §2.2 delivers the decoded attributes for free.

**Proposal**
- `vt-core`: `CellStyle` gains an `attrs: u16` with Alacritty's bit names
  (minus the wrap/wide bits, which are row/cell state not style) and an
  optional underline colour stored in `AttributeMap` beside the style;
  `apply_sgr` (or `terminal_attribute` after §2.2) sets them; `22/23/24/25/28/29`
  reset. Snapshot: widen `STYLE_RUN_WORDS` by one word (checklist in
  `TERMINAL.md` §2 applies).
- `ts/renderer-dom`: `style-code.ts` decodes the word; `row-builder.ts`
  emits `font-style: italic`, `text-decoration` (underline / double / wavy /
  dotted / dashed via `text-decoration-style`, colour via
  `text-decoration-color`), `line-through`, `visibility: hidden` for 8, and a
  `blink` class the theme may animate or ignore (Warp ignores blink — cite
  when the plan checks `warp_terminal` for SGR 5).
- Theme: `theme-warp.ts` supplies the underline default colour.

**Tests**
- `vt-core/tests/sgr.rs`: each attribute set and reset, `4:3` undercurl,
  `58;2;r;g;b`, attributes survive eviction and rewrap; the Alacritty
  reference recordings `sgr`, `underline`, `colored_underline`,
  `clear_underline`, `colored_reset` (§2.9) pass.
- `style-code.test.ts`, `row-builder.test.ts`: decode and class mapping;
  `styles-parity.test.ts`: underline sits at Warp's offset (cite when known).

**Priority:** P2 (visible fidelity loss today).

### 2.9 Reference recordings as the conformance corpus

> **Status: Done.** Plan A — `tests/ref` with Alacritty's recordings plus our own.

**Reference**
- `alacritty_terminal/tests/ref.rs:1-130`: `ref_tests! { … }` macro
  (`:16-27`) expands each directory under `tests/ref/` into a test; each
  directory holds `alacritty.recording` (raw pty bytes), `size.json`,
  `config.json` (history size) and `grid.json` (the expected grid,
  serialised with `serde`); the test replays the bytes through
  `ansi::Processor` into a fresh `Term` (`:110-114`), truncates invisible
  lines, and prints the first differing cells on failure (`:118-128`).
- Corpus (45 dirs, `tests/ref/`): `vttest_*` (cursor movement, insert,
  origin mode ×2, scroll, tab clear/set), `tmux_htop`, `tmux_git_log`,
  `vim_simple_edit`, `vim_large_window_scroll`, `vim_24bitcolors_bce`,
  `zsh_tab_completion`, `fish_cc`, `hyperlinks`, `zerowidth`, `sgr`,
  `underline`, `colored_underline`, `wrapline_alt_toggle`,
  `scroll_in_region_up_preserves_history`,
  `newline_with_cursor_beyond_scroll_region`, `history`, `saved_cursor(_alt)`,
  `selective_erasure`, `csi_rep`, `decaln_reset`, `deccolm_reset`, and the
  `*_reset` family.
- Recording is a runtime flag: `alacritty/src/cli.rs:30` `--ref-test`,
  `alacritty_terminal/src/event_loop.rs:54,221` tees every pty byte to a file.

**Ours today**
- `TERMINAL.md` §7: capture bytes by hand with `script` / a Python `pty.fork`
  tool, feed them to a `vt-core` test, compare with pyte by eye. The only
  committed corpus is the fixture in `vt-wasm/tests/exit_encoding.rs` and
  per-bug tests. No recording switch in the pty-host.
- Both projects run `vte` 0.15, so Alacritty's recordings exercise the same
  parser; expected *grids* differ where our model differs (blocks, colour
  representation, scrollback rewrap), so `grid.json` is not directly
  comparable — the visible text and cursor position are.

**Proposal**
- `crates/vt-core/tests/ref/` with the same layout; `tests/ref.rs` macro
  replaying into `TerminalCore::new(cols, history)` and comparing
  `snapshot().row_text(i)` + cursor against an expected `screen.txt` +
  `cursor.json` (text-level, model-agnostic), and optionally our own
  `snapshot.json` for full fidelity of blocks and styles.
- Import Alacritty's 45 recordings (Apache-2.0/MIT, attribution file next
  to them) with expectations regenerated as text; any divergence is triaged
  once: parser bug (fix), model difference (documented in the expectation), or
  Alacritty bug (skip with a note).
- Pty-host: `OPERATOR_PTY_RECORD=<path>` (or `--record` in `host_main.go`)
  tees the raw child output, so a Claude Code artefact is captured with one
  env var instead of the §7 scratch tooling; `RUN_APP_COMMANDS.md` documents
  it.
- The §1.14 property test feeds the same harness.

**Tests**
- The corpus itself; `host_main_test.go::TestRecordFlagTeesOutput`.

**Priority:** P2 — cheapest way to raise confidence before §2.2's parser refactor.

### 2.10 Bounded parsing per turn so a burst cannot stall the renderer

> **Status: Done.** Plan A — `enqueue`/`drain` with a 12 ms budget per animation frame. Plan 4 added a 250 ms drain per timer tick while the window is hidden (`cb7b34b3b`).

**Reference**
- `alacritty_terminal/src/event_loop.rs:23-27` `READ_BUFFER_SIZE = 1 MiB`,
  `MAX_LOCKED_READ = u16::MAX` bytes; `pty_read` `:104-171` parses at most
  `MAX_LOCKED_READ` bytes per lock acquisition (`:159-162`) and uses
  `try_lock_unfair` so the renderer is not starved (`:138-145`);
  `alacritty_terminal/src/sync.rs:7-11` `FairMutex` guarantees a waiting
  renderer gets the lock before the reader re-locks.

**Ours today**
- `useTerminalSession.ts` calls `core.feed(bytes)` synchronously per mux
  message on the main thread (exact call site: `frontend/src/renderer/hooks/useTerminalSession.ts`,
  line not known — the plan locates it); a large message (e.g. `cat` of a
  multi-MB file, or the attach replay of a long scrollback) is parsed in one
  task before any paint.

**Gap**
The browser is single-threaded; the analogue of Alacritty's bound is
"parse at most N KB per animation frame and yield". Without it a burst
freezes input handling for the duration of the parse (how long for 5 MB:
not known — measure).

**Proposal**
- `ts/core` (product-independent): `TerminalCore.enqueue(bytes)` with a
  drain loop that feeds up to `FEED_BUDGET_BYTES` (start at 64 KiB, Alacritty's
  order of magnitude) per rAF tick, then yields; `hasBacklog()` for the
  renderer to show nothing special (Alacritty shows nothing either). The
  §2.1 `tick(now)` runs in the same loop. Mouse/keyboard input is never
  queued behind the backlog.
- Host side unchanged.

**Tests**
- `terminal-core.test.ts`: a 1 MiB feed is drained over several ticks; order
  is preserved; a key sent mid-drain is not delayed by the backlog.
- Bench: time-to-first-paint for a 5 MB burst before/after.

**Priority:** P3 (P2 if the attach replay of long sessions is measured to stall).

### 2.11 Paste: strip `ESC` and `^C` inside bracketed paste; keep newlines as `\r` outside

> **Status: Done (roadmap Plan 1, 2026-09-24).** Bracketed paste removes `ESC[201~`, then every `ESC` and `^C`.

**Reference**
- `alacritty/src/event.rs:1369-1410` `paste`: search mode consumes the text;
  otherwise if bracketed paste is on, write `\x1b[200~`, the text with every
  `\x1b` **and** `\x03` removed ("some shells incorrectly terminate bracketed
  paste when they receive it", `:1381-1386`), then `\x1b[201~`; otherwise
  `\r\n` and `\n` become `\r` (`:1393-1404`).

**Ours today**
- `ts/editor/src/paste.ts:17-27`: bracketed → strips only the literal
  `PASTE_END` string; a lone `\x1b` or `\x03` passes through. Unbracketed →
  newlines to `\r`, same as Alacritty.

**Gap**
A pasted `\x1b` inside a bracketed paste can still be reassembled into
`\x1b[201~` by following bytes, and `^C` aborts the paste in some shells.
Alacritty's filter is stricter than ours and one line.

**Proposal**
- Folded into §1.10: in bracketed mode remove `\x1b` and `\x03` (Alacritty)
  instead of the `PASTE_END` substring; unbracketed multi-line asks (Ghostty).

**Tests**
- `paste.test.ts`: `"a\x1bb"` bracketed → `ab`; `"a\x03b"` → `ab`.

**Priority:** with §1.10 (P2).

### 2.12 Cursor legibility: invert the cursor when it lacks contrast with the cell

> **Status: Done.** Plan D — `cursorContrast` and `cursorHollowUnfocused` flags, both still off: `cursorContrast` changes 0 px on the Claude Code recordings (`TERMINAL.md` §5).

**Reference**
- `alacritty/src/display/content.rs:21-22` `MIN_CURSOR_CONTRAST = 1.5`;
  `:124-134`: when the configured cursor colour is not an explicit RGB and
  the cell's fg/bg contrast (`color.rs` `contrast`) is below the threshold,
  the cursor colours are swapped so it cannot vanish over a same-coloured band.
- Selection excludes the block cursor cell at its edges
  (`selection.rs:60-90`) so the cursor is drawn distinctly inside a selection.

**Ours today**
- `ts/renderer-dom/src/cursor.ts` places a `terminal-cursor` element
  (`CLASS_CURSOR`, `cursorRow/Column/Visible`); its colour comes from the
  theme (`styles.css`/`style-vars.ts`); whether it adapts to the cell under
  it: not known (no contrast code found by grep: `grep -rn contrast ts/` →
  no match). Claude Code's grey user-message band (§4.11) is the case where a
  fixed cursor colour disappears.

**Proposal**
- `ts/renderer-dom`: `cursor.ts` computes WCAG-style contrast between the
  cursor colour and the underlying run's background (available from the
  style run) and flips to the inverse pair below 1.5. Combine with §1.17's
  hollow-when-unfocused.

**Tests**
- `terminal-cursor.test.ts`: a cursor over a band whose colour equals the
  cursor colour renders inverted; over the default background it does not.

**Priority:** P3, with §1.17.

### 2.13 Keyboard-driven navigation and selection (vi mode) — available, not recommended

> **Status: Not pursued.** The entry itself says not recommended, and the agent-TUI spec lists it under non-goals.

**Reference**
- `alacritty_terminal/src/vi_mode.rs:12-55` `ViMotion` (Up/Down/Left/Right,
  First/Last/FirstOccupied, High/Middle/Low, Semantic*/Word* left/right and
  ends, Bracket); `ViModeCursor::motion` applies them against the grid;
  selection toggles by kind from the keyboard (`alacritty/src/input/mod.rs:192-202`),
  `Term::toggle_vi_mode` (`term/mod.rs:813`), `scroll_to_point` `:884`
  keeps the vi cursor in view.
- Hints (§2.7) reuse the same machinery for `MoveViModeCursor`.

**Ours today**
- Block navigation (`block-nav.ts`), find bar, jump-to-bottom; no cursor that
  the user moves over the transcript.

**Gap / Decision**
A full vi mode is a product decision Warp did not make; the block model
already gives keyboard jumps at block granularity. The parts worth having
without a mode are in §1.4 (Shift+arrow `adjust`) and §2.7 (hints). Listed
for completeness.

**Priority:** P4.

### 2.14 Robustness caps on app-driven stacks

> **Status: Done.** Roadmap Plan 3 — title stack capped at 4,096 (oldest dropped), pending notifications at 16, titles at 1,024 bytes. There is no keyboard-mode stack to cap. The grapheme byte cap (256) was already in place.

**Reference**
- `alacritty_terminal/src/term/mod.rs:42-48` `TITLE_STACK_MAX_DEPTH = 4096`,
  `KEYBOARD_MODE_STACK_MAX_DEPTH`; `push_title` `:2235-2248` and
  `push_keyboard_mode` `:1288-1300` drop the oldest entry at the cap so an
  app that pushes forever cannot grow memory.
- Zero-width chars per cell capped at 9 (`cell.rs:17`).

**Ours today**
- Zero-width cap by bytes (`screen.rs:20`); no title or keyboard-mode stacks
  (they arrive with §2.2/§1.15).

**Proposal**
- When §2.2 lands: the same depth caps on our title stack and keyboard-mode
  stack.

**Priority:** with §2.2.

### Not adopted from Alacritty, and why

| Area | Files | Reason |
|---|---|---|
| OpenGL renderer, glyph cache, `winit` window, damage-to-compositor rects | `alacritty/src/renderer/`, `display/window.rs`, `display/damage.rs:93` (`shape_frame_damage`) | DOM renderer; only the damage *bookkeeping* transfers (§2.3). |
| Ring-buffer `Storage` with `zero` offset and lazy `len` shrink | `alacritty_terminal/src/grid/storage.rs:14-52,180-199` | Equal: `ScreenGrid` is a ring (`first`, `TERMINAL.md` §2) and scrollback is append-only `Content`; nothing to gain. |
| `display_offset` scrolling in the model, `Scroll::{Delta,PageUp,PageDown,Top,Bottom}`, `scroll_to_point` | `term/mod.rs:389,884` | The DOM scroller owns the viewport (`viewport.ts`, stickiness); moving it into the model would fight the browser. |
| `FairMutex`, reader thread, `Notifier`/`Msg` channel | `sync.rs`, `event_loop.rs`, `thread.rs` | Single-threaded browser core; §2.10 is the equivalent. |
| Config system, live reload, `alacritty_config_derive` | `alacritty_config*/`, `alacritty/src/config/` | Host concern; the package takes typed options. |
| IPC socket (`alacritty msg`), CLI | `alacritty/src/ipc.rs`, `cli.rs` | Operator has the daemon API. |
| Bell (visual/audible), message bar, scheduler | `display/bell.rs`, `message_bar.rs`, `scheduler.rs` | Host chrome; the package emits events. |
| Touch zoom, macOS/Windows tty specifics | `input/mod.rs` (`TouchZoom`), `tty/windows/` | Not applicable / the pty-host owns ConPTY. |
| Wide-char `WIDE_CHAR_SPACER` cell flags as style bits | `cell.rs:29-35` | We keep spacer cells as `'\0'` (`screen.rs:377`); equivalent. |

### Alacritty section: suggested plan order

1. **2.1** parser-buffered synchronized updates (replaces §1.1's renderer skip).
2. **2.9** reference-recording harness + import the 45 recordings; add the
   pty-host record switch.
3. **2.8** full SGR attributes (with **2.2** if the refactor is approved
   first; otherwise extend `apply_sgr` by hand and refactor later).
4. **2.7** hints (with §1.15's OSC 8 storage).
5. **2.5** rotate-based anchors or §1.3 pins — one of the two.
6. **2.3**, **2.11**, **2.12**, **2.10** alongside their §1 counterparts.
7. **2.4** with the §1.5 decision.

---

## 3. xterm.js

**Repository:** `/Users/omaraly/development/AI/xterm.js` at commit `c58ea36`
(2026-08-30, package version 6.0.0). **Language:** TypeScript.
**Relevant tree:** `xterm.js/src/browser/` (DOM renderer, services,
selection, accessibility, IME, links), `xterm.js/src/common/` (buffer,
parser, input handler, write buffer, task queue), `xterm.js/addons/`
(`addon-search`, `addon-serialize`, `addon-web-links`, `addon-unicode-graphemes`,
`addon-progress`, `addon-webgl`), `xterm.js/typings/xterm.d.ts` (public API).

**Why xterm.js is worth mirroring:** it is the only production terminal that
renders in a browser, so it is the only reference for the layer where most of
our code lives — `packages/terminal/ts/renderer-dom` and `ts/react`. §1 and
§2 are ~80% `vt-core`; this section is ~80% renderer. It is also what VS
Code, Hyper and Tabby ship, so it is the browser behaviour users already
compare Operator against, and its public API (`registerMarker`,
`registerDecoration`, `registerLinkProvider`, `onWriteParsed`) shows which
seams a host needs from a terminal package.

Paths below are relative to the repository root; `xterm.js/src/…` means
`/Users/omaraly/development/AI/xterm.js/src/…`, `packages/terminal/…` means
`/Users/omaraly/development/AI/Operator/packages/terminal/…`.

### 3.1 A fixed pool of row elements, repainted by dirty row range on one animation frame

> **Status: Done.** Plan B — row-element pool with dirty-row patching. The ≤ 2 nodes per changed row target was missed (≈7 per styled row). Since Plan 4 a parked pane does not paint; row layout containment was measured with no gain (`TERMINAL.md` §4.26).

**Reference**
- `xterm.js/src/browser/renderer/dom/DomRenderer.ts:336-351`
  `_refreshRowElements`: exactly `rows` `<div>` row elements are created once
  per resize and kept (`_rowElements`, `:46`); `:353-357` `handleResize`.
- `xterm.js/src/browser/renderer/dom/DomRenderer.ts:527-563` `renderRows(start, end)`:
  only rows in `[start, end]` are touched; each is refilled with
  `rowElement.replaceChildren(...rowFactory.createRow(...))` from the buffer
  line at `y + buffer.ydisp`.
- Dirty range accumulation: `xterm.js/src/browser/services/RenderService.ts:156-183`
  `refreshRows(start, end, sync, isRedrawOnly)` merges requests;
  `xterm.js/src/browser/RenderDebouncer.ts:28-49` `refresh` keeps the min
  start / max end and schedules one `requestAnimationFrame`; `_innerRefresh`
  `:51-…` clamps and calls the renderer once. The input handler requests
  refreshes per mutated row (`xterm.js/src/common/InputHandler.ts:534,672,743`
  `_dirtyRowTracker.markDirty(buffer.y)` on print, line feed, and the other
  cursor-row mutations).
- `xterm.js/src/browser/services/RenderService.ts:36` `_isNextRenderRedrawOnly`
  and `:186-212` `_renderRows`: selection refresh is folded into the same
  frame (`_needsSelectionRefresh`), and `onRenderedViewportChange` fires only
  when content changed, not on a pure redraw.
- Cursor and blur/focus repaint only the cursor row:
  `xterm.js/src/browser/renderer/dom/DomRenderer.ts:365-375`
  (`handleBlur` → full, `handleFocus` → `renderRows(buffer.y, buffer.y)`),
  `:488-491` `handleCursorMove`.

**Ours today**
- `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:306-324`
  one rAF per feed (equivalent debounce), then `repaint` `:362-480` rebuilds
  every visible block's rows (`packages/terminal/ts/renderer-dom/src/block-body.ts:19-44`,
  new nodes each time). No dirty range: the renderer has no way to know which
  rows changed (§1.2 "Ours today").
- Row elements are created per paint and dropped with the block element when
  it leaves the window (`dom-block-renderer.ts:465-470`).

**Gap**
xterm.js confirms §1.2/§2.3 from the DOM side and adds the concrete shape
that works in a browser: a persistent row-element pool and a `[start, end]`
dirty range delivered to `renderRows`. It also shows the cheap wins we can
take before the model exports dirtiness: repaint only the cursor row on
focus/blur/cursor move, and refresh the selection in the same frame rather
than via a separate `paintSelectionFill` pass.

**Proposal**
- `packages/terminal/ts/renderer-dom`: keep a `Map<absoluteRow, HTMLElement>`
  per block element (pool), reuse nodes across paints, and drive
  `renderRows(start, end)` from the model's dirty set (§1.2) — until that
  lands, from a renderer-side heuristic: rows whose exported
  `(content range, style range)` pair is identical to the previous
  snapshot are skipped (a byte-range equality check per row is cheap because
  `Content` offsets never move). Cursor moves repaint two rows.
- Merge `paintSelectionFill` into the paint frame (`_needsSelectionRefresh`
  pattern, `RenderService.ts:37,203-206`).

**Tests**
- `dom-block-renderer.test.ts`: "row elements are reused across paints"
  (identity), "a cursor move touches two rows", "an unchanged row is not
  rebuilt when only another row changed".

**Priority:** P2, the renderer half of §1.2.

### 3.2 Row factory: span merging by attribute, joined characters, per-cell letter-spacing from a width cache

> **Status: Done.** Plan D — per-cluster letter-spacing from a width cache, on by default together with `graphemes` since 2026-09-22 (`7395b910c`); ZWJ and flag clusters are measured as one span. The ligature joiner is not adopted (Hack has no ligatures).

**Reference**
- `xterm.js/src/browser/renderer/dom/DomRendererRowFactory.ts:63-260`
  `createRow`: walks cells and appends to the current `<span>` while the
  cell is "mergeable" — same fg/bg/flags/selection state/spacing and not the
  cursor cell or a joined range (`:185-235`, conditions `:199-212`); one
  `textContent` write per span (`:231`).
- Wide characters occupy `width` cells and zero-width cells are skipped
  (`:109-116`); character joiners (ligatures/graphemes provided by
  `CharacterJoinerService`) render as one span (`:117-158`).
- `xterm.js/src/browser/renderer/dom/DomRendererRowFactory.ts:176-184`:
  a space that is underlined renders as `\xa0` so the decoration is visible;
  `spacing = width * cellWidth - widthCache.get(chars, bold, italic)` and
  `:477-480` applies `letter-spacing` per span when the glyph's measured
  width differs from the cell — this is how a fallback font's wider glyph is
  kept inside its cell.
- `xterm.js/src/browser/renderer/dom/WidthCache.ts:1-60`: a flat
  `Float32Array` cache for code points < 256 × 4 font variants plus a
  `Map` for the rest, measured with a hidden span of `REPEAT = 32` copies
  (`WidthCacheSettings`, `:8-14`), invalidated on font change.
- Underline colour and style: `:315-345` (`textDecorationColor`,
  `textDecoration`), overline, strikethrough, dim via opacity; inverse
  handled by swapping fg/bg before colour resolution (`:380-460`).

**Ours today**
- `packages/terminal/ts/renderer-dom/src/row-builder.ts:36-116`: one
  `<span class="terminal-run">` per style run from the snapshot's `runRanges`
  (runs are already merged by `vt-core`'s `AttributeMap`), a per-cell
  `<span>` only for the cursor / fill cases; no per-glyph width correction.
  `TERMINAL.md` §4.2 notes "a glyph that renders a hair wider than its cell
  must not grow a scrollbar" and clips instead.
- `packages/terminal/ts/renderer-dom/src/cell-width.ts:38-51` is a
  code-point → cell count table (East Asian width), not a pixel measurement.
- Underline/italic/strike are not rendered at all (§2.8).

**Gap**
Run merging is equal (ours is done in the model). What we lack is the
per-glyph width correction: with Hack as the shipped font and system
fallback for CJK, emoji and symbols (Claude Code's `⎿ ● ○ ◐`), a fallback
glyph wider than the cell shifts every glyph after it on that row, which
misaligns box drawing and makes `pointerCell` (mouse → column) wrong for
the rest of the row. xterm.js measures each distinct glyph once and pads
with `letter-spacing`.

**Proposal**
- `packages/terminal/ts/renderer-dom/src/width-cache.ts`: port
  `WidthCache` (flat array for ASCII/Latin-1, map beyond, `REPEAT` copies
  measured in the existing hidden measure host `dom-block-renderer.ts:139-151`);
  `row-builder.ts` splits a run where the measured width of a glyph differs
  from `cells × cellWidth` and sets `letter-spacing` on that span (xterm.js
  `:477-480`). Cache cleared on font/theme change.
- `\xa0` for underlined spaces once §2.8 renders underline.

**Tests**
- `width-cache.test.ts` (port of `xterm.js/src/browser/renderer/dom/WidthCache.test.ts`).
- `row-builder.test.ts`: "a glyph measured wider than its cell gets
  negative letter-spacing", "column geometry after a wide fallback glyph
  matches the cell grid" (`row-geometry.test.ts`).

**Priority:** P2 if a screenshot with emoji/CJK in a Claude Code row shows
drift; P3 otherwise. The plan takes the screenshot first.

### 3.3 Char size measured once per font change, with `TextMetrics` first and a DOM span as fallback

> **Status: Done.** Plan A — char metrics cached, invalidated by `setFont`, `setTheme` and the DPR query. No `ResizeObserver` on the measure host and no `TextMetrics` path, both by decision (Plan A deviations).

**Reference**
- `xterm.js/src/browser/services/CharSizeService.ts:11-40`: `measure()`
  runs on construction and on font-related option changes only; results are
  cached in `width/height` and `onCharSizeChange` fires when they differ.
- `:104-130` `TextMetricsMeasureStrategy`: an offscreen canvas
  `measureText('W')` using `width`, `fontBoundingBoxAscent/Descent` — no
  layout; `:75-100` `DomMeasureStrategy` (hidden span with 32 `W`s, `:56-60`)
  as the fallback when `fontBoundingBox*` is unsupported.

**Ours today**
- `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:139-151`
  `measure()`: `getBoundingClientRect()` on a hidden node every call; it is
  called from `repaint` (`:419`), from `jump-to-bottom`, `cellMetrics()`
  (selection paints) and `blockContentInset`. Each call is a forced layout
  read; the count per frame is not known (the plan instruments it).

**Gap**
Layout thrash risk on every paint and every mouse move; the value only
changes on font or zoom change.

**Proposal**
- Cache `{cellWidth, cellHeight}` in `DomBlockRenderer`; invalidate on
  `setFont`/theme change, `devicePixelRatio` change (`matchMedia` resolution
  query, xterm.js `DomRenderer.ts:330-334` `handleDevicePixelRatioChange`)
  and container font-size change (`ResizeObserver` on the measure host).
  Prefer `TextMetrics` when `fontBoundingBoxAscent` exists.

**Tests**
- `dom-block-renderer.test.ts`: "measure() reads layout once until the font
  changes" (spy on `getBoundingClientRect`).

**Priority:** P2 (small, likely measurable).

### 3.4 Synchronized output as a renderer-side buffered range with a 1 s timeout

> **Status: Done.** Covered by §2.1: `vt-core` buffers DEC 2026, so a sync frame lands as one dirty set and one paint; no renderer timeout needed.

**Reference**
- `xterm.js/src/common/InputHandler.ts:2035-2037` sets
  `decPrivateModes.synchronizedOutput`; `:2284` resets; `:2392` reports it
  for `DECRQM`.
- `xterm.js/src/browser/services/RenderService.ts:337-375`
  `SynchronizedOutputHandler`: while the mode is on, `refreshRows` calls are
  buffered as a growing `[start, end]` (`bufferRows`), a `setTimeout` of
  `SYNCHRONIZED_OUTPUT_TIMEOUT_MS = 1000` (`:22`) force-clears the mode;
  `flush()` returns the buffered range which the next real refresh merges
  (`:156-169`, and the second check inside `_renderRows` `:186-193` for
  frames queued before the mode was set).

**Ours today** — §1.1 / §2.1.

**Gap / Proposal**
Third implementation of the same feature: Ghostty skips frames in the
renderer, Alacritty buffers bytes in the parser, xterm.js buffers the dirty
range in the render service. xterm.js's is the DOM-specific detail worth
keeping alongside §2.1: when the parser flushes a sync block, the rows it
touched arrive as one dirty range and one paint. No separate proposal; §2.1
plus §3.1 covers it. The 1 s timeout matches Ghostty; Alacritty's 150 ms is
the parser-side one. Use 150 ms in the parser (§2.1) — the renderer never
needs its own.

**Priority:** covered.

### 3.5 Markers: line anchors kept valid by buffer events (trim / insert / delete)

> **Status: Done.** Plan B — done as stable row ids plus `onRowEvents` (trim and remap) rather than xterm.js markers.

**Reference**
- `xterm.js/src/common/buffer/Marker.ts:1-40`: a `Marker` is `{ id, line }`
  with `onDispose`.
- `xterm.js/src/common/buffer/Buffer.ts:637-664` `addMarker(y)`: the marker
  subscribes to the line list's `onTrim` (line -= amount, dispose when < 0),
  `onInsert` (shift down if at/after the index) and `onDelete` (dispose if
  inside the range, shift up if after). The `CircularList`
  (`xterm.js/src/common/CircularList.ts`) fires these for every scrollback
  trim and every `insertLines`/`deleteLines`.
- Public API: `xterm.js/typings/xterm.d.ts:1275` `registerMarker(cursorYOffset)`.
  Markers are what VS Code's shell integration uses to remember where each
  command started (§5 when VS Code is surveyed).
- Reflow keeps markers roughly right by treating line joins/splits as
  insert/delete events (`Buffer.ts:525-534`).

**Ours today** — §1.3 / §2.5 "Ours today".

**Gap**
Third variant of anchors: Ghostty rewrites tracked pins inside every
mutation, Alacritty rotates the selection on scroll, xterm.js publishes
buffer events and lets each anchor adjust itself. For our model the event
list is short and already exists implicitly: `trim_to` (trim), `evict_frame`
/ scroll-off (trim into scrollback — a no-op for flat-row anchors since
the row keeps its index), `RowIndex::rewrap` (a map = insert/delete pairs),
`insert_lines`/`delete_lines` on the screen (insert/delete). Exporting those
as events on the snapshot is the smallest change that makes selection, find
hits and future decorations self-maintaining, and it keeps `vt-core` free of
anchor bookkeeping.

**Proposal**
- `packages/terminal/crates/vt-core`: an `events: Vec<RowEvent>` on
  `GridSnapshot` (`Trim { amount }`, `Insert { at, amount }`, `Delete { at, amount }`,
  `Remap { map }` after a rewrap), drained per snapshot; exported through the
  §2 checklist.
- `packages/terminal/ts/core`: `TerminalCore.onRowEvents(listener)`.
- `packages/terminal/ts/renderer-dom`: a `Marker` class (port of
  `Marker.ts` + the three subscriptions from `Buffer.ts:637-664`);
  `selection-model.ts` anchors and find hits become markers with a column.
- Decision with §1.3/§2.5: this is the recommended one of the three because
  the model change is one exported vector and the anchors live where they
  are used.

**Tests**
- `vt-core/tests/row_events.rs`: each mutation emits the right event; a
  snapshot drains them; two snapshots with no mutation emit none.
- `marker.test.ts` (port of the xterm.js `Buffer.test.ts` marker cases:
  trim below zero disposes, insert above shifts, delete inside disposes).

**Priority:** P2; supersedes the §1.3-vs-§2.5 choice. §4.1 (stable row
indices) makes the `Trim` event unnecessary; keep `Remap` for rewrap.

### 3.6 Decorations anchored to markers, positioned by the renderer

> **Status: Partial.** Plan E — an internal overlay layer positioned from geometry (link underline, hints, redaction masks, echo prediction). Not done: host `registerDecoration`/`onRender`, the overview ruler; find hits are not decorations.

**Reference**
- API: `xterm.js/typings/xterm.d.ts:649-680` `IDecorationOptions { marker, anchor: 'left'|'right', x, width, height, backgroundColor, foregroundColor, layer, overviewRulerOptions }`;
  `:1285` `registerDecoration`; a decoration exposes `onRender(element)` so
  the host can fill the element (VS Code draws its command circles this way).
- `xterm.js/src/common/services/DecorationService.ts:20-80`: decorations
  kept in a `SortedList` keyed by `marker.line` (`:45`) so
  `getDecorationsAtCell`/`forEachDecorationAtCell` are a binary search; a
  disposed marker removes its decoration (`:60-68`).
- `xterm.js/src/browser/decorations/BufferDecorationRenderer.ts:31,66-95`:
  on every rendered-viewport change, each visible decoration's element is
  positioned by `(marker.line - ydisp) × cellHeight` and sized in cells;
  off-viewport ones are hidden (`:84`).
- `xterm.js/src/browser/decorations/OverviewRulerRenderer.ts` draws the
  same decorations as marks in a scrollbar-side ruler (search hits, command
  results).

**Ours today**
- Block chrome is built into the block element (`block-header.ts`,
  `block-actions.ts`, `pinned-header.ts`); find hits and selection are
  painted as row backgrounds. There is no host-facing way to attach a
  widget to a row. The overview ruler has no counterpart.

**Gap**
The block model gives us headers; what it does not give is "put this thing
at that row" for a host: a failing-test marker from Operator, a review
comment anchor, an inline "open in editor" affordance next to a file path,
or the overview-ruler dots for find hits and failed commands that VS Code
users expect.

**Proposal**
- `packages/terminal/ts/renderer-dom`: `registerDecoration({ marker, column?, width?, height?, layer, onRender })`
  on `DomBlockRenderer`, stored sorted by resolved row; positioned during
  paint from `row-geometry.ts`; hidden outside the window. Highlights (§1.8)
  are decorations with `layer: 'bottom'` and no element.
- An optional overview ruler (`overview-ruler.ts`) rendering decoration
  colours along the scrollbar; host opts in.
- `HostCapabilities` gains nothing; the API is on the renderer instance the
  host already holds (`BlockTerminal.tsx`).

**Tests**
- `decorations.test.ts`: positions follow the marker across a trim; hidden
  when off-window; `onRender` called once per element creation; sorted
  lookup by row.

**Priority:** P3 (P2 once a product feature needs it; the planning-tickets
work may).

### 3.7 Link providers: OSC 8 first, regex second, resolved lazily per hovered line

> **Status: Done.** Plan E — linkifier: OSC 8 provider first, URL and path providers second, per hovered logical line. Path detection rebuilt from Operator's own rules 2026-09-23 (`b17acd63c`).

**Reference**
- `xterm.js/src/browser/Linkifier.ts:14-140`: on mouse move the linkifier
  asks providers for links on the hovered *line only* (`_askForLink`,
  `:108-136`), caches the result per line until the buffer changes
  (`_linkCacheDisposables`, `:19,40-41`), fires `onShowLinkUnderline`/
  `onHideLinkUnderline` with cell ranges, and activates on click with the
  platform modifier; providers are async (`provideLinks(y, callback)`).
- `xterm.js/src/browser/OscLinkProvider.ts:12-120`: OSC 8 links from the
  cell's extended attribute `urlId`, contiguous cells only, extended across
  wrapped lines (`:116`); URIs stored once in `OscLinkService`.
- `xterm.js/addons/addon-web-links/src/WebLinksAddon.ts:21`
  `strictUrlRegex` (scheme `https?`, excludes quotes/brackets/trailing
  punctuation) and `WebLinkProvider.ts` which searches the wrapped logical
  line, not the visual row.
- Underline on hover is painted by the renderer via `_setCellUnderline`
  (`xterm.js/src/browser/renderer/dom/DomRenderer.ts:582-640`), with the
  clipping notes for links that start above / end below the viewport.
- Public API: `xterm.js/typings/xterm.d.ts:1232` `registerLinkProvider`.

**Ours today** — §1.15 / §2.7 "Ours today": nothing.

**Gap**
§1.15 (OSC 8 storage) and §2.7 (hints with labels) cover the model and the
keyboard path. xterm.js contributes the mouse path's shape for a DOM
renderer: per-line lazy resolution with a cache, async providers so the
host can add its own (file paths that exist in the workspace — an Operator
concern that stays in `frontend/`), and underline-on-hover as a renderer
primitive.

**Proposal**
- `packages/terminal/ts/renderer-dom/src/linkifier.ts`: port `Linkifier`
  (hover → `provideLinks(row)` → cache → underline decoration (§3.6) →
  click). Providers: `OscLinkProvider` over the §1.15 link runs;
  `RegexLinkProvider` over the logical line (join `wrapped` rows) with
  xterm.js's `strictUrlRegex` as one default and Alacritty's `URL_REGEX`
  (§2.7) as the permissive alternative — pick one after testing both on a
  Claude Code transcript; hosts register more through `TerminalSurface`.
- §2.7's hint mode consumes the same providers for its label pass.

**Tests**
- `linkifier.test.ts` (port of `xterm.js/src/browser/Linkifier.test.ts`);
  `osc-link-provider.test.ts` (port of `OscLinkProvider.test.ts`, including
  the wrapped-line case).

**Priority:** P2 with §1.15.

### 3.8 Selection service: column mode, drag-scroll curve, trim handling, word separators

> **Status: Partial.** Plan E — copy joins a soft-wrapped line; Plan B — selection on stable rows with a per-row damage diff. Not done: the overlay container (the fill is still per row) and column (Alt) selection.

**Reference**
- `xterm.js/src/browser/services/SelectionService.ts:26-30`
  `DRAG_SCROLL_MAX_THRESHOLD = 50px`, `DRAG_SCROLL_MAX_SPEED = 15 lines`;
  `:420-430` `_getDragScrollAmount`: speed proportional to distance past
  the edge, clamped — the curve Warp's polynomial replaced in ours.
- `:56-62` `SelectionMode { NORMAL, WORD, LINE, COLUMN }`; column
  (rectangular) selection with Alt (`shouldColumnSelect`).
- `:144` subscribes to `buffer.lines.onTrim` and `:386-390` `_handleTrim`
  → `xterm.js/src/browser/selection/SelectionModel.ts:123-140` shifts both
  ends up by the trimmed amount and clears the selection when the end goes
  below zero (Alacritty's `rotate`, event-driven).
- `:203-260` `selectionText`: column mode extracts per-row slices; normal
  mode joins wrapped rows without a newline (`isWrapped`), the "copy the
  logical line" behaviour we list as a known gap.
- `wordSeparator` option (xterm.d.ts) defines word boundaries for
  double-click; `_getWordAt` expands across wrapped rows.
- `xterm.js/src/browser/renderer/dom/DomRenderer.ts:381-470`
  `handleSelectionChanged`: the selection is painted as up to three
  absolutely positioned `<div>`s in a separate `_selectionContainer`
  (first row, middle block, last row; column mode: one per row). The
  container sits *above* the rows (`_injectCss` `:285-300`: `z-index: 1`,
  `pointer-events: none`, opaque selection colour), so the rows whose
  selection state changed are re-rendered too (`:440-458` →
  `renderRows(start, end)`) with the row factory recolouring selected cells
  to the selection foreground/background (`DomRendererRowFactory.ts:160,201-205,380`).
  The overlay carries the fill; the rows carry the text colour.

**Ours today**
- `TERMINAL.md` §4.13: model-owned grid points, Warp's autoscroll curve and
  boundary set; selection painted as `background-image` on the *row*
  elements and on painted runs (`selection-fill.ts`, §4.11), re-applied every
  paint; no column mode; wrapped rows copy as separate lines (`TERMINAL.md`
  §5).

**Gap**
Two DOM-level ideas: (1) paint the selection fill in an overlay container
positioned from geometry, so a repaint of rows never has to re-apply row
`background-image`s (our `paintSelectionFill` clears and refills every
paint) — xterm.js still re-renders the affected rows to recolour text, so
the §4.11 run-tinting problem is solved there by recolouring, not by
z-order; for us the overlay would carry the fill and the §4.11
`runFill` tint would stay for painted runs; (2) copy joins wrapped rows.

**Proposal**
- `packages/terminal/ts/renderer-dom`: `selection-overlay.ts` — an
  absolutely positioned layer inside the block list painted from
  `selection-geometry.ts` (three rects in normal mode, one per row in
  column mode, xterm.js `DomRenderer.ts:381-470`), `pointer-events: none`,
  below the run text (`z-index` under `.terminal-run`) so Warp's blend
  order (§4.11: fill above cell background, below glyphs) is kept; painted
  runs keep the §4.11 `runFill` tint. The §4.11/§4.13 guards
  (`styles-parity.test.ts`, `terminal-selection.test.ts`, the Playwright
  selection gate) must keep passing. Keep Warp's colours and curve; take
  xterm.js's container structure.
- Column mode with Alt (§1.4).
- `selection-text.ts` joins rows flagged `wrapped` (§1.4; needs the
  per-row `wrapped` export).

**Tests**
- `terminal-selection.test.ts`: existing cases pass against the overlay;
  "a repaint of the selected rows leaves the overlay nodes untouched";
  "copying a soft-wrapped line yields one line".

**Priority:** P3 (P2 for the wrapped-copy part, already a known gap).

### 3.9 Accessibility: a parallel screen-reader tree and a live region for new output

> **Status: Not done.** No screen-reader mode, row roles or live region for output; the only `aria-live` is the find-bar counter.

**Reference**
- `xterm.js/src/browser/AccessibilityManager.ts:28-100`: when
  `screenReaderMode` is on, a hidden `.xterm-accessibility` container holds
  one `role="listitem"` element per viewport row (`_rowElements`, `:70-79`,
  with top/bottom boundary focus listeners to page the viewport), and an
  `aria-live="assertive"` region (`:83-86`) into which typed characters and
  new output are announced (`_charsToAnnounce`, `:54`; debounced
  `TimeBasedDebouncer` `:87`). The renderer's own rows are `aria-hidden`
  (`DomRenderer.ts:83,87`).

**Ours today**
- `aria-label`s on block chrome (`block-header.ts:105`, `block-actions.ts:58`,
  `find-bar.ts:263-269`); the transcript rows have no roles and new output
  is not announced (`grep -rn "aria-live" packages/terminal/ts` → no match).

**Gap**
Operator is unusable with a screen reader beyond the chrome. The block
model is a better fit for accessibility than xterm.js's flat rows: a block
can be a `role="group"` with the command as its accessible name and its
output as a `region`; a finished block can announce its exit status.

**Proposal**
- `packages/terminal/ts/renderer-dom/src/accessibility.ts`: host-toggled
  `screenReaderMode`; blocks get `role="group"`/`aria-label = command`;
  rows are `role="listitem"` text; an `aria-live="polite"` region announces
  new output rows of the running block (debounced, xterm.js `:87`) and
  `assertive` for exit status. The alt-screen surface mirrors xterm.js's
  flat row list.
- `TerminalSurface`: keyboard focus order includes block headers when the
  mode is on.

**Tests**
- `accessibility.test.ts`: roles present only in the mode; a new row is
  announced once; a finished block announces its status.

**Priority:** P3 (product decision on when; the package should not block it).

### 3.10 IME composition view over the cursor, with the send-on-end race handled

> **Status: Done.** Plan D — composition view at the cursor and one send a tick after `compositionend`. Manual Japanese-IME check still pending.

**Reference**
- `xterm.js/src/browser/input/CompositionHelper.ts:20-200`: a
  `_compositionView` element is shown at the cursor during composition
  (`compositionstart` `:73-85`), updated with the in-progress text wrapped in
  LRM marks (`compositionupdate` `:91-95`), and on `compositionend` the
  final text is sent after a `setTimeout(0)` so the textarea's value has
  settled (`_finalizeComposition`, `_isSendingComposition` `:43`); a
  keydown during composition is swallowed; the view is positioned from the
  cursor cell and styled like the cell (`updateCompositionElements`).

**Ours today**
- `packages/terminal/ts/core/src/composition-target.ts:51-61`: tracks
  `compositionstart`/`compositionend` to expose `isComposing()`; the line
  editor (`ts/editor`) owns the text in shell mode, and in alt-screen mode
  keys go straight to the pty (`TerminalSurface.tsx:225-235`). Whether a
  CJK/Japanese composition in alt-screen mode (Claude Code's prompt) shows
  the candidate text at the cursor, or sends partial keystrokes: not known
  — needs a manual test with a Japanese IME.

**Gap**
Untested area with a known-good reference. Claude Code's input box is an
alt-screen TUI, so our alt path is the one that matters.

**Proposal**
- `packages/terminal/ts/react`: in alt-screen mode, port `CompositionHelper`'s
  three handlers and the composition view positioned at
  `primaryCursorPlacement` (`cursor.ts`); `encodeKey` is bypassed while
  composing; final text sent once on `compositionend`.

**Tests**
- `TerminalSurface.paste.test.tsx`-style: synthetic composition events yield
  one `onSendRaw` with the final string and none in between.

**Priority:** P2 for users typing CJK into Claude Code; P3 otherwise.

### 3.11 Serialize addon: state to VT bytes, including modes, for reconnection

> **Status: Done.** Plan C — the replay re-emits the child's modes before the frame. Soft-wrapped history rows are still replayed unjoined (`TERMINAL.md` §5).

**Reference**
- `xterm.js/addons/addon-serialize/src/SerializeAddon.ts:34-60`
  `serialize(range)`, `:490-520` `_serializeBufferByScrollback` (rows are
  written oldest→newest, soft-wrapped rows are emitted without `\r\n`
  (`:197`) so the receiving terminal re-wraps them), `:278-330`
  `_diffStyle` emits only the SGR that changed between cells, `:558-592`
  `_serializeModes` restores DECCKM, 2004, insert, origin, 1004, 7, mouse
  tracking mode, cursor visibility; the alt buffer is serialised after the
  normal one; final cursor position is restored last.
- VS Code uses this to reconnect a terminal after a window reload (§5).

**Ours today**
- `vt_replay` in `vt-host` renders the mirror's screen (`TERMINAL.md` §1,
  §4.7): rows clipped to the grid, cursor column; modes replayed: not known
  (the plan reads `vt-host/src/lib.rs` `vt_replay`) — if 2004/1049/mouse
  modes are not replayed, a reattached renderer encodes keys and pastes
  wrongly until the app re-sets them.

**Gap**
Complements §1.9 (order: frame first). xterm.js's list of *what* to replay
is the checklist: wrapped rows without CR/LF, diffed SGR, modes, alt
buffer, cursor last.

**Proposal**
- `packages/terminal/crates/vt-host` `vt_replay`: emit `\r\n` only between
  rows not joined by `wrapped`; diff SGR between cells; prepend the mode
  set from `Parser` (`?1h`, `?2004h`, `?1000/1002/1003/1006h`, `?1004h`,
  `?25l`, `?1049h` when alt is active); replay the alt grid when active;
  cursor position last.
- Go: `vtwasm/replay_test.go` cases per item.

**Tests**
- `vt-core/tests/replay.rs`: a mirror with bracketed paste on replays
  `?2004h`; a soft-wrapped row replays as one line and re-wraps identically
  on a narrower client (§4.7 guard stays).

**Priority:** P2 (the mode part is a likely live bug on reattach).

### 3.12 Search addon: line cache with TTL, incremental find, decorations for all matches, result tracker

> **Status: Partial.** Plan 2 — re-search on every paint through `findUpdate`, current hit anchored by stable row. Plan 5 — hits paint through the highlight model (§1.8). Not done: `onResultsChanged`.

**Reference**
- `xterm.js/addons/addon-search/src/SearchLineCache.ts:29-60`:
  `translateBufferLineToStringWithWrap` results cached per logical line
  with a 15 s TTL, invalidated on cursor move / write.
- `xterm.js/addons/addon-search/src/SearchEngine.ts:250-300,380-400`:
  search over logical (wrapped) lines so a match spanning a soft wrap is
  found; regex, case, whole-word options.
- `xterm.js/addons/addon-search/src/SearchAddon.ts:65-76,123-160`:
  re-run on `onWriteParsed`/`onResize` with a debounce (`_highlightTimeout`,
  `incremental: true`, `noScroll`), matches painted as decorations
  (`DecorationManager.ts`, `createHighlightDecorations`) including overview
  ruler marks; `SearchResultTracker.ts` publishes `{ resultIndex, resultCount }`
  for the find bar's "3 of 12".

**Ours today**
- `find-bar.ts` + `find.rs` (§1.7/§2.6): the re-search cadence, wrapped-line
  handling and result counting: not known (plan reads `find-bar.ts`).

**Gap**
The DOM-side shape for §1.7/§2.6: a debounce keyed on "content changed",
matches as highlight decorations (§1.8/§3.6), a result index/count event.

**Proposal**
- Folded into §1.7/§2.6/§3.6: the find bar consumes `find_update()` on
  snapshot generation change (no timer), paints hits as `layer: 'bottom'`
  decorations, and exposes `onResultsChanged({ index, count })` for the
  host's UI.

**Priority:** with §1.7.

### 3.13 Write buffer: chunked parsing with a 12 ms budget and a 50 MB discard watermark

> **Status: Partial.** Plan A (12 ms budget) and Plan C (ack every 5,000 bytes, pause at 100,000); a hidden window drains 250 ms per tick (Plan 4). No 50 MB discard watermark.

**Reference**
- `xterm.js/src/common/input/WriteBuffer.ts:20-33`:
  `WRITE_TIMEOUT_MS = 12` (parse at most ~12 ms, then yield with a 0 ms
  timeout "to keep close to 30fps / 60fps"), `DISCARD_WATERMARK = 50 MB`
  of pending data before input is dropped with a warning,
  `WRITE_BUFFER_LENGTH_THRESHOLD = 50` processed chunks retained; `write(data, callback)`
  (`xterm.js/typings/xterm.d.ts:1381`) calls back when the chunk is parsed,
  which is how `addon-attach` implements flow control with the server
  (`xterm.js/addons/addon-attach/`).
- `xterm.js/src/common/TaskQueue.ts:1-60`: `IdleTaskQueue` /
  `PriorityTaskQueue` for background work (e.g. width cache warm-up) split
  into `requestIdleCallback` slices.

**Ours today** — §2.10 "Ours today": `core.feed(bytes)` per mux message,
synchronous (`frontend/src/renderer/components/BlockTerminal.tsx:141,152`).

**Gap / Proposal**
Same as §2.10 with xterm.js's numbers: time-based budget (12 ms) rather
than byte-based, a write callback for flow control (our mux could carry
an ack so the pty-host pauses the ring for a slow renderer — a
`backend/` change, listed for the plan, not required), and an idle task
queue for the §3.2 width-cache warm-up.

**Tests** — §2.10's plus "a chunk's callback fires after its bytes are parsed".

**Priority:** with §2.10.

### 3.14 Unicode: grapheme-aware width provider, pluggable Unicode version

> **Status: Done.** Plan D — grapheme-cluster widths, on by default since 2026-09-22 (`7395b910c`); the renderer reads exported cell spans. The pty-host mirror stays in scalar mode (`TERMINAL.md` §5).

**Reference**
- `xterm.js/src/common/services/UnicodeService.ts` registers
  `IUnicodeVersionProvider`s (`wcwidth`, `charProperties`); the default is
  Unicode 6 widths (`xterm.js/src/common/input/UnicodeV6.ts`);
  `xterm.js/addons/addon-unicode11/` and
  `xterm.js/addons/addon-unicode-graphemes/src/UnicodeGraphemeProvider.ts:11-70`
  provide Unicode 15 widths and grapheme-cluster joining (`charProperties`
  returns whether a code point extends the previous cell) so emoji
  sequences (ZWJ, skin tones, flags) occupy the cells the font will draw.

**Ours today**
- `packages/terminal/crates/vt-core/src/screen.rs:363-366`: width from the
  `unicode-width` crate per `char`; zero-width chars attach to the previous
  cell (`attach_zerowidth`, `:388-410`) up to a byte cap. ZWJ sequences
  (`👨‍👩‍👧`) therefore occupy 2 cells per emoji part in the grid (three wide
  cells) while the font draws one glyph: alignment drifts on that row.
  `packages/terminal/ts/renderer-dom/src/cell-width.ts` has its own table
  for the renderer's column math.

**Gap**
Claude Code prints emoji in status lines. A grapheme-cluster rule in the
model (Ghostty also has it: `src/terminal/page.zig:2030` `grapheme` row
flag, `src/unicode/`) keeps the grid and the drawn glyph in agreement.

**Proposal**
- `packages/terminal/crates/vt-core`: add the `unicode-segmentation` crate
  (or the `unicode-width` 0.2 grapheme-aware API if sufficient — check)
  and treat a ZWJ / variation-selector / emoji-modifier continuation as
  joining the previous cell (Ghostty `src/terminal/Terminal.zig` `print`'s
  grapheme path; xterm.js `charProperties`). One width table shared with
  the renderer by exporting cell widths in the snapshot rather than
  recomputing in `cell-width.ts`.

**Tests**
- `vt-core/tests/graphemes.rs`: ZWJ family occupies 2 cells; flag pairs 2;
  skin-tone modifier joins; text+VS16 becomes wide; the Alacritty
  `zerowidth` recording (§2.9) still passes.

**Priority:** P3 (P2 if a screenshot shows drift on an emoji row).

### 3.15 Small behaviours worth copying

> **Status: Partial.** Plan A — `onFeedParsed`. Not done: the Windows wrapped-line heuristic, OSC 9;4 progress, the Kitty keyboard encoder.

- **Windows wrapped-line heuristic** —
  `xterm.js/src/common/WindowsMode.ts:1-30`: winpty/ConPTY never mark
  soft wraps, so on each line feed the previous row is marked wrapped if
  its last cell is not a space. Our Windows pty-host has the same problem
  for copy-as-logical-line; apply when `platform === windows` in the host
  mirror config. P4.
- **Progress reporting OSC 9;4** —
  `xterm.js/addons/addon-progress/src/ProgressAddon.ts:41-95`
  (ConEmu/Windows Terminal progress state: none/normal/error/indeterminate/
  paused + percent). A block could show a progress bar when a tool emits
  it; add to the OSC set in §1.15. P4.
- **Kitty keyboard protocol encoder** —
  `xterm.js/src/common/input/KittyKeyboard.ts:13-320` (flags bitfield,
  event types, modifiers, CSI u encoding with the CapsLock edge case
  `:274`). The TypeScript reference if a TUI ever needs it (Claude Code
  does not, §1 not-adopted). P4.
- **Smooth scroll option** — `xterm.js/src/browser/Viewport.ts:47-52`
  `smoothScrollDuration` on the scrollable; ours uses the native DOM
  scroller, which already smooth-scrolls on macOS. Not adopted.
- **Theme injected as a scoped `<style>`** —
  `xterm.js/src/browser/renderer/dom/DomRenderer.ts:178-312` `_injectCss`
  writes all colour/selection/cursor rules once into a per-terminal style
  element keyed by `_terminalClass`, instead of inline styles per span;
  ours sets CSS variables on the root (`style-vars.ts`) — equivalent. Not adopted.
- **`onWriteParsed` / `write(data, cb)` events** —
  `xterm.js/typings/xterm.d.ts:1100,1381`: "the parser has consumed this
  chunk" is the hook the search addon, VS Code shell integration and
  attach flow control all use. Ours has `onPainted` (`dom-block-renderer.ts:286`)
  but no "parsed" hook on `TerminalCore`; add `onFeedParsed` when §2.10
  chunking lands. P3.

### Not adopted from xterm.js, and why

| Area | Files | Reason |
|---|---|---|
| WebGL renderer, glyph atlas, canvas fallback | `xterm.js/addons/addon-webgl/`, `xterm.js/src/browser/renderer/shared/` | We chose DOM for text selection/find/a11y fidelity; the DOM renderer is xterm.js's fallback, not its fast path, which is why §3.1-3.3 matter more for us than for them. |
| Its own scrollable/scrollbar implementation | `xterm.js/src/browser/scrollable/*` (VS Code's) | Native scroller + `viewport.ts` virtualiser; a custom scrollbar is a design decision for later. |
| Typed-array `BufferLine` cell storage | `xterm.js/src/common/buffer/BufferLine.ts:69-74` | Our cells live in Rust (`ScreenGrid`) and scrollback as UTF-8 `Content`; the snapshot buffers are already typed arrays. |
| Reflow algorithm | `xterm.js/src/common/buffer/BufferReflow.ts` | Ours is word-aware with hanging indents (§4.3-4.4); xterm.js cuts at the column. |
| Escape-sequence parser, `Params`, OSC/DCS/APC parsers | `xterm.js/src/common/parser/*` | `vte` (§2.2) covers it in Rust. |
| Image addon (sixel/iTerm) | `xterm.js/addons/addon-image/` | As §1 Kitty graphics: no TUI of ours emits images. |
| Ligatures addon | `xterm.js/addons/addon-ligatures/` | Font-shaping concern; Hack has no ligatures. |
| Clipboard addon (OSC 52) | `xterm.js/addons/addon-clipboard/` | With §2.2, OSC 52 arrives parsed; the browser clipboard API is the host's. |
| `InstantiationService` DI, `Lifecycle` disposables | `xterm.js/src/common/services/InstantiationService.ts`, `Lifecycle.ts` | Architecture style, not behaviour. |

### xterm.js section: suggested plan order

1. **3.3** cache char measurement (one afternoon, likely measurable).
2. **3.11** replay modes and wrapped rows in `vt_replay` (probable live bug on reattach).
3. **3.5** row events + markers — the chosen anchor mechanism; then
   **3.1** row pool + dirty range with §1.2.
4. **3.7** linkifier with §1.15; **3.6** decorations when a product feature needs them.
5. **3.2** width cache and **3.14** graphemes after a screenshot check.
6. **3.10** IME in alt-screen after a manual Japanese-IME test.
7. **3.8** selection overlay + wrapped copy; **3.9** accessibility; **3.13**/§2.10 write budget.

---

## 4. WezTerm

**Repository:** `/Users/omaraly/development/AI/wezterm` at commit `b09b56c`
(2026-09-17, "tmuxcc: fix TmuxPty* Write impl…"). **Language:** Rust.
**Relevant tree:** `wezterm/term/src/` (the terminal model, `wezterm-term`),
`wezterm/wezterm-surface/src/` (lines, cells, `Change` diffs),
`wezterm/mux/src/` (the multiplexer: `Pane` trait, local panes, domains),
`wezterm/codec/src/lib.rs` (the client↔server PDU protocol),
`wezterm/wezterm-mux-server-impl/src/` (server side of a remote attach),
`wezterm/wezterm-client/src/` (client side: cached lines, polling,
predictive echo), `wezterm/wezterm-gui/src/overlay/` (quick select, copy
mode), `wezterm/config/src/config.rs` (defaults cited below).

**Why WezTerm is worth mirroring:** it is the only surveyed terminal whose
architecture is ours — a long-running server owns the terminal model,
clients attach late over a socket (local, SSH or TLS), and the same client
code renders local and remote panes. Operator's daemon + pty-host + desktop
renderer + mobile client is exactly that shape, but we send raw pty bytes to
every client and each one runs its own VT parser (desktop: `vt-core` wasm;
mobile: the `xterm` Dart fork), while the pty-host's mirror is used only for
the attach replay. WezTerm's design — one model on the server, clients pull
*lines* by stable row index and sequence number — is the answer to three of
our open problems at once: attach latency (§1.9/§3.11), damage tracking
across the wire (§1.2/§3.1), and the mobile client's own terminal engine.
It also has a semantic-zone model over OSC 133 in the core and a quick-select
overlay that generalises §2.7.

Paths below are relative to the repository root; `wezterm/mux/src/…` means
`/Users/omaraly/development/AI/wezterm/mux/src/…`; `packages/terminal/…` and
`backend/…` are under `/Users/omaraly/development/AI/Operator/`.

### 4.1 Stable row indices: a row id that survives scrollback trimming

> **Status: Done.** Plan B — stable rows (`trimmed_total`, `first_stable_row`, `BlockGrid::origin`).

**Reference**
- `wezterm/term/src/screen.rs:16-30`: `Screen.lines` is one `VecDeque<Line>`
  for scrollback + visible rows; `stable_row_index_offset` (`:30`) is the
  number of rows ever trimmed from the top. `phys_to_stable_row_index`
  `:523-525` (`phys + offset`) and `stable_row_to_phys` `:528-535` (returns
  `None` once the row is gone); `stable_range` `:494`.
- The offset advances exactly where rows are dropped: `:734`
  (`scroll_up` trimming to `scrollback_size`) and `:769`.
- Everything above the model is addressed in stable rows: `SemanticZone`
  (`wezterm/term/src/lib.rs:117-123`), `StableCursorPosition`,
  `SearchResult` (`wezterm/mux/src/pane.rs:44-54`), `LogicalLine.first_row`
  (`:120-127`), the whole `Pane` line API (`:172-215`) and every PDU in the
  protocol (`wezterm/codec/src/lib.rs:915-935`).
- On alt-screen switch or a resize the `Pane::get_lines` contract
  (`wezterm/mux/src/pane.rs:194-205`) says how a stale range is clamped
  rather than failing.

**Ours today**
- The flat row space (`TERMINAL.md` §2: scrollback rows then screen rows)
  is renumbered whenever `trim_to` drops rows (`packages/terminal/crates/vt-core/src/lib.rs:116,175`)
  and `BlockGrid::trim_to_first_row` rebases block rows; selection anchors,
  find hits and the renderer's `knownBlockId` all refer to the current
  numbering. Blocks carry a stable `BlockId`; rows do not.

**Gap**
The simplest of the four anchor mechanisms surveyed (Ghostty pins §1.3,
Alacritty rotate §2.5, xterm.js markers §3.5, WezTerm stable index): a
single `u64` offset that never needs rewriting, valid across processes and
the wire. It is what makes §4.2's line-delta protocol and any
cross-client reference ("the row the mobile user tapped") possible. Rewrap
still renumbers rows within a logical line; WezTerm accepts that (rows are
re-fetched when the sequence number says they changed) and the `LogicalLine`
API (§4.5) is the stable unit across a width change.

**Proposal**
- `packages/terminal/crates/vt-core`: `trimmed_rows: u64` on `Parser`,
  incremented by `trim_to` and by the shell-mode frame eviction that trims;
  `stable_row(flat) = flat + trimmed_rows`; `flat_row(stable) -> Option<usize>`.
  `GridSnapshot` exports `firstStableRow`. `BlockGrid` stores stable rows
  (its `trim_to_first_row` rebasing disappears); `find.rs` results and
  §3.5's row events carry stable rows (`Trim` becomes implicit; `Remap` stays
  for rewrap).
- `packages/terminal/ts/renderer-dom`: `selection-model.ts`, find hits and
  decorations (§3.6) hold stable rows; `row-geometry.ts` maps through
  `firstStableRow`.
- This is the recommended resolution of §1.3 / §2.5 / §3.5: stable rows for
  trimming (free), §3.5 `Remap` events for rewrap only.

**Tests**
- `vt-core/tests/stable_rows.rs`: a stable row keeps its id across `trim_to`,
  eviction, scroll-off; `flat_row` returns `None` after trim; blocks keep
  their rows without rebasing; `exit_encoding.rs` fixture unchanged except
  the new field.

**Priority:** P2; prerequisite for §4.2.

### 4.2 Server-owned model, clients pull changed lines by (stable row, sequence number)

> **Status: Not pursued.** Design spec written in Plan F (`2026-09-22-server-owned-terminal-model-design.md`); implementation dropped 2026-09-22 — Claude Code lays out its own rows, so there are no logical lines a phone could rewrap.

**Reference**
- Change tracking in the model: every `Line` carries `last_change_seqno`
  (`wezterm/wezterm-surface/src/line/line.rs:283-300` `changed_since`,
  `update_last_change_seqno`); every mutation stamps it
  (`wezterm/term/src/screen.rs:342-345 dirty_line`, `:380,:399,:409`, and
  the rewrap at `:101-180`). `Pane::get_current_seqno` and
  `get_changed_since(range, seqno) -> RangeSet<StableRowIndex>`
  (`wezterm/mux/src/pane.rs:179-192`).
- Server side: `wezterm/wezterm-mux-server-impl/src/sessionhandler.rs:39-145`
  `PerPane::compute_changes`: per attached client it remembers the last
  seqno, cursor, title, cwd, dimensions; on each push it asks the pane for
  rows changed since that seqno over `0..physical_top + viewport_rows`,
  sends the *viewport's* changed rows eagerly as `bonus_lines`
  (compressed with `compress_for_scrollback`, `:101-114`), always includes
  the cursor row (`:117-122`), and lists the remaining changed rows as
  `dirty_lines` ranges for the client to fetch on demand
  (`GetPaneRenderChangesResponse`, `wezterm/codec/src/lib.rs:915-929`).
  Scrollback rows are fetched with `GetLines { ranges }`
  (`:932-935`); the push is scheduled from the pane's output thread
  (`schedule_pane_push` `:233`).
- Client side: `wezterm/wezterm-client/src/pane/renderable.rs:31-43`
  `LineEntry::{Line, Fetching, LineAndFetching, Stale}` in an
  `LruCache<StableRowIndex, LineEntry>` (`:68`); `apply_changes_to_surface`
  `:305-370` stores bonus lines and marks dirty ranges `Stale`;
  `schedule_fetch_lines` `:495` batches fetches; `get_lines` `:727` and
  `get_changed_since` `:805` implement the same `Pane` trait over the cache,
  so the GUI renders a remote pane with the code it uses for a local one;
  `make_all_stale` `:425` after a reconnect.
- Liveness: `poll` `:586-630` with `BASE_POLL_INTERVAL = 20 ms` doubling
  to `MAX_POLL_INTERVAL = 30 s` (`:27-28`) when nothing changes; a timeout
  on a reconnectable client does not kill the pane (`:604-608`).
- Wire: `wezterm/codec/src/lib.rs:44-100` leb128-framed PDUs with a
  compressed flag in the length's high bit (`COMPRESSED_MASK` `:59`); PDU
  ids `:452-505` (`GetLines`, `GetPaneRenderChanges`, `SendPaste`,
  `SendKeyDown`, `Resize`, `SearchScrollbackRequest`, `EraseScrollbackRequest`,
  `NotifyAlert`, `SetClientId`, …).

**Ours today**
- `backend/internal/httpd/terminal_mux.go` forwards the pty-host's raw bytes
  as `{ch: 'terminal', type: 'data', data: base64}` to each attached client
  (mobile encoder at `packages/mobile/lib/core/mux/mux_client.dart:299`);
  the desktop feeds them to `vt-core`
  (`frontend/src/renderer/components/BlockTerminal.tsx:141`), the mobile
  client to its `xterm` Dart fork
  (`packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:66,117`).
  The pty-host mirror (`backend/internal/adapters/runtime/ptyhost/vtwasm`)
  already runs `vt-core` server-side, but only to produce `vt_replay` on
  attach (`TERMINAL.md` §1).
- Every client parses every byte; late attachers parse the whole replay;
  a slow link delivers bytes, not frames; the mobile app carries a second
  terminal engine that cannot know about blocks (`docs/mobile-parity-ledger.md`).

**Gap**
This is the largest architectural idea in the survey. With the mirror
promoted from "replay source" to "the model", clients would receive
`{stableRow → row snapshot}` deltas instead of bytes: attach becomes
"send the viewport rows + cursor + modes now, the rest on scroll"
(§1.9's `READY` for free), damage tracking is the sequence number
(§1.2/§3.1 without exporting dirty bits from a client-side core), and the
mobile client renders rows from JSON with no VT engine, gaining blocks,
rewrap and styles identical to desktop. Cost: the renderer core's `vt-core`
becomes a *client* of row snapshots rather than a parser (the `TerminalCore`
API stays; its `feed` is replaced by `applyDelta`), the pty-host's mirror
must run with reflow on and the client's width (one mirror per distinct
width, or rewrap on the client from logical lines — §4.5), and a new
protocol replaces `type: 'data'`.

**Proposal** (a milestone of its own; the plan should be a separate design spec)
- `backend/internal/adapters/runtime/ptyhost`: the mirror becomes the model
  of record: `vt-core` with `seqno` per row (a `u64` stamped on every row
  mutation; scrollback rows are immutable after eviction except rewrap, so
  they carry the seqno of their eviction/rewrap), `changed_since(seqno) -> ranges`,
  and `rows(stable range) -> ExportBuffers slice`. Width: the mirror tracks
  the *largest* attached grid and clients rewrap logical lines locally
  (§4.5); or one mirror per grid — decide in the design spec with a
  measurement of rewrap cost on mobile.
- Protocol (`backend/internal/httpd/terminal_mux.go`, `packages/mobile/lib/core/mux`,
  `frontend/src/renderer/hooks/useTerminalSession.ts`): `render_changes`
  push `{seqno, cursor, dims, modes, blocks, bonusRows: [{stableRow, content, styles, wrapped, indent}], dirtyRanges}`
  and a `get_rows {ranges}` request; keep the `type: 'data'` channel for
  the alt screen only until the alt grid is also served as rows.
- `packages/terminal/ts/core`: `TerminalCore.applyDelta()` and a row cache
  with `LineEntry` states (`renderable.rs:31-43`); the DOM renderer is
  unchanged above `snapshot()`.
- `packages/mobile`: a `rows` renderer replacing the `xterm` fork for
  daemon sessions (the fork stays for nothing — `packages/mobile/packages/xterm`
  is removed at the end).

**Tests**
- `vt-core/tests/seqno.rs`: printing stamps the row; `changed_since` after a
  scroll returns the moved rows; eviction stamps the evicted row; rewrap
  stamps every rewritten row.
- Go: `ptyhost` — two clients at different seqnos get disjoint deltas; a
  reattaching client with a stale seqno receives the viewport as bonus rows.
- Mobile: widget test rendering a delta with blocks.

**Priority:** P2 as a design-spec milestone; the payoff is highest for
mobile and Tailscale users.

### 4.3 Predictive local echo when the round-trip is slow

> **Status: Done.** Plan F — desktop-only overlay above a 30 ms host RTT threshold, off by default (Settings). The phone has none.

**Reference**
- `wezterm/wezterm-client/src/pane/renderable.rs:136-142` `should_predict`:
  only when the measured input RTT (`last_input_rtt`) exceeds
  `local_echo_threshold_ms` (config; `None` disables). `predict_from_key_event`
  `:212-246` and `predict_from_paste` `:270-300` write the typed text into
  the cached cursor line immediately (marking it dirty), `apply_prediction`
  `:145-206` lists the open questions (password prompts, vim normal mode).
  Each keystroke carries an `InputSerial`; the server echoes it in
  `GetPaneRenderChangesResponse.input_serial` (`codec/src/lib.rs:927`), and
  `apply_changes_to_surface` `:332-360` discards predictions once the
  server's state has caught up with that serial.

**Ours today**
- Shell mode: the line editor (`packages/terminal/ts/editor`) *is* local
  echo by construction — typing happens in the browser and the line is sent
  on Enter. Alt-screen (Claude Code's prompt): every keystroke is a
  round-trip to the daemon and back before it appears; over Tailscale from
  a phone that is the 100–300 ms lag users notice (`memory:
  verify-operator-desktop…` notes the 12 s timeouts for sleeping hosts; the
  typical RTT: not known — measure).

**Gap**
For the alt-screen path there is no local echo. WezTerm's approach — echo
only when RTT is high, tag inputs with a serial, drop the prediction when the
server confirms — is the safe version of it.

**Proposal**
- After §4.2: `packages/terminal/ts/core` row cache applies a prediction to
  the cursor row for printable keys when RTT (measured from `input` send to
  the delta carrying its serial) exceeds a host-configured threshold; the
  mux `input` message gains `serial`; the pty-host echoes the last applied
  serial in each delta. Passwords: skip prediction while the line has no
  echo (the mirror knows: the cursor did not advance after the last input).
- Without §4.2 this is not possible (the client has no row it owns).

**Tests**
- `terminal-core.test.ts`: a prediction is shown before the delta and
  replaced by it; no prediction under the threshold; none when the previous
  keystroke produced no cursor advance.

**Priority:** P3, after §4.2.

### 4.4 Output coalescing at the parser: hold a synchronized frame, else wait 3 ms for more bytes

> **Status: Partial.** Plan A — the pump holds across a DEC 2026 block. The 3 ms poll was not added: the pump already coalesces at 1/60 s.

**Reference**
- `wezterm/mux/src/lib.rs:142-232` `parse_buffered_data`: the pty reader
  thread parses into a `Vec<Action>`; on `?2026h` it sets `hold` and flushes
  prior actions, on `?2026l` (or soft reset) it releases and flushes
  (`:161-185`); otherwise, if the read was smaller than the buffer, it
  `poll()`s the pty for `mux_output_parser_coalesce_delay_ms` (default 3 ms,
  `wezterm/config/src/config.rs:1675-1677`) before sending the actions to
  the model, "to increase the chances that we coalesce a full frame from an
  unoptimized TUI program" (`:200-227`); buffer size 128 KiB (`:1679-1681`).
  `BUFSIZE = 1 MiB` socket buffers (`:118,270-273`).

**Ours today**
- The pty-host pumps bytes into the ring and to clients as they arrive
  (`backend/internal/adapters/runtime/ptyhost/host.go`; chunking policy:
  not known — the plan reads the pump). No coalescing; §2.1 buffers 2026 in
  the parser.

**Gap**
The 3 ms poll is a cheap heuristic for TUIs that do not use 2026 (older
Ink, `top`, progress bars) — it turns many tiny writes into one frame per
delta, which matters most for §4.2 (fewer pushes) and for the current
byte stream (fewer mux messages). It is an action-level hold, so a frame is
parsed but not applied until released — the same effect as §2.1 with a
different cut point.

**Proposal**
- `backend/internal/adapters/runtime/ptyhost`: in the pump, after a read
  shorter than the buffer, wait up to 3 ms for more before broadcasting
  (and, after §4.2, before stamping the seqno); a read inside a 2026 block
  never broadcasts until the block ends (the mirror knows the mode from
  §2.1's flag). Bound the hold by §2.1's 150 ms.
- Go tests: two writes 1 ms apart arrive as one mux message; a write
  followed by silence flushes at ≤3 ms.

**Priority:** P3 (P2 with §4.2).

### 4.5 Logical lines as the unit for search, hyperlinks, copy and mouse mapping

> **Status: Done.** Plan E — per-row `wrapped` export, `logicalLines`, copy joins a soft-wrapped line. History prepended on reopen stays single rows.

**Reference**
- `wezterm/mux/src/pane.rs:120-170` `LogicalLine { physical_lines, logical, first_row }`
  with `xy_to_logical_x` and `logical_x_to_physical_coord`; `Pane::get_logical_lines`
  `:215` and `for_each_logical_line_in_stable_range_mut` `:209-213`; the
  local pane joins rows whose `last_cell_was_wrapped` bit is set
  (`wezterm/wezterm-surface/src/line/line.rs:214` `wrap`, `:1119` `append_line`,
  used by `screen.rs:101-180 rewrap_lines`).
- Consumers: hyperlink rules run on the logical line so a URL split by a
  soft wrap is one link (`Pane::apply_hyperlinks` `:217-225`,
  `line.rs:531 scan_and_create_hyperlinks` cached per line with
  `LineBits::SCANNED_IMPLICIT_HYPERLINKS` and invalidated on change
  `:488-520`); search (`SearchResult` spans stable rows);
  copy/selection (`wezterm-gui` uses `logical_x` to extend a drag across
  wrapped rows); `wezterm cli get-text` (`wezterm/wezterm/src/cli/get_text.rs:8-40`)
  exports the pane text with wraps joined.

**Ours today**
- `RowIndex` knows `wrapped` per scrollback row and the screen has its
  `wrapped` flags (`TERMINAL.md` §4.2) but nothing above `vt-core` joins
  them: copying yields several lines (§5), links (§1.15/§3.7) and find
  (§1.7) would search visual rows.

**Gap / Proposal**
Same conclusion as §3.7/§3.8/§3.12 from a fourth codebase; the concrete
API to add is WezTerm's: `logical_lines(stable range) -> [{ firstRow, rows: [...], text, xyToLogicalX, logicalXToXY }]`
on `TerminalCore` (computed in `vt-core` from `RowIndex` + screen flags;
the snapshot already has both once `wrapped` is exported), used by
`selection-text.ts`, the linkifier and the find session. Hyperlink scan
results cached per logical line and invalidated by the row's seqno (§4.2).

**Tests**
- `vt-core/tests/logical_lines.rs`: a three-row soft-wrapped line is one
  logical line; a hard `\n` ends it; `xy ↔ logical x` round-trips including
  hanging indents (§4.4 of `TERMINAL.md` — the indent is not text).

**Priority:** P2 (unblocks the wrapped-copy known gap and correct links).

### 4.6 Semantic zones over OSC 133 as a core query

> **Status: Not done.** No per-row semantic tag and no `semanticZones` query.

**Reference**
- `wezterm/wezterm-cell/src/lib.rs:184-188` `SemanticType { Output, Input, Prompt }`
  is a *cell* attribute; `wezterm/wezterm-surface/src/line/line.rs:478-486`
  `semantic_zone_ranges` gives per-line runs; `wezterm/term/src/terminalstate/mod.rs:2831-2865`
  `get_semantic_zones` merges consecutive runs of the same type across
  lines into `SemanticZone { start_x, start_y, end_x, end_y, semantic_type }`
  (`wezterm/term/src/lib.rs:117-123`); exposed on every pane
  (`wezterm/mux/src/pane.rs:312`, `wezterm/mux/src/localpane.rs:641`).
- Used by key assignments `SelectTextAtMouseCursor SemanticZone`,
  `ScrollToPrompt`, and by `wezterm cli get-text --start-line/--end-line`.

**Ours today**
- `BlockGrid` gives us more than zones (blocks with ids, state, exit code,
  bookmarks), but the *within-block* partition — which rows are the prompt,
  the input line, the output — is not modelled (§1.6 proposes a per-row
  `semantic` tag).

**Gap / Proposal**
Confirms §1.6's per-row tag with a cell-level alternative. Row-level is
enough for us (Claude Code has no prompt/input rows inside a block; shells
do). Take WezTerm's *query shape*: `semanticZones(blockId) -> [{type, rows}]`
from `TerminalCore`, so "select this block's output" (§1.4) and "copy the
input only" are one call.

**Tests** — with §1.6.

**Priority:** with §1.6.

### 4.7 Quick select: label every match of a pattern set, one keystroke to copy or paste

> **Status: Done.** Plan E — hint rules are WezTerm's minus IPFS, with Kitty's `path:line` first; WezTerm's label algorithm. No host seam to replace the rule set.

**Reference**
- `wezterm/wezterm-gui/src/overlay/quickselect.rs:26-56` `PATTERNS`: markdown
  URL, URL (with `git@`, `ssh://`, `file://`), `--- a/` / `+++ b/` diff
  paths, docker sha256, **file path** (`(?:[.\w\-@~]+)?(?:/+[.\w\-@]+)+`),
  hex colour, UUID, IPFS, git sha (7–40), IPv4, IPv6, hex address, numbers
  ≥4 digits. `compute_labels_for_alphabet` `:57-100` (tmux-thumbs'
  algorithm: prefix-free labels, shortest first).
- Matches are found on logical lines in the viewport; a typed label copies
  the match (default) or, with Alt, pastes it into the pane; patterns are
  user-extensible (`quick_select_patterns` config).

**Ours today** — §2.7 "Ours today" (nothing).

**Gap / Proposal**
§2.7 describes the mechanism (Alacritty hints); WezTerm contributes the
pattern set an agent terminal actually needs — file paths, diff headers,
shas, UUIDs — and the label algorithm. Add to §2.7: ship WezTerm's
`PATTERNS` (minus IPFS) as the package default rule set, and its label
generator (port with its tests).

**Priority:** with §2.7.

### 4.8 Pane metadata every client can ask for: unseen output, progress, cwd, foreground process

> **Status: Not done.** No `hasUnseenOutput` and no OSC 9;4 progress. Alt-screen and mouse-tracking state were already on the snapshot.

**Reference**
- `wezterm/mux/src/pane.rs`: `has_unseen_output` (`:283`; local impl
  `wezterm/mux/src/localpane.rs:492-494`), `is_alt_screen_active` (`:321`), `get_progress` (`:465`,
  OSC 9;4 state), `get_current_working_dir` (OSC 7, with `CachePolicy`),
  `get_foreground_process_name` / `get_foreground_process_info`
  (`wezterm/procinfo/` reads the pty's foreground pgrp), `get_title`,
  `is_alt_screen_active`, `is_mouse_grabbed`, `get_keyboard_encoding`.
  `advise_focus`/`focus_changed` clear `unseen_output`.
- `compute_changes` (§4.2) pushes title/cwd changes with the same delta.

**Ours today**
- Operator derives "needs attention" from block state and OSC 7000
  `input-ready`; cwd/branch come from OSC 7000 (`packages/terminal/shell/zsh.sh:102`);
  the daemon knows the child process. `has_unseen_output` as "output
  arrived since the pane was last visible" exists only as sidebar unread
  logic in `frontend/` (exact source: not known).

**Gap / Proposal**
Small: expose `hasUnseenOutput` (cleared on `focusToken`, `TERMINAL.md`
§4.14) and `isAltScreenActive`/`mouseGrabbed` on `TerminalCore`, and the
OSC 9;4 progress state (§3.15) so the host does not scrape rows for a
percentage. Foreground process name is already the daemon's.

**Priority:** P4.

### 4.9 Exit behaviour: hold the pane after the process exits

> **Status: Not pursued.** The entry counts it as equal: a finished session keeps its blocks and a relaunch adds a process-boundary block (`TERMINAL.md` §4.15).

**Reference**
- `wezterm/config/src/config.rs:2037-2045` `ExitBehavior { Close, CloseOnCleanExit, Hold }`
  and `ExitBehaviorMessaging { Verbose, Brief, Terse }` `:2048-2052`: with
  `Hold`, the pane stays with the last frame and a status line
  ("process exited with code 1"); `wezterm/mux/src/localpane.rs` prints it
  into the terminal so it is part of scrollback.

**Ours today**
- A finished session keeps its block list; "Relaunch in a cleared session"
  respawns with a process-boundary mark (`TERMINAL.md` §4.15) so the old
  frame becomes a finished block. Equivalent to `Hold` with a block boundary
  — already better structured. Not adopted; noted as equal.

### 4.10 Tests as terminal-state assertions

> **Status: Partial.** Plan A — a shared `tests/common` (integrity and cell-span check) and the `tests/ref` harness. No `TestTerm` helpers.

**Reference**
- `wezterm/term/src/test/mod.rs` (27 tests), `csi.rs` (13), `selection.rs`,
  `c0.rs`, `c1.rs`: a `TestTerm` wrapper with `assert_cursor_pos`,
  `assert_visible_contents(&[...])`, `assert_lines_as_text`, `print` /
  `cup` / `erase_in_display` helpers, and `assert_eq!` on the `Line`
  vector with a diff printer; selection tests drive `SelectionRange` on
  the same terminal (`selection.rs`, 5 tests).

**Ours today**
- `vt-core` tests already assert `row_text(i)` per row (`TERMINAL.md` §7);
  the helper layer (`TestTerm`-style builders) is per test file.

**Proposal**
- A shared `crates/vt-core/tests/common/mod.rs` with `TestTerm` helpers
  (`print`, `csi`, `assert_screen(&[...])`, `assert_scrollback(&[...])`,
  `assert_blocks(&[...])`) so the §2.9 recordings and the §1.14 property
  test share one assertion vocabulary. Hygiene only.

**Priority:** P3, with §1.14/§2.9.

### Not adopted from WezTerm, and why

| Area | Files | Reason |
|---|---|---|
| GPU GUI, font shaping, window layer | `wezterm/wezterm-gui/`, `wezterm/wezterm-font/`, `wezterm/window/` | DOM renderer. |
| Lua configuration and key assignments | `wezterm/config/`, `wezterm/luahelper/`, `wezterm/lua-api-crates/` | Host concern. |
| tmux control mode (`tmuxcc`) | `wezterm/mux/src/tmux*.rs` | tmux removed from our path (`TERMINAL.md` §1). |
| SSH domains, `wezterm-ssh`, TLS PKI, mux discovery | `wezterm/mux/src/ssh.rs`, `wezterm/wezterm-ssh/`, `wezterm/wezterm-mux-server-impl/src/pki.rs`, `wezterm/wezterm-client/src/discovery.rs` | Operator's daemon auth, Tailscale and the mobile pairing flow (`packages/mobile` `ServerConfig`) already cover transport and trust; only the *protocol* (§4.2) transfers. |
| Its own escape parser and `termwiz` widgets/line editor | `wezterm/wezterm-escape-parser/`, `wezterm/termwiz/src/{widgets,lineedit}` | `vte` (§2.2); our line editor is `ts/editor`. |
| `termwiz` `Surface`/`Change` diffing | `wezterm/wezterm-surface/src/change.rs`, `lib.rs` `diff_screens` | A TUI-building abstraction; §4.2's row deltas are the terminal-model equivalent. |
| Cluster-compressed line storage | `wezterm/wezterm-surface/src/line/clusterline.rs`, `line.rs:1069-1075` | Our `Content` + `AttributeMap` is already the compressed form; `compress_for_scrollback` is the same idea applied at eviction time. |
| Kitty/iTerm/Sixel images | `wezterm/term/src/terminalstate/{kitty,iterm,sixel,image}.rs` | As §1/§3. |
| Bidi | `wezterm/bidi/` | Not needed for our TUIs; note only. |
| Copy mode overlay (vi-style) | `wezterm/wezterm-gui/src/overlay/copy.rs` | §2.13's decision. |
| Frecency-ranked launcher, workspaces, tabs/splits in the mux | `wezterm/frecency/`, `wezterm/mux/src/{tab,window}.rs` | Operator's board and panes are product-level; the mux `Tab` split tree is not our layout model. |

### WezTerm section: suggested plan order

1. **4.1** stable row indices — small, unblocks everything else here and
   settles the §1.3/§2.5/§3.5 anchor question.
2. **4.5** logical lines API — closes the wrapped-copy gap; feeds links and find.
3. **4.2** design spec for the server-owned model and row-delta protocol
   (its own milestone; decide the width strategy with a measurement).
4. **4.4** pump coalescing (Go, small) — with or before 4.2.
5. **4.7** pattern set into §2.7; **4.6** zone query into §1.6.
6. **4.3** predictive echo after 4.2; **4.8**, **4.10** as hygiene.

---

## 5. Kitty

**Repository:** `/Users/omaraly/development/AI/kitty` at commit `719c61a`
(2026-09-19). **Language:** C core (`kitty/*.c`), Python shell
(`kitty/*.py`), Go kittens (`kittens/*/`). **Relevant tree:**
`kitty/screen.c` (the model, 7.2k lines), `kitty/vt-parser.c`,
`kitty/child-monitor.c` (I/O loop), `kitty/history.c` (scrollback),
`kitty/window.py` (command lifecycle), `kitty/rc/get_text.py`,
`shell-integration/{zsh,bash,fish,ssh}/`, `docs/shell-integration.rst`
(the OSC 133 option spec Ghostty implements), `kittens/hints/`,
`kitty/marks.py`, `kitty/options/definition.py` (defaults cited below),
`kitty_tests/`.

**Why Kitty is worth mirroring:** it is the origin of most of the protocols
the other terminals implement — the OSC 133 option set (`redraw=`,
`k=s`, `click_events=`, `cmdline=`), the keyboard protocol, desktop
notifications (OSC 99), text sizing, pointer shapes, and the first
"pending mode" that became DEC 2026. Where Ghostty §1 lists the consumer
side, Kitty's docs are the normative text, and its command-output model
(`PromptKind` per line, `cmd_output` extents, `notify_on_cmd_finish`) is
the closest thing to our blocks in a non-block terminal. Its hints kitten
adds the one hint type an agent terminal needs most: `path:line` → open in
editor.

Paths are relative to the repository root: `kitty/kitty/screen.c` means
`/Users/omaraly/development/AI/kitty/kitty/screen.c`.

### 5.1 Synchronized output as "render a snapshot while the model keeps moving"

> **Status: Done.** Covered by §2.1 (`vt-core` buffers DEC 2026; the pump holds across a block).

**Reference**
- `kitty/kitty/screen.c:3774-3835` `screen_pause_rendering(self, pause, for_in_ms)`:
  on pause it copies the *visible lines*, cursor, colour profile, selection
  and image state into `paused_rendering.*` (`:3796-3830`), sets
  `expires_at = now + 2000 ms` by default (`:3794-3795`), and the renderer
  draws from the copy while the model continues to consume bytes
  (`kitty/kitty/shaders.c:832,896-898,993,1010-1042`; the cursor at
  `child-monitor.c:774`). `screen_check_pause_rendering` `:3752-3754`
  expires it; the event loop bounds its wait by the expiry
  (`kitty/kitty/child-monitor.c:538-540`). Mode 2026 maps to it via
  `set_mode_from_const` (`screen.c:2037`); the older DCS `=1s`/`=2s` pending
  mode does the same (`kitty/kitty/vt-parser.c:741-756`) with error reports
  for unbalanced start/stop. `DECRQM` reports it (`:3289`).
- Resize, reset and alt-screen switch unpause (`screen.c:210,631,2881`).

**Ours today** — §1.1 / §2.1 / §3.4.

**Gap / Proposal**
Fourth variant. Its property: on timeout the *latest* state is shown (the
model never stopped), while Alacritty's parser buffer shows the *pre-frame*
state until the timeout flushes. For a DOM renderer the last painted DOM
already is the snapshot, so §2.1 (buffer in the parser, 150 ms) + "don't
paint while set" gives Kitty's behaviour for free except the timeout
value. Take Kitty's 2 s only as the upper bound for the renderer-side
watchdog if §1.1's is kept. No new proposal.

**Priority:** covered.

### 5.2 The shell-integration protocol, as specified

> **Status: Not done.** `zsh.sh` still emits bare `133;A/B/C/D`; no `k=s`, no `cmdline`, no cursor shape by keymap. A non-goal of the agent-TUI spec.

**Reference**
- `kitty/docs/shell-integration.rst:423-500` "Notes for shell developers":
  `OSC 133;A` before PS1, `OSC 133;A;k=s` before PS2, `OSC 133;C` before
  running, `OSC 133;D;<exit>` after; options on `A`: `redraw=0`,
  `special_key=1`, `k=s`, `click_events=1|2` (absolute vs prompt-relative
  y); on `C`: `cmdline=<%q-encoded>` or `cmdline_url=<%-escaped>`.
- Model side: `kitty/kitty/screen.c:3556-3600` `parse_prompt_mark` /
  `shell_prompt_marking` sets `line_attrs[y].prompt_kind` to
  `PROMPT_START | SECONDARY_PROMPT | OUTPUT_START`
  (`kitty/kitty/data-types.h:248`) and fires `cmd_output_marking` to Python
  with the cmdline (`:3590-3597`).
- Zsh script `kitty/shell-integration/zsh/kitty-integration`: `_ksi_precmd`
  `:134-206` (emits `D` for the previous command with `$?`, then `A`, keeps
  `A;k=s` in `PS2` `:172`), `_ksi_preexec` `:210-227` (`C;cmdline=%q`),
  OSC 7 as `kitty-shell-cwd://HOST/path` `:240`, title `:273-280`, cursor
  shape follows the zle keymap (`:289-299`: `\e[1 q` in vicmd, `\e[5 q`
  otherwise, reset on preexec), `clone-in-kitty` `:464-500` (shell, pid, cwd,
  env → a new window with the same state). Feature switches by env
  `KITTY_SHELL_INTEGRATION="enabled no-cursor no-title no-prompt-mark no-complete no-cwd no-sudo"`
  (`:84-130`), injected without touching rc files (`ZDOTDIR` handoff,
  `docs/shell-integration.rst:150-224` "How it works").
- Over SSH: `kitty/shell-integration/ssh/bootstrap.sh` + `kittens/ssh` copy
  the integration to the remote host (`docs/shell-integration.rst:224-252`).

**Ours today**
- `packages/terminal/shell/zsh.sh` emits `133;A/B/C/D` plus OSC 7000
  (`id=`, `cmd=`, `exit=`, `cwd=`, `branch=`, `input-ready`/`input-released`)
  — richer on the 7000 side, but no `k=s`, `redraw=`, `cmdline=` (§1.6),
  no cursor-shape-by-keymap, no title; injection mechanism per
  `packages/terminal/shell/README.md` (not re-read here).

**Gap / Proposal**
§1.6 already lists the options; this section is the normative citation for
the plan. Two additions from the zsh script: (1) cursor shape by zle
keymap (`:289-299`) — a one-line addition to `shell/zsh.sh` that makes our
line editor's vi-mode visible if a user enables it (the DECSCUSR
sequences already reach `vt-core`? not known — the plan checks
`screen/dispatch.rs` for `CSI … q`); (2) `cmdline=%q` on `C` as the
interoperable form of our `7000 cmd=` so other tools reading the pty (tmux
users, asciinema) see the command too. Keep 7000.

**Tests** — with §1.6; `shell/zsh.test.mjs` cases for the two additions.

**Priority:** with §1.6 (P3).

### 5.3 Command-output extents and finish notifications on top of prompt marks

> **Status: Partial.** Plan E — `onBlockFinished` with duration and visibility. Plan 4 — a hidden window still drains and reports (`cb7b34b3b`); unloaded shell panes notify from the daemon (`13ad4994d`). macOS toasts `59624c9a9`. Not done: `lastVisitedBlockId` and `readBlockOutput` defaulting to it.

**Reference**
- `kitty/kitty/screen.c:5372-5395` `screen_select_cmd_output(y)`: from a
  clicked row, `find_cmd_output` walks up to the `OUTPUT_START` line and
  down to the next `PROMPT_START`, then selects that range (keyboard action
  `select_cmd_output`); `:2759-2763` and `:3626` implement `scroll_to_prompt
  ±n` over `prompt_kind`.
- `kitty/kitty/rc/get_text.py:16-40,99-110`: `get-text --extent` accepts
  `screen | all | selection | first_cmd_output_on_screen | last_cmd_output | last_visited_cmd_output | last_non_empty_output | alternate | alternate_scrollback`
  — "last visited" is the first output below the last `scroll_to_prompt`
  position, i.e. navigation state feeds copy.
- `kitty/kitty/window.py:1939-1960` `handle_cmd_end`: measures the command's
  duration from `C` to `D`, calls `on_cmd_startstop` watchers with
  `{cmdline, exit_status, time}`, and if the duration exceeds the configured
  threshold sends a desktop notification per `notify_on_cmd_finish`
  (`kitty/kitty/options/definition.py:3194-3254`: `never | unfocused | invisible | always`,
  optional seconds, optional `bell` / command action, cleared on focus
  `window.py:1569`).

**Ours today**
- Blocks give ids, state, exit code, `readBlockOutput`, bookmarks, block
  navigation and a pinned header; "output of the block under the pointer"
  is a block action, and the daemon emits session events for agents.
  Missing: per-block start/end timestamps (marks carry none; not known
  whether `BlockGrid` records a time), a "long shell command finished while
  the pane was not visible" notification, and "last visited block" as
  state that copy/select can use.

**Gap / Proposal**
- `packages/terminal/ts/renderer-dom`: stamp `startedAt` on `C` and
  `finishedAt` on `D` in the block model view (renderer-side clock; the
  package has none in `vt-core`), expose `onBlockFinished({ id, exitCode, durationMs, visible })`
  from `TerminalSurface`; the host (Operator) decides the threshold and
  notification, mirroring `notify_on_cmd_finish unfocused 10.0`. Keep
  `lastVisitedBlockId` in `block-nav.ts` and let `readBlockOutput` default
  to it (Kitty's `last_visited_cmd_output`).
- With §4.6's zone query, "select output" and "copy input only" become
  extents like Kitty's.

**Tests**
- `block-nav.test.ts`: last visited tracks jumps; `block-actions.test.ts`:
  a `D` after `C` fires `onBlockFinished` with the duration and the pane's
  visibility.

**Priority:** P3 (the host feature is small once the event exists).

### 5.4 Resize keeps the current prompt from rewrapping

> **Status: Not done.** Shell resize still evicts the frame; Kitty's exempt-the-prompt option was not taken up. A non-goal of the agent-TUI spec.

**Reference**
- `kitty/kitty/screen.c:555-600` `prevent_current_prompt_from_rewrapping`:
  before a resize, if the shell redraws prompts (`redraws_prompts_at_all`,
  `:558`, cleared by `redraw=0` `:3565`), the rows of the current prompt
  (from the last `PROMPT_START`/`SECONDARY_PROMPT` above the cursor down to
  the cursor, stopping at `OUTPUT_START`) are copied out to `prompt_copy`;
  `screen_resize` `:630-760` copies them out (`:660-664`), rewraps
  everything else, then puts those rows back *unwrapped* at the bottom so
  the shell's SIGWINCH redraw overwrites exactly them (`:739-750`),
  tracking the cursor and both saved cursors through the operation
  (`CursorTrack`, `:646-660`).

**Ours today** — §1.5 "Ours today" (evict frame once, Warp).

**Gap / Proposal**
Third answer to the §1.5 decision: Ghostty clears the prompt rows after
reflow; Kitty exempts them from reflow and lets the shell overwrite; Warp
(ours) pushes the frame to history. Kitty's is the least destructive when
the shell does *not* redraw (nothing is lost, the prompt is just
unwrapped). Add to the §1.5 decision as option (c), with the same tests.

**Priority:** with §1.5 (P4 decision).

### 5.5 Hints: `path:line` as a first-class type with an editor action

> **Status: Done.** Plan E — `path:line` hints and links open through the host; since `fdc202778` the editor chosen in Settings (VS Code, Cursor, Zed) opens at the line and column. The default "system" opener opens the file without the line.

**Reference**
- `kitty/kittens/hints/main.py:108-146` `--type url|regex|path|line|hash|word|linenum|hyperlink|ip`;
  `linenum` uses a regex with named groups `path` and `line`
  (`kitty/kittens/hints/marks.go:35-41`: `path_regex` = anything with a `/`
  or a file extension, `default_linenum_regex` = `(?P<path>…):(?P<line>\d+)`),
  `linenum_group_processor` `:158-166` splits a trailing `:N` and expands
  `~`; `--linenum-action` opens `vim +{line} {path}` in a window/tab/
  overlay (`main.py:144`). Post-processors per type
  (`PostProcessorMap`, `marks.go:167-200`: asciidoc `link:` stripping, URL
  bracket trimming). Alphabet `0-9a-z` (`marks.go:31`), `--multiple` with a
  joiner, `--ascending` label order.
- Kitty's hints run as a kitten over the *screen text* (`get-text`), i.e.
  outside the terminal core — the same seam as our host/package split.

**Ours today** — §2.7/§4.7 "Ours today" (nothing).

**Gap / Proposal**
Add the `linenum` type to the §2.7 rule set: rule
`{ id: 'file-line', regex: <Kitty's default_linenum_regex>, groups: ['path','line'] }`
with the group processor ported; `onHint` carries `{ path, line }` and
Operator's `frontend/` opens the file at that line (the editor integration
exists for the planning tickets work; exact API: not known). Claude Code
prints `path:line` in every tool result, which makes this the highest-value
hint for us.

**Tests**
- `hint-mode.test.ts`: `src/a.ts:42` → `{path:'src/a.ts', line:42}`;
  `~/x/y.go:7:` trailing colon handled; `a/b` without extension matched via
  the `/` branch; `README` without `/` or extension not matched.

**Priority:** P2 with §2.7.

### 5.6 Marks: user-toggled regex highlights over the transcript

> **Status: Done.** Roadmap Plan 5 — `setMarks(rules)` / `TerminalSurface` `marks`, literal (any case) or regex rules with a colour, painted by the §1.8 model; Operator Settings → Terminal highlights. Not built: next/previous-mark navigation. See `TERMINAL.md` §4.31.

**Reference**
- `kitty/docs/marks.rst:1-60`: `map f1 toggle_marker text 1 ERROR` /
  `itext` / `regex`, up to three colours, `scroll_to_mark` navigation;
  `kitty/kitty/marks.py:15-40` `marker_from_regex` / `marker_from_multiple_regex`
  produce a per-line marker function the C renderer calls to colour cells.

**Ours today** — highlights exist only for selection and find (§1.8).

**Gap / Proposal**
A host-supplied highlight rule (`{ regex, tag }`) applied per visible
logical line and painted as a §1.8/§3.6 highlight; "next/previous mark"
reuses find navigation. For Operator: highlight `error|FAIL|panic` in agent
output on demand. Small once §1.8 exists.

**Priority:** P4.

### 5.7 Input delay before parsing, repaint delay after

> **Status: Not pursued.** Replaced by the pump hold (1/60 s coalescing, held across a DEC 2026 block) and the 12 ms drain budget (agent-TUI spec).

**Reference**
- `kitty/kitty/options/definition.py:1440-1452` `input_delay = 3 ms`:
  "delay before input from the program is processed … decreasing it …
  might cause flicker in full screen programs that redraw the entire screen
  on each loop, because kitty is so fast that partial screen updates will
  be drawn. Ignored when the input buffer is almost full";
  `:1425-1438` `repaint_delay = 10 ms` (ignored when input is pending);
  loop at `kitty/kitty/child-monitor.c:536-542` (wait `input_delay - time_since_new_input`
  before parsing, bounded by the paused-rendering expiry).

**Ours today** — §4.4 "Ours today".

**Gap / Proposal**
Independent confirmation of WezTerm's 3 ms (`§4.4`), with the rationale
spelled out for TUIs that do not use 2026. Use 3 ms in §4.4; no separate
proposal.

**Priority:** with §4.4.

### 5.8 Scrollback in fixed segments plus an ANSI ring beyond the row cap

> **Status: Done.** Roadmap Plan 7 (2026-09-25) — cold ring in the pty-host mirror (32 MiB, not persisted) and Load older output in the pane (`TERMINAL.md` §4.33). Plan C — lazy rewrap for cold scrollback.

**Reference**
- `kitty/kitty/history.c:17-45`: history is allocated in segments of
  `SEGMENT_SIZE = 2048` lines (CPU cells + GPU cells + line attrs), grown on
  demand, so a 100k-line scrollback never reallocates one giant buffer.
- `:83-105,347-440` "pager history": when a line falls off the row cap it
  is serialised as ANSI (`as_ansi`) into a ring buffer
  (`3rdparty/ringbuf`) of up to `scrollback_pager_history_size` bytes
  (`definition.py:740`), rewrapped lazily on width change
  (`pagerhist_rewrap_to` `:489`, `:637`) and shown through the pager
  (`show_scrollback`). Structured rows for the recent past, cheap bytes for
  the deep past.

**Ours today**
- `Content` is chunked bytes (`packages/terminal/crates/vt-core/src/content.rs`)
  so the segment idea is already ours; beyond `scrollback_rows` rows are
  dropped by `trim_to` (`lib.rs:116,175`). The pty-host's `ring.go` holds
  raw output for late attachers — the same "bytes beyond the model" idea,
  but not connected to scrollback.

**Gap / Proposal**
A "load older output" path: rows trimmed by `trim_to` are appended as
`vt_render_styled` ANSI into a per-session byte ring on the host (or the
existing `ring.go` is retained longer), and the renderer can request
"prepend N older rows" which are parsed into a *detached* scrollback
prefix (§1.9's prepend). Deep history without keeping every row in two
wasm heaps. Only worth it if users hit the row cap; P4 until then.

**Priority:** P4.

### 5.9 Unicode tables generated from the current Unicode release, tested against the official grapheme corpus

> **Status: Done.** Plan D — `unicode-width`/`unicode-segmentation` on Unicode 17, tested against `GraphemeBreakTest.json`; `graphemes` on by default since `7395b910c`.

**Reference**
- `kitty/gen/wcwidth.py` downloads the Unicode data files and generates
  `kitty/kitty/char-props-data.h` (width, emoji presentation, grapheme
  break class); `kitty/kitty/char-props.h:25-35,163-170` (`CharProps`,
  `char_props_for`, `wcwidth_std`); changelog `docs/changelog.rst:916`
  "Add support for Unicode 17".
- `kitty/kitty_tests/datatypes.py:1017-1040` runs the official
  `GraphemeBreakTest.json` corpus (`kitty/kitty_tests/GraphemeBreakTest.json`)
  against the cell splitter; `kitty/kitty_tests/screen.py:285`
  `test_emoji_skin_tone_modifiers`.

**Ours today** — §3.14 "Ours today" (`unicode-width` per char; no cluster
rule; the renderer has its own width table).

**Gap / Proposal**
For §3.14: pick a crate whose tables track the current Unicode release
(`unicode-width` 0.2 does; grapheme segmentation via
`unicode-segmentation`), and add Kitty's conformance check — the
`GraphemeBreakTest` corpus (copy the JSON, MIT-compatible) as a `vt-core`
test that every cluster the corpus defines lands in one cell.

**Tests** — `vt-core/tests/grapheme_break_test.rs` over the corpus.

**Priority:** with §3.14.

### 5.10 Tests: a Python screen-level suite with byte-exact inputs

> **Status: Done.** Plan A — `vt-core` `feature = "trace"` records every dispatched action with its stream offset (Kitty's `REPORT_COMMAND`), which was the whole proposal.

**Reference**
- `kitty/kitty_tests/screen.py` (51 tests) and `parser.py` (22): each test
  feeds raw bytes (`parse_bytes(s, b'\033]133;A\007')`) and asserts on
  `s.line(y)` text, attrs and cursor; `test_prompt_marking` `:1641` covers
  prompt kinds, `scroll_to_prompt`, and `cmd_output` extents; the parser
  tests use a "report" mode (`REPORT_COMMAND` in `vt-parser.c`) that logs
  every dispatched command so a test can assert the *sequence* of model
  calls, not only the end state.

**Ours today** — byte-fed Rust tests per bug (`TERMINAL.md` §7).

**Gap / Proposal**
The `REPORT_COMMAND` idea: a `vt-core` debug feature (`cfg(test)` or a
`feature = "trace"`) that records `(sequence, handler, params)` for every
dispatched action, so a test can assert "this capture dispatched exactly
these actions" — the fastest way to pin an upstream artefact like §4.8 to a
specific sequence. Fold into §1.14 / §2.9 harness.

**Priority:** P3 with §1.14.

### Not adopted from Kitty, and why

| Area | Files | Reason |
|---|---|---|
| GPU renderer, GLFW, fonts, sprites | `kitty/kitty/{shaders,gl,glfw,fonts,glyph-cache}.c`, `kitty/kitty/fonts/` | DOM. |
| Graphics protocol, `icat`, disk cache | `kitty/kitty/graphics.c`, `disk-cache.c`, `kittens/icat` | As §1/§3/§4. |
| Keyboard protocol, text sizing, multiple cursors, pointer shapes, DnD, file transfer, wide-gamut colours | `kitty/docs/{keyboard-protocol,text-sizing-protocol,multiple-cursors-protocol,pointer-shapes,dnd-protocol,file-transfer-protocol,wide-gamut-colors}.rst` | Protocol references; consumers are in §1.15/§2.2/§3.15. None emitted by our TUIs today. |
| Desktop notifications OSC 99 | `kitty/docs/desktop-notifications.rst`, `kitty/notifications.py` | The spec; the consumer is §1.15. |
| Remote control (`kitten @`, DCS `@kitty-cmd` JSON, signed with a password) | `kitty/docs/rc_protocol.rst`, `kitty/rc/` | Operator's daemon HTTP API and OSC 7000 are the equivalents; an in-band JSON command channel is not needed. |
| `kitten ssh`, `clone-in-kitty`, `run-shell`, containers | `kitty/kittens/ssh`, `shell-integration/ssh/`, `kitty-integration:464` | Operator sessions are spawned by the daemon with a known cwd/env; cloning a live shell is not a product feature. |
| Layouts, sessions, tabs, the Python `Boss` | `kitty/kitty/{boss,layout,window,tabs}.py` | Product layer. |
| Unscroll (SD fills from scrollback) | `kitty/docs/unscroll.rst` | Fish completion nicety; no consumer. |
| Cursor trail animation, pixel scroll | `kitty/kitty/cursor_trail.c`, `screen.h:231` | Cosmetic; DOM scroller handles scrolling. |

### Kitty section: suggested plan order

1. **5.5** `path:line` hint type — into the §2.7 plan (P2).
2. **5.2** normative OSC 133 citation for §1.6; the two zsh additions.
3. **5.4** option (c) into the §1.5 decision; **5.7** confirms §4.4's 3 ms.
4. **5.3** block timestamps + finished event; **5.9** grapheme corpus with §3.14.
5. **5.10** dispatch trace in the test harness; **5.6**, **5.8** as P4.

---

## 6. VS Code's integrated terminal

**Repository:** `/Users/omaraly/development/AI/vscode` (sparse checkout of
`src/vs/workbench/contrib/terminal`, `src/vs/workbench/contrib/terminalContrib`,
`src/vs/platform/terminal` only) at commit `d3c24c3` (2026-09-19).
**Language:** TypeScript. **Relevant tree:**
`vscode/src/vs/platform/terminal/common/` (capabilities — the command model
— shell integration addon, data buffering, recorder, flow control),
`vscode/src/vs/platform/terminal/node/` (pty host with persistence and
reconnection), `vscode/src/vs/workbench/contrib/terminal/browser/xterm/`
(decorations, mark navigation), `vscode/src/vs/workbench/contrib/terminalContrib/*`
(links, typeAhead, quickFix, stickyScroll, history, suggest, chatAgentTools,
accessibility), `vscode/src/vs/workbench/contrib/terminal/common/scripts/`
(shell integration scripts).

**Why VS Code is worth mirroring:** it is not a terminal engine (xterm.js
§3 underneath) but it is the product closest to ours in *what it does with
shell integration*: a command model with markers, timestamps, exit codes and
output extraction; decorations, sticky scroll, run-recent-command, quick
fixes and terminal IntelliSense built on that model; a pty host that
survives window reloads and replays with the command model intact; and —
since 2025 — an agent tool layer (`chatAgentTools`) that runs commands for
an AI, polls for idle, compresses output for the model and detects prompts.
That last part is Operator's core loop seen from the other side.

Paths are relative to the sparse checkout root:
`vscode/src/vs/platform/terminal/common/xterm/shellIntegrationAddon.ts` means
`/Users/omaraly/development/AI/vscode/src/vs/platform/terminal/common/xterm/shellIntegrationAddon.ts`.

### 6.1 OSC 633: a private shell-integration vocabulary with nonces, properties and env sync

> **Status: Not done.** No nonce, `trusted` flag or continuation property. The rerun action fills the line editor and does not execute.

**Reference**
- `vscode/src/vs/platform/terminal/common/xterm/shellIntegrationAddon.ts:39-54`:
  the addon listens to `133` (FinalTerm), `633` (VS Code), `1337` (iTerm),
  `7` and `9;9` (Windows-friendly cwd). `VSCodeOscPt` `:103-303`:
  `A/B/C/D` as in 133, `E` = command line (`:143-169`, values escaped
  `\ → \\`, `\n → \x0a`, `; → \x3b`, plus an **optional nonce**: "helps
  ensure no malicious command injection has occurred"), `F/G` continuation
  start/end, `H/I` right prompt, `P;<Property>=<Value>` (`:210-227`: `Cwd`,
  `IsWindows`, `ContinuationPrompt`, `HasRichCommandDetection`, and
  `PromptType=p10k|oh-my-zsh|starship` from the script), `SetMark` with
  `Id=` and `Hidden` (`:229-239`), `EnvJson`/`EnvSingle*` (`:241-303`) to
  mirror the shell's environment into the editor — all nonce-gated
  (`:510,527`: a value is trusted only if `arg === this._nonce`).
- Script side `vscode/src/vs/workbench/contrib/terminal/common/scripts/shellIntegration-rc.zsh`:
  injected by redirecting `ZDOTDIR` and re-sourcing the user's rc
  (`:9-31`), nonce from `VSCODE_NONCE` then unset (`:151-152`),
  `ContinuationPrompt` from `$PS2` (`:160`), `HasRichCommandDetection`
  (`:163`), `P;Cwd=` on every precmd (`:174`), env entries with the nonce
  (`:183`).

**Ours today**
- OSC 7000 (`packages/terminal/shell/zsh.sh:15-103`) carries `id`, `cmd`,
  `exit`, `cwd`, `branch`, `input-ready/released`; no nonce, no
  continuation prompt, no right-prompt marks, no `IsWindows`, no env mirror.
  `crates/marks/src/extension.rs` parses `7000;k=v;…`.
- Trust: anything on the pty can emit `7000;cmd=…` and the block header
  shows it; the same is true of every terminal's 133 handling, but VS Code
  is the one that gates *actions* (rerun, quick fix, env) behind the nonce.

**Gap**
Two ideas. (1) The nonce: a per-session secret in the environment that
the integration script echoes back, so a block's command line (and any
future action derived from it — rerun, quick fix) is trusted only when it
came from our script, not from a program printing bytes. (2) Properties
we lack that the block model would use: `ContinuationPrompt` (to strip PS2
from multi-line commands), `IsWindows` (ConPTY heuristics), `PromptType`
(known prompt frameworks that misplace marks).

**Proposal**
- `packages/terminal/shell/*`: read `OPERATOR_TERMINAL_NONCE` (name is the
  host's; the package documents the env key it expects), unset it, append
  `nonce=<v>` to the `7000` `cmd=`/`exit=` messages; emit
  `7000;v=1;continuation=<PS2>` once.
- `crates/marks`: keep `nonce` on the event; `vt-core` block records get
  `trusted: bool` = nonce matched the value handed to `TerminalCore::new`
  (or `set_nonce`); the snapshot exports it. The pty-host passes the nonce
  into the child env (`backend/…/ptyhost`) and to the mirror; the renderer
  learns it from the attach handshake.
- `ts/renderer-dom`: untrusted command lines render the same but
  `block-actions.ts` refuses "rerun" and Operator's future quick fixes on
  them; a small "unverified" glyph in the header (Warp has no such state;
  cite VS Code).

**Tests**
- `crates/marks`: nonce parsed; missing nonce → untrusted.
- `vt-core/tests/blocks.rs`: trusted flag set only on match.
- `shell/zsh.test.mjs`: the nonce is echoed and no longer in `env`.

**Priority:** P3 (P2 the moment "rerun this block" or quick fixes ship).

### 6.2 The command model: markers, timestamps, confidence, output extraction, invalidation, serialisation

> **Status: Partial.** Plan E — block timestamps from the feed clock, timed from output start (`288cb4770`); links resolve against the hovered block's cwd. Not done: confidence, invalidation, serialisation, PS2/right-prompt stripping, core `blockForRow`/`cwdForRow`.

**Reference**
- `vscode/src/vs/platform/terminal/common/capabilities/capabilities.ts:214-250`
  `ICommandDetectionCapability`: `commands`, `executingCommand(Object)`,
  `executingCommandConfidence: low|medium|high`, `cwd`,
  `hasRichCommandDetection`, `currentCommand` (partial), events
  `onCommandStarted/Executed/Finished/Invalidated`, `getCommandForLine(line)`,
  `getCwdForLine(line)`, `handle{PromptStart,ContinuationStart/End,RightPromptStart/End,CommandStart,CommandExecuted,CommandFinished}`.
- `IBaseTerminalCommand` `:300-316` (`command`, `cwd`, `exitCode` `:310`,
  `timestamp` `:304`, `duration` `:305`) and `ITerminalCommand` `:317-331`:
  `promptStartMarker`, `marker` (command start), `executedMarker`,
  `endMarker` `:321`, `aliases`, `wasReplayed`, `extractCommandLine()`,
  `getOutput()`, `getOutputMatch(matcher)`, `hasOutput()`,
  `getPromptRowCount()`, `getCommandRowCount()`.
- `vscode/src/vs/platform/terminal/common/capabilities/commandDetectionCapability.ts`:
  `serialize()` `:457` → `ISerializedTerminalCommand` (`capabilities.ts:334-340`:
  lines instead of markers) and `restoreCommands`, so the command list
  survives a pty-host reconnect (`ptyService.ts:1106` sends
  `commands: this._shellIntegrationAddon.serialize()` with the replay);
  `setIsCommandStorageDisabled` `:251` (privacy: keep markers, drop text);
  `onCommandInvalidated` `:75,203` when a `clear` removes rows.
- `vscode/src/vs/platform/terminal/common/capabilities/commandDetection/promptInputModel.ts:21-44,79`
  `PromptInputModel`: "a model of the prompt input state using shell
  integration and analyzing the terminal buffer" — value, cursor index,
  ghost text, `onDidStartInput/ChangeInput/FinishInput/Interrupt`, fed by
  `ContinuationPrompt` and the last prompt line; this is what terminal
  IntelliSense (`terminalContrib/suggest`) and the agent tools read to know
  what the user has typed *before* Enter.

**Ours today**
- `BlockGrid` + `crates/marks`: blocks with `(first_row, row_count)`, id,
  state, exit code, command, cwd/branch from 7000, bookmarks;
  `readBlockOutput`; `process_boundary` (`TERMINAL.md` §4.15). Missing:
  timestamps/duration (§5.3), prompt-vs-command row counts, right prompt
  and continuation handling, a confidence level when marks are missing or
  misplaced, and an "invalidated" event when rows are cleared. The line
  editor (`ts/editor`) *is* our prompt input model in shell mode; in
  agent-TUI mode there is none (the app owns the prompt).

**Gap / Proposal**
- `vt-core`: on each block record add `prompt_rows` (rows between `A` and
  `B`), `command_rows` (`B`→`C`), `started_at`/`finished_at` (host clock
  passed into `feed` as a `u64 ms`, so the mirror and the renderer agree),
  `confidence` (`high` when `A/B/C/D` arrived in order at column 0; `low`
  when synthesised from a boundary or missing `C`), and a
  `blocks_invalidated: Vec<BlockId>` in the snapshot when a clear or
  `trim_to` removed a block's rows (§3.5 events).
- Continuation/right prompt: with §1.6's `k=s` and VS Code's `F/G`/`H/I`
  equivalents on OSC 7000 (`continuation-start/end`, `right-prompt`),
  `readBlockCommand` strips PS2 and right-prompt text; the header then
  shows exactly what the user typed for multi-line commands.
- `ts/core`: `TerminalCore.blockForRow(row)` and `cwdForRow(row)`
  (`getCommandForLine`/`getCwdForLine`) so links (§3.7) resolve relative
  paths against the cwd *at that row*.

**Tests**
- `vt-core/tests/blocks.rs`: row counts; confidence; invalidation on
  `ESC[2J` in shell mode and on trim; cwd-for-row across three blocks
  with different cwds.
- `block-header.test.ts`: multi-line command with a PS2 renders one
  command line.

**Priority:** P2 (`cwdForRow` unblocks correct file links; the rest is small).

### 6.3 Pty host persistence: reconnect with grace periods, replay with command state, flow control, heartbeat

> **Status: Partial.** Plan C — replay with block marks and flow-control acks. Roadmap Plan 4 (2026-09-24) — hung pty-host detection (3 consecutive failed reaper probes, `ptyhost/health.go`) with Restart terminal, and mirror persistence across a host's death (`ptyhost/persist.go`). Not done: resize-aware ring.

**Reference**
- `vscode/src/vs/platform/terminal/node/ptyService.ts:687-810`
  `PersistentTerminalProcess`: a process outlives its window; on
  disconnect two timers run — `shortGraceTime = 6 s` (reconnect quickly
  during a reload) and `graceTime = 60 s` (after which the pty is killed),
  `vscode/src/vs/platform/terminal/common/terminal.ts:865-874`; an "orphan
  question" barrier (`:696-697,494-495`) lets the host ask a possibly-dead
  client before killing.
- Replay: `XtermSerializer` (`ptyService.ts:1037-1108`) runs a headless
  xterm.js in the pty host, feeds every byte (`handleData`), and on
  reattach `generateReplayEvent` serialises the buffer with `SerializeAddon`
  (`:1082-1106`) — `{cols, rows, data}` plus `commands: shellIntegrationAddon.serialize()`
  so the client's command decorations come back; `normalBufferOnly`
  excludes alt buffer and modes for the "revive after restart" path;
  `reviveTerminalProcesses` (`:256`) restores from a serialised state
  written at shutdown (`serializeTerminalState` `:230`) so terminals survive
  an *application* restart with their scrollback, not just a reload.
- Cheap fallback: `vscode/src/vs/platform/terminal/common/terminalRecorder.ts:10,23-101`
  `TerminalRecorder` keeps the last 10 MB of raw output as
  `[{cols, rows, data[]}]` entries split at each resize, so a replay can
  re-run the bytes at the sizes they were produced at.
- Flow control `terminal.ts:876-896`: the client acks every
  `CharCountAckSize = 5000` chars; the host pauses the pty at
  `HighWatermarkChars = 100000` unacknowledged and resumes at
  `LowWatermarkChars = 5000`.
- Data buffering `vscode/src/vs/platform/terminal/common/terminalDataBuffering.ts:16-38`:
  output events coalesced for 5 ms before crossing the IPC boundary.
- Heartbeat `terminal.ts:461-470`, `platform/terminal/node/heartbeatService.ts:19`:
  a 5 s beat (20 s while starting) so the workbench can show "pty host
  unresponsive" and restart it.

**Ours today**
- The daemon and pty-host outlive the window (`TERMINAL.md` §1: "one
  subprocess per session", `ring.go` for late attachers, `vt_replay` from
  the mirror); grace periods/orphan handling: the daemon keeps sessions
  regardless (Operator sessions are long-lived by design). Replay does not
  carry block state — the client re-derives blocks by re-parsing the replay
  bytes, which is why `BlockTerminal.tsx:141` strips ranges
  (`withoutRanges(bytes, marks)`) for history blocks; details: not re-read
  here. Flow control: none found (`grep -rn "ack" backend/internal/httpd/terminal_mux.go`
  — not run; the plan checks). Heartbeat: the mux has a status stream
  (`mux_client.dart:98-101`); the pty-host liveness: not known.

**Gap / Proposal**
- With §4.2 the replay problem changes shape (rows, not bytes). Until
  then: (a) `vt_replay` also emits the mirror's block records
  (`BlockGrid` as OSC 7000 marks with `id=`, `exit=`, `cmd=`, and the new
  timestamps) so the client's blocks are identical to the mirror's
  (VS Code's `commands:` in the replay), removing the client-side
  re-derivation; (b) the recorder idea is `ring.go` already — make it
  resize-aware (`[{cols, rows, bytes}]`, `terminalRecorder.ts:23-60`) so a
  raw replay at a different size does not double rows (§4.7 of
  `TERMINAL.md` clips instead; this is the other half); (c) flow control:
  the mux client acks bytes; the pty-host pauses reading the pty at a high
  watermark (Go: stop `Read`ing; the kernel back-pressures the child) —
  matters for `cat bigfile` on mobile over Tailscale; (d) heartbeat from
  pty-host to daemon so a hung host is restarted rather than left
  attached with a frozen pane (`RUN_APP_COMMANDS.md` / `TERMINAL.md` §8
  today say "restart the daemon and app").

**Tests**
- Go `vtwasm/replay_test.go`: replay carries block ids and exit codes;
  `ring_test.go`: entries split at resize; `host_test.go`: pty read pauses
  past the watermark and resumes on ack; heartbeat timeout marks the host
  dead.

**Priority:** P2 for (a) and (c); P3 for (b), (d).

### 6.4 Links: suffix grammar (`file:line:col` and friends), validation against the file system, per-line caps

> **Status: Done.** Hover tries the spans through the hovered cell, longest first, in one capped `resolveFirstPath` host call; VS Code's suffix grammar (ported with its test table) strips the line/column; VS Code's per-line caps. Multi-line and word links not done.

**Reference**
- `vscode/src/vs/workbench/contrib/terminalContrib/links/browser/terminalLinkParsing.ts:44-140`
  `generateLinkSuffixRegex`: one regex for every row/column suffix form
  seen in compiler and test output — `foo:339`, `foo:339:12`,
  `foo:339:12-789`, `foo:339:12-341.789`, `foo:339.12`, `foo 339`,
  `foo 339:12`, `foo#339`, `foo, 339`, `"foo",339`, `"foo", line 339`,
  `foo(339)`, `foo(339,12)`, `foo[339]`, `foo:line 339`, … (each with the
  issue number that added it; the legend `:64-75`); `getLinkSuffix`
  `:183`, `removeLinkSuffix` `:141`, `removeLinkQueryString` `:153`,
  `detectLinks(line, os)` `:214` (path + suffix candidates for POSIX and
  Windows).
- `vscode/src/vs/workbench/contrib/terminalContrib/links/browser/terminalLocalLinkDetector.ts:22-34`
  caps (`MaxLineLength = 2000`, `MaxResolvedLinksInLine = 10`,
  `MaxResolvedLinkLength = 1024`); `detect` `:81-250` resolves each
  candidate against the file system (`_validateAndGetLink` →
  `terminalLinkResolver.ts`, relative to the cwd for that line from
  `getCwdForLine`, §6.2) so only paths that exist become links; separate
  detectors for URIs, words (`terminalWordLinkDetector.ts`, search the
  workspace for a bare word), multi-line links (`terminalMultiLineLinkDetector.ts`,
  the `path` on one line and `line 339` on the next, as in some test
  runners), and external providers.
- `terminalLinkOpeners.ts`: openers for file (at line/col), folder, URL,
  search-workspace fallback.

**Ours today** — nothing (§1.15/§2.7/§3.7/§5.5).

**Gap / Proposal**
This is the grammar for §5.5's `path:line` hint and §3.7's linkifier:
port `terminalLinkParsing.ts` (pure functions, MIT, with its test file's
exhaustive list) into `packages/terminal/ts/renderer-dom/src/link-parsing.ts`;
the package emits `{ path, row?, col?, rowEnd?, colEnd? }` candidates and
the host validates existence (Operator's daemon has the file system; the
mobile client asks the daemon). Keep VS Code's caps per line.
`cwdForRow` (§6.2) resolves relative paths.

**Tests**
- `link-parsing.test.ts`: the ported VS Code table (every format above,
  POSIX and Windows).

**Priority:** P2 with §2.7/§3.7.

### 6.5 Type-ahead: local echo with a prediction timeline, style, and exclusions

> **Status: Done.** Plan F — renderer-only overlay armed above a 30 ms host RTT, off by default; behavioural exclusions (no-echo, row jump, alt screen, paste, control keys, open 2026 block, TTL). Overlay-only is the proposal's own choice, so no timeline. Phone not pursued.

**Reference**
- `vscode/src/vs/workbench/contrib/terminalContrib/typeAhead/browser/terminalTypeAheadAddon.ts`:
  predictions are objects with `apply/rollback/matches`
  (`CharacterPrediction` `:387`, `BackspacePrediction` `:454`,
  `CursorMovePrediction` `:558`, boundaries `HardBoundary` `:328` /
  `TentativeBoundary` `:352`); a `PredictionTimeline` `:718` applies them
  to the buffer immediately, then consumes real output and either confirms
  or `undoAllPredictions` `:810` on mismatch; `PredictionStats` `:647`
  measures latency; the addon `:1297-1350` only predicts when measured
  latency exceeds `localEchoLatencyThreshold` (default 30 ms,
  `typeAhead/common/terminalTypeAheadConfiguration.ts:31`), is `auto`
  (remote workspaces only, `:43`), skips programs in
  `localEchoExcludePrograms` (vim, nano, … `:53`) and styles predicted
  text `dim` (`:58`) so the user can tell it apart.

**Ours today** — §4.3 "Ours today".

**Gap / Proposal**
Complements §4.3 (WezTerm): VS Code's is the reference for the *client*
side without a row-delta protocol — it predicts into the xterm buffer and
reconciles against the byte stream. That works for our alt-screen path
today, before §4.2: `TerminalSurface` could apply a `CharacterPrediction`
to the cursor cell in the DOM (a dim overlay glyph, not a model change) and
drop it when the next feed advances the cursor past it. Excluded programs
list is the host's; the threshold measured from `input → first byte`.
Keep the model untouched (predictions are renderer overlays), which avoids
the reconciliation complexity of VS Code's timeline.

**Tests**
- `TerminalSurface.test.tsx`: a typed char shows dim at the cursor within
  one frame; it disappears when output arrives; none below the threshold.

**Priority:** P3 (P2 for mobile-over-Tailscale users).

### 6.6 Quick fixes: match a failed command's line and output, offer an action

> **Status: Not done.** No quick-fix matcher or `onQuickFix`. A non-goal of the agent-TUI spec.

**Reference**
- `vscode/src/vs/workbench/contrib/terminalContrib/quickFix/browser/terminalQuickFixBuiltinActions.ts:27-330`:
  each fix is `{ commandLineMatcher, outputMatcher: { lineMatcher, anchor: 'top'|'bottom', offset, length }, exitStatus, getQuickFixes(match) }`;
  built-ins: `gitSimilar` (`:27`, "did you mean"), `gitFastForwardPull`
  (`:64`), `gitTwoDashes` (`:88`), `freePort` (`:115`, kill the process on
  a busy port), `gitPushSetUpstream` (`:147`), `gitCreatePr` (`:213`,
  offer the URL git printed), PowerShell errors (`:258,307`). Fixes are
  surfaced as a lightbulb on the command decoration (`quickFixAddon.ts`),
  and extensions register more (`terminalQuickFixService.ts`).
- Matching runs on `ITerminalCommand.getOutputMatch` (§6.2), i.e. on the
  block's output rows near its top or bottom.

**Ours today**
- Block actions exist (`block-actions.ts`) but are static; nothing reads
  a failed block's output to offer a fix.

**Gap / Proposal**
For an agent terminal, "quick fix" generalises to "suggested next prompt":
a failed shell block whose output matches a rule can offer "Ask the agent
to fix this" with the matched lines attached, or the built-in git fixes
when the block is a plain shell. The package provides the matcher
(`QuickFixRule { commandLine, output: { lineMatcher, anchor, offset, length }, exitStatus }`
evaluated on a finished block via `readBlockOutput`) and an
`onQuickFix({ blockId, ruleId, match })` event; the host owns the actions.

**Tests**
- `quick-fix.test.ts`: the `gitPushSetUpstream` rule matches VS Code's
  fixture output at `anchor: bottom`; a rule with `exitStatus: true` does
  not match a successful block.

**Priority:** P3.

### 6.7 Sticky scroll of the *prompt line* rendered by a second terminal

> **Status: Not pursued.** Not adopted by the entry itself; `pinned-header.ts` pins the block header, not the prompt.

**Reference**
- `vscode/src/vs/workbench/contrib/terminalContrib/stickyScroll/browser/terminalStickyScrollOverlay.ts:111-250`:
  a second xterm instance (`_stickyScrollOverlay`, `:111`) is fed the
  *serialised* prompt rows of the command whose output is at the top of
  the viewport (`getCommandForLine(viewportY)` `:231`,
  `SerializeAddon` `:141-142`), so the sticky header is pixel-identical to
  the real prompt (colours, git status, everything); hidden when the
  command is fully visible (`:239,250`), max lines configurable.

**Ours today**
- `pinned-header.ts` pins the *block header* (command text + status
  chrome), not the prompt rows (`TERMINAL.md` §4.13 mentions it as chrome).
  For Warp parity that is the right call; VS Code's variant matters only
  for shells whose prompt carries information the header lacks (git
  branch, venv) — our header shows cwd/branch from OSC 7000 already.

**Priority:** not adopted; noted as an alternative if a user wants the
literal prompt pinned.

### 6.8 Run recent command / recent directory from shell history and the command model

> **Status: Not done.** Line-editor history reads only this session's blocks. A non-goal of the agent-TUI spec.

**Reference**
- `vscode/src/vs/workbench/contrib/terminalContrib/history/browser/terminalRunRecentQuickPick.ts:34-200`:
  a quick pick merging the session's detected commands (with output
  preview and "open output in editor" `:65,183`), the shell's own history
  files (`history/common/history.ts` `getShellFileHistory` for bash/zsh/
  fish/pwsh) and a persisted cross-session store (`getCommandHistory`,
  `:144`, `storageService` `:50`); "recent directory" from
  `getDirectoryHistory` uses the cwd of each command.

**Ours today**
- Block navigation and the palette (`palette.ts`) search *this session's*
  blocks; no cross-session or shell-history source.

**Gap / Proposal**
Host feature; the package needs only `blocks()` with `command`, `cwd`,
timestamps (§6.2). Operator's palette gains "run recent" from the
daemon's block store and from the shell history file — listed for the
product backlog.

**Priority:** P4.

### 6.9 Agent tools on top of the terminal: idle detection, output compression, prompt detection

> **Status: Partial.** Roadmap Plan 8 (2026-09-25) — the idle/prompt detector (`TerminalCore.agentActivity()`/`onAgentActivity`) and `readBlockOutput({ compact })` are in `ts/core` (`TERMINAL.md` §4.34). Operator does not consume them; its board state still comes from `opr mcp` (`2e54a6bfb`) and the daemon (`0cd094f12`).

**Reference**
- `vscode/src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/executeStrategy/executeStrategy.ts:14-31`:
  three strategies for running an agent's command — `rich` (shell
  integration with command detection: wait for `D`, read
  `getOutput()`), `basic` (marks only), `none` (no integration: idle
  heuristics).
- `…/tools/monitoring/types.ts:30-52`: `OutputMonitorState { Initial, Idle, PollingForIdle, Prompting, Timeout, Active, Cancelled }`
  and `PollingConsts { MinIdleEvents = 2, MinPollingDuration = 500 ms, FirstPollingMaxDuration = 20 s, ExtendedPollingMaxDuration = 2 min, MaxPollingIntervalDuration = 10 s (exponential backoff), MaxRecursionCount = 5 }`;
  `…/tools/monitoring/outputMonitor.ts:61-230`: poll until the output is
  unchanged for two checks, detect a *prompt* (a question the command is
  asking, e.g. "Overwrite? (y/n)") and hand it to the user or the model,
  track `_userInputtedSinceIdleDetected` (`:85-88`).
- `…/tools/terminalOutputCompressor.ts:180-310`: strip ANSI, collapse
  progress-bar rewrites, dedupe repeated lines, truncate to a token budget;
  `…/tools/consoleCompactor/` classifies command output (counts,
  reductions) so the model sees a summary; `…/tools/terminalOutputCache.ts`
  keeps the full output for `getTerminalOutputTool` on demand;
  `…/tools/getTerminalLastCommandTool.ts`, `getTerminalSelectionTool.ts`,
  `sendToTerminalTool.ts`, `killTerminalTool.ts` are the tool surface;
  `terminalToolAutoApprove.ts` + `platform/terminal/common/autoApprove/`
  decide which command lines run without confirmation (a parsed,
  allow/deny-listed command line via `treeSitterCommandParser.ts`).

**Ours today**
- Operator runs the agent *in* the terminal (Claude Code owns the pty);
  the daemon detects idle/attention from block state and OSC 7000
  `input-ready` (exact logic lives in `backend/` session state; not
  re-read). There is no "run this command for the agent and return
  compressed output" tool because the agent has its own; but Operator's
  orchestrator (`docs/superpowers/specs/2026-09-11-autonomous-orchestrator-design.md`)
  and the mobile "suggested prompt" feature read session output.

**Gap / Proposal**
Two transferable pieces for the *host*, listed so the plan can decide
where they live: (1) the idle/prompt state machine with its constants as
the daemon's definition of "session waiting for input" when OSC 7000
`input-ready` is absent (agent TUIs without our shell integration);
(2) output compression for anything Operator feeds to a model (the
orchestrator's summaries, the mobile suggested prompt): strip ANSI via
`vt_render` (already text), collapse rewrites — which the block model
already does because a repainted frame is one block — and dedupe. The
package contribution is `readBlockOutput({ compact: true })` in
`renderer-dom`/`vt-core` (collapse repeated rows, cap by rows from top and
bottom with a marker).

**Priority:** P3 for `compact` output; the state machine is a `backend/`
decision (P4 here).

### 6.10 Decorations on commands with context menus; mark navigation

> **Status: Done.** Already before the survey: block headers show duration (`fa6cec10b`); block actions include copy, share, bookmark, filter, jump and rerun; `block-nav`. Nonce gating is §6.1.

**Reference**
- `vscode/src/vs/workbench/contrib/terminal/browser/xterm/decorationAddon.ts:125-127,228-233,294-300`:
  a gutter decoration per command (blue dot running, green/red on exit
  code) via xterm.js `registerDecoration` (§3.6), with an overview-ruler
  twin; `:398-489` its context menu: rerun, copy command, copy output,
  copy command and output, open output in editor, learn more; hover shows
  exit code, duration, timestamp.
- `…/xterm/markNavigationAddon.ts`: jump to previous/next command, select
  to previous/next command, scroll to a mark by id (`SetMark Id=`).

**Ours today**
- Block header + actions cover rerun-less variants (copy, bookmark,
  navigate: `block-actions.ts`, `block-nav.ts`); duration/timestamp
  missing (§5.3/§6.2). "Rerun" needs the nonce (§6.1) to be safe.

**Priority:** covered by §5.3/§6.1/§6.2; nothing separate.

### 6.11 Resize: rows immediately, columns debounced; hidden terminals resize on idle

> **Status: Done.** A parked pane sends no resize; on show its grid goes through the normal debounced publish (`be9d35222`, `TERMINAL.md` §4.24). Plan 4 added the visibility seam, paint gate and 30-minute unload. Rows-immediate not adopted (`TERMINAL.md` §4.6).

**Reference**
- `vscode/src/vs/workbench/contrib/terminal/browser/terminalResizeDebouncer.ts:11-80`:
  below `StartDebouncingThreshold = 200` buffer rows resize immediately;
  otherwise rows apply at once (cheap) and columns after
  `DebounceResizeXDelay = 100 ms` (reflow is the expensive axis); a
  terminal that is not visible resizes in `runWhenWindowIdle`.

**Ours today** — `TERMINAL.md` §4.6: 100 ms trailing debounce on both
axes, leading edge only for the first grid; "do not re-add a leading
edge". The reason differs from VS Code's: our cost is not reflow but the
SIGWINCH repaint of the agent TUI (§4.8), which rows-immediate would
trigger just as often. Not adopted for the live pane. The *hidden pane on
idle* rule is worth taking: a parked pane (`TERMINAL.md` §4.14
retained-terminal cache) currently gets its resize when? — not known; if
it resizes while parked, defer to `requestIdleCallback` and to the moment
it is shown.

**Priority:** P4.

### Not adopted from VS Code, and why

| Area | Files | Reason |
|---|---|---|
| xterm.js wrapper, WebGL/canvas selection, addon importer | `vscode/src/vs/workbench/contrib/terminal/browser/xterm/xtermTerminal.ts`, `xtermAddonImporter.ts` | §3 covers the engine. |
| Terminal IntelliSense (`suggest`) with LSP completions | `vscode/src/vs/workbench/contrib/terminalContrib/suggest/` | Our line editor (`ts/editor`) has `completions.ts`; VS Code's model is xterm-buffer-based because it has no editor of its own. |
| Profiles, environment variable collections, launch configs | `vscode/src/vs/platform/terminal/common/terminalProfiles.ts`, `environmentVariable*.ts` | Operator spawns sessions from projects; env is the daemon's. |
| Tabs, groups, editor-area terminals, split view | `terminalGroup*.ts`, `terminalEditor*.ts`, `terminalTabbedView.ts` | Product layout. |
| Accessibility contribution (accessible view of the buffer, command navigation) | `terminalContrib/accessibility/` | §3.9 proposes the package primitive; VS Code's is workbench-wide. |
| Auto replies ("Terminate batch job (Y/N)?") | `terminalContrib/autoReplies/` | Windows-specific nuisance; noted. |
| Voice, zoom, send-signal, resize overlay, WSL recommendation | `terminalContrib/{voice,zoom,sendSignal,resizeDimensionsOverlay,wslRecommendation}/` | Chrome or platform features; Operator has its own. |
| Agent host pty (`agentHost*`) | `terminal/browser/agentHost*.ts` | A 2026 sandboxed pty for VS Code's own agents; Operator's agents already run in the daemon's pty-host. |
| Windows shell helper, ConPTY heuristics | `platform/terminal/node/windowsShellHelper.ts`, `IsWindows` property | Only if the Windows host becomes a priority; `IsWindows` is listed in §6.1. |

### VS Code section: suggested plan order

1. **6.4** link suffix grammar → into the §2.7/§3.7/§5.5 plan (P2).
2. **6.2** block timestamps/row counts/confidence/`cwdForRow` (P2; §5.3 folds in).
3. **6.3(a)** replay carries block records; **6.3(c)** flow control (P2).
4. **6.1** nonce-trusted command lines before any "rerun"/quick-fix ships.
5. **6.5** dim type-ahead overlay in alt-screen; **6.6** quick-fix matcher; **6.9** compact output.
6. **6.3(b,d)**, **6.8**, **6.11** as backlog.

---

## 7. Warp — what we have not taken yet

**Repository:** `/Users/omaraly/development/AI/warp` (no git metadata read;
tree as of 2026-09-19). **Language:** Rust. **Relevant tree:**
`warp/crates/warp_terminal/src/` (the model: `model/grid/`, `model/ansi/`,
`model/secrets.rs`, `bootstrap.rs`, `shared_session.rs`),
`warp/app/src/terminal/` (the block list, `cli_agent*.rs`,
`cli_agent_sessions/`, `model/early_output.rs`, `recorder.rs`,
`ref_tests/`, `shared_session/`, `warpify/`), `warp/crates/warp_tui/`.

**Why this section exists:** Warp is already the cited reference for
`packages/terminal` (`TERMINAL.md` §3.2); every rendering and resize
decision we made is traced to a Warp file. This section is the inverse
list — approaches Warp has in the terminal domain that we have *not*
ported — so the plan does not have to re-survey Warp. It says "equal" where
we already match, and it cross-references §1–§6 where another terminal has
the same idea with a clearer implementation.

Paths are relative to the repository root: `warp/app/src/terminal/cli_agent.rs`
means `/Users/omaraly/development/AI/warp/app/src/terminal/cli_agent.rs`.

### 7.1 CLI-agent session events over OSC 777 from an installed agent plugin

> **Status: Partial.** Roadmap Plan 8 (2026-09-25) — an in-band agent-state channel over OSC 777 (`protocol/SPEC.md` §10, `TERMINAL.md` §4.34) parsed by `vt-core` and surfaced by `ts/core`; Plan 3 parses OSC 777 `notify` and OSC 9. Agent events still reach the daemon out of band (hooks, `opr mcp` `session_report`, the transcript's interrupt marker); nothing emits or consumes the in-band channel yet.

**Reference**
- `warp/app/src/terminal/cli_agent.rs:1-4`: "detecting and working with
  CLI-based AI agents like Claude Code, Gemini CLI, Codex, Amp, and Droid";
  `detect` `:404` classifies the command line being run (via
  `warp_completer::parsers::simple::top_level_command`).
- `warp/app/src/terminal/cli_agent_sessions/plugin_manager/claude.rs:14-22`:
  Warp installs a Claude Code plugin from the marketplace
  `warpdotdev/claude-code-warp` (`PLUGIN_KEY = warp@claude-code-warp`,
  minimum version pinned) whose hooks emit structured events; `codex.rs`,
  `gemini.rs`, `opencode.rs` do the same per agent.
- Transport: the hook writes `OSC 777 ; notify ; <title> ; <JSON> ST` to
  the pty; the model parses OSC 777 as a notification
  (`warp/crates/warp_terminal/src/model/ansi/mod.rs:1028-1050`, handler
  callback `warp/crates/warp_terminal/src/model/ansi/handler.rs:411-414`),
  and the app-level listener turns the JSON body into a `CLIAgentEvent`
  (`warp/app/src/terminal/cli_agent_sessions/listener/mod.rs:133-152`,
  with an OSC 9 plain-text fallback for Codex `:99-132`).
- Event schema `warp/app/src/terminal/cli_agent_sessions/event/mod.rs:10-52`:
  `SessionStart, PromptSubmit, ToolComplete, Stop, StopFailure, PermissionRequest, PermissionReplied, QuestionAsked, IdlePrompt`
  with `query, response, transcript_path, summary, tool_name, tool_input_preview, plugin_version, error_type`;
  session status `warp/app/src/terminal/cli_agent_sessions/mod.rs:22-40`
  `InProgress | Success | Failed{error_type,message} | Blocked{message} | Interrupted`,
  where "interrupted" is inferred from a synthesised Ctrl-C with no plugin
  activity for `CTRL_C_CANCEL_WINDOW = 2 s` (`:17-20`).
- `warp/crates/warp_tui/` is Warp's own TUI framework that emits the same
  OSC 777 events natively (`listener/mod.rs:63`).

**Ours today**
- Operator already has agent hooks, out of band: `opr` runs as the
  agent's hook command and posts an activity body to the daemon over
  loopback HTTP (`backend/internal/cli/hooks.go:21-38`, schema version
  `hookSchemaVersion = "1"`, failures appended to `hooks.log`); per-agent
  adapters under `backend/internal/adapters/agent/{claudecode,codex,cline,devin,…}`
  register the hooks and map them to session state (`activitystate/`,
  `activitydispatch/`). The suggested-prompt feature (commit `9d3230c63`)
  rides the same channel.

**Gap**
Functionally equal or better (structured HTTP, versioned, logged). Two
things Warp's design has that ours does not: (1) the in-band transport
works wherever the pty goes — over SSH, inside a container, on a remote
host with no loopback to our daemon — because the bytes come back through
the terminal; (2) the *terminal package* can react to agent events
(status in the block header, "waiting for permission" chrome) without the
host plumbing them, because the model already sees them. Neither matters
until Operator runs agents remotely.

**Proposal**
- `vt-core`: parse `OSC 777 ; notify ; title ; body` into an
  `event_bridge` notification (already planned as OSC 9/99 in §1.15) — one
  parser for all three.
- Backend: keep HTTP as primary; accept an OSC 777 JSON body from the
  mirror as a *secondary* source with the same schema, deduplicated by an
  event id, so a remote session (future) degrades to in-band. Listed for
  the remote-agents design, not for the terminal plan.

**Priority:** P4 (equal today); the OSC 777 parse is folded into §1.15.

### 7.2 Early output: typeahead and background output between blocks

> **Status: Partial.** Background output after the last block is kept as a running synthetic block (`e7684bed8`). Typeahead done for zsh (roadmap Plan 6, `TERMINAL.md` §4.32); bash and fish keep the old behaviour.

**Reference**
- `warp/app/src/terminal/model/early_output.rs:26-48`: output that arrives
  "after a `BlockFinished` hook but before Warp has written the next
  command from the input editor to the PTY" is one of two things —
  *typeahead* (the user typed while a command ran; the shell echoes it as
  the start of the next command; Warp captures it into the input editor so
  users can queue commands on a slow connection) or *background output*
  (job-control messages, background processes). `TypeaheadMode::ShellReported`
  (the shell reports its input buffer) vs `InputMatching` (bash 3.2 only,
  match typed bytes against echoed bytes).

**Ours today**
- Rows before the first `A` and after the last `D` are synthetic blocks
  (`TERMINAL.md` §4.15 / CHANGELOG "markless rows"), so background output
  is kept and rendered. Typeahead: keys typed while a command runs go to
  the pty (`ts/editor/src/line-editor.ts` `passthrough`, since
  `4b31952aa`). Since roadmap Plan 6, zsh reports what was waiting on the
  tty at its next prompt as `OSC 7000;v=1;typeahead=` (Warp's
  `ShellReported`, clean-room) and the line editor adopts it
  (`TERMINAL.md` §4.32); bash and fish do not report it.

**Priority:** equal; noted so nobody ports it.

### 7.3 Secret redaction in the grid

> **Status: Done.** Plan E — the daemon's patterns masked in copy, selection, links, hints and block text; default off. The phone view is not masked, and a masked token stays readable by assistive tech (`TERMINAL.md` §5).

**Reference**
- `warp/crates/warp_terminal/src/model/secrets.rs:27-135`: regex patterns
  at two levels, `User` and `Enterprise` (`:94-100`, enterprise wins);
  `RespectObfuscatedSecrets` when *reading* grid contents (copy, AI
  context) and `ObfuscateSecrets::{Yes, Strikethrough, No}` when
  *rendering*, tied to a Safe Mode setting (`:121-135`); the grid keeps
  secret ranges per row (`warp/crates/warp_terminal/src/model/grid/secrets.rs`)
  and `warp/app/src/terminal/secret_regex_updater.rs` refreshes the pattern
  set from the server.
- Interaction: a redacted token is revealed on hover/click, copied
  redacted unless the user asks otherwise.

**Ours today**
- Nothing. Agent output regularly contains tokens (`.env` cats, `gh auth
  status`, curl headers), and Operator's mobile client and orchestrator
  summaries re-transmit block text.

**Gap / Proposal**
- `packages/terminal/ts/renderer-dom`: a `redaction.ts` pass over logical
  lines (§4.5) with a host-supplied pattern list (Warp's defaults are
  server-fed; the package ships a small default: AWS keys, GitHub
  `ghp_/gho_`, Slack `xox`, JWTs, `sk-…`), painted as a highlight tag
  (§1.8) with `text-security: disc`-style masking via a span class; hover
  reveals; `selection-text.ts`/`readBlockOutput` honour
  `respectRedactions`. The mobile client applies the same rule set
  (shared regex list in `packages/terminal`'s package output).
- Not in `vt-core`: the model stores bytes; redaction is a view concern.

**Tests**
- `redaction.test.ts`: each default pattern; overlapping matches; copy
  with and without respect; hover reveal toggles one match.

**Priority:** P3 (P2 before any "share block" / summary-to-model feature).

### 7.4 OSC 8 hyperlinks interned per grid with hard caps

> **Status: Done.** Plan E — capped, never-reclaimed registry; the link id is the sixth style word.

**Reference**
- `warp/crates/warp_terminal/src/model/grid/hyperlink_registry.rs:1-15`:
  URIs interned behind a 4-byte `HyperlinkId` per cell; **bounded**
  (`MAX_DISTINCT_ENTRIES`, refuses further interns; `MAX_URI_BYTES`
  enforced in the parser `model/ansi/control_sequence_parameters.rs`) and
  **never reclaimed** while the grid lives, deliberately, to avoid the
  use-after-free/leak hazards of refcounting across RLE split/merge,
  eviction, reflow and deserialisation.

**Ours today** — §1.15 proposes OSC 8 storage keyed by content offset.

**Gap / Proposal**
Take Warp's two rules for §1.15's implementation: cap distinct URIs and
URI bytes (a hostile program printing millions of distinct `OSC 8`s must
not grow memory), and do not reclaim — our `AttributeMap` is append-only
anyway. Cite this file in the §1.15 plan.

**Priority:** with §1.15.

### 7.5 Grapheme cursor over cells

> **Status: Done.** Plan D — cells, word boundaries and selection step by exported cell spans. The cursor covers a whole cluster only with `cursorContrast` (off); the line editor steps by code point.

**Reference**
- `warp/crates/warp_terminal/src/model/grid/grapheme_cursor.rs:10-30,241-260`:
  a cursor that iterates forward/backward over *graphemes* in a row,
  skipping wide-char spacers and treating a cluster as one step; used by
  selection, word boundaries and the line editor's cursor movement.

**Ours today** — `cell-width.ts` (renderer) and `words.ts` step by code
point; §3.14 proposes cluster-aware widths in the model.

**Priority:** with §3.14; Warp's is the reference for the iteration API.

### 7.6 Per-session pty recording and Alacritty-derived ref tests

> **Status: Done.** Plan A — `OPERATOR_PTY_RECORD` plus the Alacritty-derived ref tests.

**Reference**
- `warp/app/src/terminal/recorder.rs:14-30`: a per-session `PtyRecorder`
  writing raw pty reads to `<state dir>/pty_recordings/<session>` when a
  per-session toggle is on — the debugging tool `TERMINAL.md` §7 wishes for.
- `warp/app/src/terminal/ref_tests/mod.rs:1-2,25,94-160`: "adapted from
  the alacritty_terminal crate" — the same `ref_tests!` macro and 40
  recorded directories (`ref_tests/data/`), replayed through Warp's block
  model with the block started as a background block so shell output lands
  in the output grid (`:145-150`).

**Ours today** — §2.9 "Ours today".

**Gap / Proposal**
Warp already validated the §2.9 approach against a block model, including
the trick of starting a synthetic block before replay so marks are not
required. Adopt §2.9 as written; add the per-session recording toggle in
the pty-host (`OPERATOR_PTY_RECORD`, §2.9) as Warp's `recorder.rs` does per
session rather than globally.

**Priority:** with §2.9 (P2).

### 7.7 Shared sessions: a session viewed live in a browser

> **Status: Not pursued.** With §4.2. The phone already co-views as a secondary mux client; replay covers reattach. No browser share links.

**Reference**
- `warp/app/src/terminal/shared_session/{mod.rs,manager.rs}`: a local
  session can be shared by link; viewers join through the web client
  (`warp/crates/serve-wasm`, `warp_web_event_bus`: the same
  `warp_terminal` crate compiled to wasm renders in the browser); selection
  updates are throttled at 20 ms on the trailing edge so the viewer sees
  the presenter's selection live (`mod.rs:38-42`); `ai_agent.rs` shares an
  agent session.

**Ours today**
- Mobile is exactly a "viewer" of a daemon session, fed bytes (§4.2
  "Ours today"). Warp confirms the shape: the *model* runs where the
  session is, and viewers render from state, not bytes; and that the
  Rust core compiled to wasm is the right client (which is what
  `vt-wasm` is).

**Priority:** covered by §4.2; Warp is a second reference for it.

### 7.8 Warpify: shell integration inside subshells (ssh, docker, su)

> **Status: Not pursued.** The package design forbids reading ssh arguments or running commands in the user's session (`2026-08-29-warp-terminal-package-design.md`); OSC 133 from a remote shell works without setup.

**Reference**
- `warp/app/src/terminal/warpify/mod.rs:25-100`: when a command that
  starts a subshell is detected (`ssh`, `docker exec`, `wsl`, `su`), Warp
  offers to "Warpify" it — inject its bootstrap script into the remote
  shell through the pty so blocks and completions work there; the
  templated block explains what happened; `warp/crates/warp_terminal/src/bootstrap.rs:28-193`
  builds the per-shell init script (`script_for_shell`,
  `init_shell_script_for_shell`, `generate_session_id`).
- Kitty's `kitten ssh` (§5.2) solves the same problem by copying files.

**Ours today** — `packages/terminal/shell/` is injected for local
sessions only (mechanism per `shell/README.md`); an agent that `ssh`es
gets no blocks inside the remote shell.

**Priority:** P4 until remote sessions are a product goal; then Warp's
in-band injection is the reference (no file copy needed).

### 7.9 Alt-screen reporting and typeahead-aware line editor status

> **Status: Not needed.** `LineEditorState` (`Unknown`/`Owned`/`Released`) and `altScreen` on the snapshot already match Warp.

**Reference**
- `warp/app/src/terminal/alt_screen_reporting.rs`, `model/alt_screen.rs`:
  the app reports which program entered the alt screen and for how long
  (telemetry used to prioritise TUI support), and `line_editor_status.rs`
  tracks whether Warp's editor or the child owns input.

**Ours today** — `line_editor.rs` (`Unknown|Owned|Released`) and
`altScreen` in the snapshot; equal. Telemetry is a host decision.

**Priority:** equal.

### 7.10 The Warp-specific pieces we deliberately do not clone

> **Status: N/A.** A do-not-clone list, not a proposal.

| Area | Files | Reason |
|---|---|---|
| AI panes, agent mode, code review, notebooks, drive, billing, onboarding | `warp/app/src/{ai,ai_assistant,code_review,notebooks,drive,billing,onboarding}` | Product; Operator has its own. |
| Completions engine and `command-signatures-v2` corpus | `warp/crates/warp_completer/`, `warp/command-signatures-v2/` | Our line editor has `completions.ts`; the corpus is a licensing/product question, not a terminal one. |
| Input classifier / natural-language detection | `warp/crates/input_classifier/`, `natural_language_detection/` | Operator's prompt goes to the agent, not to a classifier. |
| GPU renderer (`warpui`, `grid_renderer`) | `warp/crates/warpui*`, `warp/app/src/terminal/grid_renderer*` | Already cited where relevant (`TERMINAL.md` §4.11); DOM. |
| Images (iTerm, Kitty) | `warp/crates/warp_terminal/src/model/{iterm_image,kitty,image_map}.rs` | As §1/§3/§4. |
| Vim mode in the editor | `warp/crates/vim/` | §2.13 decision. |
| Remote server / SSH domains | `warp/crates/remote_server/`, `warp/app/src/terminal/remote_tty`, `ssh/` | Remote sessions are not a goal yet (§7.8). |

### Warp section: suggested plan order

1. **7.4** caps → into §1.15; **7.6** → confirms §2.9; **7.5** → §3.14.
2. **7.3** secret redaction (P3, P2 before sharing block text further).
3. **7.1**, **7.7**, **7.8** are references for the remote-agents design, not the terminal plan.

---

## 8. (next project)

Appended when surveyed. Same entry shape; the "Ours today" column must be
re-checked against the tree at that date, since sections above may have landed.

---

## Appendix A. Cross-project dependency graph

```
1.14 integrity ──► everything in vt-core below
1.1  sync output (standalone)
1.2  dirty rows ──► 1.7 find session (screen generation)
1.3  pins ──► 1.4 selection extras
          ──► 1.7 find session ──► 1.8 highlights
          ──► 1.5 reflow-in-place (cursor pin)
1.6  OSC 133 options ──► 1.5 (redraw=, k=s)
1.12 row flags ──► 1.15 hyperlinks (has_hyperlink), 1.6 (semantic)
1.9  READY attach (standalone; touches vt-host + Go)
1.10 paste (standalone; ts/editor + ts/react) ◄── 2.11
1.17 renderer bits (standalone) ◄── 2.12

2.1  sync in parser (standalone; supersedes 1.1 renderer skip)
2.9  ref recordings ──► gate for 2.2
2.2  vte::ansi::Handler ──► 2.8 SGR attrs, 1.15 OSC set, 1.16 XTWINOPS, 2.14 caps
2.5  rotate anchors  ═══ alternative to 1.3 pins
2.6  directional find ──► 2.7 hints (with 1.15 OSC 8 storage, 1.8 highlight tag)
2.3  selection/cursor diff ──► with 1.2
2.4  cursor-carrying reflow ──► with 1.5 decision
2.10 feed budget (standalone; ts/core) ◄── 3.13

3.5  row events + markers ═══ replaces the 1.3 / 2.5 choice ──► 3.6 decorations ──► 3.7 linkifier, 3.12 find hits
3.1  row pool + dirty range ──► with 1.2 / 2.3
3.3  cached char metrics (standalone)
3.2  width cache ──► needs 3.3
3.11 replay modes/wrapped rows ──► with 1.9
3.14 graphemes (vt-core; standalone)
3.10 IME alt-screen (ts/react; standalone)
3.8  selection overlay ──► must keep 4.11 guards
3.9  accessibility (standalone; product timing)

4.1  stable row ids ──► 3.5 markers (Remap only), 4.2, 4.5, blocks without rebasing
4.5  logical lines ──► 1.4/3.8 wrapped copy, 3.7 links, 1.7/2.6 find
4.2  server-owned model + row deltas ══ milestone; subsumes 1.9, 3.11, 1.2 wire side ──► 4.3 predictive echo
4.4  pump coalescing (Go; standalone)
4.7  pattern set ──► 2.7 hints;  4.6 zone query ──► 1.6

5.5  path:line hint type ──► 2.7
5.2  OSC 133 spec citation ──► 1.6;  5.4 option (c) ──► 1.5 decision;  5.7 ──► 4.4
5.3  block timestamps + finished event (ts/renderer-dom; standalone)
5.9  GraphemeBreakTest corpus ──► 3.14;  5.10 dispatch trace ──► 1.14 / 2.9

6.4  link suffix grammar ──► 2.7 / 3.7 / 5.5
6.2  block timestamps, row counts, confidence, cwdForRow ──► 5.3, 3.7 (relative paths), 6.6
6.1  nonce-trusted commands ──► any rerun / quick fix (6.6, 6.10)
6.3a replay with block records ──► with 1.9 / 3.11 (superseded by 4.2 if adopted);  6.3c flow control (Go + mux)
6.5  type-ahead overlay ═══ client-only alternative to 4.3
6.9  compact block output (vt-core/renderer-dom; standalone)

7.4  hyperlink caps ──► 1.15;  7.6 recorder + ref tests ──► 2.9;  7.5 grapheme cursor ──► 3.14
7.3  secret redaction (renderer-dom; needs 4.5 logical lines, 1.8 highlights)
7.1 / 7.7 / 7.8 ──► remote-agents design (out of scope here)
```

## Appendix B. Evidence commands used for this survey

```bash
strings -n 6 /opt/homebrew/Caskroom/claude-code@latest/2.1.273/claude \
  | grep -o '\[?2026[hl]\|\[?1049[hl]\|\[?2004[hl]\|\[?1004[hl]\|\[?1000[hl]\|\[?1006[hl]\|\[>[0-9]*u\|133;[A-D]\|\[?2048' \
  | sort | uniq -c
# → ?2026 h/l, ?1049 h/l, ?1006 h/l, ?1000 h/l; nothing else
```

```bash
grep -rn "2026\|synchronized" packages/terminal/crates/vt-core/src   # no match
grep -rn "hyperlink\|OSC 8" packages/terminal/crates/vt-core/src packages/terminal/ts   # no match
grep -n "^vte" packages/terminal/Cargo.toml                            # vte = "=0.15.0", default-features = false
grep -n "^vte" /Users/omaraly/development/AI/alacritty/alacritty_terminal/Cargo.toml   # vte 0.15.0, features = ["std", "ansi"]
ls ~/.cargo/registry/src/index.crates.io-*/vte-0.15.0/src/ansi.rs     # the shared crate source cited in §2.1/§2.2
grep -rn contrast packages/terminal/ts                                 # no match (§2.12)
```
