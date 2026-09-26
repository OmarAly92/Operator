# Changelog

## Unreleased

- vt-core: a Load older output chunk of more than 999 rows lands every row (`TERMINAL.md` §4.33). The history receiver parsed a chunk into one `ScreenGrid` sized to the chunk's row count, which `ScreenGrid::new` clamps to `MAX_DIMENSION` (1,000), so a full 2,048-row older answer scrolled its oldest 1,049 rows off that screen and landed 999 real rows followed by 1,049 blank ones under the chunk's labels (`seq 1 400000`: rows 198970..199968, then about 1,000 empty rows, then 199969). The receiver now exports each row when its line feed arrives and resets a one-row screen, so it holds O(cols) cells whatever the chunk's row count. Attach-history chunks (512 rows) were never affected. Guards: `tests/cold_ring.rs` `a_full_older_chunk_lands_every_row_with_its_text`, `vtwasm/older_test.go` `TestAFullOlderChunkLandsEveryRowInTheReceivingCore`, `ts/core/src/older-output.test.ts` "lands every row of a full 2,048-row chunk with its text".
- vt-core: Plan 10 review fixes (`TERMINAL.md` §4.36, §4.37, §5). A resize at an owned prompt no longer cuts output printed below the prompt for good (at 10×5, `$ ` then `line0-abcd`, resized to 5 and back, came back as `line0`) and no longer unjoins a line soft-wrapped into the prompt row: it keeps the prompt only when the prompt start is on screen, the row above it does not wrap into it, and every kept row below the shell's own prompt and input line fits the new width; otherwise it takes the pre-Plan-10 path. The prompt row copies are element loops again (native parser 7–16 % faster than `bef8a00ec`). A find session now rescans history after an older-output chunk is prepended (before, a chunk loaded after a front trim reused scanned offsets and was never searched), and the reuse cut list is capped at 1,024 pairs. A resize that truncates rows without reflow (mirror, agent-TUI, alternate screen, scroll region) blanks a wide lead cut from its continuation; the synthetic goldens `resize-no-integration-1..3`, `resize-running-1..3`, `resize-alt-screen-1..3` and `resize-at-prompt-mirror-agent-1` were re-recorded for that only.
- vt-core: a character printed over one half of a wide character blanks the other half (`TERMINAL.md` §4.37). Before, `日日` then `日` at column 1 of a 4-column row left a 3-cell span; a narrow character over a lead kept the orphaned continuation. `ScreenGrid::clear_split_wide` runs before every print path. The edit commands blank a wide character they cut in half too (`ICH`, `DCH`, `ECH`, and `EL`/`ED` from or up to the cursor): before, `日日` then `DCH` at column 2 of a 6-column row left a 3-cell span, and `ECH` or `ICH` on one half left a 2-cell space or a continuation without its lead. The goldens `synthetic-unicode-mix`, `synthetic-edits-styled`, `resize-running-3`, `resize-no-integration-1` and `resize-running-1` were re-recorded for split wide characters only.
- vt-core/shell: a resize at a shell prompt keeps the prompt (roadmap Plan 10, survey §1.5, §2.4, §5.4). While the line editor is `Owned` (OSC 7000 `input-ready`), on the primary screen, in a core that reflows on resize, `TerminalCore::resize` sends the rows above the open block's first row to scrollback (rewrapped there as before) and keeps the prompt rows unrewrapped — cut or padded, a wide character cut in half blanked — with the cursor at the same place, so zsh, bash and fish, which redraw relative to the rows they drew at the old width, overwrite them instead of leaving a stale copy in scrollback (Kitty's behaviour, clean-room from the survey; Ghostty's reflow-and-clear rejected by measurement, `TERMINAL.md` §4.36). Then the newest scrollback rows are pulled back onto the screen so the prompt keeps its distance from the bottom — only rows that commit back to the same bytes and style runs. Row numbers do not change. A command running, the alternate screen, panes without shell integration, agent-TUI mode and the pty-host mirror are unchanged (`tests/resize_goldens.rs`, `tests/parser_goldens.rs`). Content offsets can now be reused after a pull-back, so `Content` counts pull-backs that cut below its end from before the resize (not the ones that only take back rows that resize just evicted, which would reset an open find session on every width change) and the lowest cut since each count, and a find session whose count moved drops only its history hits from the start of the line holding that cut and rescans from there (growing the window with the find bar open no longer rescans all history), and `AttributeMap::prepend_runs` raises its run start past the runs it prepends (an older-output chunk keeps its styles after a full pull-back), and `AttributeMap::truncate_to` takes the content's first byte as its run start when no style key is left below the cut. New: `Content::truncate_to`, `Content::note_reuse`, `Content::lowest_cut_since`, `Content::truncations`, `AttributeMap::truncate_to`, `RowIndex::pop_completed`, `BlockGrid::open_block_ref`; `shell/pty.mjs` `runInPtySegments`. Both wasm artifacts and the daemon must be rebuilt.
- vt-core: Plan 9 review fixes. The printable-run buffer flushes at 4 KiB and releases oversized capacity (one long line no longer pins its size in memory); the unknown-sequence ring records an OSC by its number only when it is 1–5 digits (`OSC ?` otherwise, so payload-first OSCs never leak), reuses one buffer, checks the newest entry first and records at most 128 sequences per feed; an ESC with intermediates (`ESC # 8`, `ESC ( 0`) is no longer dispatched to the screen (`ESC # 8` used to run DECRC).
- vt-core: erase/insert/delete a row slice at a time (roadmap Plan 9 Part C, survey §1.12). `ScreenGrid` erases (`EL`/`ED` on the cursor row, `ECH`) with one slice fill and inserts/deletes characters (`ICH`/`DCH`) with one slice rotation instead of cell by cell; nothing observable changes (`tests/bulk_edits.rs`, the goldens). Row flags (`styled`, `grapheme`) with a plain-row commit path were built and measured with no gain, and are not applied (`TERMINAL.md` §4.35). Both wasm artifacts and the daemon must be rebuilt.
- vt-core/vt-wasm: parser fast path (roadmap Plan 9 Part B, survey §1.11). Printable ASCII is buffered between control sequences and written a row segment at a time (`ScreenGrid::print_ascii_run`), ASCII after an ASCII cell skips the width lookup and the grapheme join, and the join no longer allocates. Nothing observable changes (`tests/parser_goldens.rs`: 53 recordings × 4 configurations, goldens from the tree before). `TerminalCore::unknown_sequences()` / `clear_unknown_sequences()` and `WasmTerminalCore.unknown_sequences()` keep the newest 64 distinct CSI/ESC/DCS/OSC that nothing handled (OSC by number only, text ≤ 48 bytes), for debugging. `ScreenGrid::csi` and `Parser::xtwinops` report whether they handled a sequence. `src/screen.rs`'s print path moved to `src/screen/print.rs`. Both wasm artifacts and the daemon must be rebuilt.
- vt-core/marks/core: Plan 8 review fixes. The attach replay window opens at every `origin=` mark, adopted or not, and excludes the mark's own bytes (also split across feeds; `MarkDecoder::open_osc_bytes`), so a reconnect's replay into a reused core is neither live output nor an agent event (`protocol/SPEC.md` §10.3). `AgentActivityMonitor`: a late subscriber no longer strands earlier listeners on a stale state; each threshold is timed from the latest output; the cursor line is padded in cells, not code points; `prompting` is not reported while the shell's line editor owns the line (panes without shell integration unchanged); `AgentActivitySource` gains optional `lineEditorOwnsLine()`. Agent event and activity listeners run isolated and their failures are thrown together as an `AggregateError` after every listener ran; `feed()`/`tick()` always finish polling, activity and change notification. `compact` drops only lines that are wholly a spinner frame and only runs that redraw the lines immediately before them (`claude-markdown-reply` without agent-TUI mode 101 → 96 lines, was 88). `readBlockOutput`'s `maxLines`: 0 or less gives nothing, `Infinity` no cap, a fraction its floor, 1–2 no longer throw; `NaN` is a `RangeError`. Both wasm artifacts and the daemon must be rebuilt.

- vt-core/vt-wasm/core: agent awareness (roadmap Plan 8, survey §7.1 and §6.9). `vt-core` parses `OSC 777 ; agent-state ; v=1 ; state=<working|waiting|idle|done> [; detail=<percent-encoded UTF-8>] ST` (our wire format, `protocol/SPEC.md` §10, vectors `protocol/agent-vectors/agent-state.json`) into `take_agent_events()`: identical consecutive events collapse, at most 16 wait (oldest dropped), a payload that fills vte's 1,024-byte OSC buffer, a bad percent escape, a repeated key or a version other than 1 is ignored, `detail` is cut to 256 bytes; history chunks, older answers and the attach replay frame (adopted `origin=` to `ready=`) never deliver one; OSC 777 `notify` is unchanged. `live_output_bytes()` counts bytes that reach the live parser (not history rows, gated answers or the replay frame). TS: `TerminalCore.onAgentEvent(listener)`; `agentActivity()` / `onAgentActivity(listener)` report `active` (live output in the last 500 ms), `pollingForIdle`, `idle` (quiet 1,500 ms) or `prompting` (quiet and the cursor line matches VS Code's `detectsHighConfidenceInputPattern`, ported under MIT in `input-patterns.ts`); on the three Claude Code recordings replayed one frame per 100 ms: `active` throughout, `idle` 1,500 ms after the last byte, never `prompting`. `readBlockOutput(id, { compact, maxLines })` returns a block's logical lines; `compact` trims them, drops spinner status lines, blank runs, back-to-back repeats and frames of ≥ 3 lines redrawn within 256 lines (`claude-markdown-reply` without agent-TUI mode 101 → 88 lines; all 60,000 number lines of `claude-long-50k` kept). `vt-core` `lib.rs` moves its mode getters to `core_modes.rs` and `terminal-core.ts` its helpers to `core-checks.ts` (600-line limit). Operator consumes none of this yet. Both wasm artifacts and the daemon must be rebuilt.
- vt-core/marks: Load older output review fixes (`TERMINAL.md` §4.33). `older_chunk` answers nothing when `before` is past the core's completed rows or outside its ring, instead of clamping and labelling its own newest rows as ending at `before` (after a respawn every click prepended the new process's rows; a pane numbered ahead got the same rows under each new label). A process boundary clears `older_state().floor`. `history=` and `older=` marks never reach the live vte parser, across feed splits, so an answer queued inside a live CSI or UTF-8 character no longer prints `1mRED` or `caf��`; the mark scanner restarts on an ESC inside a CSI or after an ESC instead of dropping it. `rewrap_hot` trims stale runs to the rows below the hot window, fixing `StaleRunOutsideRows` after prepended wide rows, a touch and a resize. The cold ring keeps each row's length and width in its one buffer (10 bytes per row, was a separate index that doubled), so its heap stays at its cap (was up to 2× with blank rows). A row larger than the answer budget loads blank instead of stopping every later click. pty-host: an older request the mirror cannot serve is answered `older=<before>`. Both wasm artifacts and the daemon must be rebuilt.
- vt-core/vt-wasm/vt-host/core/react/renderer-dom: messages from programs (roadmap Plan 3, survey §1.15, §1.16, §2.14). OSC 0/2 set `TerminalCore::title()` (control characters dropped, capped at 1,024 bytes like Ghostty); `CSI 22/23 ; 0|2 t` push and pop it on a stack capped at 4,096 that drops the oldest (Alacritty `term/mod.rs:42,2235-2248`, behaviour only). OSC 9 (ConEmu sub-commands 1-12 excluded), OSC 777 `notify` and OSC 99 (single- and multi-part, plain text) queue `ProgramNotification`s (at most 16) for `take_notifications()`; OSC 22 records a CSS pointer shape (`pointer_shape()`, X11 names mapped). A core that answers queries (the pty-host mirror) now also answers `CSI 14/16/18 t`, mode 2048 (report on enable, on resize and on a cell-size change; DECRQM 2048) once `set_cell_pixels` is known, and `OSC 10/11 ; ?` once `set_default_colors` is known. A process boundary clears the title, stack, pointer and 2048. History chunks never change the title or raise notifications. TS: `TerminalCore.title()`, `pointerShape()`, `onProgramMessage()`, and the core calls `HostCapabilities.notify` for each notification; `TerminalSurface` sets `--terminal-pointer-shape` on the surface, takes `onTitle`, and passes the measured cell size as `onGeometry`'s third argument. `.terminal-block, .terminal-alt-surface` use `cursor: var(--terminal-pointer-shape, default)` — no pixel change. Both wasm artifacts and the daemon must be rebuilt.
- vt-core/vt-host/core/renderer-dom/react: very old output (roadmap Plan 7, survey §5.8). A core given `set_cold_ring_bytes(cap)` keeps every row `trim_to` drops, serialised with the replay writer (now `vt_core::style_sgr`, moved from `vt-host`), in a byte-capped ring (payload + 8 bytes per row ≤ cap; oldest dropped; the cap is reserved once on the first spilled row). `older_chunk(before, max_rows, max_bytes)` answers with an ordinary history chunk ending at `before`, from the core's own history when `before` is newer than its front, else from the ring, carrying `cols=<n>` (its widest row); `older_mark()` is `OSC 7000;v=1;older=<floor>`. A receiving core sizes its history screen to `cols=`, marks a chunk wider than itself stale so the lazy rewrap re-lays it, records the floor (`older_state()`, TS `olderOutput()`), and now trims only on a feed that committed a live row, so loaded rows stay until the next one. `Content::trim_front_to` fixes a prepend into a core that had already trimmed, which left a gap before the first retained row (`RowsNotContiguous`). `mountLoadOlder` draws **Load older output** (`TerminalStrings.loadOlderOutput`) at the top of the scrollback when `HostCapabilities.loadOlderOutput` exists and the floor is below the pane's first row; `TerminalSurface` wires it. Operator's mirror keeps 32 MiB per terminal: 77,594,624 bytes wasm with a full ring vs 35,979,264 without (`docs/superpowers/specs/2026-09-25-old-output-measurement.md`); a click fetches ≤ 2,048 rows in 1.382 ms host-side and costs the renderer one full re-export (1,193.38 ms at 200k rows, same order as the first full export). Both wasm artifacts and the daemon must be rebuilt.
- vt-core/vt-wasm/core/renderer-dom: highlight-mark regexes run on vt-core's linear-time `regex-automata` engine (`MarkRegex`, `WasmMarkRegex`, `compileMarkRegex`, `markRegexValid`) instead of JavaScript's backtracking `RegExp`, so a pattern like `(a+)+$` can no longer freeze a pane. Rust regex syntax: lookaround and backreferences are rejected. `disposeMarks` frees compiled marks. Literal marks are unchanged.
- renderer-dom/react: one highlight model (roadmap Plan 5, survey §1.8 and §5.6). `highlights.ts` holds `Highlight { kind, range, colour, rank }` with ranges in stable rows and the priority selection > current find hit > other find hits > user marks; `highlight-painter.ts` is the only code that paints them (row `background-image` layers top first, the same layers clipped onto runs with their own background, and the find row classes); `renderer-highlights.ts` owns the selection, the find hits and the marks and paints from `finishPaint` and on every change without scheduling a repaint. The find bar no longer marks rows: it hands `{ rows, current }` to `FindBarHost.highlightFind` (new, required), which `TerminalSurface` wires to `DomBlockRenderer.setFindHighlights`. User marks: `DomBlockRenderer.setMarks(rules)` and `TerminalSurface`'s `marks` prop take `MarkRule { pattern, regex, colour }` (literal = any case; regex = as written; invalid, empty, zero-width or badly coloured rules are ignored), matched per painted logical line and cached per line, so they survive a trim and a rewrap. Pixels: with nothing highlighted, `bench:feel` is unchanged; selection and find screenshots are byte-identical to before; a row with both a find hit and a mark draws the find tint as a layer above the mark (≤ 1 colour level from the old fill). Links, hints, redaction and prediction stay overlays in `decorations.ts` (they paint above the text). Bench: `affordance-gate.mjs --action select|find|marks`, `--out`, `--compare`; agent-session `?marks=N`; `run.mjs --marks N`.
- shell: `bash.sh`'s percent-encoder now encodes UTF-8 bytes (`é` → `%c3%a9`, `€` → `%e2%82%ac`) instead of code points, and no longer lets accented letters through unencoded; `cmd=`/`cwd=`/`branch=` with non-ASCII text now decode correctly. Works on bash 3.2, which sign-extends bytes above 127.
- shell/vt-core/vt-wasm/core/editor: typing ahead in zsh (roadmap Plan 6, survey §7.2). Keys typed while a command runs still go to the running program (`LineEditor.passthrough` is unchanged). At the first primary prompt after a command, `zsh.sh`'s `line-init` hook reads the input waiting on the tty (`read -t 0 -k 1`), gives it straight back to zle (`zle -U`) and, when it is 1–256 characters with no control character, reports it after `input-ready` as `OSC 7000;v=1;typeahead=<percent-encoded UTF-8>` (`protocol/SPEC.md` §4.5, vector `typeahead.json`). vt-core keeps the report only while the line is owned (`LineEditorTracker::on_typeahead`; dropped on `input-released` and the alternate screen); `TerminalCore.takeTypeahead()` hands it over once. `LineEditor` adopts it only if the user sent keys, IME text or a paste to the running command since the last report (`TypeaheadGate`, `ts/editor/src/typeahead.ts`), appends it to the input box without submitting it, and sends `^U` so zsh's copy is cleared — a report nobody adopts (the daemon's `SendMessage`, the phone, a program faking the mark) leaves the text with the shell, which behaves as before. bash and fish are unchanged (`TERMINAL.md` §4.32 has the evidence). Fixed on the way: `zsh.sh`'s percent-encoder encoded code points (`é` → `%e9`, `€` → `%c`); it now encodes UTF-8 bytes, which also corrects non-ASCII `cmd=`/`cwd=`. Clean-room from the survey's description of Warp's shell-reported typeahead; no Warp code read. Both wasm artifacts and the daemon must be rebuilt; shells started before the daemon is rebuilt keep the old script.
- core/editor/react: paste safety (roadmap Plan 1, survey §1.10 and §2.11). `encodePaste(text, bracketedPaste)` in `ts/editor/src/paste.ts` returns the pty bytes and a verdict. Inside bracketed paste every `ESC[201~`, then every `ESC` and `^C`, is removed (Alacritty's rule, `alacritty/src/event.rs:1369-1410`) and the paste is always safe; before, only the literal `ESC[201~` was removed. Outside bracketed paste, when the child owns the line, `\r\n`/`\n` still become `\r`, and the paste is unsafe with reason `"paste-end"` (it holds `ESC[201~`), `"control"` (a C0 control other than tab, LF or CR) or `"newline"` (Ghostty's `isSafe`, `src/input/paste.zig:160-190`, plus control characters). `deliverPaste` sends a safe paste at once and asks the new optional `HostCapabilities.confirmPaste(preview, reason)` for an unsafe one; `false`, a rejection or a throw sends nothing, and a paste confirmed after its editor or alt-screen handler was torn down is dropped. With no `confirmPaste` the bytes are sent at once, exactly as before. The line editor's own line (a shell prompt) is unchanged and never asks. `pastePreview` shows CR as a line break and controls as `^X`. `LineEditor.setPasteConfirm`, `PasteUnsafeReason` (core, re-exported by react) and `PasteVerdict`/`EncodedPaste`/`PasteConfirm` (editor) are new. Behaviour only: no Ghostty or Alacritty code was copied. No `vt-core` change.
- vt-core/vt-wasm/core/renderer-dom/react: find keeps up. `FindSession` replaces `FindCursor`: `TerminalCore::find_update(&mut session, budget_bytes)` scans settled history once from a `scanned_to` content offset and never again, re-searches the unsettled tail and the live screen only when `generation()` changed, and `find_results` resolves hits (content byte ranges) to stable rows through the row index, so a trim drops only the trimmed hits and a rewrap needs no rescan. A soft-wrapped line is one line to the search; a hard row break is never crossed. Smart case (Alacritty `alacritty_terminal/src/term/search.rs:39-40`): a query without a capital is case-insensitive, for literals and regexes. TS: `findUpdate(id, budgetBytes = FIND_UPDATE_BUDGET_BYTES)` → `{ added, removed, complete }`, `findResults(id)` → `{ blockId, row, endRow, startByte, endByte }` (six words per hit), `findHistoryBytesScanned(id)`; `findStep`, `findIsComplete` and `FIND_STEP_BUDGET` are removed and `findCancel` forgets the session. The find bar updates on every paint while open (new matches appear without retyping), refetches results only when hits were added or removed, keeps the current hit anchored by (stable row, byte), scrolls to the hit's row (`DomBlockRenderer.scrollToRow`, `FindBarHost.scrollToRow`), and has a `.*` regex toggle (`TerminalStrings.findRegexLabel`; an unparseable pattern shows "No matches" with `aria-invalid`). Fixed on the way: the old walker searched only blocks whose every row was in scrollback, so it found nothing in a pane without OSC 133 marks (every Claude Code pane) and nothing still on the screen. Measured on `claude-long-50k` (60,097 history rows, 341,367 history bytes; `npm run bench:find-update`, order alternated): update 1.99/1.59/0.77 ms against a rescan of 3.91/3.81/3.18 ms, same hit count. `find-500k`: p95 36.40 ms, sensitivity 2.08×. Both wasm artifacts and the daemon must be rebuilt.
- renderer-dom: `DEFAULT_FEATURES.attributes` is `"warp"`, so a host that passes no `features` (Operator) paints italic, the five underline styles with SGR 58 colour, strike, overline and hidden, and tags blink; bold and dim are unchanged. Evidence: a new fixture, `bench/agent-session/fixtures/claude-markdown-reply` (Claude Code v2.1.280: a markdown reply, an edit shown as a diff, a Bash call, idle at the prompt), emits italic 5 times, bold 18 and dim 6, and no underline, strike, inverse, blink, hidden, overline or SGR 58. On every Claude Code recording the flip changes exactly two words, both italic, on `claude-markdown-reply` offset-0; `claude-long-50k`, `claude-spinner-10s` and `act-probe` are byte-identical, and `glyph-probe` changes on its `attrs:` row. Feel baselines re-recorded for those two targets. `baselines/*/feature-attributes_warp/` is removed (byte-identical to the new defaults) and `feature-attributes_plain/` holds the old look (byte-identical to the pre-flip defaults). glyph-probe's other five feature views are re-recorded over the new default. The new fixture also gets all six feature views. Pass `{ attributes: "plain" }` for the old behaviour. `cursorContrast` (0 px on every Claude Code recording) and `cursorHollowUnfocused` stay off.
- bench: the agent-session page takes `?css=<stylesheet>` and exposes `repaintLoop(frames)` (a synchronous feed-and-repaint loop timed with `performance.now()`, so it also runs in WebKit); `run.mjs` takes `--css` and `--profile-row`; `layout-trace.mjs` counts forced and render-step layouts per frame from a Chromium trace; `repaint-loop.mjs --browser chromium|webkit` runs the loop. Measurement tooling only; nothing in `ts/` changes.
- react: a `DomBlockRenderer` that `TerminalSurface` rebuilds (its mount effect reruns on a new `onSend`, `onSendRaw` or `core`) now gets the current `features` and `host.secretPatterns` straight after `mount`, read through refs. Before, the features and secret-pattern effects ran only when those props changed, so the rebuilt renderer painted with `DEFAULT_FEATURES` and no redaction. Guards: `TerminalSurface.test.tsx` "keeps the features on a renderer the surface rebuilds for a new onSend" and "keeps the secret patterns on a renderer the surface rebuilds for a new onSend".
- vt-core: a block without a hook `start_ms` is timed from its command's output start (`OSC 133;C`) instead of its prompt (`OSC 133;A`), so `durationMs` no longer counts time spent typing at the prompt and a quick command run after a long pause no longer earns a "finished" notification. A hook `start_ms` still wins; a block whose command never started keeps its prompt's clock. Matches Warp (`app/src/terminal/model/block.rs` `Block::start`, `view.rs` `block_duration`). Both wasm artifacts and the daemon must be rebuilt.
- renderer-dom/react: `DomBlockRenderer.setVisible(boolean | null)` and `TerminalSurface`'s `visible` prop let a host state whether a pane is shown. `onBlockFinished`'s `visible` now follows that fact when set (and is always false while the document is hidden); unset keeps the `rendererVisible` DOM check.
- renderer-dom: a renderer whose host set `setVisible(false)` stops painting. Each frame still drains and ticks the core (the 12 ms feed budget is unchanged) and still reports finished blocks; the DOM, the link underline, hints, redaction masks and the predictive-echo overlay are left alone, `noteSend` is ignored, and the wasm dirty set is discarded. Pending predictions and an in-flight round-trip sample are dropped on the first hidden frame (`RttMeter.cancel()`), not by `setVisible(false)` itself, so a park and show within one frame (a split-layout change) keeps them. A renderer given `setVisible(false)` before `mount` does not paint at mount, and a host without `requestAnimationFrame` gets the same gate. `setVisible(true)` paints the current model synchronously, so the first visible frame is the current tail: a full rebuild once a hidden frame has run (the dirty set it discarded is made up by `catchUp`), an ordinary repaint when the pane is parked and shown again before any hidden frame. Measured cost of a parked pane before this: the same as a visible one (docs/superpowers/specs/2026-09-23-background-pane-cost-measurement.md).
- editor/react: `LineEditor.setVisible(false)` (driven by `TerminalSurface`'s `visible`) skips the per-change render and does it once when shown again. History is still ingested on every change (reading the snapshot the renderer's hidden frame builds anyway), so a command whose block scrolls out of the core while hidden stays in Up-arrow recall.
- renderer-dom: while `document.visibilityState` is `"hidden"` (a minimised or hidden window, where WebKit fires no animation frames) the renderer drains (with a 250 ms budget per tick, `HIDDEN_DRAIN_MS`, since nothing paints and WebKit throttles the timer to ~1/s; animation-frame drains keep the 12 ms `FEED_BUDGET_MS`), ticks and reports finished blocks on a timer instead of animation frames, and paints the visible pane once the document is shown. Before, a hidden window parsed nothing and fired no `onBlockFinished` until it was shown again.
- editor/react: `EditorHost.onDraftChange(draft)` and `TerminalSurface`'s `onDraftChange` prop report the line editor's unsent text each time it changes (typing, submit, `setText`), and an empty draft when the editor is disposed holding one, so a host can tell whether a pane holds a draft.
- core/renderer-dom/react: hover file-path detection is rebuilt from Operator's own rules (`TERMINAL.md` §4.23). `HostCapabilities.resolvePath` is replaced by `resolveFirstPath(candidates, cwd)`: the path provider sends every span through the hovered cell — up to four whitespace-separated words, longest first, broken at quotes, brackets, `|;,=` and the glyphs Claude Code draws — in one call, and the host answers the first that exists. VS Code's suffix grammar strips `file:12:3`, `file(12,3)`, `"file", line 12` and the rest of its table, plus GitHub's `#L12`; trailing sentence punctuation is dropped; `a/`/`b/` diff prefixes are also tried bare; a directory links only without a line suffix and only for path-like text. At most `MAX_PATH_CANDIDATES = 20` per hover. Found paths are cached per line text; misses are not. `LinkProvider` now receives the hovered offset, and `LogicalLineView.offsetAt(row, cell)` maps a cell to it. Claude Code's banner `~/…` working directory now underlines.
- renderer-dom: `DEFAULT_FEATURES` turns on `graphemes` and `widthCache` together, so a host that passes no `features` (Operator) now prints by grapheme cluster and corrects fallback glyphs toward the core's cell widths. Glyph-probe drift, both off → both on: emoji sequence -37.92 → +0.27 px, CJK -19.94 → +1.09 px, wide emoji +3.08 → +0.08 px (`EVIDENCE.json` → `EVIDENCE-graphemes_widthCache.json`); `widthCache` alone would take the emoji sequence to -50.89 px, which is why the two move as one. On the Claude Code recordings the only pixel changes are on rows carrying `⎿` (the text after it moves 6 px left, onto the grid) and `⏵⏵` (the row moves 2 px right); `bench/agent-session/baselines/*/feature-graphemes_false_widthCache_false/diff-offset-*.png` crop each one, and the feel baselines are re-recorded to match. The agent-session harness now puts its core in the renderer's resolved grapheme mode instead of only when `graphemes` is listed, so the feel gate shows the defaults the app shows. Spinner DOM nodes per paint 73.11 → 75.98 (the `[data-terminal-width]` span on each corrected cluster); row nodes per paint, `feed()`, `feed()`+`snapshot()` and renderer memory unchanged. Pass `{ graphemes: false, widthCache: false }` for the old behaviour.
- core/renderer-dom/editor/react: predictive local echo. While the median of the last eight measured input round trips stays at or above a host-supplied threshold, a printable keystroke paints a dim provisional glyph at the cursor in the terminal's own font, on either surface: the primary screen, where keys reach a child that owns the line through the line editor's passthrough (`EditorHost.beforePassthrough`, new) — this is where Claude Code runs; its recordings never enter the alternate screen — and the alternate screen's own key handler. A prediction is retired the moment real output moves the cursor past it: kept out if the cell under it holds the typed character (a trailing blank the row export trimmed counts as a space), dropped with echo suppressed if it holds anything else, so a masked or transformed echo never leaves the plaintext glyph beside it. Suppression lifts only when a later keystroke is seen echoed as typed. An unconfirmed prediction expires on its own timer after `max(500 ms, 2 × median RTT)`, with or without further output. A round trip is sampled only when the cursor has moved since the keystroke, so a spinner frame that returns the cursor to the prompt is not taken for the echo; samples up to 2 s are kept, and a keystroke left unanswered that long is replaced by the next one. Cells are compared by cell column, not string index (`cellString`, new, in `clusters.ts`), so a wide character earlier on the line does not break confirmation. An overlay in the decoration layer (`.terminal-prediction`) — no row, snapshot or model is touched. Off unless the host sets `HostCapabilities.predictiveEcho.thresholdMs`; skipped for pastes, control and modified keys, IME composition and anything outside printable ASCII. `TerminalSurface` tears predictions down with the renderer.
- vt-core: SGR 3, 4 and `4:0-5`, 5/6, 8, 9, 21, 23, 24, 25, 28, 29, 53, 55, 58 and 59 are parsed into `CellStyle.attrs` (`Attrs`, ten bits after `alacritty_terminal/src/term/cell.rs` `Flags`) and `CellStyle.underline`; the style run grows to five words `(end, fg, bg, attrs, underline)` — `STYLE_RUN_WORDS = 5` in `vt-wasm` and `@operator/terminal-core`. The renderer still paints words 0–2 only, so nothing is drawn differently until `RendererFeatures.attributes` is `"warp"`. The mirror re-emits the attributes in the attach replay, and the Alacritty `sgr`, `underline`, `colored_underline` and `clear_underline` recordings now assert a `styles.json` derived from Alacritty's own grid.
- vt-core: `CSI > Ps m` (XTMODKEYS, `modifyOtherKeys`) and `CSI ? Ps m` no longer reach the SGR path — vte dispatches `m` by its intermediates (`vte-0.15.0/src/ansi.rs:1678-1694`), so `apply_sgr` now runs only with none. Claude Code sends `CSI > 4;2 m` at startup, which was being read as SGR 4 + SGR 2: on `development` that dimmed the banner and the prompt band of every Claude Code session (the `claude-spinner-10s` feel baseline is re-recorded in this commit for that reason — the mascot, title and warning line were painted at 55 % opacity), and on this branch it also underlined every coloured run and split the style map 300-fold (87,023 entries against 260). Guard: `sgr_attributes.rs::a_private_m_sequence_is_not_sgr`, `…_in_a_history_chunk_is_not_sgr_either`, `the_claude_code_recording_carries_no_attribute_bits`.
- bench: `glyph-probe.mjs` measures the `|` marker against cell 39 — `CSI 40 G` is a 1-based column — so every `EVIDENCE*.json` is re-generated without the one-cell bias the first run carried; the two verdicts (box drawing not needed, width cache needed) are unchanged. The alt-screen row fingerprint also includes `widthCache`, so toggling it repaints alt rows.
- renderer-dom: `RendererFeatures.attributes: "warp"` paints italic, underline (single/double/curly/dotted/dashed with SGR 58 colour), strikethrough, overline and hidden from the style word's attribute bits, and tags blink with `terminal-blink` without animating it (Warp ignores SGR 5). Default `"plain"` paints exactly as before. Side-by-side: `bench/agent-session/baselines/*/feature-attributes_warp/`. Neither Claude Code fixture uses any of these attributes: under `"warp"` both render byte-identical to their baselines (the underlines first reported here were the XTMODKEYS parse bug below, not Claude Code).
- vt-core: `TerminalCore::set_grapheme_clusters(true)` (TS `setGraphemeClusters`, `RendererFeatures.graphemes`) prints by extended grapheme cluster: ZWJ sequences, emoji modifier sequences and regional-indicator pairs occupy two cells, VS16 widens a text-presentation base, and the rewrap measures the same clusters (`unicode-segmentation` 1.13.3 + `unicode-width` 0.2.2, both Unicode 17). Default off: scalar widths as before. The Unicode `GraphemeBreakTest` corpus (`tests/grapheme/`, via kitty) runs against the splitter. In both modes a zero-width scalar after a space now rewraps with the space instead of starting a row. Evidence: glyph probe `seqDriftPx` -37.92 → +4.22 px (`baselines/glyph-probe/EVIDENCE.json` → `EVIDENCE-graphemes.json`); the residual is the emoji glyphs' own advance widths, which `widthCache` removes (+0.27 px with both on).
- vt-core/vt-wasm/core: the snapshot exports `spanRanges`/`cellSpans` (`CELL_SPAN_WORDS = 3`: row-relative byte `start`, `end`, cell `width`) for every cluster that is not a single width-1 scalar, on the primary and the alternate screen, through the incremental export like the style runs. Nothing reads them yet. This buffer and the five-word style run are always exported: renderer core wasm memory at the 60k-row fixture is 11,730,944 bytes (~11.2 MiB) against 9,371,648 bytes (~8.9 MiB) on `development` measured the same way on the same day — the 5/3 stride on 60k style runs plus the 16-byte `CellStyle`, well under the 128 MiB budget. The style-run *count* is unchanged (260 entries, 60,277 runs on that fixture).
- renderer-dom: selection and copy place cells from the snapshot's exported cell spans instead of a hand-written width table (`cell-width.ts`, deleted). Copying across a code point the table misclassified (`🚀` U+1F680 was one cell in the table and is two in the core) now yields the characters under the selection. With `graphemes` on, a ZWJ sequence or a flag is one two-cell cluster to the selection too.
- renderer-dom: `RendererFeatures.cursorContrast` inverts the cursor (foreground box, background-coloured glyph) when the cell's background is within contrast 1.5 of the cursor colour (Alacritty `MIN_CURSOR_CONTRAST`); `cursorHollowUnfocused` draws a hollow block while the surface has no focus (Ghostty `cursor.zig`), reported by `TerminalSurface` through `DomBlockRenderer.setFocused`. Both default off. Side-by-side: `baselines/glyph-probe/feature-cursorContrast/`, `feature-cursorHollowUnfocused/`.
- core/editor/react: IME composition draws its in-progress text at the cursor cell (`.terminal-composition-view`, underlined like Warp's marked text) in both the transcript editor and the alternate screen, and the composed text is sent once from the textarea's settled value a tick after `compositionend` (xterm.js `CompositionHelper`), so Chromium's early `compositionend` no longer sends a partial string. Manual Japanese-IME check: pending — not yet performed by the user.
- renderer-dom: `RendererFeatures.widthCache` measures each non-ASCII cluster once per font variant (xterm.js `WidthCache`) and applies `letter-spacing` so a fallback glyph wider or narrower than its cells no longer shifts the rest of the row; on the glyph probe the emoji / CJK rows go from +3.08 / -19.94 px of drift to +0.08 / +1.09 px (`EVIDENCE.json` → `EVIDENCE-widthCache.json`). Default off. It corrects glyphs toward the *core's* cell widths, so with `graphemes` off it squeezes emoji sequences into the scalar-mode cells the core assigned them (`❤️` is one cell there, so it gets `letter-spacing: -10px`; the probe's `seq:` row reads -50.89 px with `widthCache` alone) and with `graphemes` on the same row lands at +0.27 px (`EVIDENCE-graphemes_widthCache.json`). Chromium shapes a ZWJ sequence across the per-cluster spans (the follow-on spans measure 0 px), so the split itself is not the cause. Use `widthCache` with `graphemes`.
- renderer-dom: the transcript scroller sets `overscroll-behavior-y: none`, so it stops hard at both edges like Warp's block list (`app/src/terminal/block_list_viewport.rs`, `scroll_position_for_delta` clamps the new top to `[0, max_scroll_top]` and there is no elastic region) instead of rubber-banding past the bottom.
- renderer-dom: an elastic overscroll past the top or bottom edge (WebKit rubber-band, where `scrollTop` overshoots its range) no longer has the sticky-bottom and scroll-anchor writes snapping the position back every frame, which vibrated the pane at the end of the scroll.

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
- vt-core/vt-wasm/core: the snapshot exports one `rowWrapped` byte per row (1 when the next row continues this one — a printer soft-wrap or a rewrap cut), through the incremental export like `rowIndents`; a soft-wrapped screen row now exports its trailing blanks the way `scrollback::commit_row` already committed them, so the break space survives the join. `TerminalCore.logicalLines(range)` joins the flagged rows (WezTerm `mux/src/pane.rs` `LogicalLine`).
- renderer-dom: copying a selection joins a soft-wrapped line into one line — the first `TERMINAL.md` §5 gap. The last row of a line is still trimmed of trailing spaces; a wrapped row is joined verbatim. Rows a reopened pane received as history are never flagged (`history.rs:193`), so a line the mirror wrapped before the reopen still copies as several lines.
- vt-core/vt-wasm/core: `OSC 8 ; params ; URI ST` is parsed in `Parser::osc_dispatch` and interned per core in a `HyperlinkRegistry` with Warp's two rules (`warp/crates/warp_terminal/src/model/grid/hyperlink_registry.rs`): at most `MAX_DISTINCT_ENTRIES = 4096` distinct links, URIs over `MAX_URI_BYTES = 2083` refused, entries never reclaimed. `CellStyle` gains `link: u16` (0 = none; SGR 0 keeps it, a process boundary drops it) in the padding after `attrs`, so it stays 16 bytes; the style run grows to six words `(end, fg, bg, attrs, underline, link)` — `STYLE_RUN_WORDS = 6`, `STYLE_WORD_LINK = 5` — and the snapshot exports the URI table as `linkRanges`/`linkText`, appended incrementally. `TerminalCore.linkUri(id)` resolves an id. The table is outside `Limits { bytes }` — `trim_to` and `memory_stats` weigh content plus styles only — so a core can hold up to ~17 MB of interned URIs above its budget for its lifetime, since `HyperlinkRegistry` stores each URI twice (the `by_link` map key and the `by_id` vec element; corrected from an earlier ~8.5 MB single-copy estimate in Task 10's measurement); the two caps are what bounds it. Nothing paints or opens a link yet.
- vt-host/vt-core: the attach replay, `vt_render_styled` and every history chunk bracket a linked run with `OSC 8 ;; <uri> ST` … `OSC 8 ;; ST`, and a reopened pane's history receiver interns those into its own registry, so links survive a reattach and a reopen like colours do.
- vt-core/vt-wasm/core: a block missing the hook's `start_ms`/`end_ms` is stamped from the clock `feed_at` was last called with — open and close for OSC 133 blocks, first feed and process boundary for the synthetic blocks of a markless pane (Kitty `window.py` `handle_cmd_end`, VS Code `ITerminalCommand.timestamp`). `BlockRecord`/`BlockView` carry `startedAtMs`/`finishedAtMs` (`BLOCK_RECORD_WORDS = 18`). A shell without the bootstrap hook therefore shows a duration in its block header where it showed none. The TS core now feeds and ticks with `Date.now()` so its stamps are epoch milliseconds like the Go mirror's and the hook's.
- renderer-dom/react: `DomBlockRenderer.onBlockFinished` / the `onBlockFinished` prop of `TerminalSurface` fire `{ id, exitCode, durationMs, visible }` when a block that was running on the previous paint is finished or abandoned; `visible` says whether the pane was in layout, not `inert`, and the document visible. The host decides what to do with it.
- renderer-dom/react: hovering the transcript underlines the link under the pointer and swaps the arrow for a hand only there (Warp `app/src/terminal/view.rs`); a press with the platform modifier (Cmd on macOS, Ctrl elsewhere) opens it — `HostCapabilities.openLink` for a URL or an OSC 8 hyperlink, the new optional `HostCapabilities.openPath(path, line?, column?)` for a file. Links are found per hovered logical line by providers in priority order (xterm.js `src/browser/Linkifier.ts`): OSC 8 runs, then xterm.js's strict `https?` grammar, then — only when the host supplies `HostCapabilities.resolveFirstPath(candidates, cwd)` — a file path through the hovered cell, as the hover file-path entry above describes. Nothing paints without a pointer; the feel gate is unchanged. Side-by-side: `bench/agent-session/baselines/act-probe/affordance-hover/`.
- bench: the `act-probe` fixture (URLs, an OSC 8 link, a soft-wrapped URL, `path:line` references, token-shaped strings, diff headers, hashes) and `npm run bench:affordances -- --action <name>`, which drives one affordance through the harness page and records screenshots beside the probe's baseline, never diffed.
- renderer-dom/react: Ctrl+Shift+Space (WezTerm's QuickSelect chord, `wezterm-gui/src/commands.rs`) labels every match of the package's rule set on the visible logical lines — WezTerm's `quickselect.rs` patterns minus IPFS, with Kitty's `path:line` (`kittens/hints/marks.go` `default_linenum_regex`) taking precedence over the bare path — with prefix-free labels from WezTerm's `compute_labels_for_alphabet`, assigned to the bottom-most match first and shared by identical texts. Typing a label emits `onHint({ ruleId, text, path?, line? })` and closes the mode; a character narrows the set, Backspace un-types, Escape or any other key cancels. While the mode is active no key reaches the pty. The chord costs one key: Ctrl+Shift+Space used to encode `\x00` like Ctrl+Space (`encodeKey`'s control branch ignores Shift), and the shifted form no longer reaches the child. Plain Ctrl+Space, the emacs set-mark readline binds, is unaffected and pinned by `encode-key.test.ts`. Side-by-side: `bench/agent-session/baselines/act-probe/affordance-hint/`.
- renderer-dom/react: with `HostCapabilities.secretPatterns` set, every match on a visible logical line is painted as a masked highlight and masked cell-for-cell with `*` (Warp's placeholder, `crates/warp_terminal/src/model/grid/grid_handler.rs`) in every text the renderer *reads* — the copy path, word selection, the linkifier, hint mode and the block-output source — so a token cannot reach the clipboard or a ticket. A leading capture group at the match start stays visible ("Bearer [redacted]"), overlapping matches merge, and a secret split by a soft wrap is masked on both rows. A plain click reveals one match until the next feed. Default off: with no patterns nothing is compiled, masked or painted. The row DOM keeps the original text (the mask is a paint plus a read transform), so a screen reader and the accessibility tree still see it — recorded in `TERMINAL.md` §5. Side-by-side: `bench/agent-session/baselines/act-probe/affordance-redact/`.
- Operator (host side, no package change): `resolvePath` is a Tauri command (`resolve_path`) that canonicalises a candidate against the block's cwd or the session's workspace path and answers only for a file that exists; `openPath` hands the resolved file to the OS opener (`open_path`), which opens the user's editor — the line and column the package passes are accepted and not yet used, because `tauri-plugin-opener` takes no editor argument. `secretPatterns` comes from the daemon's own built-in shapes over `GET /api/v1/redaction/patterns` behind a Settings switch, default off, so the desktop masks exactly what the daemon redacts. `onHint` opens a path in the editor, a URL in the browser and copies anything else; `onBlockFinished` raises one desktop notification for a command that took at least 10 s and finished while its pane was out of sight (Kitty's `notify_on_cmd_finish unfocused 10.0`). `SlashOutput` and the agent-handoff terminal tail now pass through `redact.Text` like the block-event log already did.
- renderer-dom: `maskedTextRows` now overrides `rowSpans` alongside `rowText`, dropping a span whose cluster started inside a masked range and shifting a later span by the byte delta the mask introduced. A secret containing a non-ASCII byte sequence (reachable through the daemon's `password:`/`token:`/`secret:`/`api_key:` pattern) shrinks or grows the row's UTF-8 byte length when replaced by ASCII `*`; the stale, unshifted spans this used to leave behind pointed `cellSlice` at the wrong byte offset for any wide or multi-scalar cluster later in the same row, corrupting the copy of the row's tail.


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
