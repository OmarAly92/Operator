# Terminal Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shift+click extends a selection (from its anchor, or from the last plain click when there is none) across blocks and across rows scrolled out of view; Alt-drag selects a rectangle whose copy is one slice per row; and a selection stays on the same text, and copies the same text, when the pane changes width — in shell panes and in agent (Claude Code) panes.

**Architecture:** Everything lives in the renderer's own selection (`ts/renderer-dom/src/renderer-selection.ts`, grid points in stable rows) and its gesture (`ts/react/src/use-surface-input.ts`); the browser selection is never used. A width change reaches the selection through the core's existing row events: each selection point also keeps a *line anchor* (the stable row of its logical line's first row plus the cell offset into that line), the rewrap `remap` moves the anchor's line start, and the point is re-resolved against the new rows on the next read. Rows after the rewrapped ones (an agent's live frame, a kept prompt) move by a new `remapEnd` pair that vt-core reports outside `Delta`, so no golden changes. Rectangles are a fourth `SelectionKind` whose resolved range carries `rectangle: true`; the painter and the copy path read it.

**Tech Stack:** Rust 1.96.0 (`vt-core`, `vt-wasm`, `vt-host`), wasm32 + wasm-bindgen, Go ≥ 1.25.7 (pty-host tests only), TypeScript 5.9.3 + vitest 4.1.8 + jsdom, React 19.2.7, Playwright 1.60.0 (benches).

**Spec:** docs/terminal/2026-09-27-terminal-wishlist.md (items 1, 6) and survey §1.3, §1.4, §2.5, §3.8 (`docs/terminal/2026-09-19-terminal-reference-survey.md:327`, `:402`, `:1467`, `:2297`); `TERMINAL.md` end to end — §1 (pipeline), §2 (stable rows, stale runs, delta and row events), §3 (hard rules), §4.2–4.4 (rewrap, hanging indent), §4.10 (agent-TUI resize), §4.11/§4.13/§4.31 (selection and the highlight model), §4.36 (prompt resize keeps prompt rows on screen), §5 ("Claude Code runs on the primary screen"), §6 (verify and ship).

## Global Constraints

- Work in a worktree on branch `terminal/wave1-selection` cut from `development`; never commit to `master`, never bump a version, never force-push, never `git stash` in the shared checkout.
- Commits name explicit paths (`git add <path> …`); never `git add -A`, `git add .` or `git commit -a`.
- Every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- No comments in new code (Rust, TypeScript, tests, scripts).
- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no Operator name, path or concept under `crates/`, `ts/`, `bench/` test data.
- Never call `document.getSelection()` in terminal code; `.terminal-block` stays `user-select: none`.
- Licences: Warp (AGPL-3.0) is read for behaviour only and cited by file:line; no Warp code is adapted. Ghostty (MIT), Alacritty (Apache-2.0/MIT) and xterm.js (MIT) are cited for behaviour only. No attribution file is added.
- No file under `packages/terminal` may exceed 600 lines (`npm run check:boundaries`, `scripts/check-boundaries.mjs:42,188`). Planned sizes: `crates/vt-core/src/parser.rs` 537 → 557, `crates/vt-core/src/lib.rs` 597 → 598, `crates/vt-core/src/remap_end.rs` new 5, `crates/vt-wasm/src/lib.rs` 581 → 582, `ts/core/src/terminal-core.ts` 599 → 593, `ts/core/src/row-events.ts` new 32, `ts/renderer-dom/src/dom-block-renderer.ts` 598 → 598 (no net line may be added to it), `renderer-selection.ts` 78 → 150, `selection-anchor.ts` new 70, `selection-model.ts` 51 → 75, `selection-text.ts` 47 → 72, `selection-view.ts` 148 → 157, `selection-geometry.ts` 62 → 69, `ts/react/src/use-surface-input.ts` 341 → 344, `selection-gesture.ts` 59 → 63.
- `vt-core` changes are live only when **both** wasm artifacts are rebuilt (`TERMINAL.md` §6): the renderer's (`npm run build:wasm -- --force`, gitignored) and the host mirror's (`vt_host.wasm`, committed). The mirror's behaviour does not change.
- `Delta` is not changed. `tests/parser_goldens.rs` and `tests/resize_goldens.rs` and every `crates/vt-core/tests/goldens/*.golden` stay byte-identical; if one fails, the change is wrong.
- `ts/renderer-dom` and `ts/react` tests import `@operator/terminal-core` and `@operator/terminal-renderer-dom` from `dist/` (`ts/renderer-dom/package.json` `"main": "./dist/index.js"`): after any change under `ts/core` or `ts/renderer-dom`, run `npm run build:ts` in `packages/terminal` before running a downstream package's tests.
- Use absolute paths in every command (`TERMINAL.md` §6). `$WT` below is `/Users/omaraly/development/AI/Operator-wave1-selection`.
- `bench:feel` must show zero pixel diff; committed baselines under `packages/terminal/bench/agent-session/baselines/**` are never committed from this branch.
- New `TERMINAL.md` section number: **§4.51**.
- Every claim in docs cites `file:line` or says "not known".

## Review Focus

1. **Shift+click after the anchor's rows were trimmed from scrollback.** Expected: the selection runs from the block's first retained row; if the anchor's whole block was trimmed away, the Shift+click places a new caret and selects nothing. Pinned in Task 6 by `selection-extend.test.ts` "extends from the first retained row when the caret's row was trimmed" and "places a fresh caret when the caret's block was trimmed away".
2. **A rectangle whose edges cut wide characters or hanging-indent rows.** Expected: a cluster is copied when its first cell is inside the box (the stream selection's `cellSlice` rule), never half a character; an indented row is cut by its painted cells. Pinned in Task 8 by `selection-text.test.ts` "keeps a wide character that starts inside the box and drops one that starts before it" and "cuts an indented row by the cells it paints".
3. **A width change when the selected rows are older than the eager rewrap window** (`HOT_ROWS = 2_000`, `TERMINAL.md` §2 "Stale runs"): they rewrap only later, when touched, in a second remap. Expected: the same text before the resize, after it, and after the lazy pass. Pinned in Task 4 by `selection-rewrap.test.ts` "keeps a selection in rows older than the eager rewrap window through the later lazy pass".
4. **A width change while the alternate screen is up.** Alternate-screen rows are not stable rows, so a primary-screen remap must not move an alternate-screen selection; a real resize of a full-screen program clears it (the program repaints, as in Warp). Pinned by `renderer-selection.test.ts` "leaves an alternate-screen selection alone when the primary screen's rows move" (Task 4) and `TerminalSurface.selection.test.tsx` "clears an alternate-screen selection on a real resize" (Task 5).
5. **A selection on an agent pane's live frame** (Claude Code runs in agent-TUI mode on the primary screen; a width change truncates the frame in place and rewraps only scrollback, `TERMINAL.md` §2 "Modes", §4.10). Expected: the point stays on the same frame row. Needs `remapEnd` (Tasks 1–2). Pinned in Task 4 by `selection-rewrap.test.ts` "keeps a selection on an agent's live frame when the rows above it rewrap".

---

## Design decisions (decided; the executor does not re-decide them)

### D1 — Rectangle modifier: Alt (Option) held at press, on every platform

- Warp: `SelectionType::from_mouse_event` makes a rectangle on **Cmd+Option** on macOS and **Ctrl+Alt** elsewhere (`/Users/omaraly/development/AI/warp/crates/warpui_core/src/text/mod.rs:42-54`); the block list uses it behind `FeatureFlag::RectSelection` (`app/src/terminal/block_list_element.rs:1588-1592`), and so does the alternate screen (`app/src/terminal/alt_screen/alt_screen_element.rs:273`). A Cmd+Option drag is not a block-selection drag (`block_list_element.rs:4690-4695`). Warp joins a rectangle's rows with `\n` (`app/src/terminal/model/blocks/selection.rs:1024-1094`).
- macOS terminals: Ghostty uses **Option alone** on macOS and Ctrl/Super+Alt elsewhere (`/Users/omaraly/development/AI/ghostty/src/surface_mouse.zig:98-103`); xterm.js uses **Alt** (`/Users/omaraly/development/AI/xterm.js/src/browser/services/SelectionService.ts:607-611`); Alacritty uses **Ctrl** (`/Users/omaraly/development/AI/alacritty/alacritty/src/input/mod.rs:660-673`); Terminal.app's Option-drag and iTerm2's Cmd+Option-drag are from memory, not verified here.
- The wishlist says "Alt-drag" (item 1). **Chosen: Alt held at mousedown makes a rectangle, with or without Cmd/Ctrl.** That is the user's wording and Ghostty/xterm.js's rule, and it is a superset of Warp's chord on both platforms (Cmd+Option and Ctrl+Alt both hold Alt), so a Warp user's habit works too.
- Conflicts checked in our code, none blocking:
  - Links open on Cmd-click (macOS) / Ctrl-click, and `linkModifierHeld` already refuses Alt (`ts/react/src/selection-gesture.ts:53-59`), so Cmd+Option and Ctrl+Alt never open a link.
  - Alt-click already skips revealing a masked secret (`ts/react/src/use-surface-input.ts:166`); an Alt-drag over a secret keeps it masked.
  - Hint mode is keyboard-only (`isHintChord`, `selection-gesture.ts:48-51`); block navigation and jump-to-bottom ignore Alt/Shift keys (`ts/renderer-dom/src/block-nav.ts:50`, `jump-to-bottom.ts:175`).
  - Operator's Alt-click on `<a href>` opens the system browser (`frontend/src/renderer/lib/external-link-policy.ts:20-35`, bound on `document` in `routes/_shell.tsx:129`); the terminal creates no `<a>` elements (`grep 'createElement("a")' packages/terminal/ts/*/src` finds none), so it never fires on a transcript.
  - With mouse reporting on, Alt is passed to the program (`use-surface-input.ts:113-136`, only Shift bypasses at `:122`). A rectangle there needs **Shift+Alt**; when both are held the rectangle wins over Shift+click extension.
  - On Linux desktops Alt+drag is often a window-manager move; Ctrl+Alt still works because it holds Alt.

### D2 — Shift+click extends; Shift+click with no selection starts at the last plain click

- Warp does **not** extend text on Shift+click in the block list: Shift+click range-selects *blocks* (`app/src/terminal/view.rs:18407-18413`) and Shift+drag is a block-selection drag (`block_list_element.rs:4690-4695`). Operator has no block selection, so Shift goes to text, following Ghostty: Shift+press with a selection continues the previous gesture to the pointer, keeping the selection kind, and a Shift+press inside the multi-click interval does not extend (`/Users/omaraly/development/AI/ghostty/src/Surface.zig:3852-3882`). Shift already bypasses mouse reporting (`use-surface-input.ts:122`), so Shift+click extends inside `vim`/`htop` too.
- Anchor = the selection's `head` (the press point of the gesture that made it); the new `tail` is the clicked cell. A word or line selection extended by Shift+click grows by words or lines (the kind is kept; `resolveRange` expands both ends, `selection-model.ts:44-51`).
- `event.detail >= 2` with Shift is an ordinary double/triple click (Ghostty's click-interval rule).
- "Last plain click" (the *caret*) = the point of the latest non-Shift press that went to the selection: a click-release (recorded by `selectionClear(caret)`), a drag start or a double/triple click (recorded by `selectionBegin`). A press reported to a program, a link click and a press on chrome record nothing. The caret has its own line anchor, so it survives a rewrap; a caret in a block that no longer exists is replaced by the Shift+click point (no selection).
- A Shift+drag keeps extending while the button is down.

### D3 — A selection survives a width change (user decision; Warp clears it)

- Today `TerminalSurface.tsx:330` clears the selection on every grid change. Warp does the same: `BlockList::resize` calls `clear_selection()` when rows or columns change (`app/src/terminal/model/blocks.rs:2296-2301`), and the alternate screen clears too (`app/src/terminal/model/alt_screen.rs:125-127`). The wishlist's owner asked for survival (item 6), which is Ghostty's behaviour (tracked selection pins, survey §1.3). **Primary-screen selections survive; alternate-screen selections are still cleared on a real resize** (the program redraws its screen, the rows are not stable rows, and Warp clears there too).
- Mechanism (survey §2.5's "rotate" variant, no `PinSet`): each point keeps a `LineAnchor { blockId, lineRow, cells, side }` — `lineRow` is the stable row of the first row of its logical line (walked back over `rowWrapped`), `cells` the cell offset into the line's text (hanging indents excluded). A rewrap never moves content bytes and every line start stays a row start (`TERMINAL.md` §4.2, `row_index.rs:317-336` maps each old row to the new row holding its start), so `remap` moves `lineRow` exactly, and walking the new rows by cell width finds the same text. The anchors are computed on the first read after a selection change (every paint reads it, `renderer-highlights.ts:44-56`), so a mousemove costs nothing extra; a remap that arrives before any read falls back to moving the point's row only.
- Rows **after** the rewrapped ones — an agent's live frame, a Plan 10 prompt kept on screen — move by the change in the completed-row count, which the TypeScript side cannot know: the pairs cover only old completed rows (`parser.rs:188-211`), and later commits make `historyRows` unreliable. vt-core records `(old_end, new_end)` beside the pending remap and `TerminalCore::take_remap_end()` hands it out **outside `Delta`** (the goldens hash `format!("{delta:?}")`, `tests/golden_support/mod.rs:117-118`, so a new `Delta` field would change every golden). vt-wasm appends it as the last pair of its remap buffer; `ts/core` pops it into `RowEvent.remapEnd`, so `RowEvent.remap` and the scroll anchor (`scroll-tracker.ts:88-91,170-183`) see exactly what they see today.
- Not used: content byte offsets as anchors (would need a new per-row export through the §2 checklist); Ghostty-style pins in vt-core (survey §1.3, P2, a much larger change).
- A rectangle keeps its rows only when the remap moves them as a block (every row maps to the previous row's target plus one); otherwise it is dropped, since a rewrapped table has no rectangle that means the same thing.

### D4 — Hanging-indent rows copy what is painted (bug fixed on the way)

`row-builder.ts:37,50-51` pads a rewrapped continuation row by `indent * cellWidth`; `measureRow` takes the padded element's left edge (`selection-view.ts:133-139`) and `pointAtFromRows` counts columns from it (`selection-geometry.ts:41-43`), so a point's column includes the indent. `selectedText` slices the row text, which has no indent (`selection-text.ts:15-17,32-41`), and `wordCellRange` looks up the word at the raw column (`selection-model.ts:33-38`). Copy and double-click on every rewrapped bullet continuation (Claude Code's `⎿`, `-`, `●` lists after a width change) are therefore shifted by the indent. `TextRows` gains an optional `rowIndent`; copy, word expansion, rectangles and line anchors subtract it. Hover links and hint labels on such rows use the same column space and are out of scope (see the report).

### D5 — Shell panes and agent panes

Both mount `TerminalSurface` on the primary-screen block list (`TERMINAL.md` §1, `TerminalPane.tsx` passes `agentTui={kind === "worker"}`); Claude Code never enters the alternate screen (`TERMINAL.md` §5, "Claude Code runs on the primary screen", guarded by `TerminalSurface.test.tsx` "keeps Claude Code on the primary screen…"). So Shift+click, rectangles and width-change survival all apply to agent panes; the only agent-specific case is the live frame (Review Focus 5). The alternate screen (vim, less, htop) shares the same `RendererSelection` with block id `alt` (`selection-view.ts:8,54-66,115-119`): Shift+click and rectangles work there; width-change survival does not apply (D3).

---

## File Structure

| File | Task | Responsibility |
|---|---|---|
| `packages/terminal/crates/vt-core/src/parser.rs` (modify) | 1 | record where the rows after a rewrap went (`pending_remap_end`) |
| `packages/terminal/crates/vt-core/src/remap_end.rs` (new), `src/lib.rs` (modify) | 1 | `TerminalCore::take_remap_end` |
| `packages/terminal/crates/vt-core/tests/remap_end.rs` (new) | 1 | the end pair, its composition, its absence |
| `packages/terminal/crates/vt-wasm/src/lib.rs` (modify) | 2 | append the end pair to the remap buffer |
| `packages/terminal/ts/core/src/row-events.ts` (new) + test | 2 | read a row event from wasm; `remapStableRow` |
| `packages/terminal/ts/core/src/{terminal-core.ts,types.ts,index-browser.ts,terminal-core.test.ts}` (modify) | 2 | `RowEvent.remapEnd`, export |
| `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` (rebuilt) | 2 | mirror wasm after the vt-core change |
| `packages/terminal/ts/renderer-dom/src/{selection-text.ts,selection-model.ts,selection-view.ts}` (modify) + tests, `selection-indent.test.ts` (new) | 3 | `rowIndent`; copy and word selection by painted cells |
| `packages/terminal/ts/renderer-dom/src/selection-anchor.ts` (new) + test | 4, 8 | line anchors, remapping, rectangle shape check |
| `packages/terminal/ts/renderer-dom/src/renderer-selection.ts` (modify) + `renderer-selection.test.ts` (new) | 4, 6, 8 | follow row events; caret; extend; rectangle drop rule |
| `packages/terminal/ts/renderer-dom/src/{renderer-wiring.ts,dom-block-renderer.ts}` (modify) | 4, 6 | deliver whole row events; renderer API |
| `packages/terminal/ts/renderer-dom/src/selection-rewrap.test.ts` (new) | 4 | real-core width-change tests |
| `packages/terminal/ts/react/src/TerminalSurface.tsx` (modify), `TerminalSurface.selection.test.tsx` (modify) | 5 | stop clearing a primary-screen selection on resize |
| `packages/terminal/ts/renderer-dom/src/selection-extend.test.ts` (new) | 6 | real-core extend and trim cases |
| `packages/terminal/ts/react/src/use-surface-input.ts` (modify), `TerminalSurface.shift-click.test.tsx` (new) | 7, 9 | Shift+click and Alt-drag gestures |
| `packages/terminal/ts/renderer-dom/src/{selection-geometry.ts,highlight-painter.ts}` (modify) + tests, `selection-rectangle.test.ts` (new) | 8 | rectangle range, paint, copy |
| `packages/terminal/ts/react/src/selection-gesture.ts` (modify) + test, `TerminalSurface.rectangle.test.tsx` (new) | 9 | `rectangleModifierHeld` |
| `packages/terminal/bench/selection-extras-gate.mjs` (new), `packages/terminal/package.json` (modify) | 10 | Playwright gate: Shift+click across scrolled rows, Alt-drag, resize |
| `TERMINAL.md`, `packages/terminal/CHANGELOG.md`, survey, roadmap spec | 11 | §4.51, status lines, deferred app checks |

---

### Task 0: Worktree, installs and baselines

**Files:** none changed.

**Interfaces:**
- Consumes: nothing.
- Produces: the worktree `$WT`, branch `terminal/wave1-selection`, `$HOME/wave1-goldens.sha256`, the recorded test counts, the `bench:feel` decision (committed baselines or a local recording).

- [ ] **Step 1: Create the worktree**

```bash
cd /Users/omaraly/development/AI/Operator
git fetch origin
git worktree add /Users/omaraly/development/AI/Operator-wave1-selection -b terminal/wave1-selection development
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && npm ci
cd /Users/omaraly/development/AI/Operator-wave1-selection/frontend && npm ci
```
Expected: `Preparing worktree (new branch 'terminal/wave1-selection')`; both `npm ci` end with `added … packages`.

- [ ] **Step 2: Build and record the test counts**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal
npm run build:wasm -- --force 2>&1 | tail -1 && npm run build:ts 2>&1 | tail -1
for p in core renderer-dom react editor completions; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Tests  "); done
npm run check:boundaries 2>&1 | tail -1
```
Expected: `build-wasm: … ready`; five `Tests  N passed (N)` lines — write the five numbers into the task report; `boundary check passed`.

- [ ] **Step 3: Pin the goldens**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/crates/vt-core/tests/goldens && shasum -a 256 *.golden > "$HOME/wave1-goldens.sha256" && wc -l < "$HOME/wave1-goldens.sha256"
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && cargo test --release -p vt-core --test parser_goldens --test resize_goldens 2>&1 | grep "test result"
```
Expected: a line count (65 at planning time); two `test result: ok.` lines.

- [ ] **Step 4: Bench baselines**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal
npm run bench:selection
npm run bench:feel 2>&1 | tail -3
```
Expected: `PASS selection survived N repaints`. If `bench:feel` reports zero diff, Task 12 compares against the committed baselines. If it reports a diff on the unmodified tree, run `npm run bench:feel -- --record`, note "local baseline" in the report, and restore at the end of Task 12 with `git checkout -- packages/terminal/bench/agent-session/baselines && git clean -fdq packages/terminal/bench/agent-session/baselines`. Nothing is committed in this task.

---

### Task 1: vt-core reports where the rows after a rewrap went

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/parser.rs:67` (field), `:111` (init), `:188-211` (`note_remap`), after `:237` (end of `take_delta`)
- Create: `packages/terminal/crates/vt-core/src/remap_end.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs:27-28` (module list)
- Test: `packages/terminal/crates/vt-core/tests/remap_end.rs` (new)

**Interfaces:**
- Consumes: `Parser::note_remap(&mut self, map: &[usize])` — `map` holds, for each old completed row, the new row holding its start, then the new completed-row count (`row_index.rs:317-336`, `:127-152`).
- Produces: `pub fn take_remap_end(&mut self) -> Option<(u64, u64)>` on `Parser` and on `TerminalCore`: `(old_end, new_end)` in stable rows — every stable row `r >= old_end` that existed before the pending rewraps is now `r - old_end + new_end`. `Some` exactly when a remap is pending; composed across rewraps like `pending_remap`; `Delta` unchanged.

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/crates/vt-core/tests/remap_end.rs`:

```rust
mod common;

use vt_core::{Limits, TerminalCore};

fn agent_core() -> TerminalCore {
    let mut core = TerminalCore::with_limits(20, Limits::rows_only(100)).unwrap();
    core.resize(20, 3);
    core.set_agent_tui_mode(true);
    core.feed(b"aaaaaaaaaabbbbbbbbbbcccccccccc\r\ntail\r\nx\r\nzeta");
    core.take_delta();
    core.take_remap_end();
    core
}

#[test]
fn a_rewrap_reports_where_the_rows_after_the_rewrapped_ones_went() {
    let mut core = agent_core();
    assert_eq!(core.history_rows(), 2);
    assert_eq!(core.snapshot().unwrap().row_text(4), "zeta");
    core.resize(40, 3);
    let delta = core.take_delta();
    assert_eq!(delta.remap, Some(vec![(0, 0), (1, 0)]));
    assert_eq!(core.take_remap_end(), Some((2, 1)));
    assert_eq!(core.snapshot().unwrap().row_text(3), "zeta");
    common::check(&core);
}

#[test]
fn two_rewraps_before_a_take_compose_into_one_end() {
    let mut core = agent_core();
    core.resize(40, 3);
    core.resize(10, 3);
    core.take_delta();
    assert_eq!(core.take_remap_end(), Some((2, 3)));
    assert_eq!(core.snapshot().unwrap().row_text(5), "zeta");
    common::check(&core);
}

#[test]
fn output_without_a_width_change_has_no_remap_end() {
    let mut core = agent_core();
    core.feed(b"\r\nmore\r\n");
    core.take_delta();
    assert_eq!(core.take_remap_end(), None);
}

#[test]
fn taking_the_end_leaves_nothing_behind() {
    let mut core = agent_core();
    core.resize(40, 3);
    core.take_delta();
    assert!(core.take_remap_end().is_some());
    assert_eq!(core.take_remap_end(), None);
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && cargo test -p vt-core --test remap_end 2>&1 | tail -5`
Expected: compile error `no method named 'take_remap_end' found for struct 'TerminalCore'`.

- [ ] **Step 3: Implement**

In `crates/vt-core/src/parser.rs`, after line 67 (`pending_remap: Option<Vec<(u64, u64)>>,`) add:

```rust
    pending_remap_end: Option<(u64, u64)>,
```

After line 111 (`pending_remap: None,`) add:

```rust
            pending_remap_end: None,
```

Replace `note_remap` (lines 188-211) with:

```rust
    fn note_remap(&mut self, map: &[usize]) {
        let Some((&new_len, old_rows)) = map.split_last() else {
            return;
        };
        let origin = self.trimmed_total;
        let through = |stable: u64| -> u64 {
            let Some(row) = stable.checked_sub(origin).map(|row| row as usize) else {
                return stable;
            };
            match old_rows.get(row) {
                Some(&new) => new as u64 + origin,
                None => (row - old_rows.len() + new_len) as u64 + origin,
            }
        };
        let end = (origin + old_rows.len() as u64, origin + new_len as u64);
        self.pending_remap_end = Some(match self.pending_remap_end.take() {
            None => end,
            Some((first, mid)) => (first, through(mid)),
        });
        let pairs: Vec<(u64, u64)> = old_rows
            .iter()
            .enumerate()
            .map(|(old, &new)| (old as u64 + origin, new as u64 + origin))
            .collect();
        self.pending_remap = Some(match self.pending_remap.take() {
            None => pairs,
            Some(previous) => previous
                .into_iter()
                .map(|(first, mid)| {
                    let last = mid
                        .checked_sub(origin)
                        .and_then(|index| old_rows.get(index as usize))
                        .map_or(mid, |&new| new as u64 + origin);
                    (first, last)
                })
                .collect(),
        });
    }
```

(The `pending_remap` half is the existing code unchanged, so `Delta.remap` and the goldens stay identical.)

Directly after the closing brace of `take_delta` (line 237) add:

```rust

    pub fn take_remap_end(&mut self) -> Option<(u64, u64)> {
        self.pending_remap_end.take()
    }
```

Create `crates/vt-core/src/remap_end.rs`:

```rust
impl crate::TerminalCore {
    pub fn take_remap_end(&mut self) -> Option<(u64, u64)> {
        self.parser.take_remap_end()
    }
}
```

In `crates/vt-core/src/lib.rs`, between line 27 (`pub mod program;`) and line 28 (`pub mod row_index;`) add:

```rust
mod remap_end;
```

- [ ] **Step 4: Run the tests and the goldens**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal
cargo test -p vt-core --test remap_end 2>&1 | grep "test result"
cargo test --release -p vt-core --test parser_goldens --test resize_goldens --test delta --test lazy_rewrap 2>&1 | grep "test result"
cd crates/vt-core/tests/goldens && shasum -a 256 -c --quiet "$HOME/wave1-goldens.sha256" && echo goldens-unchanged
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && cargo fmt --check && cargo clippy -p vt-core --all-targets -- -D warnings 2>&1 | tail -1 && wc -l crates/vt-core/src/parser.rs crates/vt-core/src/lib.rs
```
Expected: `test result: ok. 4 passed`; four `test result: ok.` lines; `goldens-unchanged`; clippy `Finished …`; `parser.rs` ≤ 600, `lib.rs` 598.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection
git add packages/terminal/crates/vt-core/src/parser.rs packages/terminal/crates/vt-core/src/remap_end.rs packages/terminal/crates/vt-core/src/lib.rs packages/terminal/crates/vt-core/tests/remap_end.rs
git commit -m "feat(vt-core): report where the rows after a rewrap went (take_remap_end)

Kept outside Delta so the parser and resize goldens are unchanged.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The end pair reaches TypeScript as `RowEvent.remapEnd`

**Files:**
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs:166` (after `take_delta`), `:193-199` (remap buffer)
- Create: `packages/terminal/ts/core/src/row-events.ts`, `packages/terminal/ts/core/src/row-events.test.ts`
- Modify: `packages/terminal/ts/core/src/types.ts:80`, `packages/terminal/ts/core/src/terminal-core.ts:30` (drop the `RowEvent` import), `:382-392` (`emitRowEvents`), imports; `packages/terminal/ts/core/src/index-browser.ts:74`; `packages/terminal/ts/core/src/terminal-core.test.ts:168` and a new test after `:177`
- Rebuilt: `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`

**Interfaces:**
- Consumes: `TerminalCore::take_remap_end()` (Task 1).
- Produces: `type RowEvent = Readonly<{ trimmed: number; remap: ReadonlyArray<readonly [number, number]> | null; remapEnd: readonly [number, number] | null }>`; `export function remapStableRow(row: number, event: RowEvent): number` from `@operator/terminal-core`; `takeRowEvent(inner: WasmTerminalCore): RowEvent | null` (internal to `ts/core`).

- [ ] **Step 1: Write the failing tests**

Create `packages/terminal/ts/core/src/row-events.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { remapStableRow } from "./row-events";
import type { RowEvent } from "./types";

const event: RowEvent = { trimmed: 0, remap: [[10, 10], [11, 10], [12, 11]], remapEnd: [13, 12] };

describe("remapStableRow", () => {
	it("moves a rewrapped row to the row that now holds its start", () => {
		expect(remapStableRow(11, event)).toBe(10);
		expect(remapStableRow(12, event)).toBe(11);
	});
	it("shifts a row after the rewrapped ones by the change in their count", () => {
		expect(remapStableRow(13, event)).toBe(12);
		expect(remapStableRow(20, event)).toBe(19);
	});
	it("leaves a row before the rewrapped ones alone", () => {
		expect(remapStableRow(4, event)).toBe(4);
	});
	it("leaves every row alone for a trim", () => {
		expect(remapStableRow(20, { trimmed: 3, remap: null, remapEnd: null })).toBe(20);
	});
	it("shifts every row from the end when no completed row was rewrapped", () => {
		expect(remapStableRow(2, { trimmed: 0, remap: null, remapEnd: [0, 3] })).toBe(5);
	});
});
```

In `packages/terminal/ts/core/src/terminal-core.test.ts`, change line 168 to:

```ts
		expect(events).toEqual([{ trimmed: 1, remap: null, remapEnd: null }]);
```

and after the closing `});` of that test (line 177) add:

```ts

	it("reports where the rows after the rewrapped ones went", () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100, rows: 3 });
		core.setAgentTuiMode(true);
		const events: RowEvent[] = [];
		core.onRowEvents((event) => events.push(event));
		core.feed(new TextEncoder().encode("aaaaaaaaaabbbbbbbbbbcccccccccc\r\ntail\r\nx\r\nzeta"));
		core.snapshot();
		core.resize(40, 3);
		core.snapshot();
		expect(events.at(-1)).toEqual({ trimmed: 0, remap: [[0, 0], [1, 0]], remapEnd: [2, 1] });
		expect(remapStableRow(4, events.at(-1)!)).toBe(3);
	});
```

and add `import { remapStableRow } from "./row-events";` to that file's imports.

- [ ] **Step 2: Run them to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/core && npx vitest run src/row-events.test.ts src/terminal-core.test.ts 2>&1 | tail -8`
Expected: FAIL — `Failed to resolve import "./row-events"`.

- [ ] **Step 3: Implement**

`crates/vt-wasm/src/lib.rs`: after line 166 (`let delta = self.core.take_delta();`) add

```rust
        let remap_end = self.core.take_remap_end();
```

and replace lines 193-199 with:

```rust
        if let Some(pairs) = delta.remap {
            self.remap.clear();
            for (old, new) in pairs.into_iter().chain(remap_end) {
                self.remap.push(checked_u32_from_u64(old)?);
                self.remap.push(checked_u32_from_u64(new)?);
            }
        }
```

Create `packages/terminal/ts/core/src/row-events.ts`:

```ts
import type { WasmTerminalCore } from "../wasm/vt_core.js";
import type { RowEvent } from "./types.js";
import { getMemory, u32View } from "./wasm-runtime.js";

export function takeRowEvent(inner: WasmTerminalCore): RowEvent | null {
	const trimmed = inner.row_events_trimmed();
	const remapLen = inner.remap_len();
	if (trimmed === 0 && remapLen === 0) return null;
	const words = u32View(getMemory(), inner.remap_ptr(), remapLen);
	const pairs: Array<readonly [number, number]> = [];
	for (let index = 0; index + 1 < words.length; index += 2) pairs.push([words[index]!, words[index + 1]!]);
	inner.clear_row_events();
	const remapEnd = pairs.pop() ?? null;
	return { trimmed, remap: pairs.length > 0 ? pairs : null, remapEnd };
}

export function remapStableRow(row: number, event: RowEvent): number {
	const remap = event.remap ?? [];
	let low = 0;
	let high = remap.length - 1;
	while (low <= high) {
		const mid = (low + high) >> 1;
		const [from, to] = remap[mid]!;
		if (from === row) return to;
		if (from < row) low = mid + 1;
		else high = mid - 1;
	}
	const end = event.remapEnd;
	return end && row >= end[0] ? row - end[0] + end[1] : row;
}
```

`ts/core/src/types.ts` line 80 becomes:

```ts
export type RowEvent = Readonly<{ trimmed: number; remap: ReadonlyArray<readonly [number, number]> | null; remapEnd: readonly [number, number] | null }>;
```

`ts/core/src/terminal-core.ts`: remove `RowEvent,` from the type import list (line 30); add `import { takeRowEvent } from "./row-events.js";` after line 19 (`import { budgetNow, … } from "./core-checks.js";`); replace `emitRowEvents` (lines 382-392) with:

```ts
	private emitRowEvents(): void {
		const event = takeRowEvent(this.inner);
		if (!event) return;
		for (const listener of [...this.rowEventListeners]) listener(event);
	}
```

`ts/core/src/index-browser.ts`: after line 74 (`export { joinLogicalLine, type LogicalLine } from "./logical-lines.js";`) add:

```ts
export { remapStableRow } from "./row-events.js";
```

- [ ] **Step 4: Rebuild both wasm artifacts and run everything that reads them**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal
cargo fmt --check && cargo clippy -p vt-wasm --all-targets -- -D warnings 2>&1 | tail -1
npm run build:wasm -- --force 2>&1 | tail -1 && npm run build:ts 2>&1 | tail -1
(cd ts/core && npx vitest run 2>&1 | grep -E "Tests  ")
(cd ts/renderer-dom && npx vitest run 2>&1 | grep -E "Tests  ")
cargo build --release -p vt-host --target wasm32-unknown-unknown 2>&1 | tail -1
cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd /Users/omaraly/development/AI/Operator-wave1-selection/backend && go test ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -4
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && npm run check:boundaries 2>&1 | tail -1 && wc -l ts/core/src/terminal-core.ts
```
Expected: clippy `Finished`; `ts/core` count = Task 0 count + 6; `renderer-dom` count unchanged from Task 0 (the scroll anchor still sees the same `remap`); Go `ok` for every package (if only `TestProcessEnvironmentLetsOverridesWin` fails, it is the pre-existing failure in `TERMINAL.md` §5); `boundary check passed`; `terminal-core.ts` 593.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection
git add packages/terminal/crates/vt-wasm/src/lib.rs packages/terminal/ts/core/src/row-events.ts packages/terminal/ts/core/src/row-events.test.ts packages/terminal/ts/core/src/types.ts packages/terminal/ts/core/src/terminal-core.ts packages/terminal/ts/core/src/terminal-core.test.ts packages/terminal/ts/core/src/index-browser.ts backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
git commit -m "feat(terminal-core): RowEvent.remapEnd and remapStableRow

vt-wasm appends the end pair to its remap buffer; takeRowEvent pops it, so
RowEvent.remap and the scroll anchor are unchanged. vt_host.wasm rebuilt.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Copy and double-click on a hanging-indent row use the painted cells

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/selection-text.ts:4-13` (`TextRows`), `:31-41` (loop)
- Modify: `packages/terminal/ts/renderer-dom/src/selection-model.ts:9-11` (types), `:26-51` (`expand`, `resolveRange`)
- Modify: `packages/terminal/ts/renderer-dom/src/selection-view.ts:13-19` (`resolveSelectionView`), `:56-65` (alt rows), `:69-103` (block rows)
- Test: `selection-text.test.ts` (append), `selection-model.test.ts` (append inside `describe("resolveRange")`), `selection-indent.test.ts` (new)

**Interfaces:**
- Consumes: `snapshot.rowIndents: Uint16Array` indexed by flat row (`row-builder.ts:37`).
- Produces: `TextRows.rowIndent?(blockId: string, row: number): number`; `export type RowIndent = (blockId: string, row: number) => number` in `selection-model.ts`; `resolveRange(state, order, rowText, rowSpans = () => [], rowIndent: RowIndent = () => 0)`. Selection cells stay in painted space (indent included); text lookups subtract the indent.

- [ ] **Step 1: Write the failing tests**

Append to `packages/terminal/ts/renderer-dom/src/selection-text.test.ts`:

```ts

const indented: TextRows = {
	blockIds: ["i"],
	firstRow: () => 0,
	rowCount: () => 2,
	rowText: (_id, row) => ["- aaaa bbbb ", "cc dd ee"][row] ?? "",
	rowSpans: () => [],
	rowWrapped: (_id, row) => row === 0,
	rowIndent: (_id, row) => (row === 1 ? 2 : 0),
};

describe("selectedText over a hanging indent", () => {
	it("copies the painted cells of an indented row, not cells shifted by the indent", () => {
		expect(selectedText({ start: { blockId: "i", row: 1, cell: 5 }, end: { blockId: "i", row: 1, cell: 7 } }, indented)).toBe("dd");
	});
	it("copies nothing from a range that covers only the indent", () => {
		expect(selectedText({ start: { blockId: "i", row: 1, cell: 0 }, end: { blockId: "i", row: 1, cell: 2 } }, indented)).toBe("");
	});
	it("joins an indented continuation to its line", () => {
		expect(selectedText({ start: { blockId: "i", row: 0, cell: 2 }, end: { blockId: "i", row: 1, cell: ROW_END } }, indented)).toBe("aaaa bbbb cc dd ee");
	});
});
```

Append inside `describe("resolveRange", …)` of `selection-model.test.ts` (before its closing `});` at line 51):

```ts
	it("expands a word on an indented row to the cells where that word is painted", () => {
		const text = (_id: string, row: number) => (row === 1 ? "cc dd ee" : "");
		const indent = (_id: string, row: number) => (row === 1 ? 2 : 0);
		const range = resolveRange({ head: at("0", 1, 5), tail: at("0", 1, 5), kind: "word" }, order, text, () => [], indent)!;
		expect(range.start).toEqual({ blockId: "0", row: 1, cell: 5 });
		expect(range.end).toEqual({ blockId: "0", row: 1, cell: 7 });
	});
	it("expands a click inside the indent to the row's first word", () => {
		const text = (_id: string, row: number) => (row === 1 ? "cc dd ee" : "");
		const indent = (_id: string, row: number) => (row === 1 ? 2 : 0);
		const range = resolveRange({ head: at("0", 1, 0), tail: at("0", 1, 0), kind: "word" }, order, text, () => [], indent)!;
		expect(range.start.cell).toBe(2);
		expect(range.end.cell).toBe(4);
	});
```

Create `packages/terminal/ts/renderer-dom/src/selection-indent.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore, type TerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "./dom-block-renderer";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");
beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function rowOf(core: TerminalCore, text: string): number {
	const snapshot = core.snapshot();
	for (let row = 0; row * 2 < snapshot.rows.length; row += 1) {
		if (decoder.decode(snapshot.content.subarray(snapshot.rows[row * 2]!, snapshot.rows[row * 2 + 1]!)) === text) return snapshot.firstStableRow + row;
	}
	throw new Error(`no row reads ${JSON.stringify(text)}`);
}

describe("a rewrapped bullet continuation", () => {
	it("copies and double-clicks the word painted under the pointer", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100, rows: 2 });
		core.feed(encoder.encode("- aaaa bbbb cc dd ee\r\nx\r\ny\r\n"));
		core.resize(12, 2);
		const host = document.createElement("div");
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		const blockId = host.querySelector<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		const row = rowOf(core, "cc dd ee");
		expect(core.snapshot().rowIndents[row - core.snapshot().firstStableRow]).toBe(2);
		renderer.selectionBegin({ blockId, row, column: 5, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId, row, column: 6, side: "right" });
		expect(renderer.selectedText()).toBe("dd");
		renderer.selectionBegin({ blockId, row, column: 5, side: "left" }, "word");
		expect(renderer.selectedText()).toBe("dd");
		renderer.dispose();
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/renderer-dom && npx vitest run src/selection-text.test.ts src/selection-model.test.ts src/selection-indent.test.ts 2>&1 | tail -12`
Expected: FAIL — `expected ' e' to be 'dd'`-style mismatches in `selection-text.test.ts` ("copies the painted cells…" gets `e`, "covers only the indent" gets `cc`), `resolveRange` tests get `cell: 3`/`cell: 0`, and `selection-indent.test.ts` gets `e` then `""`.

- [ ] **Step 3: Implement**

`selection-text.ts` — `TextRows` (lines 4-13) gains one member after `rowWrapped`:

```ts
	rowIndent?(blockId: string, row: number): number;
```

and lines 31-41 (the row loop body) become:

```ts
		for (let row = fromRow; row <= toRow; row += 1) {
			const indent = rows.rowIndent?.(blockId, row) ?? 0;
			const from = Math.max((index === first && row === range.start.row ? range.start.cell : 0) - indent, 0);
			const to = index === last && row === range.end.row ? Math.max(range.end.cell - indent, 0) : ROW_END;
			const text = rows.rowText(blockId, row);
			const spans = rows.rowSpans(blockId, row);
			const joins = row < toRow && rows.rowWrapped(blockId, row);
			if (joins) {
				pending += to === ROW_END && from === 0 ? text : cellSlice(text, spans, from, to === ROW_END ? Number.MAX_SAFE_INTEGER : to);
				continue;
			}
			lines.push(pending + cut(text, spans, from, to));
			pending = "";
		}
```

`selection-model.ts` — after line 10 (`export type RowSpans …`) add:

```ts
export type RowIndent = (blockId: string, row: number) => number;
```

replace `expand` and `resolveRange` (lines 26-51) with:

```ts
function expand(point: SelectionPoint, kind: SelectionKind, rowText: RowText, rowSpans: RowSpans, rowIndent: RowIndent): [Boundary, Boundary] {
	if (kind === "line") {
		return [
			{ blockId: point.blockId, row: point.row, cell: 0 },
			{ blockId: point.blockId, row: point.row, cell: ROW_END },
		];
	}
	if (kind === "word") {
		const indent = rowIndent(point.blockId, point.row);
		const word = wordCellRange(rowText(point.blockId, point.row), rowSpans(point.blockId, point.row), Math.max(point.column - indent, 0));
		return [
			{ blockId: point.blockId, row: point.row, cell: word.start + indent },
			{ blockId: point.blockId, row: point.row, cell: word.end + indent },
		];
	}
	const boundary = boundaryOf(point);
	return [boundary, boundary];
}

export function resolveRange(state: SelectionState, order: BlockOrder, rowText: RowText, rowSpans: RowSpans = () => [], rowIndent: RowIndent = () => 0): SelectionRange | null {
	const [headStart, headEnd] = expand(state.head, state.kind, rowText, rowSpans, rowIndent);
	const [tailStart, tailEnd] = expand(state.tail, state.kind, rowText, rowSpans, rowIndent);
	const start = compareBoundary(headStart, tailStart, order) <= 0 ? headStart : tailStart;
	const end = compareBoundary(headEnd, tailEnd, order) >= 0 ? headEnd : tailEnd;
	if (compareBoundary(start, end, order) >= 0) return null;
	return { start, end };
}
```

`selection-view.ts` — line 17 becomes:

```ts
	const range = resolveRange(selection, order, rows.rowText, rows.rowSpans, rows.rowIndent ?? (() => 0));
```

in the alt branch (after line 62 `rowWrapped: () => false,`) add:

```ts
			rowIndent: () => 0,
```

in the block branch (after the `rowWrapped` member, line 94) add:

```ts
		rowIndent: (id, row) => {
			const block = byId.get(id);
			if (!block) return 0;
			const flat = row - base;
			if (flat < block.firstRow || flat >= block.firstRow + block.rowCount) return 0;
			return snapshot.rowIndents[flat] ?? 0;
		},
```

`maskedTextRows` spreads `...rows` (`redaction.ts:129-133`), so `rowIndent` reaches the copy path unchanged.

- [ ] **Step 4: Run the tests**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/renderer-dom && npx vitest run 2>&1 | grep -E "Tests  |FAIL"
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && npm run build:ts 2>&1 | tail -1 && (cd ts/react && npx vitest run 2>&1 | grep -E "Tests  |FAIL")
```
Expected: renderer-dom = Task 0 count + 6, no `FAIL`; react count unchanged.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection
git add packages/terminal/ts/renderer-dom/src/selection-text.ts packages/terminal/ts/renderer-dom/src/selection-model.ts packages/terminal/ts/renderer-dom/src/selection-view.ts packages/terminal/ts/renderer-dom/src/selection-text.test.ts packages/terminal/ts/renderer-dom/src/selection-model.test.ts packages/terminal/ts/renderer-dom/src/selection-indent.test.ts
git commit -m "fix(renderer-dom): copy and word selection on a hanging-indent row use the painted cells

A rewrapped continuation row is padded by its indent, so a selection column
counts the indent; copy and word expansion now subtract it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The selection follows a rewrap

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/selection-anchor.ts`, `selection-anchor.test.ts`, `renderer-selection.test.ts`, `selection-rewrap.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/renderer-selection.ts:1-78` (whole file)
- Modify: `packages/terminal/ts/renderer-dom/src/renderer-wiring.ts:1`, `:10`, `:26`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:143`

**Interfaces:**
- Consumes: `remapStableRow`, `RowEvent` (Task 2); `TextRows.rowIndent` (Task 3); `cellCount(text, spans)` (`clusters.ts:61-64`); `ALT_BLOCK_ID` (`selection-view.ts:8`).
- Produces:
  - `selection-anchor.ts`: `type LineAnchor = Readonly<{ blockId: string; lineRow: number; cells: number; side: SelectionSide }>`; `anchorOf(point: SelectionPoint, rows: TextRows): LineAnchor | null`; `pointOf(anchor: LineAnchor, rows: TextRows): SelectionPoint | null`; `followAnchor(anchor: LineAnchor, event: RowEvent): LineAnchor`; `followPoint(point: SelectionPoint, event: RowEvent): SelectionPoint` (alt points unchanged).
  - `RendererSelection.followRows(event: RowEvent): void`.
  - `RendererWiringHost.onRowEvents: (event: RowEvent) => void` (replaces `onRowRemap`).

- [ ] **Step 1: Write the failing tests**

Create `packages/terminal/ts/renderer-dom/src/selection-anchor.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { anchorOf, followAnchor, followPoint, pointOf } from "./selection-anchor";
import type { TextRows } from "./selection-text";
import { ALT_BLOCK_ID } from "./selection-view";

function rowsOf(lines: readonly string[], wrapped: ReadonlySet<number> = new Set(), indents: ReadonlyMap<number, number> = new Map(), firstRow = 0): TextRows {
	return {
		blockIds: ["b"],
		firstRow: () => firstRow,
		rowCount: () => lines.length,
		rowText: (_id, row) => lines[row - firstRow] ?? "",
		rowSpans: () => [],
		rowWrapped: (_id, row) => wrapped.has(row),
		rowIndent: (_id, row) => indents.get(row) ?? 0,
	};
}

describe("line anchors", () => {
	it("measures a point from the first row of its logical line", () => {
		const rows = rowsOf(["alpha beta ", "gamma delta"], new Set([0]));
		expect(anchorOf({ blockId: "b", row: 1, column: 3, side: "left" }, rows)).toEqual({ blockId: "b", lineRow: 0, cells: 14, side: "left" });
	});
	it("finds the same cell after the line is cut differently", () => {
		const before = rowsOf(["alpha beta gamma delta"]);
		const anchor = anchorOf({ blockId: "b", row: 0, column: 11, side: "left" }, before)!;
		const after = rowsOf(["alpha beta ", "gamma delta"], new Set([0]));
		expect(pointOf(anchor, after)).toEqual({ blockId: "b", row: 1, column: 0, side: "left" });
	});
	it("leaves out a continuation row's hanging indent", () => {
		const rows = rowsOf(["- aaaa bbbb ", "cc dd ee"], new Set([0]), new Map([[1, 2]]));
		const anchor = anchorOf({ blockId: "b", row: 1, column: 5, side: "left" }, rows)!;
		expect(anchor.cells).toBe(15);
		expect(pointOf(anchor, rows)).toEqual({ blockId: "b", row: 1, column: 5, side: "left" });
	});
	it("keeps a point past a wrapped row's text on that row", () => {
		const rows = rowsOf(["abc", "def"], new Set([0]));
		expect(anchorOf({ blockId: "b", row: 0, column: 9, side: "right" }, rows)!.cells).toBe(2);
	});
	it("has no anchor for the alternate screen or a row outside its block", () => {
		expect(anchorOf({ blockId: ALT_BLOCK_ID, row: 0, column: 0, side: "left" }, rowsOf(["x"]))).toBeNull();
		expect(anchorOf({ blockId: "b", row: 7, column: 0, side: "left" }, rowsOf(["x"]))).toBeNull();
	});
	it("moves a line start and a point with a row event, but never an alternate-screen point", () => {
		const event = { trimmed: 0, remap: [[0, 0], [1, 0]] as const, remapEnd: [2, 1] as const };
		expect(followAnchor({ blockId: "b", lineRow: 4, cells: 0, side: "left" }, event).lineRow).toBe(3);
		expect(followPoint({ blockId: "b", row: 1, column: 2, side: "left" }, event).row).toBe(0);
		expect(followPoint({ blockId: ALT_BLOCK_ID, row: 1, column: 2, side: "left" }, event).row).toBe(1);
	});
});
```

Create `packages/terminal/ts/renderer-dom/src/renderer-selection.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { RendererSelection } from "./renderer-selection";
import type { TextRows } from "./selection-text";
import { ALT_BLOCK_ID } from "./selection-view";

function rowsOf(blockId: string, lines: readonly string[], wrapped: ReadonlySet<number> = new Set(), firstRow = 0): TextRows {
	return {
		blockIds: [blockId],
		firstRow: () => firstRow,
		rowCount: () => lines.length,
		rowText: (_id, row) => lines[row - firstRow] ?? "",
		rowSpans: () => [],
		rowWrapped: (_id, row) => wrapped.has(row),
	};
}

function selectionOver(rows: { current: TextRows }): RendererSelection {
	return new RendererSelection({ hasCore: () => true, textRows: () => rows.current, repaint: () => undefined });
}

describe("RendererSelection follows row events", () => {
	it("follows a line that a narrower width cut into more rows", () => {
		const rows = { current: rowsOf("b", ["alpha beta gamma delta"]) };
		const selection = selectionOver(rows);
		selection.begin({ blockId: "b", row: 0, column: 11, side: "left" }, "simple");
		selection.update({ blockId: "b", row: 0, column: 15, side: "right" });
		expect(selection.text()).toBe("gamma");
		rows.current = rowsOf("b", ["alpha beta ", "gamma delta"], new Set([0]));
		selection.followRows({ trimmed: 0, remap: [[0, 0]], remapEnd: [1, 2] });
		expect(selection.text()).toBe("gamma");
	});
	it("moves a point on a row after the rewrapped ones by the end pair", () => {
		const rows = { current: rowsOf("b", ["aaaa bbbb", "tail"]) };
		const selection = selectionOver(rows);
		selection.begin({ blockId: "b", row: 1, column: 0, side: "left" }, "simple");
		selection.update({ blockId: "b", row: 1, column: 3, side: "right" });
		expect(selection.text()).toBe("tail");
		rows.current = rowsOf("b", ["aaaa ", "bbbb", "tail"], new Set([0]));
		selection.followRows({ trimmed: 0, remap: [[0, 0]], remapEnd: [1, 2] });
		expect(selection.text()).toBe("tail");
	});
	it("leaves an alternate-screen selection alone when the primary screen's rows move", () => {
		const rows = { current: rowsOf(ALT_BLOCK_ID, ["alt text here"]) };
		const selection = selectionOver(rows);
		selection.begin({ blockId: ALT_BLOCK_ID, row: 0, column: 0, side: "left" }, "simple");
		selection.update({ blockId: ALT_BLOCK_ID, row: 0, column: 2, side: "right" });
		expect(selection.text()).toBe("alt");
		selection.followRows({ trimmed: 0, remap: [[0, 3], [1, 4]], remapEnd: [2, 5] });
		expect(selection.text()).toBe("alt");
	});
	it("ignores a trim-only event", () => {
		const rows = { current: rowsOf("b", ["one", "two"]) };
		const selection = selectionOver(rows);
		selection.begin({ blockId: "b", row: 1, column: 0, side: "left" }, "line");
		selection.followRows({ trimmed: 1, remap: null, remapEnd: null });
		expect(selection.text()).toBe("two");
	});
});
```

Create `packages/terminal/ts/renderer-dom/src/selection-rewrap.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore, type TerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "./dom-block-renderer";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");
beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function rowOf(core: TerminalCore, text: string): number {
	const snapshot = core.snapshot();
	for (let row = 0; row * 2 < snapshot.rows.length; row += 1) {
		if (decoder.decode(snapshot.content.subarray(snapshot.rows[row * 2]!, snapshot.rows[row * 2 + 1]!)) === text) return snapshot.firstStableRow + row;
	}
	throw new Error(`no row reads ${JSON.stringify(text)}`);
}

function mounted(core: TerminalCore): { renderer: DomBlockRenderer; blockIds: string[] } {
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	const blockIds = [...host.querySelectorAll<HTMLElement>("[data-terminal-block-id]")].map((element) => element.dataset.terminalBlockId!);
	return { renderer, blockIds };
}

describe("a selection across a width change", () => {
	it("keeps a selection on the same words when a narrower width rewraps its line", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100, rows: 2 });
		core.feed(encoder.encode("alpha beta gamma delta epsilon\r\nx\r\ny\r\n"));
		const { renderer, blockIds } = mounted(core);
		const row = rowOf(core, "alpha beta gamma delta epsilon");
		renderer.selectionBegin({ blockId: blockIds[0]!, row, column: 11, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId: blockIds[0]!, row, column: 21, side: "left" });
		expect(renderer.selectedText()).toBe("gamma delta");
		core.resize(12, 2);
		expect(rowOf(core, "gamma delta ")).toBe(row + 1);
		expect(renderer.selectedText()).toBe("gamma delta");
		core.resize(40, 2);
		expect(renderer.selectedText()).toBe("gamma delta");
		renderer.dispose();
	});

	it("keeps a selection that crosses two blocks", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100, rows: 2 });
		core.feed(encoder.encode("\x1b]133;A\x07\x1b]133;C\x07one two three four five\r\n\x1b]133;D;0\x07\x1b]133;A\x07\x1b]133;C\x07six seven eight nine ten\r\n\x1b]133;D;0\x07\x1b]133;A\x07"));
		const { renderer, blockIds } = mounted(core);
		const first = rowOf(core, "one two three four five");
		const second = rowOf(core, "six seven eight nine ten");
		renderer.selectionBegin({ blockId: blockIds[0]!, row: first, column: 8, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId: blockIds[1]!, row: second, column: 14, side: "right" });
		expect(renderer.selectedText()).toBe("three four five\nsix seven eight");
		core.resize(10, 2);
		expect(renderer.selectedText()).toBe("three four five\nsix seven eight");
		renderer.dispose();
	});

	it("keeps a selection on an agent's live frame when the rows above it rewrap", () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100, rows: 3 });
		core.setAgentTuiMode(true);
		core.feed(encoder.encode("aaaaaaaaaabbbbbbbbbbcccccccccc\r\ntail\r\nx\r\nzeta"));
		const { renderer, blockIds } = mounted(core);
		const row = rowOf(core, "zeta");
		renderer.selectionBegin({ blockId: blockIds[0]!, row, column: 0, side: "left" }, "line");
		expect(renderer.selectedText()).toBe("zeta");
		core.resize(40, 3);
		expect(rowOf(core, "zeta")).toBe(row - 1);
		expect(renderer.selectedText()).toBe("zeta");
		renderer.dispose();
	});

	it("keeps a selection in rows older than the eager rewrap window through the later lazy pass", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 5000, rows: 2 });
		let text = "";
		for (let line = 0; line < 2100; line += 1) text += `line ${String(line).padStart(4, "0")} alpha beta gamma delta\r\n`;
		core.feed(encoder.encode(text));
		const { renderer, blockIds } = mounted(core);
		const row = rowOf(core, "line 0005 alpha beta gamma delta");
		renderer.selectionBegin({ blockId: blockIds[0]!, row, column: 21, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId: blockIds[0]!, row, column: 25, side: "right" });
		expect(renderer.selectedText()).toBe("gamma");
		core.resize(16, 2);
		expect(renderer.selectedText()).toBe("gamma");
		core.setExportWindow(0, 50);
		core.snapshot();
		expect(rowOf(core, "line 0005 alpha ")).toBeGreaterThan(row);
		expect(renderer.selectedText()).toBe("gamma");
		renderer.dispose();
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/renderer-dom && npx vitest run src/selection-anchor.test.ts src/renderer-selection.test.ts src/selection-rewrap.test.ts 2>&1 | tail -15`
Expected: FAIL — `Failed to resolve import "./selection-anchor"`; `selection.followRows is not a function`; in `selection-rewrap.test.ts` the width-change assertions get `""`, `"\nsix seven eight"`-style text or another row's text instead of the expected words.

- [ ] **Step 3: Implement**

Create `packages/terminal/ts/renderer-dom/src/selection-anchor.ts`:

```ts
import { remapStableRow, type RowEvent } from "@operator/terminal-core";
import { cellCount } from "./clusters.js";
import type { SelectionPoint, SelectionSide } from "./selection-model.js";
import type { TextRows } from "./selection-text.js";
import { ALT_BLOCK_ID } from "./selection-view.js";

export type LineAnchor = Readonly<{ blockId: string; lineRow: number; cells: number; side: SelectionSide }>;

function rowCells(rows: TextRows, blockId: string, row: number): number {
	return cellCount(rows.rowText(blockId, row), rows.rowSpans(blockId, row));
}

function inBlock(rows: TextRows, blockId: string, row: number): boolean {
	const first = rows.firstRow(blockId);
	return row >= first && row < first + rows.rowCount(blockId);
}

export function anchorOf(point: SelectionPoint, rows: TextRows): LineAnchor | null {
	if (point.blockId === ALT_BLOCK_ID || !inBlock(rows, point.blockId, point.row)) return null;
	const first = rows.firstRow(point.blockId);
	let lineRow = point.row;
	while (lineRow > first && rows.rowWrapped(point.blockId, lineRow - 1)) lineRow -= 1;
	let cells = Math.max(point.column - (rows.rowIndent?.(point.blockId, point.row) ?? 0), 0);
	if (rows.rowWrapped(point.blockId, point.row)) cells = Math.min(cells, Math.max(rowCells(rows, point.blockId, point.row) - 1, 0));
	for (let row = lineRow; row < point.row; row += 1) cells += rowCells(rows, point.blockId, row);
	return { blockId: point.blockId, lineRow, cells, side: point.side };
}

export function pointOf(anchor: LineAnchor, rows: TextRows): SelectionPoint | null {
	if (!inBlock(rows, anchor.blockId, anchor.lineRow)) return null;
	const last = rows.firstRow(anchor.blockId) + rows.rowCount(anchor.blockId) - 1;
	let row = anchor.lineRow;
	let cells = anchor.cells;
	while (row < last && rows.rowWrapped(anchor.blockId, row)) {
		const width = rowCells(rows, anchor.blockId, row);
		if (cells < width) break;
		cells -= width;
		row += 1;
	}
	return { blockId: anchor.blockId, row, column: cells + (rows.rowIndent?.(anchor.blockId, row) ?? 0), side: anchor.side };
}

export function followAnchor(anchor: LineAnchor, event: RowEvent): LineAnchor {
	return { ...anchor, lineRow: remapStableRow(anchor.lineRow, event) };
}

export function followPoint(point: SelectionPoint, event: RowEvent): SelectionPoint {
	return point.blockId === ALT_BLOCK_ID ? point : { ...point, row: remapStableRow(point.row, event) };
}
```

Replace `packages/terminal/ts/renderer-dom/src/renderer-selection.ts` with:

```ts
import type { BlockView, RowEvent } from "@operator/terminal-core";
import { anchorOf, followAnchor, followPoint, pointOf, type LineAnchor } from "./selection-anchor.js";
import type { SelectionKind, SelectionPoint, SelectionState } from "./selection-model.js";
import { selectedText, type TextRows } from "./selection-text.js";
import { resolveSelectionView, type SelectionView } from "./selection-view.js";

export type RendererSelectionDeps = Readonly<{
	hasCore: () => boolean;
	textRows: () => TextRows;
	repaint: () => void;
}>;

type Anchors = Readonly<{ head: LineAnchor | null; tail: LineAnchor | null }>;

export class RendererSelection {
	private selection: SelectionState | null = null;
	private anchors: Anchors | null = null;
	private anchoredFor: SelectionState | null = null;
	private moved = false;
	private readonly selectionListeners = new Set<() => void>();

	constructor(private readonly deps: RendererSelectionDeps) {}

	begin(point: SelectionPoint, kind: SelectionKind): void {
		this.set({ head: point, tail: point, kind });
	}

	update(point: SelectionPoint): void {
		if (!this.selection) return;
		this.set({ ...this.selection, tail: point });
	}

	clear(): void {
		if (!this.selection) return;
		this.forget();
		this.changed();
	}

	followRows(event: RowEvent): void {
		const selection = this.selection;
		if (!selection || (!event.remap && !event.remapEnd)) return;
		this.selection = { ...selection, head: followPoint(selection.head, event), tail: followPoint(selection.tail, event) };
		if (this.anchors && this.anchoredFor === selection) {
			this.anchors = {
				head: this.anchors.head && followAnchor(this.anchors.head, event),
				tail: this.anchors.tail && followAnchor(this.anchors.tail, event),
			};
			this.anchoredFor = this.selection;
			this.moved = true;
			return;
		}
		this.anchors = null;
		this.anchoredFor = null;
	}

	text(): string | null {
		const view = this.view();
		return view ? selectedText(view.range, view.rows) : null;
	}

	onChange(listener: () => void): () => void {
		this.selectionListeners.add(listener);
		return () => {
			this.selectionListeners.delete(listener);
		};
	}

	drop(): void {
		if (!this.selection) return;
		this.forget();
		this.notifyListeners();
	}

	dropUnlessShown(blocks: readonly BlockView[]): void {
		if (this.selection) {
			const ids = new Set(blocks.map((block) => block.id));
			if (!ids.has(this.selection.head.blockId) || !ids.has(this.selection.tail.blockId)) this.drop();
		}
	}

	view(): SelectionView | null {
		if (!this.selection || !this.deps.hasCore()) return null;
		const rows = this.deps.textRows();
		const selection = this.settle(rows);
		return selection ? resolveSelectionView(selection, rows) : null;
	}

	reset(): void {
		this.forget();
	}

	private set(selection: SelectionState): void {
		this.selection = selection;
		this.changed();
	}

	private settle(rows: TextRows): SelectionState | null {
		const selection = this.selection;
		if (!selection) return null;
		if (this.moved && this.anchors) {
			this.moved = false;
			const head = (this.anchors.head && pointOf(this.anchors.head, rows)) ?? selection.head;
			const tail = (this.anchors.tail && pointOf(this.anchors.tail, rows)) ?? selection.tail;
			this.selection = { ...selection, head, tail };
			this.anchoredFor = this.selection;
			return this.selection;
		}
		if (this.anchoredFor !== selection) {
			this.anchors = { head: anchorOf(selection.head, rows), tail: anchorOf(selection.tail, rows) };
			this.anchoredFor = selection;
		}
		return selection;
	}

	private forget(): void {
		this.selection = null;
		this.anchors = null;
		this.anchoredFor = null;
		this.moved = false;
	}

	private changed(): void {
		this.deps.repaint();
		this.notifyListeners();
	}

	private notifyListeners(): void {
		for (const listener of [...this.selectionListeners]) listener();
	}
}
```

`view()` reads `textRows()` before it reads the selection: `textRows()` calls `core.snapshot()`, which delivers pending row events (`terminal-core.ts` `snapshot` → `emitRowEvents`), so a read right after `core.resize` sees the moved selection.

`renderer-wiring.ts`: line 1 becomes

```ts
import { defaultStrings, type BlockId, type BlockView, type RowEvent, type TerminalCore } from "@operator/terminal-core";
```

line 10 becomes

```ts
	onRowEvents: (event: RowEvent) => void;
```

line 26 becomes

```ts
	const rowEventsUnsubscribe = core.onRowEvents((event) => host.onRowEvents(event));
```

`dom-block-renderer.ts` line 143 becomes (one line, so the file stays at 598):

```ts
			onRowEvents: (event) => { this.scroll.remapAnchor(event.remap); this.highlights.selection.followRows(event); },
```

- [ ] **Step 4: Run the tests**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/renderer-dom && npx vitest run 2>&1 | grep -E "Tests  |FAIL"
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && grep -rn "onRowRemap" ts/*/src bench/*.ts bench/agent-session/*.ts; npm run check:boundaries 2>&1 | tail -1 && wc -l ts/renderer-dom/src/dom-block-renderer.ts
```
Expected: renderer-dom = previous count + 14, no `FAIL`; the grep prints nothing; `boundary check passed`; `598`.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection
git add packages/terminal/ts/renderer-dom/src/selection-anchor.ts packages/terminal/ts/renderer-dom/src/selection-anchor.test.ts packages/terminal/ts/renderer-dom/src/renderer-selection.ts packages/terminal/ts/renderer-dom/src/renderer-selection.test.ts packages/terminal/ts/renderer-dom/src/selection-rewrap.test.ts packages/terminal/ts/renderer-dom/src/renderer-wiring.ts packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts
git commit -m "feat(renderer-dom): a selection follows a rewrap

Each point keeps a line anchor (first row of its logical line plus cells into
it); row events move the anchor and the point is resolved against the new rows.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `TerminalSurface` keeps a primary-screen selection across a resize

**Files:**
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx:330`
- Test: `packages/terminal/ts/react/src/TerminalSurface.selection.test.tsx:122-136` (replaced by two tests)

**Interfaces:**
- Consumes: Task 4 (`followRows` wired in the renderer).
- Produces: a grid change clears the selection only while `core.snapshot().altScreen !== null`.

- [ ] **Step 1: Write the failing tests**

Replace the test at `TerminalSurface.selection.test.tsx:122-136` ("keeps a selection across a same-geometry refit but clears it on a real resize") with:

```tsx
	it("keeps a primary-screen selection on its words across a real resize", async () => {
		const originalPlatform = Object.getOwnPropertyDescriptor(navigator, "platform");
		Object.defineProperty(navigator, "platform", { value: "MacIntel", configurable: true });
		try {
			const writeClipboard = vi.fn(async () => {});
			const caps = { writeClipboard, readClipboard: async () => "", openLink: async () => {} };
			const { container, core, host, refit } = renderSurface({ host: caps });
			setHostSize(host, 1000, 500);
			act(() => { feed(core, "alpha beta gamma delta\r\nzeta\r\n"); });
			await flushRepaint();
			let rows = layoutRows(container);
			mouse(rows[0]!, "mousedown", cellWidth * 11 + 1, cellHeight * 0.5, { detail: 1 });
			mouse(window, "mousemove", cellWidth * 16 - 1, cellHeight * 0.5);
			mouse(window, "mouseup", cellWidth * 16 - 1, cellHeight * 0.5);
			const surface = container.querySelector(".terminal-host") as HTMLElement;
			surface.dispatchEvent(new KeyboardEvent("keydown", { key: "c", metaKey: true, bubbles: true, cancelable: true }));
			expect(writeClipboard).toHaveBeenLastCalledWith("gamma");
			refit(1);
			expect(rows[0]!.style.backgroundImage).toContain("var(--terminal-selection)");
			setHostSize(host, 150, 500);
			await flushRepaint();
			rows = layoutRows(container);
			surface.dispatchEvent(new KeyboardEvent("keydown", { key: "c", metaKey: true, bubbles: true, cancelable: true }));
			expect(writeClipboard).toHaveBeenLastCalledWith("gamma");
			expect(rows.map((row) => row.textContent?.trimEnd())).toContain("gamma delta");
		} finally {
			if (originalPlatform) Object.defineProperty(navigator, "platform", originalPlatform);
		}
	});

	it("clears an alternate-screen selection on a real resize", async () => {
		const { container, core, host } = renderSurface();
		setHostSize(host, 1000, 500);
		act(() => { feed(core, "\x1b[?1049halpha beta\r\n"); });
		await flushRepaint();
		const rows = layoutRows(container.querySelector(".terminal-alt-surface") as HTMLElement);
		mouse(rows[0]!, "mousedown", 0, cellHeight * 0.5, { detail: 1 });
		mouse(window, "mousemove", cellWidth * 4, cellHeight * 0.5);
		mouse(window, "mouseup", cellWidth * 4, cellHeight * 0.5);
		expect(rows[0]!.style.backgroundImage).toContain("var(--terminal-selection)");
		setHostSize(host, 300, 150);
		expect(rows[0]!.style.backgroundImage).toBe("");
	});
```

(At 150 px the grid is `floor((150 - 32) / 8.4) = 14` columns, so `alpha beta gamma delta` rewraps to `alpha beta ` / `gamma delta`. The paint after the resize lands on row elements jsdom has not been given a layout for, so this test checks the copy and the rewrap; the painted rows after a resize are checked by the Playwright gate in Task 10.)

- [ ] **Step 2: Run them to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && npm run build:ts 2>&1 | tail -1 && cd ts/react && npx vitest run src/TerminalSurface.selection.test.tsx 2>&1 | tail -8`
Expected: FAIL in "keeps a primary-screen selection…": the second copy is not called with `gamma` (the resize cleared the selection, so `selectedText()` is `null` and nothing is written). The alternate-screen test passes (guard).

- [ ] **Step 3: Implement**

`TerminalSurface.tsx` line 330 becomes:

```tsx
			if (changed && core.snapshot().altScreen !== null) renderer.selectionClear();
```

- [ ] **Step 4: Run the tests**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/react && npx vitest run 2>&1 | grep -E "Tests  |FAIL"`
Expected: react = Task 0 count + 1, no `FAIL`.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection
git add packages/terminal/ts/react/src/TerminalSurface.tsx packages/terminal/ts/react/src/TerminalSurface.selection.test.tsx
git commit -m "feat(terminal-react): keep a primary-screen selection across a resize

The alternate screen still clears on a real resize: the program repaints and
its rows are not stable rows (Warp clears in both, model/blocks.rs:2299-2301;
the wishlist asks for survival on the transcript).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The renderer can extend a selection, from a remembered caret

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/renderer-selection.ts` (whole file, Task 4 version)
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:275-281`
- Test: `packages/terminal/ts/renderer-dom/src/renderer-selection.test.ts` (append), `selection-extend.test.ts` (new)

**Interfaces:**
- Consumes: `anchorOf`, `pointOf`, `followAnchor`, `followPoint` (Task 4).
- Produces:
  - `RendererSelection.update(point: SelectionPoint, extendFromCaret = false): void` — with a selection: moves its tail (kind kept); without one and `extendFromCaret`: selects from the caret to `point` (`kind: "simple"`), or, with no usable caret, only places the caret at `point`.
  - `RendererSelection.clear(caret?: SelectionPoint): void` — records `caret` (if given), then clears.
  - `RendererSelection.begin` also records the caret.
  - `DomBlockRenderer.selectionUpdate(point: SelectionPoint, extendFromCaret = false): void`, `DomBlockRenderer.selectionClear(caret?: SelectionPoint): void`.

- [ ] **Step 1: Write the failing tests**

Append to `renderer-selection.test.ts`:

```ts

describe("RendererSelection extends", () => {
	it("extends the current selection from its anchor and keeps its kind", () => {
		const rows = { current: rowsOf("b", ["alpha beta", "gamma delta"]) };
		const selection = selectionOver(rows);
		selection.begin({ blockId: "b", row: 0, column: 1, side: "left" }, "word");
		selection.update({ blockId: "b", row: 1, column: 7, side: "left" }, true);
		expect(selection.text()).toBe("alpha beta\ngamma delta");
	});
	it("selects from the last plain click when there is no selection", () => {
		const rows = { current: rowsOf("b", ["alpha beta", "gamma delta"]) };
		const selection = selectionOver(rows);
		selection.clear({ blockId: "b", row: 0, column: 6, side: "left" });
		selection.update({ blockId: "b", row: 1, column: 4, side: "right" }, true);
		expect(selection.text()).toBe("beta\ngamma");
	});
	it("does nothing on a plain update with no selection", () => {
		const rows = { current: rowsOf("b", ["alpha beta"]) };
		const selection = selectionOver(rows);
		selection.clear({ blockId: "b", row: 0, column: 0, side: "left" });
		selection.update({ blockId: "b", row: 0, column: 4, side: "right" });
		expect(selection.text()).toBeNull();
	});
	it("only places the caret when nothing was clicked before", () => {
		const rows = { current: rowsOf("b", ["alpha beta"]) };
		const selection = selectionOver(rows);
		selection.update({ blockId: "b", row: 0, column: 6, side: "left" }, true);
		expect(selection.text()).toBeNull();
		selection.update({ blockId: "b", row: 0, column: 9, side: "right" }, true);
		expect(selection.text()).toBe("beta");
	});
	it("keeps the caret on its text through a rewrap", () => {
		const rows = { current: rowsOf("b", ["alpha beta gamma delta"]) };
		const selection = selectionOver(rows);
		selection.clear({ blockId: "b", row: 0, column: 11, side: "left" });
		rows.current = rowsOf("b", ["alpha beta ", "gamma delta"], new Set([0]));
		selection.followRows({ trimmed: 0, remap: [[0, 0]], remapEnd: [1, 2] });
		selection.update({ blockId: "b", row: 1, column: 4, side: "right" }, true);
		expect(selection.text()).toBe("gamma");
	});
	it("replaces a caret whose block is gone", () => {
		const rows = { current: rowsOf("old", ["gone"]) };
		const selection = selectionOver(rows);
		selection.clear({ blockId: "old", row: 0, column: 0, side: "left" });
		rows.current = rowsOf("new", ["alpha beta"]);
		selection.update({ blockId: "new", row: 0, column: 6, side: "left" }, true);
		expect(selection.text()).toBeNull();
		selection.update({ blockId: "new", row: 0, column: 9, side: "right" }, true);
		expect(selection.text()).toBe("beta");
	});
});
```

Create `packages/terminal/ts/renderer-dom/src/selection-extend.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore, type TerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "./dom-block-renderer";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");
beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

const encoder = new TextEncoder();
const frames = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));

function mount(core: TerminalCore): { host: HTMLElement; renderer: DomBlockRenderer } {
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	return { host, renderer };
}

describe("extending a selection in a trimmed session", () => {
	it("extends from the first retained row when the caret's row was trimmed", () => {
		const lines = ["1", "2", "needle", "4", "5", "6", "7", "8"];
		const core = createTerminalCore({ columns: 40, limits: { rows: 6, bytes: 0xffff_ffff }, rows: 2 });
		for (const line of lines.slice(0, 4)) core.feed(encoder.encode(`${line}\r\n`));
		const { host, renderer } = mount(core);
		const blockId = host.querySelector<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionClear({ blockId, row: 0, column: 0, side: "left" });
		for (const line of lines.slice(4)) core.feed(encoder.encode(`${line}\r\n`));
		const first = core.snapshot().firstStableRow;
		expect(first).toBeGreaterThan(0);
		renderer.selectionUpdate({ blockId, row: 6, column: 0, side: "right" }, true);
		expect(renderer.selectedText()).toBe(lines.slice(first, 7).join("\n"));
		renderer.dispose();
	});

	it("places a fresh caret when the caret's block was trimmed away", async () => {
		const core = createTerminalCore({ columns: 40, limits: { rows: 8, bytes: 0xffff_ffff }, rows: 2 });
		const block = (text: string) => `\x1b]133;A\x07\x1b]133;C\x07${text}\r\n\x1b]133;D;0\x07`;
		core.feed(encoder.encode(block("first")));
		const { host, renderer } = mount(core);
		const firstId = host.querySelector<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionBegin({ blockId: firstId, row: 0, column: 0, side: "left" }, "line");
		expect(renderer.selectedText()).toBe("first");
		for (let index = 0; index < 12; index += 1) core.feed(encoder.encode(block(`later ${index}`)));
		await frames();
		expect(core.snapshot().firstStableRow).toBeGreaterThan(0);
		expect(renderer.hasSelection()).toBe(false);
		const lastElement = [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")].find((element) => element.textContent === "later 11")!;
		const lastId = lastElement.closest<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		expect(lastId).not.toBe(firstId);
		const lastRow = Number(lastElement.dataset.terminalRow);
		renderer.selectionUpdate({ blockId: lastId, row: lastRow, column: 0, side: "left" }, true);
		expect(renderer.hasSelection()).toBe(false);
		renderer.selectionUpdate({ blockId: lastId, row: lastRow, column: 4, side: "right" }, true);
		expect(renderer.selectedText()).toBe("later");
		renderer.dispose();
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/renderer-dom && npx vitest run src/renderer-selection.test.ts src/selection-extend.test.ts 2>&1 | tail -12`
Expected: FAIL — "selects from the last plain click…", "only places the caret…", "keeps the caret…", "replaces a caret…" and both `selection-extend.test.ts` cases get `null` (no caret exists yet); "extends the current selection…" and "does nothing…" pass (guards).

- [ ] **Step 3: Implement**

Replace `packages/terminal/ts/renderer-dom/src/renderer-selection.ts` with:

```ts
import type { BlockView, RowEvent } from "@operator/terminal-core";
import { anchorOf, followAnchor, followPoint, pointOf, type LineAnchor } from "./selection-anchor.js";
import type { SelectionKind, SelectionPoint, SelectionState } from "./selection-model.js";
import { selectedText, type TextRows } from "./selection-text.js";
import { resolveSelectionView, type SelectionView } from "./selection-view.js";

export type RendererSelectionDeps = Readonly<{
	hasCore: () => boolean;
	textRows: () => TextRows;
	repaint: () => void;
}>;

type Anchors = Readonly<{ head: LineAnchor | null; tail: LineAnchor | null }>;

export class RendererSelection {
	private selection: SelectionState | null = null;
	private anchors: Anchors | null = null;
	private anchoredFor: SelectionState | null = null;
	private moved = false;
	private caret: SelectionPoint | null = null;
	private caretAnchor: LineAnchor | null = null;
	private readonly selectionListeners = new Set<() => void>();

	constructor(private readonly deps: RendererSelectionDeps) {}

	begin(point: SelectionPoint, kind: SelectionKind): void {
		this.placeCaret(point);
		this.set({ head: point, tail: point, kind });
	}

	update(point: SelectionPoint, extendFromCaret = false): void {
		if (this.selection) {
			this.set({ ...this.selection, tail: point });
			return;
		}
		if (!extendFromCaret) return;
		const head = this.currentCaret();
		if (head) this.set({ head, tail: point, kind: "simple" });
		else this.placeCaret(point);
	}

	clear(caret?: SelectionPoint): void {
		if (caret) this.placeCaret(caret);
		if (!this.selection) return;
		this.forget();
		this.changed();
	}

	followRows(event: RowEvent): void {
		if (!event.remap && !event.remapEnd) return;
		if (this.caret) this.caret = followPoint(this.caret, event);
		if (this.caretAnchor) this.caretAnchor = followAnchor(this.caretAnchor, event);
		const selection = this.selection;
		if (!selection) return;
		this.selection = { ...selection, head: followPoint(selection.head, event), tail: followPoint(selection.tail, event) };
		if (this.anchors && this.anchoredFor === selection) {
			this.anchors = {
				head: this.anchors.head && followAnchor(this.anchors.head, event),
				tail: this.anchors.tail && followAnchor(this.anchors.tail, event),
			};
			this.anchoredFor = this.selection;
			this.moved = true;
			return;
		}
		this.anchors = null;
		this.anchoredFor = null;
	}

	text(): string | null {
		const view = this.view();
		return view ? selectedText(view.range, view.rows) : null;
	}

	onChange(listener: () => void): () => void {
		this.selectionListeners.add(listener);
		return () => {
			this.selectionListeners.delete(listener);
		};
	}

	drop(): void {
		if (!this.selection) return;
		this.forget();
		this.notifyListeners();
	}

	dropUnlessShown(blocks: readonly BlockView[]): void {
		if (this.selection) {
			const ids = new Set(blocks.map((block) => block.id));
			if (!ids.has(this.selection.head.blockId) || !ids.has(this.selection.tail.blockId)) this.drop();
		}
	}

	view(): SelectionView | null {
		if (!this.selection || !this.deps.hasCore()) return null;
		const rows = this.deps.textRows();
		const selection = this.settle(rows);
		return selection ? resolveSelectionView(selection, rows) : null;
	}

	reset(): void {
		this.forget();
		this.caret = null;
		this.caretAnchor = null;
	}

	private set(selection: SelectionState): void {
		this.selection = selection;
		this.changed();
	}

	private placeCaret(point: SelectionPoint): void {
		this.caret = point;
		this.caretAnchor = this.deps.hasCore() ? anchorOf(point, this.deps.textRows()) : null;
	}

	private currentCaret(): SelectionPoint | null {
		if (!this.caret || !this.deps.hasCore()) return null;
		const rows = this.deps.textRows();
		const caret = (this.caretAnchor && pointOf(this.caretAnchor, rows)) ?? this.caret;
		return rows.blockIds.includes(caret.blockId) ? caret : null;
	}

	private settle(rows: TextRows): SelectionState | null {
		const selection = this.selection;
		if (!selection) return null;
		if (this.moved && this.anchors) {
			this.moved = false;
			const head = (this.anchors.head && pointOf(this.anchors.head, rows)) ?? selection.head;
			const tail = (this.anchors.tail && pointOf(this.anchors.tail, rows)) ?? selection.tail;
			this.selection = { ...selection, head, tail };
			this.anchoredFor = this.selection;
			return this.selection;
		}
		if (this.anchoredFor !== selection) {
			this.anchors = { head: anchorOf(selection.head, rows), tail: anchorOf(selection.tail, rows) };
			this.anchoredFor = selection;
		}
		return selection;
	}

	private forget(): void {
		this.selection = null;
		this.anchors = null;
		this.anchoredFor = null;
		this.moved = false;
	}

	private changed(): void {
		this.deps.repaint();
		this.notifyListeners();
	}

	private notifyListeners(): void {
		for (const listener of [...this.selectionListeners]) listener();
	}
}
```

`dom-block-renderer.ts` lines 275-281 become (same line count):

```ts
	selectionUpdate(point: SelectionPoint, extendFromCaret = false): void {
		this.highlights.selection.update(point, extendFromCaret);
	}

	selectionClear(caret?: SelectionPoint): void {
		this.highlights.selection.clear(caret);
	}
```

- [ ] **Step 4: Run the tests**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/renderer-dom && npx vitest run 2>&1 | grep -E "Tests  |FAIL"
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && npm run build:ts 2>&1 | tail -1 && (cd ts/react && npx vitest run 2>&1 | grep -E "Tests  |FAIL") && wc -l ts/renderer-dom/src/dom-block-renderer.ts ts/renderer-dom/src/renderer-selection.ts
```
Expected: renderer-dom = previous + 8, react unchanged, no `FAIL`; `598` and ≤ 160.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection
git add packages/terminal/ts/renderer-dom/src/renderer-selection.ts packages/terminal/ts/renderer-dom/src/renderer-selection.test.ts packages/terminal/ts/renderer-dom/src/selection-extend.test.ts packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts
git commit -m "feat(renderer-dom): extend a selection, or select from the last plain click

selectionUpdate(point, true) extends the selection's tail, or selects from a
remembered caret (set by selectionBegin and selectionClear(caret)); the caret
follows rewraps through its own line anchor.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Shift+click and Shift+drag in the surface

**Files:**
- Modify: `packages/terminal/ts/react/src/use-surface-input.ts:41` (state), `:57` (`extendTo`), `:77` (drag start), `:89-92` (release), `:180-184` (press)
- Test: `packages/terminal/ts/react/src/TerminalSurface.shift-click.test.tsx` (new)

**Interfaces:**
- Consumes: `DomBlockRenderer.selectionUpdate(point, extendFromCaret)`, `selectionClear(caret)` (Task 6).
- Produces: a left press with Shift, `event.detail <= 1`, not reported to a program, extends; a plain click-release records the caret.

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/ts/react/src/TerminalSurface.shift-click.test.tsx`:

```tsx
import { act, cleanup } from "@testing-library/react";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { cellHeight, cellWidth, feed, flushRepaint, loadWasm, renderSurface } from "./surface-harness";

function layoutRows(container: HTMLElement): HTMLElement[] {
	const rows = [...container.querySelectorAll<HTMLElement>("[data-terminal-row]")];
	rows.forEach((row, index) => {
		row.getBoundingClientRect = () => ({ left: 0, right: 600, width: 600, top: index * cellHeight, bottom: (index + 1) * cellHeight, height: cellHeight, x: 0, y: index * cellHeight, toJSON: () => ({}) }) as DOMRect;
	});
	return rows;
}

function mouse(target: EventTarget, type: string, x: number, y: number, init: MouseEventInit = {}): void {
	target.dispatchEvent(new MouseEvent(type, { clientX: x, clientY: y, button: 0, bubbles: true, cancelable: true, ...init }));
}

function click(target: EventTarget, x: number, y: number, init: MouseEventInit = {}): void {
	mouse(target, "mousedown", x, y, { detail: 1, ...init });
	mouse(window, "mouseup", x, y, init);
}

async function mounted(text: string, onSendRaw = vi.fn()) {
	const writeClipboard = vi.fn(async (_text: string) => {});
	const host = { writeClipboard, readClipboard: async () => "", openLink: async () => {} };
	const { container, core } = renderSurface({ host, onSendRaw });
	act(() => { feed(core, text); });
	await flushRepaint();
	const rows = layoutRows(container);
	const surface = container.querySelector(".terminal-host") as HTMLElement;
	const copy = () => {
		surface.dispatchEvent(new KeyboardEvent("keydown", { key: "c", metaKey: true, bubbles: true, cancelable: true }));
		return writeClipboard.mock.lastCall?.[0];
	};
	return { rows, copy, onSendRaw };
}

describe("Shift+click", () => {
	const originalPlatform = Object.getOwnPropertyDescriptor(navigator, "platform");
	beforeAll(async () => {
		await loadWasm();
		Object.defineProperty(navigator, "platform", { value: "MacIntel", configurable: true });
	});
	afterEach(() => cleanup());
	afterAll(() => {
		if (originalPlatform) Object.defineProperty(navigator, "platform", originalPlatform);
	});

	it("extends a dragged selection from its anchor to the clicked cell", async () => {
		const { rows, copy } = await mounted("alpha\r\nbeta\r\ngamma\r\n");
		mouse(rows[0]!, "mousedown", 1, cellHeight * 0.5, { detail: 1 });
		mouse(window, "mousemove", cellWidth * 3, cellHeight * 0.5);
		mouse(window, "mouseup", cellWidth * 3, cellHeight * 0.5);
		click(rows[2]!, cellWidth * 4 + 1, cellHeight * 2.5, { shiftKey: true });
		expect(copy()).toBe("alpha\nbeta\ngamm");
	});

	it("selects from the last plain click when there is no selection", async () => {
		const { rows, copy } = await mounted("alpha\r\nbeta\r\ngamma\r\n");
		click(rows[0]!, cellWidth * 2 + 1, cellHeight * 0.5);
		click(rows[1]!, cellWidth * 3 - 1, cellHeight * 1.5, { shiftKey: true });
		expect(copy()).toBe("pha\nbet");
	});

	it("keeps extending while a Shift press is dragged", async () => {
		const { rows, copy } = await mounted("alpha\r\nbeta\r\ngamma\r\n");
		click(rows[0]!, 1, cellHeight * 0.5);
		mouse(rows[1]!, "mousedown", cellWidth + 1, cellHeight * 1.5, { detail: 1, shiftKey: true });
		mouse(window, "mousemove", cellWidth * 2 + 1, cellHeight * 2.5, { shiftKey: true });
		mouse(window, "mouseup", cellWidth * 2 + 1, cellHeight * 2.5, { shiftKey: true });
		expect(copy()).toBe("alpha\nbeta\nga");
	});

	it("does not extend on a Shift double-click", async () => {
		const { rows, copy } = await mounted("alpha beta\r\ngamma delta\r\n");
		mouse(rows[0]!, "mousedown", 1, cellHeight * 0.5, { detail: 1 });
		mouse(window, "mousemove", cellWidth * 3, cellHeight * 0.5);
		mouse(window, "mouseup", cellWidth * 3, cellHeight * 0.5);
		click(rows[1]!, cellWidth * 7 + 1, cellHeight * 1.5, { shiftKey: true, detail: 2 });
		expect(copy()).toBe("delta");
	});

	it("extends inside a mouse-reporting program instead of reporting the click", async () => {
		const { rows, copy, onSendRaw } = await mounted("\x1b[?1000h\x1b[?1006halpha\r\nbeta\r\n");
		mouse(rows[0]!, "mousedown", 1, cellHeight * 0.5, { detail: 1, shiftKey: true });
		mouse(window, "mousemove", cellWidth * 2, cellHeight * 0.5, { shiftKey: true });
		mouse(window, "mouseup", cellWidth * 2, cellHeight * 0.5, { shiftKey: true });
		onSendRaw.mockClear();
		click(rows[1]!, cellWidth * 3 + 1, cellHeight * 1.5, { shiftKey: true });
		expect(onSendRaw).not.toHaveBeenCalled();
		expect(copy()).toBe("alpha\nbet");
	});
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/react && npx vitest run src/TerminalSurface.shift-click.test.tsx 2>&1 | tail -10`
Expected: FAIL — the Shift press starts a fresh selection or clears it, so copies are `undefined`, `"a"`-style or `"alpha"`, not the extended text; "does not extend on a Shift double-click" passes (guard).

- [ ] **Step 3: Implement**

`use-surface-input.ts` — after line 41 (`let pressKind: SelectionKind = "simple";`) add:

```ts
		let pressExtends = false;
```

line 57 becomes:

```ts
			if (point) target.selectionUpdate(point, pressExtends);
```

line 77 becomes:

```ts
				if (pressKind === "simple" && !pressExtends) target.selectionBegin(pressPoint, "simple");
```

lines 89-92 become:

```ts
			if (target && pressOrigin && pressPoint && !dragging && !pressExtends && pressKind === "simple") target.selectionClear(pressPoint);
			pressOrigin = null;
			pressPoint = null;
			pressExtends = false;
```

lines 180-184 become:

```ts
			pressOrigin = { x: event.clientX, y: event.clientY };
			pressPoint = point;
			pressKind = kindForClickCount(event.detail);
			pressExtends = event.shiftKey && pressKind === "simple";
			dragging = false;
			if (pressExtends) target.selectionUpdate(point, true);
			else if (pressKind !== "simple") target.selectionBegin(point, pressKind);
```

- [ ] **Step 4: Run the tests**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/react && npx vitest run 2>&1 | grep -E "Tests  |FAIL"`
Expected: react = previous + 5, no `FAIL` (the existing "leaves the drag to a mouse-reporting app unless shift is held" still passes: its Shift press has no caret, places one and the drag selects from it).

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection
git add packages/terminal/ts/react/src/use-surface-input.ts packages/terminal/ts/react/src/TerminalSurface.shift-click.test.tsx
git commit -m "feat(terminal-react): Shift+click extends the selection

From the selection's anchor, or from the last plain click; a Shift double-click
is a plain double-click and Shift+drag keeps extending (Ghostty
Surface.zig:3852-3882, behaviour only).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Rectangle selections — model, paint, copy, rewrap rule

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/selection-model.ts:3` (`SelectionKind`), `:8` (`SelectionRange`), `resolveRange` (Task 3 version)
- Modify: `packages/terminal/ts/renderer-dom/src/selection-geometry.ts:47-62` (`rowFillSpan`)
- Modify: `packages/terminal/ts/renderer-dom/src/selection-text.ts` (`selectedText` entry, new `rectangleText`)
- Modify: `packages/terminal/ts/renderer-dom/src/highlight-painter.ts:83` (`highlightKey`)
- Modify: `packages/terminal/ts/renderer-dom/src/selection-anchor.ts` (append `rowsKeepTheirShape`), `renderer-selection.ts` (`followRows`, `settle`)
- Test: `selection-model.test.ts`, `selection-geometry.test.ts`, `selection-text.test.ts`, `highlight-painter.test.ts`, `renderer-selection.test.ts` (append), `selection-rectangle.test.ts` (new)

**Interfaces:**
- Consumes: `boundaryOf`, `compareBoundary` (`selection-model.ts:15-24`); `TextRows.rowIndent` (Task 3); `remapStableRow` (Task 2).
- Produces: `SelectionKind = "simple" | "word" | "line" | "rectangle"`; `SelectionRange = Readonly<{ start: Boundary; end: Boundary; rectangle?: boolean }>` — for a rectangle, `start` is the top row with `cell = left`, `end` the bottom row with `cell = right` (exclusive), in painted cells; `rowsKeepTheirShape(top: number, bottom: number, event: RowEvent): boolean`.

- [ ] **Step 1: Write the failing tests**

Append inside `describe("resolveRange", …)` in `selection-model.test.ts`:

```ts
	it("makes a rectangle from the two points' rows and the cells between them, in any drag direction", () => {
		const range = resolveRange({ head: at("0", 1, 7, "right"), tail: at("0", 0, 2), kind: "rectangle" }, order, rowText)!;
		expect(range).toEqual({ start: { blockId: "0", row: 0, cell: 2 }, end: { blockId: "0", row: 1, cell: 8 }, rectangle: true });
	});
	it("gives no rectangle with no width", () => {
		expect(resolveRange({ head: at("0", 0, 3), tail: at("0", 1, 3), kind: "rectangle" }, order, rowText)).toBeNull();
	});
```

Append inside `describe("rowFillSpan", …)` in `selection-geometry.test.ts`:

```ts
	it("fills the same cells on every row of a rectangle", () => {
		const box = { start: { blockId: "a", row: 0, cell: 2 }, end: { blockId: "b", row: 0, cell: 5 }, rectangle: true };
		expect(rows.slice(0, 3).map((row) => rowFillSpan(box, row, order, cw))).toEqual([
			{ left: 16, right: 40 },
			{ left: 16, right: 40 },
			{ left: 16, right: 40 },
		]);
		expect(rowFillSpan(box, rows[3]!, order, cw)).toBeNull();
	});
```

Append to `selection-text.test.ts`:

```ts

describe("selectedText over a rectangle", () => {
	const table: TextRows = {
		blockIds: ["t", "u"],
		firstRow: () => 0,
		rowCount: (id) => (id === "t" ? 3 : 1),
		rowText: (id, row) => (id === "t" ? ["ab漢字cd", "0123456789", ""] : ["UVWXYZ"])[row] ?? "",
		rowSpans: (id, row) => (id === "t" && row === 0 ? [2, 5, 2, 5, 8, 2] : []),
		rowWrapped: () => true,
	};
	it("copies one slice per row, one line per row, and never joins wrapped rows", () => {
		expect(selectedText({ start: { blockId: "t", row: 1, cell: 3 }, end: { blockId: "t", row: 2, cell: 6 }, rectangle: true }, table)).toBe("345\n");
	});
	it("keeps a wide character that starts inside the box and drops one that starts before it", () => {
		expect(selectedText({ start: { blockId: "t", row: 0, cell: 3 }, end: { blockId: "t", row: 1, cell: 6 }, rectangle: true }, table)).toBe("字\n345");
		expect(selectedText({ start: { blockId: "t", row: 0, cell: 2 }, end: { blockId: "t", row: 0, cell: 5 }, rectangle: true }, table)).toBe("漢字");
	});
	it("runs across blocks", () => {
		expect(selectedText({ start: { blockId: "t", row: 1, cell: 1 }, end: { blockId: "u", row: 0, cell: 3 }, rectangle: true }, table)).toBe("12\n\nVW");
	});
	it("cuts an indented row by the cells it paints", () => {
		expect(selectedText({ start: { blockId: "i", row: 0, cell: 2 }, end: { blockId: "i", row: 1, cell: 7 }, rectangle: true }, indented)).toBe("aaaa\ncc dd");
	});
});
```

Append to `highlight-painter.test.ts` inside `describe("HighlightPainter", …)`:

```ts
	it("repaints when a selection becomes a rectangle with the same corners", () => {
		const rows = [row(0), row(1)];
		const painter = new HighlightPainter();
		const range = { start: { blockId: "b", row: 0, cell: 2 }, end: { blockId: "b", row: 1, cell: 5 } };
		painter.paint(rows, [{ kind: "selection", range, colour: SELECTION_COLOUR, rank: 0 }], order, CELL);
		const stream = rows[0]!.element.style.backgroundImage;
		painter.paint(rows, [{ kind: "selection", range: { ...range, rectangle: true }, colour: SELECTION_COLOUR, rank: 0 }], order, CELL);
		expect(rows[0]!.element.style.backgroundImage).not.toBe(stream);
		expect(rows[0]!.element.style.backgroundImage).toContain("50px");
	});
```

Append to `renderer-selection.test.ts`:

```ts

describe("a rectangle across a rewrap", () => {
	it("keeps a rectangle whose rows only moved", () => {
		const rows = { current: rowsOf("b", ["ab", "cd", "ef"]) };
		const selection = selectionOver(rows);
		selection.begin({ blockId: "b", row: 0, column: 0, side: "left" }, "rectangle");
		selection.update({ blockId: "b", row: 2, column: 0, side: "right" });
		expect(selection.text()).toBe("a\nc\ne");
		rows.current = rowsOf("b", ["ab", "cd", "ef"], new Set(), 5);
		selection.followRows({ trimmed: 0, remap: [[0, 5], [1, 6], [2, 7]], remapEnd: [3, 8] });
		expect(selection.text()).toBe("a\nc\ne");
	});
	it("drops a rectangle whose rows a rewrap split or joined", () => {
		const rows = { current: rowsOf("b", ["ab", "cd", "ef"]) };
		const selection = selectionOver(rows);
		selection.begin({ blockId: "b", row: 0, column: 0, side: "left" }, "rectangle");
		selection.update({ blockId: "b", row: 2, column: 0, side: "right" });
		selection.followRows({ trimmed: 0, remap: [[0, 0], [1, 2], [2, 3]], remapEnd: [3, 4] });
		expect(selection.text()).toBeNull();
	});
});
```

Create `packages/terminal/ts/renderer-dom/src/selection-rectangle.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore, type FontConfig } from "@operator/terminal-core";
import { ALT_BLOCK_ID, DomBlockRenderer, warpDarkTheme } from "./index";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");
const font: FontConfig = { family: "ui-monospace, monospace", sizePx: 14, lineHeight: 1.2, weight: 400, letterSpacingPx: 0, ligatures: false };
const CELL_W = 8.4;
const CELL_H = 16.8;
beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

function layoutRows(host: HTMLElement): HTMLElement[] {
	const rows = [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")];
	rows.forEach((row, index) => {
		row.getBoundingClientRect = () => ({ left: 0, right: 600, width: 600, top: index * CELL_H, bottom: (index + 1) * CELL_H, height: CELL_H, x: 0, y: index * CELL_H, toJSON: () => ({}) }) as DOMRect;
	});
	return rows;
}

function mountWith(input: string) {
	const core = createTerminalCore({ columns: 40, scrollback: 100 });
	core.feed(new TextEncoder().encode(input));
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(warpDarkTheme);
	renderer.setFont(font);
	renderer.measure = () => ({ cellWidth: CELL_W, cellHeight: CELL_H });
	return { core, host, renderer };
}

describe("rectangle selection in the renderer", () => {
	it("paints the same cells on every row and copies each row's slice", () => {
		const { host, renderer } = mountWith("alpha beta\r\ngamma delta\r\nepsilon\r\n");
		const rows = layoutRows(host);
		const blockId = host.querySelector<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionBegin({ blockId, row: 0, column: 2, side: "left" }, "rectangle");
		renderer.selectionUpdate({ blockId, row: 2, column: 5, side: "right" });
		expect(renderer.selectedText()).toBe("pha\nmma\nsilo");
		for (const row of rows.slice(0, 3)) {
			expect(row.style.backgroundImage).toContain(`transparent ${2 * CELL_W}px`);
			expect(row.style.backgroundImage).toContain(`${6 * CELL_W}px`);
		}
		renderer.dispose();
	});

	it("works on the alternate screen", () => {
		const { host, renderer } = mountWith("\x1b[?1049halpha beta\r\ngamma delta\r\n");
		renderer.selectionBegin({ blockId: ALT_BLOCK_ID, row: 0, column: 6, side: "left" }, "rectangle");
		renderer.selectionUpdate({ blockId: ALT_BLOCK_ID, row: 1, column: 9, side: "right" });
		expect(renderer.selectedText()).toBe("beta\ndelt");
		expect(host.querySelector(".terminal-alt-surface")).not.toBeNull();
		renderer.dispose();
	});
});
```

(Cells 2–5 of `alpha beta` are `pha `; trailing spaces are trimmed per row.)

`renderer-dom` and `react` compile their tests with `tsc -b` (`ts/renderer-dom/tsconfig.json` includes `src/**/*.ts` with no test exclusion), so every test above must type-check once its task is implemented; `npm run build:ts` in Step 4 is that check.

- [ ] **Step 2: Run them to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/renderer-dom && npx vitest run src/selection-model.test.ts src/selection-geometry.test.ts src/selection-text.test.ts src/highlight-painter.test.ts src/renderer-selection.test.ts src/selection-rectangle.test.ts 2>&1 | tail -15`
Expected: FAIL — `resolveRange` treats `rectangle` like `simple` (no `rectangle: true`, and a zero-width rectangle across two rows is not null); `rowFillSpan` fills the middle row to the edge (`right: 400`); `selectedText` joins wrapped rows (`"3456789"`-style text); the painter reuses the cached stream paint; the rewrap drop test gets text instead of `null`; the renderer tests copy a stream selection.

- [ ] **Step 3: Implement**

`selection-model.ts` line 3 becomes

```ts
export type SelectionKind = "simple" | "word" | "line" | "rectangle";
```

line 8 becomes

```ts
export type SelectionRange = Readonly<{ start: Boundary; end: Boundary; rectangle?: boolean }>;
```

and add, above `resolveRange`, and as the first statement inside it:

```ts
function rectangleRange(state: SelectionState, order: BlockOrder): SelectionRange | null {
	const head = boundaryOf(state.head);
	const tail = boundaryOf(state.tail);
	const left = Math.min(head.cell, tail.cell);
	const right = Math.max(head.cell, tail.cell);
	if (right <= left) return null;
	const headFirst = compareBoundary({ ...head, cell: 0 }, { ...tail, cell: 0 }, order) <= 0;
	const top = headFirst ? head : tail;
	const bottom = headFirst ? tail : head;
	return { start: { ...top, cell: left }, end: { ...bottom, cell: right }, rectangle: true };
}
```

```ts
	if (state.kind === "rectangle") return rectangleRange(state, order);
```

`selection-geometry.ts` — `rowFillSpan` (lines 47-62) becomes:

```ts
export function rowFillSpan(
	range: SelectionRange,
	box: RowBox,
	order: BlockOrder,
	cellWidth: number,
): FillSpan | null {
	const here = { blockId: box.blockId, row: box.row, cell: 0 };
	if (range.rectangle) {
		if (compareBoundary(here, { ...range.start, cell: 0 }, order) < 0 || compareBoundary(here, { ...range.end, cell: 0 }, order) > 0) return null;
		const left = Math.min(range.start.cell * cellWidth, box.width);
		const right = Math.min(range.end.cell * cellWidth, box.width);
		return right - left <= 0.5 ? null : { left, right };
	}
	const startsHere = range.start.blockId === box.blockId && range.start.row === box.row;
	const endsHere = range.end.blockId === box.blockId && range.end.row === box.row;
	if (!startsHere && compareBoundary(here, range.start, order) < 0) return null;
	if (!endsHere && compareBoundary(here, range.end, order) > 0) return null;
	const left = startsHere ? Math.min(range.start.cell * cellWidth, box.width) : 0;
	const right = endsHere ? Math.min(range.end.cell * cellWidth, box.width) : box.width;
	if (right - left <= 0.5) return null;
	return { left, right };
}
```

`selection-text.ts` — add before `selectedText`:

```ts
function rectangleText(range: SelectionRange, rows: TextRows): string {
	const first = rows.blockIds.indexOf(range.start.blockId);
	const last = rows.blockIds.indexOf(range.end.blockId);
	if (first < 0 || last < 0 || last < first) return "";
	const lines: string[] = [];
	for (let index = first; index <= last; index += 1) {
		const blockId = rows.blockIds[index]!;
		const top = rows.firstRow(blockId);
		const fromRow = Math.max(index === first ? range.start.row : top, top);
		const toRow = index === last ? range.end.row : top + rows.rowCount(blockId) - 1;
		for (let row = fromRow; row <= toRow; row += 1) {
			const indent = rows.rowIndent?.(blockId, row) ?? 0;
			lines.push(cut(rows.rowText(blockId, row), rows.rowSpans(blockId, row), Math.max(range.start.cell - indent, 0), Math.max(range.end.cell - indent, 0)));
		}
	}
	return lines.join("\n");
}
```

and make the first statement of `selectedText`:

```ts
	if (range.rectangle) return rectangleText(range, rows);
```

`highlight-painter.ts` line 83 becomes:

```ts
		.map(({ kind, colour, rank, range: { start, end, rectangle } }) => `${kind}:${colour}:${rank}:${start.blockId}:${start.row}:${start.cell}:${end.blockId}:${end.row}:${end.cell}:${rectangle === true}`)
```

Append to `selection-anchor.ts`:

```ts

export function rowsKeepTheirShape(top: number, bottom: number, event: RowEvent): boolean {
	const base = remapStableRow(top, event);
	for (let row = top + 1; row <= bottom; row += 1) if (remapStableRow(row, event) !== base + (row - top)) return false;
	return true;
}
```

`renderer-selection.ts`: import `rowsKeepTheirShape` from `./selection-anchor.js` and `ALT_BLOCK_ID` from `./selection-view.js`; in `followRows`, directly after `if (!selection) return;` insert:

```ts
		if (selection.kind === "rectangle" && selection.head.blockId !== ALT_BLOCK_ID) {
			if (!rowsKeepTheirShape(Math.min(selection.head.row, selection.tail.row), Math.max(selection.head.row, selection.tail.row), event)) {
				this.drop();
				return;
			}
		}
```

and in `settle`, the anchor line becomes:

```ts
			this.anchors = selection.kind === "rectangle" ? null : { head: anchorOf(selection.head, rows), tail: anchorOf(selection.tail, rows) };
```

(A rectangle has no anchors, so `followRows` moves its two points by row only, keeping its columns.)

- [ ] **Step 4: Run the tests**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/renderer-dom && npx vitest run 2>&1 | grep -E "Tests  |FAIL"
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && npm run build:ts 2>&1 | tail -1 && (cd ts/react && npx vitest run 2>&1 | grep -E "Tests  |FAIL") && npm run check:boundaries 2>&1 | tail -1
```
Expected: renderer-dom = previous + 12, react unchanged, no `FAIL`; `boundary check passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection
git add packages/terminal/ts/renderer-dom/src/selection-model.ts packages/terminal/ts/renderer-dom/src/selection-geometry.ts packages/terminal/ts/renderer-dom/src/selection-text.ts packages/terminal/ts/renderer-dom/src/highlight-painter.ts packages/terminal/ts/renderer-dom/src/selection-anchor.ts packages/terminal/ts/renderer-dom/src/renderer-selection.ts packages/terminal/ts/renderer-dom/src/selection-model.test.ts packages/terminal/ts/renderer-dom/src/selection-geometry.test.ts packages/terminal/ts/renderer-dom/src/selection-text.test.ts packages/terminal/ts/renderer-dom/src/highlight-painter.test.ts packages/terminal/ts/renderer-dom/src/renderer-selection.test.ts packages/terminal/ts/renderer-dom/src/selection-rectangle.test.ts
git commit -m "feat(renderer-dom): rectangle selections

A fourth SelectionKind; the range carries rectangle: true, the painter fills the
same cells on every row and copy gives one slice per row (Warp joins rectangle
rows with a newline, model/blocks/selection.rs:1024-1094). A rewrap that
reshapes the rectangle's rows drops it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Alt-drag selects a rectangle

**Files:**
- Modify: `packages/terminal/ts/react/src/selection-gesture.ts` (append after line 59)
- Modify: `packages/terminal/ts/react/src/use-surface-input.ts:4` (import), `:77` (drag start), `:89` (release), press lines from Task 7
- Test: `packages/terminal/ts/react/src/selection-gesture.test.ts` (append), `TerminalSurface.rectangle.test.tsx` (new)

**Interfaces:**
- Consumes: `SelectionKind` `"rectangle"` (Task 8); Task 7's `pressExtends`.
- Produces: `export function rectangleModifierHeld(event: { altKey: boolean }): boolean`; a left press with Alt (any other modifiers) selects a rectangle on drag; Alt wins over Shift.

- [ ] **Step 1: Write the failing tests**

Append to `selection-gesture.test.ts` (and add `rectangleModifierHeld` to its import):

```ts

describe("rectangleModifierHeld", () => {
	it("is Alt (Option) with or without other modifiers, so Warp's Cmd+Option and Ctrl+Alt count too", () => {
		expect(rectangleModifierHeld({ altKey: true })).toBe(true);
		expect(rectangleModifierHeld({ altKey: false })).toBe(false);
	});
});
```

Create `packages/terminal/ts/react/src/TerminalSurface.rectangle.test.tsx`:

```tsx
import { act, cleanup } from "@testing-library/react";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { cellHeight, cellWidth, feed, flushRepaint, loadWasm, renderSurface } from "./surface-harness";

function layoutRows(container: HTMLElement): HTMLElement[] {
	const rows = [...container.querySelectorAll<HTMLElement>("[data-terminal-row]")];
	rows.forEach((row, index) => {
		row.getBoundingClientRect = () => ({ left: 0, right: 600, width: 600, top: index * cellHeight, bottom: (index + 1) * cellHeight, height: cellHeight, x: 0, y: index * cellHeight, toJSON: () => ({}) }) as DOMRect;
	});
	return rows;
}

function mouse(target: EventTarget, type: string, x: number, y: number, init: MouseEventInit = {}): void {
	target.dispatchEvent(new MouseEvent(type, { clientX: x, clientY: y, button: 0, bubbles: true, cancelable: true, ...init }));
}

function drag(from: HTMLElement, x0: number, y0: number, x1: number, y1: number, init: MouseEventInit): void {
	mouse(from, "mousedown", x0, y0, { detail: 1, ...init });
	mouse(window, "mousemove", x1, y1, init);
	mouse(window, "mouseup", x1, y1, init);
}

async function mounted(text: string, onSendRaw = vi.fn()) {
	const writeClipboard = vi.fn(async (_text: string) => {});
	const host = { writeClipboard, readClipboard: async () => "", openLink: async () => {} };
	const { container, core } = renderSurface({ host, onSendRaw });
	act(() => { feed(core, text); });
	await flushRepaint();
	const rows = layoutRows(container);
	const surface = container.querySelector(".terminal-host") as HTMLElement;
	const copy = () => {
		writeClipboard.mockClear();
		surface.dispatchEvent(new KeyboardEvent("keydown", { key: "c", metaKey: true, bubbles: true, cancelable: true }));
		return writeClipboard.mock.lastCall?.[0];
	};
	return { rows, copy, onSendRaw };
}

const TEXT = "alpha beta\r\ngamma delta\r\nepsilon\r\n";

describe("Alt-drag", () => {
	const originalPlatform = Object.getOwnPropertyDescriptor(navigator, "platform");
	beforeAll(async () => {
		await loadWasm();
		Object.defineProperty(navigator, "platform", { value: "MacIntel", configurable: true });
	});
	afterEach(() => cleanup());
	afterAll(() => {
		if (originalPlatform) Object.defineProperty(navigator, "platform", originalPlatform);
	});

	it("selects a rectangle and copies one slice per row", async () => {
		const { rows, copy } = await mounted(TEXT);
		drag(rows[0]!, cellWidth + 1, cellHeight * 0.5, cellWidth * 5 - 1, cellHeight * 2.5, { altKey: true });
		expect(copy()).toBe("lpha\namma\npsil");
		for (const row of rows.slice(0, 3)) expect(row.style.backgroundImage).toContain(`transparent ${cellWidth}px`);
	});

	it("takes Warp's Cmd+Option chord as a rectangle too", async () => {
		const { rows, copy } = await mounted(TEXT);
		drag(rows[0]!, cellWidth + 1, cellHeight * 0.5, cellWidth * 5 - 1, cellHeight * 2.5, { altKey: true, metaKey: true });
		expect(copy()).toBe("lpha\namma\npsil");
	});

	it("needs Shift with Alt in a mouse-reporting program, and Alt wins over Shift", async () => {
		const { rows, copy, onSendRaw } = await mounted(`\x1b[?1000h\x1b[?1006h${TEXT}`);
		drag(rows[0]!, cellWidth + 1, cellHeight * 0.5, cellWidth * 5 - 1, cellHeight * 2.5, { altKey: true });
		expect(onSendRaw).toHaveBeenCalled();
		onSendRaw.mockClear();
		drag(rows[0]!, cellWidth + 1, cellHeight * 0.5, cellWidth * 5 - 1, cellHeight * 2.5, { altKey: true, shiftKey: true });
		expect(onSendRaw).not.toHaveBeenCalled();
		expect(copy()).toBe("lpha\namma\npsil");
	});

	it("clears the selection on an Alt-click without a drag", async () => {
		const { rows, copy } = await mounted(TEXT);
		drag(rows[0]!, cellWidth + 1, cellHeight * 0.5, cellWidth * 5 - 1, cellHeight * 2.5, { altKey: true });
		mouse(rows[1]!, "mousedown", 1, cellHeight * 1.5, { detail: 1, altKey: true });
		mouse(window, "mouseup", 1, cellHeight * 1.5, { altKey: true });
		expect(copy()).toBeUndefined();
		expect(rows[0]!.style.backgroundImage).toBe("");
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/react && npx vitest run src/selection-gesture.test.ts src/TerminalSurface.rectangle.test.tsx 2>&1 | tail -10`
Expected: FAIL — `rectangleModifierHeld is not a function`; the drags copy stream text (`"lpha beta\ngamma delta\nepsil"`); the Alt-click test passes (guard).

- [ ] **Step 3: Implement**

Append to `selection-gesture.ts`:

```ts

export function rectangleModifierHeld(event: { altKey: boolean }): boolean {
	return event.altKey;
}
```

`use-surface-input.ts`: line 4 becomes

```ts
import { autoScrollRows, exceedsDragThreshold, isCopyChord, isHintChord, kindForClickCount, linkModifierHeld, rectangleModifierHeld } from "./selection-gesture.js";
```

the drag-start line (Task 7's line 77) becomes

```ts
				if (!pressExtends && (pressKind === "simple" || pressKind === "rectangle")) target.selectionBegin(pressPoint, pressKind);
```

the release line (Task 7's first line of the release block) becomes

```ts
			if (target && pressOrigin && pressPoint && !dragging && !pressExtends && (pressKind === "simple" || pressKind === "rectangle")) target.selectionClear(pressPoint);
```

and the press block (Task 7's version of lines 180-186) becomes

```ts
			pressOrigin = { x: event.clientX, y: event.clientY };
			pressPoint = point;
			pressKind = rectangleModifierHeld(event) ? "rectangle" : kindForClickCount(event.detail);
			pressExtends = event.shiftKey && pressKind === "simple";
			dragging = false;
			if (pressExtends) target.selectionUpdate(point, true);
			else if (pressKind === "word" || pressKind === "line") target.selectionBegin(point, pressKind);
```

- [ ] **Step 4: Run the tests**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/ts/react && npx vitest run 2>&1 | grep -E "Tests  |FAIL"
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && npm run check:boundaries 2>&1 | tail -1 && wc -l ts/react/src/use-surface-input.ts ts/react/src/selection-gesture.ts
```
Expected: react = previous + 5, no `FAIL`; `boundary check passed`; 344 and 63.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection
git add packages/terminal/ts/react/src/selection-gesture.ts packages/terminal/ts/react/src/selection-gesture.test.ts packages/terminal/ts/react/src/use-surface-input.ts packages/terminal/ts/react/src/TerminalSurface.rectangle.test.tsx
git commit -m "feat(terminal-react): Alt-drag selects a rectangle

Alt held at the press, with or without Cmd/Ctrl, so Warp's Cmd+Option and
Ctrl+Alt (warpui_core/src/text/mod.rs:42-54) and Ghostty's Option
(surface_mouse.zig:98-103) all work. Alt wins over Shift; in a mouse-reporting
program Shift+Alt selects.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Playwright gate for Shift+click, Alt-drag and a resize

**Files:**
- Create: `packages/terminal/bench/selection-extras-gate.mjs`
- Modify: `packages/terminal/package.json:17` (add a script after `bench:selection`)

**Interfaces:**
- Consumes: the existing harness `bench/select.html` + `bench/select-main.ts` (40 command blocks, `window.__gate.copied`, `window.__gateReady`; `select-main.ts:31-107`), Tasks 5, 7, 9.
- Produces: `npm run bench:selection:extras` printing three `PASS` lines, exit code 0.

- [ ] **Step 1: Write the gate (it is the test)**

Create `packages/terminal/bench/selection-extras-gate.mjs`:

```js
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const configFile = fileURLToPath(new URL("./vite.config.ts", import.meta.url));
const copyChord = process.platform === "darwin" ? "Meta+c" : "Control+Shift+c";

async function copy(page) {
	const before = await page.evaluate(() => window.__gate.copied.length);
	await page.keyboard.press(copyChord);
	await page.waitForFunction((count) => window.__gate.copied.length > count, before, { timeout: 5000 });
	return page.evaluate(() => window.__gate.copied.at(-1) ?? "");
}

function visibleRows(page) {
	return page.evaluate(() =>
		[...document.querySelectorAll("[data-terminal-row]")]
			.filter((element) => element.getClientRects().length > 0)
			.map((element) => {
				const box = element.getBoundingClientRect();
				return { row: Number(element.dataset.terminalRow), text: element.textContent ?? "", left: box.left, top: box.top, bottom: box.bottom, width: box.width };
			})
			.filter((row) => row.top > 60 && row.bottom < 840)
			.sort((a, b) => a.row - b.row),
	);
}

const middle = (row) => (row.top + row.bottom) / 2;

const server = await createServer({ configFile, logLevel: "error" });
let browser;
try {
	await server.listen(0);
	const address = server.httpServer?.address();
	if (!address || typeof address === "string") throw new Error("Vite did not bind a loopback port");
	browser = await chromium.launch({ headless: true });
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await page.goto(`http://127.0.0.1:${address.port}/select.html`);
	await page.waitForFunction(() => window.__gateReady === true, undefined, { timeout: 15000 });
	const cell = await page.evaluate(() => {
		const run = [...document.querySelectorAll("[data-terminal-run]")].find((element) => /^[ -~]{10,}$/u.test(element.textContent ?? ""));
		if (!run) throw new Error("no ASCII run to measure a cell from");
		return run.getBoundingClientRect().width / (run.textContent ?? "").length;
	});

	await page.mouse.move(800, 450);
	await page.mouse.wheel(0, -100000);
	await page.waitForTimeout(300);
	const first = (await visibleRows(page)).find((row) => row.text.startsWith("Thinking through step"));
	if (!first) throw new Error("no 'Thinking through step' row on screen at the top");
	await page.mouse.click(first.left + 2, middle(first));
	await page.mouse.move(800, 450);
	await page.mouse.wheel(0, 100000);
	await page.waitForTimeout(300);
	const bottomRows = await visibleRows(page);
	if (bottomRows.some((row) => row.row === first.row)) throw new Error("the clicked row is still on screen, so the Shift+click would not cross rows scrolled out of view");
	const last = [...bottomRows].reverse().find((row) => row.text.startsWith("Edited file"));
	if (!last) throw new Error("no 'Edited file' row on screen at the bottom");
	await page.keyboard.down("Shift");
	await page.mouse.click(last.left + last.width - 4, middle(last));
	await page.keyboard.up("Shift");
	const extended = await copy(page);
	if (!extended.startsWith(first.text.trimEnd()) || !extended.endsWith(last.text.trimEnd())) {
		throw new Error(`Shift+click copied ${JSON.stringify(extended.slice(0, 80))}…${JSON.stringify(extended.slice(-80))}`);
	}
	const extendedLines = extended.split("\n").length;
	if (extendedLines < 40) throw new Error(`Shift+click copied ${extendedLines} lines, expected at least 40`);
	process.stdout.write(`PASS shift-click copied ${extendedLines} lines from row ${first.row} to row ${last.row}\n`);

	const textRows = (await visibleRows(page)).filter((row) => row.text.trim().length > 12);
	if (textRows.length < 8) throw new Error(`only ${textRows.length} text rows on screen for the rectangle`);
	const top = textRows[textRows.length - 8];
	const bottom = textRows[textRows.length - 5];
	const from = { x: top.left + cell * 2 + 1, y: middle(top) };
	const to = { x: top.left + cell * 12 - 1, y: middle(bottom) };
	await page.keyboard.down("Alt");
	await page.mouse.move(from.x, from.y);
	await page.mouse.down();
	for (let step = 1; step <= 20; step += 1) await page.mouse.move(from.x + ((to.x - from.x) * step) / 20, from.y + ((to.y - from.y) * step) / 20);
	await page.mouse.up();
	await page.keyboard.up("Alt");
	const expected = await page.evaluate(([a, b]) => {
		const byRow = new Map();
		for (const element of document.querySelectorAll("[data-terminal-row]")) {
			if (element.getClientRects().length === 0) continue;
			const row = Number(element.dataset.terminalRow);
			if (row >= a && row <= b) byRow.set(row, (element.textContent ?? "").slice(2, 12).replace(/ +$/u, ""));
		}
		return [...byRow.entries()].sort((x, y) => x[0] - y[0]).map(([, text]) => text);
	}, [top.row, bottom.row]);
	const boxed = await copy(page);
	if (boxed !== expected.join("\n")) throw new Error(`Alt-drag copied ${JSON.stringify(boxed)}, expected ${JSON.stringify(expected.join("\n"))}`);
	const painted = await page.evaluate(() => document.querySelectorAll('[data-terminal-row][style*="terminal-selection"]').length);
	if (painted !== expected.length) throw new Error(`Alt-drag painted ${painted} rows, expected ${expected.length}`);
	process.stdout.write(`PASS alt-drag copied ${expected.length} slices of cells 2-12\n`);

	const target = [...(await visibleRows(page))].reverse().find((row) => /^Edited file src\/module-\d+\.ts/u.test(row.text));
	if (!target) throw new Error("no 'Edited file src/module-N.ts' row on screen");
	const word = target.text.split(" ")[2];
	await page.mouse.dblclick(target.left + cell * 15 + 1, middle(target));
	const before = await copy(page);
	if (before !== word) throw new Error(`double-click copied ${JSON.stringify(before)}, expected ${JSON.stringify(word)}`);
	await page.setViewportSize({ width: 260, height: 900 });
	await page.waitForTimeout(600);
	const after = await copy(page);
	if (after !== word) throw new Error(`after the resize the selection copied ${JSON.stringify(after)}, expected ${JSON.stringify(word)}`);
	const paintedText = await page.evaluate(() => [...document.querySelectorAll('[data-terminal-row][style*="terminal-selection"]')].map((element) => element.textContent ?? "").join("\n"));
	if (!paintedText.includes(word)) throw new Error(`after the resize the painted rows read ${JSON.stringify(paintedText)}`);
	process.stdout.write(`PASS ${word} stayed selected across a resize to 260 px\n`);
} catch (error) {
	process.stderr.write(`FAIL ${error instanceof Error ? error.message : String(error)}\n`);
	process.exitCode = 1;
} finally {
	await browser?.close();
	await server.close();
}
```

In `packages/terminal/package.json`, after line 17 (`"bench:selection": "node ./bench/selection-gate.mjs",`) add:

```json
		"bench:selection:extras": "node ./bench/selection-extras-gate.mjs",
```

- [ ] **Step 2: Prove the gate catches a regression**

Run the new gate against the commit before Shift+click existed (Task 6's commit), in a throwaway worktree:

```bash
BASE=$(git -C /Users/omaraly/development/AI/Operator-wave1-selection log --format=%H -1 --grep='extend a selection, or select from the last plain click')
git -C /Users/omaraly/development/AI/Operator-wave1-selection worktree add --detach /Users/omaraly/development/AI/Operator-wave1-gate-check "$BASE"
cp /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal/bench/selection-extras-gate.mjs /Users/omaraly/development/AI/Operator-wave1-gate-check/packages/terminal/bench/
cd /Users/omaraly/development/AI/Operator-wave1-gate-check/packages/terminal && npm ci >/dev/null && npm run build:wasm -- --force >/dev/null && npm run build:ts >/dev/null && node ./bench/selection-extras-gate.mjs; echo "exit $?"
git -C /Users/omaraly/development/AI/Operator-wave1-selection worktree remove --force /Users/omaraly/development/AI/Operator-wave1-gate-check
```
Expected: one line starting with `FAIL` (the Shift+click clears the selection there, so the copy chord writes nothing and `copy()` times out) and `exit 1`.

- [ ] **Step 3: Run it on the branch**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && npm run build:ts >/dev/null && npm run bench:selection:extras && npm run bench:selection`
Expected: three `PASS` lines from the new gate, then `PASS selection survived N repaints`.

- [ ] **Step 4: Boundaries**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal && npm run check:boundaries 2>&1 | tail -1`
Expected: `boundary check passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection
git add packages/terminal/bench/selection-extras-gate.mjs packages/terminal/package.json
git commit -m "test(terminal): Playwright gate for Shift+click, Alt-drag and a resize

bench:selection:extras: Shift+click across rows scrolled out of view, an
Alt-drag rectangle, and a word that stays selected when the pane narrows.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Documentation

**Files:**
- Modify: `TERMINAL.md` (§2 delta bullet, new §4.51 after §4.50 ending at line 1985, §6 recipe after line 2452)
- Modify: `packages/terminal/CHANGELOG.md:3-4` (Unreleased)
- Modify: `docs/terminal/2026-09-19-terminal-reference-survey.md:329`, `:404`, `:1469`, `:2299` (status lines)
- Modify: `docs/terminal/2026-09-24-terminal-roadmap-design.md` (append to "Real-app checks, deferred to the end", after line 551)

**Interfaces:**
- Consumes: Tasks 1–10.
- Produces: documentation only.

- [ ] **Step 1: TERMINAL.md**

In §2, at the end of the "Delta / incremental export" bullet (after "…without diffing the whole snapshot." at line 250), add:

```markdown
  A rewrap's `remap` pairs cover only the old completed rows; where the rows
  after them went (an agent's live frame, a prompt kept on screen) is
  `TerminalCore::take_remap_end()` (`crates/vt-core/src/remap_end.rs`), kept
  outside `Delta` so the parser goldens' delta digests do not change. vt-wasm
  appends it as the last pair of its remap buffer and `takeRowEvent`
  (`ts/core/src/row-events.ts`) pops it into `RowEvent.remapEnd`;
  `remapStableRow(row, event)` applies both.
```

After §4.50 (before `## 5. Known gaps`) add:

```markdown
### 4.51 Shift+click, rectangles, and a selection that survives a width change (wishlist wave 1, 2026-09-27)
- Before: Shift only bypassed mouse reporting (`ts/react/src/use-surface-input.ts:122`);
  nothing remembered a plain click; there was no rectangle; and
  `TerminalSurface.tsx:330` cleared the selection on every grid change. Warp also
  clears on a resize (`app/src/terminal/model/blocks.rs:2299-2301`,
  `model/alt_screen.rs:125-127`); the wishlist's owner asked for survival (item 6).
  Copy and double-click on a rewrapped continuation row were shifted by its hanging
  indent: the row is padded (`row-builder.ts:50-51`), columns count from the padded
  edge, the text has no indent.
- Now: Shift+press (one click, not reported) extends the selection's tail from its
  head, keeping the kind; with no selection it selects from the *caret*, the last
  plain press that went to the selection (Ghostty `src/Surface.zig:3852-3882`,
  behaviour only; Warp's Shift+click selects blocks, `app/src/terminal/view.rs:18407`,
  and Operator has no block selection). Alt held at the press (with or without
  Cmd/Ctrl) selects a rectangle: `SelectionKind` `"rectangle"`, a range with
  `rectangle: true`, the same cells painted on every row, copy one slice per row
  (Warp's chord is Cmd+Option / Ctrl+Alt, `warpui_core/src/text/mod.rs:42-54`;
  Ghostty's Option alone, `surface_mouse.zig:98-103`). Alt wins over Shift; in a
  mouse-reporting program Shift+Alt selects. A primary-screen selection keeps a
  *line anchor* per point (first row of its logical line + cells into it,
  `selection-anchor.ts`); row events move the anchor and `RendererSelection.view()`
  resolves the point against the new rows, so the highlight and the copy stay on
  the same text; rows after the rewrapped ones move by `remapEnd` (§2). The
  alternate screen is not remapped and a real resize still clears it. A rectangle is
  kept only when a remap moves its rows as a block. `TextRows.rowIndent` makes copy,
  word expansion, rectangles and anchors subtract a row's hanging indent.
- Not covered: hover links and hint labels on an indented continuation row still
  use the padded column space; a caret or selection on rows that a Plan 10 pull-back
  rewrites keeps its stable row but not its text (not known to occur); two rewraps
  delivered by two syncs without a snapshot in between lose the first remap
  (`vt-wasm/src/lib.rs` clears the buffer per delta; not known to occur, every
  renderer `sync` is followed by a snapshot).
- Guards: `crates/vt-core/tests/remap_end.rs`; `ts/core/src/row-events.test.ts`,
  `terminal-core.test.ts` "reports where the rows after the rewrapped ones went";
  renderer-dom `selection-anchor.test.ts`, `renderer-selection.test.ts`,
  `selection-rewrap.test.ts`, `selection-extend.test.ts`,
  `selection-rectangle.test.ts`, `selection-indent.test.ts` and the new cases in
  `selection-model.test.ts`, `selection-text.test.ts`, `selection-geometry.test.ts`,
  `highlight-painter.test.ts`; react `TerminalSurface.shift-click.test.tsx`,
  `TerminalSurface.rectangle.test.tsx`, `TerminalSurface.selection.test.tsx`
  "keeps a primary-screen selection on its words across a real resize" and "clears
  an alternate-screen selection on a real resize", `selection-gesture.test.ts`
  "rectangleModifierHeld"; `npm run bench:selection:extras`.
```

In §6, after the `npm run bench:selection` line (line 2452) add:

```bash
npm run bench:selection:extras  # Playwright: Shift+click across scrolled rows, Alt-drag rectangle, a word selected across a resize
```

- [ ] **Step 2: CHANGELOG**

Insert after line 4 (the blank line under `## Unreleased`):

```markdown
- react: Shift+click extends the selection from its anchor to the clicked cell (across blocks and rows scrolled out of view); with no selection it selects from the last plain click. A Shift double-click is a plain double-click; Shift+drag keeps extending (`TERMINAL.md` §4.51).
- react/renderer-dom: Alt-drag (Option-drag; Cmd+Option and Ctrl+Alt too) selects a rectangle; copy gives each row's slice, one line per row. In a mouse-reporting program use Shift+Alt.
- renderer-dom/react: a selection on the transcript stays on the same text, and copies the same text, when the pane changes width; a full-screen program's selection is still cleared by a resize. core: `RowEvent.remapEnd` and `remapStableRow`; vt-core: `TerminalCore::take_remap_end`, outside `Delta`.
- renderer-dom: copy and double-click on a rewrapped continuation row (a hanging indent) use the cells that are painted, not cells shifted by the indent.
```

- [ ] **Step 3: Survey status lines and deferred app checks**

Replace line 329 of the survey with:

```markdown
> **Status: Partial.** Plan B — selection and find hits are keyed by stable row ids, so they survive a trim. Wishlist wave 1 (2026-09-27) — the selection and the Shift+click caret follow the rewrap `remap` through line anchors and `RowEvent.remapEnd` (`TERMINAL.md` §4.51). Not done: no `PinSet`; find hits and the cursor are not carried through a reflow.
```

line 404:

```markdown
> **Status: Partial.** Plan E — copy joins a soft-wrapped line. Wishlist wave 1 — rectangle (Alt-drag) and Shift+click extension (`TERMINAL.md` §4.51). Not done: Shift+arrow adjust, the select-block-output gesture, configurable click behaviours.
```

line 1469:

```markdown
> **Status: Done for the selection.** Plan B — `onRowEvents` (trim and rewrap `remap`) and stable rows make trims harmless. Wishlist wave 1 — the selection applies `remap` plus `remapEnd` (`TERMINAL.md` §4.51). Find hits do not.
```

line 2299:

```markdown
> **Status: Partial.** Plan E — copy joins a soft-wrapped line; Plan B — selection on stable rows with a per-row damage diff; wishlist wave 1 — column (Alt) selection (`TERMINAL.md` §4.51). Not done: the overlay container (the fill is still per row).
```

Append to `docs/terminal/2026-09-24-terminal-roadmap-design.md` after line 551:

```markdown
- **Wishlist wave 1 — selection:** in a zsh pane run `seq 1 300`; click on `10`,
  scroll to the bottom, Shift+click after `290`, Cmd+C: the clipboard holds 10 to 290.
  Plain click, then Shift+click in a Claude Code pane across a reply and the grey
  message band: one selection, copy gives the text. Alt-drag over `ls -l` output:
  a box; copy gives each row's slice. Cmd+Option-drag does the same. Select a
  sentence in a long Claude reply and drag the window narrower and wider: the
  highlight stays on the sentence and copy gives it unchanged. In `vim` (with
  `:set mouse=a`) Shift+click extends and Shift+Alt-drag makes a box; resizing
  clears a selection there.
```

- [ ] **Step 4: Check the docs build nothing and cite real lines**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-selection && grep -n "4.51" TERMINAL.md | head -3 && sed -n 327,330p docs/terminal/2026-09-19-terminal-reference-survey.md`
Expected: the new heading and the §2/§6 references; the new status line.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection
git add TERMINAL.md packages/terminal/CHANGELOG.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/terminal/2026-09-24-terminal-roadmap-design.md
git commit -m "docs(terminal): §4.51 selection wave 1, changelog, survey status, deferred app checks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Every gate, the headless real-app run, and the report

**Files:** none changed unless a gate fails (then fix in the owning task's files and commit with that task's style).

**Interfaces:**
- Consumes: Tasks 1–11.
- Produces: the report.

- [ ] **Step 1: Rust and the goldens**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal
cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
cargo test --release -p vt-core --test parser_goldens --test resize_goldens --test remap_end 2>&1 | grep "test result"
cd crates/vt-core/tests/goldens && shasum -a 256 -c --quiet "$HOME/wave1-goldens.sha256" && echo goldens-unchanged
```
Expected: clippy `Finished …`; only `rust-done`; three `test result: ok.`; `goldens-unchanged`.

- [ ] **Step 2: Both wasm builds, the mirror and the daemon**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal
cargo build --release -p vt-host --target wasm32-unknown-unknown 2>&1 | tail -1
cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
git -C /Users/omaraly/development/AI/Operator-wave1-selection status --short backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
npm run build:wasm -- --force 2>&1 | tail -1 && npm run build:ts 2>&1 | tail -1
cd /Users/omaraly/development/AI/Operator-wave1-selection/backend && go test ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -4 && go vet ./internal/adapters/runtime/ptyhost/...
cd /Users/omaraly/development/AI/Operator-wave1-selection && npm --prefix frontend run build:daemon 2>&1 | tail -2
```
Expected: no status line for `vt_host.wasm` (the committed one from Task 2 is current); `build-wasm: … ready`; Go `ok` (only the pre-existing `TestProcessEnvironmentLetsOverridesWin` may fail, `TERMINAL.md` §5); `frontend/daemon/opr` built.

- [ ] **Step 3: TypeScript suites and boundaries**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal
for p in core renderer-dom react editor completions; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Tests  "); done
npm run check:boundaries 2>&1 | tail -1
node --test ./scripts/browser-types.test.mjs ./scripts/spawn-recipe-package.test.mjs ./bench/agent-session/fixtures.test.mjs ./bench/agent-session/session-api.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"
wc -l crates/vt-core/src/parser.rs crates/vt-core/src/lib.rs crates/vt-wasm/src/lib.rs ts/core/src/terminal-core.ts ts/renderer-dom/src/dom-block-renderer.ts ts/react/src/use-surface-input.ts
```
Expected: core = Task 0 + 6, renderer-dom = Task 0 + 40, react = Task 0 + 11, editor and completions unchanged; `boundary check passed`; `ℹ fail 0`; every file ≤ 600 and `dom-block-renderer.ts` 598.

- [ ] **Step 4: Frontend**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/frontend && npx tsc --noEmit -p . && echo typecheck-ok
npm test 2>&1 | grep -E "Tests  |FAIL" | tail -3
```
Expected: `typecheck-ok`; the frontend suite passes with no `FAIL`.

- [ ] **Step 5: Benches — the headless real-app run**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-selection/packages/terminal
npm run bench:selection
npm run bench:selection:extras
npm run bench:feel 2>&1 | tail -3
npm run bench:agent:gate 2>&1 | tail -2
npm run bench:agent:scroll 2>&1 | tail -3
git -C /Users/omaraly/development/AI/Operator-wave1-selection status --short packages/terminal/bench/agent-session/baselines
```
Expected: `PASS selection survived N repaints`; the three extras `PASS` lines; `bench:feel` zero pixel diff (against the committed or Task 0 local baseline); `bench:agent:gate` PASS; `bench:agent:scroll` full coverage and the trim and width anchors holding (the scroll anchor code is unchanged); no baseline file listed (if Task 0 recorded locally, restore with `git checkout -- packages/terminal/bench/agent-session/baselines && git clean -fdq packages/terminal/bench/agent-session/baselines`). On Linux, record `bench:selection` and `bench:selection:extras` as `not run: Linux copy chord` if the chord is refused.

The desktop-window checks are appended to the roadmap's deferred list (Task 11 Step 3) and are not run now (user decision 2026-09-25).

- [ ] **Step 6: Report**

Report, in this order: the commit list (`git log --oneline development..HEAD`); the five test counts against Task 0; each gate's output line; files over 550 lines; anything recorded as `not run` with its reason; any deviation from this plan with the reason. Then tell the user to restart the daemon and the app (`TERMINAL.md` §3.5), since `vt_host.wasm` changed. Do not merge; merging to `development` is the reviewing session's step.
