# Warp Terminal Phase 3 Implementation Plan — the alternate screen

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:executing-plans`. Work
> task by task, top to bottom. Every step is a checkbox. Do not skip a "run it and watch
> it fail" step — several defects in Phase 2 were tests that passed for the wrong reason,
> and the only thing that catches those is seeing red before you see green.

**Goal:** render full-screen TUIs (`vim`, `htop`, `less`, and an agent CLI) in the
package's own surface, so the pane an Operator session actually shows is ours end to end.
`XtermTerminal.tsx` stays in the tree as a one-flag fallback; deleting it is Phase 7.

**Spec:** `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`. §11 is
normative for this phase, §14 Phase 3 holds the acceptance criteria, §2.8 records why the
phase exists at all.

**Depends on:** Phase 2, merged to `master` at `9930a3128`.

---

## 0. How to read this plan

This plan is written to be executed literally. It gives you complete file contents rather
than descriptions, because a described implementation is a re-derived implementation and
that is where accuracy goes.

Three rules that override your instincts:

1. **Paste the given code, then make the tests pass.** If a given implementation is wrong,
   the tests in the same task will say so. Fix it and note what you changed at the end of
   the task. Do not rewrite working code because you would have structured it differently.
2. **When a step says "expected: FAIL", run it and confirm it fails for the stated
   reason.** A step that fails for a *different* reason means something upstream is wrong;
   stop and say so rather than pushing through.
3. **Never edit a test to make it pass.** If a test and the implementation disagree, one
   of them encodes the spec. Work out which, in writing, before changing either.

---

## 1. Ground truth — what the code actually is today

Every line below was read out of the tree at `9930a3128`. The earlier draft of this plan
got several of these wrong; if something here contradicts your memory, this section wins.

| Fact | Where | Why it matters |
| --- | --- | --- |
| `TerminalCore::new(columns, scrollback_rows)` — **two** arguments | `crates/vt-core/src/lib.rs:47` | There is no rows dimension. 26 call sites use the 2-arg form. |
| Alt-screen enter/leave is detected by the **marks scanner**, not by `vte` | `crates/marks/src/scanner.rs:126-132` | `?1049h`/`?1049l` produce `MarkEvent::AltScreenEnter`/`Leave`. **Do not add 1049 handling to `csi_dispatch`.** |
| `TerminalCore::feed` interleaves scanner events with `vte` byte ranges by offset | `crates/vt-core/src/lib.rs:66-96` | An event applies only after the bytes before it are parsed. This is exactly the hook the alt switch needs. |
| While alt is active, every mark event except `AltScreenLeave` is dropped | `crates/vt-core/src/lib.rs:82-84` | The shred rule already works. Do not touch it. |
| `parser.rs` `csi_dispatch` handles **only** `m` (SGR) | `crates/vt-core/src/parser.rs:181-185` | No cursor, no addressing, nothing else. |
| `Perform::execute` treats `0x0D` (CR) as a **no-op** | `crates/vt-core/src/parser.rs:176` | Correct for an append-only buffer. In the alt grid CR must move the cursor. |
| `StyleCode::DEFAULT` is `255`; `StyleCode::ansi(i)` is `0..=15` | `crates/vt-core/src/style.rs` | The alt grid stores the same `StyleCode`. |
| `AttributeMap::runs(start, end)` returns `(relative_end_offset, style)`, last pair ending at the row's byte length | `crates/vt-core/src/attribute_map.rs:35-51` | The alt snapshot must produce **exactly** this shape or the renderer's row builder mis-slices. |
| `GridSnapshot` carries `content`, `rows`, `run_ranges`, `style_pairs`, `blocks`, `block_text`, `line_editor_state` | `crates/vt-core/src/grid.rs:18-26` | Alt data is added alongside, not folded in. |
| `dom-block-renderer.ts` is **561 lines**; the limit is 600 | `check-boundaries.mjs:41` | You have ~39 lines of headroom. The alt renderer must live in new files. |
| `populateBlock` builds rows inline as a free function | `ts/renderer-dom/src/dom-block-renderer.ts:456` | Task 8 extracts the row loop so both paths share it. |
| The renderer's container gets `overflow: auto` and `contain: strict` | `dom-block-renderer.ts` `mount` | The alt screen must set `overflow: hidden` or it will scroll. |
| `BlockTerminal.tsx` detects the alt screen by `text.includes("\x1b[?1049h")` on each chunk | `frontend/src/renderer/components/BlockTerminal.tsx:257-265` | A second, weaker detector than the core's. Task 10 deletes it. |
| `BlockTerminalTransport` already declares `resize?: (cols, rows) => void` — and **nothing calls it** | `BlockTerminal.tsx:37` | The PTY is never told the size. `vim` will draw for the wrong geometry until Task 9 wires this. |
| `LineEditor` already passes keys through raw whenever ownership is not `owned` | `ts/editor/src/line-editor.ts:141-143` | Alt input is already raw. What is missing is *hiding* the editor and keeping focus somewhere. |
| `passthroughFor` is private to `line-editor.ts` | `ts/editor/src/line-editor.ts:346` | Task 9 exports it so the alt surface can encode keys. |
| The perf baseline is still the single-draw one from `71f4ab6aa` | `bench/baselines/darwin-arm64-xterm.json` | The best-of-5 re-record has **not** landed. Task 0 handles it. |

### Two consequences the whole plan is built around

1. **The alternate buffer needs its own data structure.** `Content` + `RowIndex` are
   append-only by design, and that design is why blocks, find and scrollback are cheap. A
   2D overwritable matrix cannot be expressed in them. So: a separate `AltGrid`, owned by
   the parser, alive only while the alternate screen is.
2. **The switch is driven by mark events, not by the CSI parser.** `TerminalCore::feed`
   already applies `AltScreenEnter`/`Leave` at exactly the right byte offset. Task 4 hangs
   the grid creation off those two lines and nothing else.

---

## 2. Decisions already taken — do not re-litigate

These are settled. Each one exists because the obvious alternative is worse.

**D1. `TerminalCore::new` keeps its two-argument signature.** Rows arrive through
`resize(columns, rows)` and default to `DEFAULT_ROWS = 24`. The earlier draft added rows as
a third constructor parameter, which breaks 26 call sites across five test files for no
behavioural gain — and a weak-model mass edit across 26 sites is a much likelier source of
a broken tree than a default is of a wrong render. Tests that need specific rows call
`resize`.

**D2. `AltGrid` lives in `crates/vt-core/src/alt/`, split five ways from the start:**
`mod.rs` (cells, cursor, print, resize), `edit.rs` (ED/EL/IL/DL/ICH/DCH/ECH), `scroll.rs`
(DECSTBM/IND/RI/NEL/SU/SD), `dispatch.rs` (the CSI and ESC tables), `snapshot.rs` (the wire
export). Splitting after the 600-line check fails means moving code you have already
debugged.

**D3. The alt snapshot uses the block path's wire shape** — `(content, rowRanges,
runRanges, stylePairs)` with run ends relative to each row's start. Not because it is
elegant, but because `renderer-dom` already has a loop that consumes exactly that, and a
second shape means a second loop that drifts.

**D4. Rows and columns are clamped to `1..=1000`.** This makes `rows * cols * 4` a hard
4 MB bound, which is what lets the snapshot use plain `as u32` casts without the
`checked_u32` ceremony the unbounded scrollback path needs.

**D5. The alternate screen gets no virtualization and no scrollback.** It is exactly one
screen. Windowing it adds machinery that saves nothing, and synthesizing scrollback is a
bug per §11.

**D6. Keyboard focus in the alternate screen moves to the renderer container**, which
becomes `tabIndex=0` and encodes keys with the editor's `mapKey` + `passthroughFor`. The
editor host is hidden with the `hidden` attribute. This is why `passthroughFor` gets
exported: a hidden element cannot hold focus, so "hide the editor" and "keep receiving
keys" cannot both be true of the same element. The keydown handler lives in
`ts/react/TerminalSurface.tsx` because **`renderer-dom` must not import `editor`**.

**D7. `BlockTerminal` stops sniffing bytes for `?1049h` and reads the core instead.** One
detector, in the parser that already has to be right.

---

## 3. Global constraints

Every task's requirements implicitly include all of these.

- **No source file over 600 lines.** `npm --prefix packages/terminal run check:boundaries`
  enforces it across `.ts .tsx .js .mjs .cjs .rs .go .sh .fish .ps1`.
- **No import may escape `packages/terminal/`.** `frontend/` imports the package by name.
- **`renderer-dom` MUST NOT import `editor`; `editor` MUST NOT import `completions`.**
- **The alternate buffer has no scrollback.** None, not a small one.
- **Mark events stay frozen while the alternate screen is active.** Blocks recorded before
  entry MUST be byte-identical after leave.
- **Ownership stays `Released` inside the alternate screen.** Phase 2 already enforces it.
- **`XtermTerminal.tsx` is not deleted** and stays reachable via
  `VITE_ALT_SCREEN_SURFACE=xterm`. `bench/adapters/xterm.ts` is never deleted.
- **Do not write code comments.** User instruction in `/Users/omaraly/.claude/CLAUDE.md`.
  The existing code has comments; new code you add does not get them. Match structure, not
  comment density.
- **No timers for ownership or for resize.** `scripts/check-no-ownership-timer.mjs`
  enforces the first; §3.5 is the reason. A debounce on resize is the same anti-pattern in
  a different costume — a `ResizeObserver` already coalesces.
- **No new user-facing strings are expected in this phase.** If you find you need one, it
  goes into all eight locale files under `frontend/src/renderer/i18n/` and you flag it.

---

## 4. File map

**New**

| File | Responsibility |
| --- | --- |
| `packages/terminal/crates/vt-core/src/alt/mod.rs` | `Cell`, `AltGrid`: storage, cursor, print, wrap, resize |
| `packages/terminal/crates/vt-core/src/alt/edit.rs` | ED, EL, IL, DL, ICH, DCH, ECH |
| `packages/terminal/crates/vt-core/src/alt/scroll.rs` | DECSTBM, IND, RI, NEL, SU, SD |
| `packages/terminal/crates/vt-core/src/alt/dispatch.rs` | the CSI and ESC tables |
| `packages/terminal/crates/vt-core/src/alt/snapshot.rs` | `AltSnapshot` in the block wire shape |
| `packages/terminal/crates/vt-core/tests/alt_grid.rs` | unit coverage for the four above |
| `packages/terminal/crates/vt-core/tests/alt_routing.rs` | routing, the shred rule, ownership |
| `packages/terminal/crates/vt-core/tests/alt_conformance.rs` | the tmux oracle |
| `packages/terminal/tools/tmux-capture.mjs` | records a real program's bytes + tmux's grid |
| `packages/terminal/protocol/alt-vectors/*.json` | the recorded vectors, committed |
| `packages/terminal/ts/renderer-dom/src/row-builder.ts` | the row/run DOM loop, shared |
| `packages/terminal/ts/renderer-dom/src/alt-surface.ts` | the full-height raw surface |
| `packages/terminal/ts/renderer-dom/src/alt-surface.test.ts` | its tests |

**Modified**

| File | Change |
| --- | --- |
| `crates/vt-core/src/lib.rs` | `mod alt`, rows, `resize`, `alt_grid()`, alt switch in `feed` |
| `crates/vt-core/src/parser.rs` | owns `Option<AltGrid>`; `Perform` forks |
| `crates/vt-core/src/grid.rs` | `GridSnapshot.alt: Option<AltSnapshot>` |
| `crates/vt-wasm/src/lib.rs` | export the alt buffers, cursor and `resize` |
| `ts/core/src/types.ts`, `terminal-core.ts`, `index.ts` | `AltScreenView`, `altScreen`, `resize` |
| `ts/renderer-dom/src/dom-block-renderer.ts` | fork `repaint`; use `row-builder` |
| `ts/renderer-dom/src/styles.css` + `styles.ts` | alt surface classes |
| `ts/editor/src/index.ts` | export `passthroughFor` |
| `ts/react/src/TerminalSurface.tsx` | alt state, hide editor, focus + keys, resize |
| `frontend/src/renderer/components/BlockTerminal.tsx` | read alt from core; wire `transport.resize` |

---

## Task 0: Pre-flight

Nothing here is optional. Two of these three caught real breakage at the Phase 2 merge.

- [ ] **Step 1: Branch and link the workspace**

```bash
cd /Users/omaraly/development/AI/Operator && git checkout master && git pull --ff-only 2>/dev/null; git checkout -b phase-3
```

```bash
npm install
```

`npm install` is not ceremony. Phase 2 added the `ts/editor` workspace and the main
checkout had never linked it; the first typecheck after the merge failed with
`Cannot find module '@operator/terminal-editor'`. Confirm `git status` shows **no**
tracked changes after the install — if `package-lock.json` moved, stop and say so.

- [ ] **Step 2: Confirm the tree is green before you touch it**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -q 2>&1 | tail -20
```

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm test 2>&1 | tail -20
```

Expected: all Rust suites pass; TS reports 119 tests (core 21, editor 44, react 9,
renderer-dom 45). If anything is red **before** your first edit, that is the thing to
report — do not start Task 1 on a red tree.

- [ ] **Step 3: Record the perf baseline that Phase 2 shipped the tool for**

The gate currently fails `input-latency` at 8.90 against an 8.60 baseline. That 8.60 is a
single lucky draw: measured across runs the two renderers overlap completely (dom
8.30–8.90, xterm 8.30–9.20). Phase 2 added `--repeat` to fix exactly this and it was never
run. Run it now, on a clean master-equivalent tree, before any Phase 3 code can be blamed:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:baseline -- --renderer xterm --record --repeat 5
```

This takes roughly 40 minutes. Then:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:gate
```

Commit the new baseline:

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/bench/baselines && git commit -m "bench(terminal): re-record the xterm baseline as a best-of-5"
```

**If the gate still fails `input-latency` after a best-of-5 baseline, say so and continue
to Task 1.** Do not re-record a third time hoping for friendlier numbers. A gate you
re-roll until it passes is not a gate, and Task 11 will re-check it anyway.

---

## Task 1: The cell grid

**Files**
- Create `packages/terminal/crates/vt-core/src/alt/mod.rs`
- Create `packages/terminal/crates/vt-core/tests/alt_grid.rs`
- Modify `packages/terminal/crates/vt-core/src/lib.rs`

**Produces** (Tasks 2–5 consume these, unchanged):

```rust
pub struct Cell { pub ch: char, pub style: StyleCode }
impl AltGrid {
    pub fn new(rows: usize, cols: usize) -> Self;
    pub fn rows(&self) -> usize;
    pub fn cols(&self) -> usize;
    pub fn cell(&self, row: usize, col: usize) -> Cell;
    pub fn cursor(&self) -> (usize, usize);
    pub fn cursor_visible(&self) -> bool;
    pub fn set_cursor_visible(&mut self, visible: bool);
    pub fn move_to(&mut self, row: usize, col: usize);
    pub fn move_by(&mut self, rows: isize, cols: isize);
    pub fn carriage_return(&mut self);
    pub fn tab(&mut self);
    pub fn print(&mut self, ch: char, style: StyleCode);
    pub fn resize(&mut self, rows: usize, cols: usize);
    pub fn row_text(&self, row: usize) -> String;
    pub fn reset(&mut self);
    pub fn save_cursor(&mut self);
    pub fn restore_cursor(&mut self);
}
```

- [ ] **Step 1: Write the failing test file**

Create `packages/terminal/crates/vt-core/tests/alt_grid.rs` with exactly this:

```rust
use vt_core::alt::AltGrid;
use vt_core::StyleCode;

fn grid() -> AltGrid {
    AltGrid::new(4, 8)
}

fn print(g: &mut AltGrid, text: &str) {
    for ch in text.chars() {
        g.print(ch, StyleCode::DEFAULT);
    }
}

#[test]
fn starts_blank_with_the_cursor_at_the_origin() {
    let g = grid();
    assert_eq!(g.cursor(), (0, 0));
    assert_eq!(g.row_text(0), "        ");
}

#[test]
fn printing_advances_the_cursor_and_lands_in_the_cell() {
    let mut g = grid();
    print(&mut g, "hi");
    assert_eq!(g.cursor(), (0, 2));
    assert_eq!(g.row_text(0), "hi      ");
}

#[test]
fn printing_past_the_right_margin_wraps_to_the_next_row() {
    let mut g = grid();
    print(&mut g, "123456789");
    assert_eq!(g.row_text(0), "12345678");
    assert_eq!(g.row_text(1), "9       ");
    assert_eq!(g.cursor(), (1, 1));
}

#[test]
fn filling_a_row_exactly_does_not_scroll_until_the_next_character() {
    let mut g = AltGrid::new(2, 4);
    print(&mut g, "abcd");
    assert_eq!(g.cursor(), (0, 3));
    assert_eq!(g.row_text(0), "abcd");
    assert_eq!(g.row_text(1), "    ");
}

#[test]
fn carriage_return_moves_to_column_zero_without_erasing() {
    let mut g = grid();
    print(&mut g, "abcd");
    g.carriage_return();
    print(&mut g, "XY");
    assert_eq!(g.row_text(0), "XYcd    ");
}

#[test]
fn cursor_moves_clamp_at_the_edges_instead_of_wrapping_or_panicking() {
    let mut g = grid();
    g.move_by(-5, -5);
    assert_eq!(g.cursor(), (0, 0));
    g.move_by(99, 99);
    assert_eq!(g.cursor(), (3, 7));
}

#[test]
fn move_to_is_absolute_and_clamped() {
    let mut g = grid();
    g.move_to(2, 3);
    assert_eq!(g.cursor(), (2, 3));
    g.move_to(99, 99);
    assert_eq!(g.cursor(), (3, 7));
}

#[test]
fn tab_advances_to_the_next_eight_column_stop() {
    let mut g = AltGrid::new(2, 20);
    print(&mut g, "ab");
    g.tab();
    assert_eq!(g.cursor(), (0, 8));
    g.tab();
    assert_eq!(g.cursor(), (0, 16));
}

#[test]
fn a_wide_character_occupies_two_cells() {
    let mut g = grid();
    g.print('世', StyleCode::DEFAULT);
    assert_eq!(g.cursor(), (0, 2));
    assert_eq!(g.row_text(0), "世      ");
}

#[test]
fn a_wide_character_that_does_not_fit_wraps_rather_than_splitting() {
    let mut g = AltGrid::new(2, 3);
    print(&mut g, "ab");
    g.print('世', StyleCode::DEFAULT);
    assert_eq!(g.row_text(0), "ab ");
    assert_eq!(g.row_text(1), "世 ");
}

#[test]
fn a_zero_width_character_is_dropped_rather_than_consuming_a_cell() {
    let mut g = grid();
    print(&mut g, "a");
    g.print('\u{0301}', StyleCode::DEFAULT);
    assert_eq!(g.cursor(), (0, 1));
}

#[test]
fn printing_keeps_the_style_it_was_given() {
    let mut g = grid();
    g.print('x', StyleCode::ansi(2));
    assert_eq!(g.cell(0, 0).style, StyleCode::ansi(2));
    assert_eq!(g.cell(0, 1).style, StyleCode::DEFAULT);
}

#[test]
fn growing_keeps_content_and_shrinking_drops_what_falls_outside() {
    let mut g = grid();
    print(&mut g, "abcdefgh");
    g.resize(4, 4);
    assert_eq!(g.row_text(0), "abcd");
    g.resize(4, 8);
    assert_eq!(g.row_text(0), "abcd    ");
}

#[test]
fn resize_clamps_a_cursor_that_is_now_outside() {
    let mut g = grid();
    g.move_to(3, 7);
    g.resize(2, 2);
    assert_eq!(g.cursor(), (1, 1));
}

#[test]
fn a_zero_or_absurd_dimension_is_clamped_instead_of_panicking() {
    let mut g = AltGrid::new(0, 0);
    assert_eq!(g.rows(), 1);
    assert_eq!(g.cols(), 1);
    g.resize(100_000, 100_000);
    assert_eq!(g.rows(), 1000);
    assert_eq!(g.cols(), 1000);
}

#[test]
fn saving_and_restoring_the_cursor_round_trips() {
    let mut g = grid();
    g.move_to(2, 5);
    g.save_cursor();
    g.move_to(0, 0);
    g.restore_cursor();
    assert_eq!(g.cursor(), (2, 5));
}

#[test]
fn reset_blanks_everything_and_homes_the_cursor() {
    let mut g = grid();
    print(&mut g, "abc");
    g.move_to(2, 2);
    g.reset();
    assert_eq!(g.cursor(), (0, 0));
    assert_eq!(g.row_text(0), "        ");
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test alt_grid 2>&1 | tail -20
```

Expected: a compile error, `unresolved import vt_core::alt`. Any other failure means you
edited something you should not have.

- [ ] **Step 3: Create `crates/vt-core/src/alt/mod.rs`**

```rust
mod dispatch;
mod edit;
mod scroll;
mod snapshot;

pub use snapshot::AltSnapshot;

use unicode_width::UnicodeWidthChar;

use crate::style::StyleCode;

pub(crate) const MAX_DIMENSION: usize = 1000;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cell {
    pub ch: char,
    pub style: StyleCode,
}

impl Cell {
    pub const BLANK: Self = Self {
        ch: ' ',
        style: StyleCode::DEFAULT,
    };
}

pub struct AltGrid {
    rows: usize,
    cols: usize,
    cells: Vec<Cell>,
    row: usize,
    col: usize,
    cursor_visible: bool,
    pending_wrap: bool,
    saved: Option<(usize, usize)>,
    pub(crate) scroll_top: usize,
    pub(crate) scroll_bottom: usize,
}

fn clamp_dimension(value: usize) -> usize {
    value.clamp(1, MAX_DIMENSION)
}

impl AltGrid {
    pub fn new(rows: usize, cols: usize) -> Self {
        let rows = clamp_dimension(rows);
        let cols = clamp_dimension(cols);
        Self {
            rows,
            cols,
            cells: vec![Cell::BLANK; rows * cols],
            row: 0,
            col: 0,
            cursor_visible: true,
            pending_wrap: false,
            saved: None,
            scroll_top: 0,
            scroll_bottom: rows - 1,
        }
    }

    pub fn rows(&self) -> usize {
        self.rows
    }

    pub fn cols(&self) -> usize {
        self.cols
    }

    pub fn cursor(&self) -> (usize, usize) {
        (self.row, self.col)
    }

    pub fn cursor_visible(&self) -> bool {
        self.cursor_visible
    }

    pub fn set_cursor_visible(&mut self, visible: bool) {
        self.cursor_visible = visible;
    }

    pub fn cell(&self, row: usize, col: usize) -> Cell {
        if row >= self.rows || col >= self.cols {
            return Cell::BLANK;
        }
        self.cells[row * self.cols + col]
    }

    pub(crate) fn set(&mut self, row: usize, col: usize, cell: Cell) {
        if row >= self.rows || col >= self.cols {
            return;
        }
        let index = row * self.cols + col;
        self.cells[index] = cell;
    }

    pub(crate) fn blank_row(&mut self, row: usize) {
        for col in 0..self.cols {
            self.set(row, col, Cell::BLANK);
        }
    }

    pub(crate) fn copy_row(&mut self, from: usize, to: usize) {
        if from == to {
            return;
        }
        for col in 0..self.cols {
            let cell = self.cell(from, col);
            self.set(to, col, cell);
        }
    }

    pub(crate) fn clear_pending_wrap(&mut self) {
        self.pending_wrap = false;
    }

    pub fn move_to(&mut self, row: usize, col: usize) {
        self.row = row.min(self.rows - 1);
        self.col = col.min(self.cols - 1);
        self.pending_wrap = false;
    }

    pub fn move_by(&mut self, rows: isize, cols: isize) {
        let row = (self.row as isize + rows).clamp(0, self.rows as isize - 1) as usize;
        let col = (self.col as isize + cols).clamp(0, self.cols as isize - 1) as usize;
        self.move_to(row, col);
    }

    pub fn carriage_return(&mut self) {
        self.col = 0;
        self.pending_wrap = false;
    }

    pub fn tab(&mut self) {
        let target = (((self.col / 8) + 1) * 8).min(self.cols - 1);
        self.move_to(self.row, target);
    }

    pub fn save_cursor(&mut self) {
        self.saved = Some((self.row, self.col));
    }

    pub fn restore_cursor(&mut self) {
        if let Some((row, col)) = self.saved {
            self.move_to(row, col);
        }
    }

    pub fn print(&mut self, ch: char, style: StyleCode) {
        let width = UnicodeWidthChar::width(ch).unwrap_or(0);
        if width == 0 {
            return;
        }
        if self.pending_wrap || self.col + width > self.cols {
            self.carriage_return();
            self.line_feed();
        }
        self.set(self.row, self.col, Cell { ch, style });
        for offset in 1..width {
            self.set(self.row, self.col + offset, Cell { ch: '\0', style });
        }
        self.col += width;
        if self.col >= self.cols {
            self.col = self.cols - 1;
            self.pending_wrap = true;
        }
    }

    pub fn row_text(&self, row: usize) -> String {
        (0..self.cols)
            .map(|col| self.cell(row, col).ch)
            .filter(|ch| *ch != '\0')
            .collect()
    }

    pub fn reset(&mut self) {
        self.cells.fill(Cell::BLANK);
        self.row = 0;
        self.col = 0;
        self.scroll_top = 0;
        self.scroll_bottom = self.rows - 1;
        self.pending_wrap = false;
        self.cursor_visible = true;
        self.saved = None;
    }

    pub fn resize(&mut self, rows: usize, cols: usize) {
        let rows = clamp_dimension(rows);
        let cols = clamp_dimension(cols);
        let mut next = vec![Cell::BLANK; rows * cols];
        for row in 0..rows.min(self.rows) {
            for col in 0..cols.min(self.cols) {
                next[row * cols + col] = self.cells[row * self.cols + col];
            }
        }
        self.cells = next;
        self.rows = rows;
        self.cols = cols;
        self.scroll_top = 0;
        self.scroll_bottom = rows - 1;
        self.row = self.row.min(rows - 1);
        self.col = self.col.min(cols - 1);
        self.pending_wrap = false;
        self.saved = None;
    }
}
```

**`pending_wrap` is the deferred-wrap rule**, and it is the single most commonly missed
behaviour in a hand-written terminal. Printing into the last column leaves the cursor *on*
that column; the wrap happens only when the next character arrives. Without it a program
that fills a row exactly and then repositions scrolls the screen by a line it never asked
for — which in `htop` means the whole display walks upward once per refresh.
`filling_a_row_exactly_does_not_scroll_until_the_next_character` is the test that pins it.

**Temporary stubs.** `mod.rs` above references `line_feed` (Task 3) and declares four
modules that do not exist yet. To make Task 1 compile on its own, create these four files
now with exactly this content, and nothing else:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/crates/vt-core/src/alt
printf 'use crate::alt::AltGrid;\n\nimpl AltGrid {\n    pub fn line_feed(&mut self) {\n        let (row, col) = self.cursor();\n        if row + 1 < self.rows() {\n            self.move_to(row + 1, col);\n        }\n    }\n}\n' > scroll.rs
: > edit.rs
: > dispatch.rs
: > snapshot.rs
```

`snapshot.rs` being empty means `pub use snapshot::AltSnapshot;` will not compile — comment
out that one line for Task 1 only and restore it in Task 5. Note it in your task summary so
it is not forgotten.

- [ ] **Step 4: Register the module**

In `crates/vt-core/src/lib.rs`, add `pub mod alt;` to the module list, alphabetically
before `pub mod attribute_map;`.

- [ ] **Step 5: Run the tests**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test alt_grid 2>&1 | tail -20
```

Expected: `test result: ok. 17 passed`.

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/vt-core && git commit -m "feat(terminal): add the alternate-screen cell grid"
```

---

## Task 2: Erase and line editing

**Files**
- Fill `packages/terminal/crates/vt-core/src/alt/edit.rs`
- Append to `packages/terminal/crates/vt-core/tests/alt_grid.rs`

- [ ] **Step 1: Append the failing tests**

```rust
fn filled() -> AltGrid {
    let mut g = AltGrid::new(3, 4);
    for row in 0..3 {
        g.move_to(row, 0);
        print(&mut g, "abcd");
    }
    g
}

fn labelled(rows: usize) -> AltGrid {
    let mut g = AltGrid::new(rows, 4);
    for (row, text) in ["one", "two", "six"].iter().enumerate().take(rows) {
        g.move_to(row, 0);
        print(&mut g, text);
    }
    g
}

#[test]
fn erase_in_line_right_clears_from_the_cursor_to_the_end() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_line(0);
    assert_eq!(g.row_text(1), "ab  ");
    assert_eq!(g.row_text(0), "abcd");
}

#[test]
fn erase_in_line_left_clears_through_the_cursor_cell() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_line(1);
    assert_eq!(g.row_text(1), "   d");
}

#[test]
fn erase_in_line_all_clears_the_row_and_leaves_the_cursor_put() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_line(2);
    assert_eq!(g.row_text(1), "    ");
    assert_eq!(g.cursor(), (1, 2));
}

#[test]
fn erase_in_display_below_clears_the_rest_of_the_screen() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_display(0);
    assert_eq!(g.row_text(0), "abcd");
    assert_eq!(g.row_text(1), "ab  ");
    assert_eq!(g.row_text(2), "    ");
}

#[test]
fn erase_in_display_above_clears_everything_before_the_cursor() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_display(1);
    assert_eq!(g.row_text(0), "    ");
    assert_eq!(g.row_text(1), "   d");
    assert_eq!(g.row_text(2), "abcd");
}

#[test]
fn erase_in_display_all_clears_everything_and_leaves_the_cursor_put() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_display(2);
    assert_eq!(g.row_text(0), "    ");
    assert_eq!(g.row_text(2), "    ");
    assert_eq!(g.cursor(), (1, 2));
}

#[test]
fn insert_lines_pushes_rows_down_and_drops_the_bottom() {
    let mut g = labelled(3);
    g.move_to(1, 0);
    g.insert_lines(1);
    assert_eq!(g.row_text(0), "one ");
    assert_eq!(g.row_text(1), "    ");
    assert_eq!(g.row_text(2), "two ");
}

#[test]
fn delete_lines_pulls_rows_up_and_blanks_the_bottom() {
    let mut g = labelled(3);
    g.move_to(0, 0);
    g.delete_lines(1);
    assert_eq!(g.row_text(0), "two ");
    assert_eq!(g.row_text(1), "six ");
    assert_eq!(g.row_text(2), "    ");
}

#[test]
fn insert_chars_shifts_right_within_the_row_only() {
    let mut g = filled();
    g.move_to(1, 1);
    g.insert_chars(2);
    assert_eq!(g.row_text(1), "a  b");
    assert_eq!(g.row_text(2), "abcd");
}

#[test]
fn delete_chars_shifts_left_and_blanks_the_tail() {
    let mut g = filled();
    g.move_to(1, 1);
    g.delete_chars(2);
    assert_eq!(g.row_text(1), "ad  ");
}

#[test]
fn erase_chars_blanks_in_place_without_shifting() {
    let mut g = filled();
    g.move_to(1, 1);
    g.erase_chars(2);
    assert_eq!(g.row_text(1), "a  d");
}

#[test]
fn an_absurd_count_saturates_instead_of_panicking() {
    let mut g = filled();
    g.move_to(1, 1);
    g.delete_chars(usize::MAX);
    g.insert_chars(usize::MAX);
    g.erase_chars(usize::MAX);
    g.insert_lines(usize::MAX);
    g.delete_lines(usize::MAX);
    assert_eq!(g.rows(), 3);
    assert_eq!(g.cursor(), (1, 1));
}

#[test]
fn deleting_every_line_from_the_top_blanks_the_screen_without_underflow() {
    let mut g = labelled(3);
    g.move_to(0, 0);
    g.delete_lines(3);
    assert_eq!(g.row_text(0), "    ");
    assert_eq!(g.row_text(2), "    ");
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test alt_grid 2>&1 | tail -20
```

Expected: `no method named erase_in_line found`.

- [ ] **Step 3: Write `crates/vt-core/src/alt/edit.rs`**

```rust
use crate::alt::{AltGrid, Cell};

impl AltGrid {
    pub fn erase_in_display(&mut self, mode: u16) {
        let (row, col) = self.cursor();
        let rows = self.rows();
        let cols = self.cols();
        match mode {
            0 => {
                for c in col..cols {
                    self.set(row, c, Cell::BLANK);
                }
                for r in (row + 1)..rows {
                    self.blank_row(r);
                }
            }
            1 => {
                for r in 0..row {
                    self.blank_row(r);
                }
                for c in 0..=col {
                    self.set(row, c, Cell::BLANK);
                }
            }
            _ => {
                for r in 0..rows {
                    self.blank_row(r);
                }
            }
        }
    }

    pub fn erase_in_line(&mut self, mode: u16) {
        let (row, col) = self.cursor();
        let cols = self.cols();
        match mode {
            0 => {
                for c in col..cols {
                    self.set(row, c, Cell::BLANK);
                }
            }
            1 => {
                for c in 0..=col {
                    self.set(row, c, Cell::BLANK);
                }
            }
            _ => self.blank_row(row),
        }
    }

    pub fn insert_chars(&mut self, count: usize) {
        let (row, col) = self.cursor();
        let cols = self.cols();
        let count = count.min(cols - col);
        if count == 0 {
            return;
        }
        for c in ((col + count)..cols).rev() {
            let cell = self.cell(row, c - count);
            self.set(row, c, cell);
        }
        for c in col..(col + count) {
            self.set(row, c, Cell::BLANK);
        }
    }

    pub fn delete_chars(&mut self, count: usize) {
        let (row, col) = self.cursor();
        let cols = self.cols();
        let count = count.min(cols - col);
        if count == 0 {
            return;
        }
        for c in col..(cols - count) {
            let cell = self.cell(row, c + count);
            self.set(row, c, cell);
        }
        for c in (cols - count)..cols {
            self.set(row, c, Cell::BLANK);
        }
    }

    pub fn erase_chars(&mut self, count: usize) {
        let (row, col) = self.cursor();
        let cols = self.cols();
        let count = count.min(cols - col);
        for c in col..(col + count) {
            self.set(row, c, Cell::BLANK);
        }
    }

    pub fn insert_lines(&mut self, count: usize) {
        let row = self.cursor().0;
        if row < self.scroll_top || row > self.scroll_bottom {
            return;
        }
        let room = self.scroll_bottom - row + 1;
        let count = count.min(room);
        if count == 0 {
            return;
        }
        for r in ((row + count)..=self.scroll_bottom).rev() {
            self.copy_row(r - count, r);
        }
        for r in row..(row + count) {
            self.blank_row(r);
        }
    }

    pub fn delete_lines(&mut self, count: usize) {
        let row = self.cursor().0;
        if row < self.scroll_top || row > self.scroll_bottom {
            return;
        }
        let room = self.scroll_bottom - row + 1;
        let count = count.min(room);
        if count == 0 {
            return;
        }
        if count < room {
            for r in row..=(self.scroll_bottom - count) {
                self.copy_row(r + count, r);
            }
        }
        for r in (self.scroll_bottom + 1 - count)..=self.scroll_bottom {
            self.blank_row(r);
        }
    }
}
```

Two things to notice, because they are where an "obvious simplification" breaks it:

- `delete_lines` guards `count < room` before the copy loop. Without it,
  `scroll_bottom - count` underflows when the caller deletes the whole region from the top,
  and `usize` underflow in release mode is a wrong answer rather than a panic. The test
  `deleting_every_line_from_the_top_blanks_the_screen_without_underflow` pins this.
- `IL`/`DL` are no-ops outside the scroll region and clamp to it, not to the screen. Task 3
  sets a real region; until then top is 0 and bottom is `rows - 1`, so the behaviour is
  identical and the tests written here stay valid.

- [ ] **Step 4: Run the tests**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test alt_grid 2>&1 | tail -20
```

Expected: `test result: ok. 30 passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/vt-core && git commit -m "feat(terminal): erase and line editing on the alternate grid"
```

---

## Task 3: The scroll region

This is the task `less`, `vim` and every pager depend on, and the one most likely to be
subtly wrong.

**Files**
- Replace `packages/terminal/crates/vt-core/src/alt/scroll.rs` (the Task 1 stub)
- Append to `packages/terminal/crates/vt-core/tests/alt_grid.rs`

- [ ] **Step 1: Append the failing tests**

```rust
fn numbered(rows: usize) -> AltGrid {
    let mut g = AltGrid::new(rows, 2);
    for row in 0..rows {
        g.move_to(row, 0);
        print(&mut g, &format!("{row}"));
    }
    g
}

#[test]
fn a_line_feed_at_the_bottom_scrolls_the_whole_screen_by_default() {
    let mut g = numbered(3);
    g.move_to(2, 0);
    g.line_feed();
    assert_eq!(g.row_text(0), "1 ");
    assert_eq!(g.row_text(1), "2 ");
    assert_eq!(g.row_text(2), "  ");
    assert_eq!(g.cursor().0, 2);
}

#[test]
fn a_line_feed_elsewhere_just_moves_down_and_keeps_the_column() {
    let mut g = numbered(3);
    g.move_to(0, 1);
    g.line_feed();
    assert_eq!(g.cursor(), (1, 1));
    assert_eq!(g.row_text(0), "0 ");
}

#[test]
fn a_line_feed_at_the_region_bottom_scrolls_only_the_region() {
    let mut g = numbered(4);
    g.set_scroll_region(1, 2);
    g.move_to(2, 0);
    g.line_feed();
    assert_eq!(g.row_text(0), "0 ");
    assert_eq!(g.row_text(1), "2 ");
    assert_eq!(g.row_text(2), "  ");
    assert_eq!(g.row_text(3), "3 ");
}

#[test]
fn reverse_index_at_the_region_top_scrolls_the_region_down() {
    let mut g = numbered(4);
    g.set_scroll_region(1, 2);
    g.move_to(1, 0);
    g.reverse_index();
    assert_eq!(g.row_text(0), "0 ");
    assert_eq!(g.row_text(1), "  ");
    assert_eq!(g.row_text(2), "1 ");
    assert_eq!(g.row_text(3), "3 ");
}

#[test]
fn setting_a_region_homes_the_cursor() {
    let mut g = numbered(4);
    g.move_to(3, 1);
    g.set_scroll_region(1, 2);
    assert_eq!(g.cursor(), (0, 0));
}

#[test]
fn an_inverted_or_out_of_range_region_resets_to_the_full_screen() {
    let mut g = numbered(4);
    g.set_scroll_region(3, 1);
    g.move_to(3, 0);
    g.line_feed();
    assert_eq!(g.row_text(0), "1 ");
}

#[test]
fn insert_lines_outside_the_region_does_nothing() {
    let mut g = numbered(4);
    g.set_scroll_region(1, 2);
    g.move_to(0, 0);
    g.insert_lines(1);
    assert_eq!(g.row_text(0), "0 ");
    assert_eq!(g.row_text(1), "1 ");
}

#[test]
fn next_line_returns_to_column_zero_and_moves_down() {
    let mut g = numbered(3);
    g.move_to(0, 1);
    g.next_line();
    assert_eq!(g.cursor(), (1, 0));
}

#[test]
fn scrolling_by_more_than_the_region_blanks_it_without_underflow() {
    let mut g = numbered(4);
    g.set_scroll_region(1, 2);
    g.scroll_up(99);
    assert_eq!(g.row_text(0), "0 ");
    assert_eq!(g.row_text(1), "  ");
    assert_eq!(g.row_text(2), "  ");
    assert_eq!(g.row_text(3), "3 ");
    g.scroll_down(99);
    assert_eq!(g.row_text(3), "3 ");
}

#[test]
fn resize_resets_the_region_to_the_new_full_screen() {
    let mut g = numbered(4);
    g.set_scroll_region(1, 2);
    g.resize(3, 2);
    g.move_to(2, 0);
    g.line_feed();
    assert_eq!(g.row_text(0), "1 ");
}

#[test]
fn wrapping_at_the_last_row_scrolls_rather_than_overwriting() {
    let mut g = AltGrid::new(2, 2);
    g.move_to(1, 0);
    print(&mut g, "ab");
    print(&mut g, "cd");
    assert_eq!(g.row_text(0), "ab");
    assert_eq!(g.row_text(1), "cd");
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test alt_grid 2>&1 | tail -20
```

Expected: `no method named set_scroll_region found`.

- [ ] **Step 3: Replace `crates/vt-core/src/alt/scroll.rs` entirely**

```rust
use crate::alt::AltGrid;

impl AltGrid {
    pub fn set_scroll_region(&mut self, top: usize, bottom: usize) {
        if top >= bottom || bottom >= self.rows() {
            self.scroll_top = 0;
            self.scroll_bottom = self.rows() - 1;
        } else {
            self.scroll_top = top;
            self.scroll_bottom = bottom;
        }
        self.move_to(0, 0);
    }

    pub fn scroll_up(&mut self, count: usize) {
        if count == 0 {
            return;
        }
        let span = self.scroll_bottom - self.scroll_top + 1;
        if count >= span {
            for r in self.scroll_top..=self.scroll_bottom {
                self.blank_row(r);
            }
            return;
        }
        for r in self.scroll_top..=(self.scroll_bottom - count) {
            self.copy_row(r + count, r);
        }
        for r in (self.scroll_bottom + 1 - count)..=self.scroll_bottom {
            self.blank_row(r);
        }
    }

    pub fn scroll_down(&mut self, count: usize) {
        if count == 0 {
            return;
        }
        let span = self.scroll_bottom - self.scroll_top + 1;
        if count >= span {
            for r in self.scroll_top..=self.scroll_bottom {
                self.blank_row(r);
            }
            return;
        }
        for r in ((self.scroll_top + count)..=self.scroll_bottom).rev() {
            self.copy_row(r - count, r);
        }
        for r in self.scroll_top..(self.scroll_top + count) {
            self.blank_row(r);
        }
    }

    pub fn line_feed(&mut self) {
        let (row, col) = self.cursor();
        if row == self.scroll_bottom {
            self.scroll_up(1);
            self.clear_pending_wrap();
        } else if row + 1 < self.rows() {
            self.move_to(row + 1, col);
        } else {
            self.clear_pending_wrap();
        }
    }

    pub fn reverse_index(&mut self) {
        let (row, col) = self.cursor();
        if row == self.scroll_top {
            self.scroll_down(1);
            self.clear_pending_wrap();
        } else if row > 0 {
            self.move_to(row - 1, col);
        }
    }

    pub fn next_line(&mut self) {
        self.carriage_return();
        self.line_feed();
    }
}
```

The rules these pin, stated so you do not have to infer them from the standard:

- `set_scroll_region(top, bottom)` with `top >= bottom` or `bottom >= rows` **resets to the
  full screen**. DECSTBM also **homes the cursor** — that is in the standard and programs
  rely on it. Skipping the home is the single most common way `less` ends up drawing its
  first page one line low.
- `line_feed` at `scroll_bottom` scrolls the region and leaves the cursor where it is.
  Anywhere else it moves the cursor down one and keeps the column.
- `reverse_index` at `scroll_top` scrolls the region down. Anywhere else it moves up one.
- `next_line` is `carriage_return` then `line_feed`.

- [ ] **Step 4: Run the tests**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test alt_grid 2>&1 | tail -20
```

Expected: `test result: ok. 41 passed`. The Task 1 wrap tests must still pass — `print`
now calls the real `line_feed` instead of the stub, and
`wrapping_at_the_last_row_scrolls_rather_than_overwriting` is the test that proves the
swap did the right thing.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/vt-core && git commit -m "feat(terminal): scroll regions on the alternate grid"
```

---

## Task 4: Route bytes to the grid

**Files**
- Fill `packages/terminal/crates/vt-core/src/alt/dispatch.rs`
- Modify `packages/terminal/crates/vt-core/src/parser.rs`
- Modify `packages/terminal/crates/vt-core/src/lib.rs`
- Create `packages/terminal/crates/vt-core/tests/alt_routing.rs`

**Read this before you write anything.** The alternate screen is entered and left by
`MarkEvent::AltScreenEnter` / `AltScreenLeave`, produced by the marks scanner
(`crates/marks/src/scanner.rs:126`), and applied inside `TerminalCore::feed` at the exact
byte offset where the sequence ended. You are hanging the grid's lifetime off those two
events. **Do not add `?1049` handling to `csi_dispatch`** — `vte` will also see those bytes
and must ignore them, or you get a double switch.

- [ ] **Step 1: Write `crates/vt-core/tests/alt_routing.rs`**

```rust
use vt_core::{LineEditorState, TerminalCore};

fn core() -> TerminalCore {
    let mut core = TerminalCore::new(80, 100).expect("core");
    core.resize(80, 24);
    core
}

fn alt_row(core: &TerminalCore, row: usize) -> String {
    core.alt_grid()
        .expect("alt grid is active")
        .row_text(row)
        .trim_end()
        .to_string()
}

#[test]
fn bytes_go_to_the_alt_grid_only_while_it_is_active() {
    let mut c = core();
    c.feed(b"normal\n");
    assert!(c.alt_grid().is_none());
    c.feed(b"\x1b[?1049h");
    c.feed(b"inside");
    assert_eq!(alt_row(&c, 0), "inside");
    c.feed(b"\x1b[?1049l");
    assert!(c.alt_grid().is_none());
}

#[test]
fn the_normal_buffer_is_untouched_by_what_the_alt_screen_printed() {
    let mut c = core();
    c.feed(b"before\n");
    c.feed(b"\x1b[?1049hinside\x1b[?1049l");
    c.feed(b"after\n");
    let snapshot = c.snapshot().expect("snapshot");
    let text: Vec<&str> = (0..snapshot.row_count()).map(|i| snapshot.row_text(i)).collect();
    assert!(text.contains(&"before"));
    assert!(text.contains(&"after"));
    assert!(!text.iter().any(|row| row.contains("inside")));
}

#[test]
fn entering_the_alt_screen_starts_from_a_blank_grid() {
    let mut c = core();
    c.feed(b"\x1b[?1049hfirst\x1b[?1049l");
    c.feed(b"\x1b[?1049h");
    assert_eq!(alt_row(&c, 0), "");
}

#[test]
fn a_repeated_enter_while_already_inside_does_not_blank_the_screen() {
    let mut c = core();
    c.feed(b"\x1b[?1049hkeep me");
    c.feed(b"\x1b[?1049h");
    assert_eq!(alt_row(&c, 0), "keep me");
}

#[test]
fn cursor_addressing_inside_the_alt_screen_lands_where_it_says() {
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[3;5Hx");
    assert_eq!(c.alt_grid().expect("alt").cell(2, 4).ch, 'x');
}

#[test]
fn carriage_return_is_no_longer_a_no_op_inside_the_alt_screen() {
    let mut c = core();
    c.feed(b"\x1b[?1049habcd\rXY");
    assert_eq!(alt_row(&c, 0), "XYcd");
}

#[test]
fn carriage_return_is_still_a_no_op_in_the_normal_buffer() {
    let mut c = core();
    c.feed(b"abcd\rXY\n");
    let snapshot = c.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "abcdXY");
}

#[test]
fn erase_in_display_clears_the_screen_the_way_a_tui_expects() {
    let mut c = core();
    c.feed(b"\x1b[?1049hjunk\x1b[H\x1b[2Jclean");
    assert_eq!(alt_row(&c, 0), "clean");
}

#[test]
fn a_scroll_region_and_a_line_feed_scroll_only_the_region() {
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[2;3r\x1b[2;1Htop\x1b[3;1Hbottom\x1b[3;1H\n");
    assert_eq!(alt_row(&c, 1), "bottom");
}

#[test]
fn sgr_inside_the_alt_screen_colours_the_cells_it_precedes() {
    use vt_core::StyleCode;
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[31mR\x1b[0mD");
    let alt = c.alt_grid().expect("alt");
    assert_eq!(alt.cell(0, 0).style, StyleCode::ansi(1));
    assert_eq!(alt.cell(0, 1).style, StyleCode::DEFAULT);
}

#[test]
fn the_cursor_can_be_hidden_and_shown() {
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[?25l");
    assert!(!c.alt_grid().expect("alt").cursor_visible());
    c.feed(b"\x1b[?25h");
    assert!(c.alt_grid().expect("alt").cursor_visible());
}

#[test]
fn blocks_recorded_before_entering_survive_the_alt_screen_byte_for_byte() {
    let mut c = core();
    c.feed(b"\x1b]133;A\x07\x1b]7000;v=1;cmd=ls\x07out\n\x1b]133;D;0\x07");
    let before = c.snapshot().expect("snapshot");
    let blocks_before: Vec<_> = before
        .blocks
        .iter()
        .map(|b| (b.id, b.first_row, b.row_count, b.exit_code))
        .collect();

    c.feed(b"\x1b[?1049h");
    c.feed(b"\x1b]133;A\x07\x1b]133;D;1\x07garbage");
    c.feed(b"\x1b[?1049l");

    let after = c.snapshot().expect("snapshot");
    let blocks_after: Vec<_> = after
        .blocks
        .iter()
        .map(|b| (b.id, b.first_row, b.row_count, b.exit_code))
        .collect();
    assert_eq!(blocks_before, blocks_after);
}

#[test]
fn ownership_stays_released_inside_the_alt_screen() {
    let mut c = core();
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    c.feed(b"\x1b[?1049h");
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Released);
}

#[test]
fn a_sequence_split_across_two_feeds_still_switches() {
    let mut c = core();
    c.feed(b"\x1b[?10");
    c.feed(b"49h");
    c.feed(b"split");
    assert_eq!(alt_row(&c, 0), "split");
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test alt_routing 2>&1 | tail -20
```

Expected: `no method named resize`/`alt_grid` on `TerminalCore`.

- [ ] **Step 3: Write `crates/vt-core/src/alt/dispatch.rs`**

```rust
use vte::Params;

use crate::alt::AltGrid;

fn param(params: &Params, index: usize, default: u16) -> u16 {
    params
        .iter()
        .nth(index)
        .and_then(|group| group.first().copied())
        .filter(|value| *value != 0)
        .unwrap_or(default)
}

impl AltGrid {
    pub(crate) fn csi(&mut self, params: &Params, intermediates: &[u8], c: char) {
        if intermediates.first() == Some(&b'?') {
            match (param(params, 0, 0), c) {
                (25, 'h') => self.set_cursor_visible(true),
                (25, 'l') => self.set_cursor_visible(false),
                _ => {}
            }
            return;
        }
        if !intermediates.is_empty() {
            return;
        }
        match c {
            'A' => self.move_by(-(param(params, 0, 1) as isize), 0),
            'B' | 'e' => self.move_by(param(params, 0, 1) as isize, 0),
            'C' | 'a' => self.move_by(0, param(params, 0, 1) as isize),
            'D' => self.move_by(0, -(param(params, 0, 1) as isize)),
            'H' | 'f' => {
                let row = param(params, 0, 1) as usize - 1;
                let col = param(params, 1, 1) as usize - 1;
                self.move_to(row, col);
            }
            'G' | '`' => {
                let row = self.cursor().0;
                self.move_to(row, param(params, 0, 1) as usize - 1);
            }
            'd' => {
                let col = self.cursor().1;
                self.move_to(param(params, 0, 1) as usize - 1, col);
            }
            'E' => {
                let row = self.cursor().0 + param(params, 0, 1) as usize;
                self.move_to(row, 0);
            }
            'F' => {
                let row = self.cursor().0.saturating_sub(param(params, 0, 1) as usize);
                self.move_to(row, 0);
            }
            'J' => self.erase_in_display(param(params, 0, 0)),
            'K' => self.erase_in_line(param(params, 0, 0)),
            'L' => self.insert_lines(param(params, 0, 1) as usize),
            'M' => self.delete_lines(param(params, 0, 1) as usize),
            '@' => self.insert_chars(param(params, 0, 1) as usize),
            'P' => self.delete_chars(param(params, 0, 1) as usize),
            'X' => self.erase_chars(param(params, 0, 1) as usize),
            'S' => self.scroll_up(param(params, 0, 1) as usize),
            'T' => self.scroll_down(param(params, 0, 1) as usize),
            'r' => {
                let top = param(params, 0, 1) as usize - 1;
                let bottom = param(params, 1, self.rows() as u16) as usize - 1;
                self.set_scroll_region(top, bottom);
            }
            's' => self.save_cursor(),
            'u' => self.restore_cursor(),
            _ => {}
        }
    }

    pub(crate) fn esc(&mut self, byte: u8) {
        match byte {
            b'7' => self.save_cursor(),
            b'8' => self.restore_cursor(),
            b'D' => self.line_feed(),
            b'E' => self.next_line(),
            b'M' => self.reverse_index(),
            b'c' => self.reset(),
            _ => {}
        }
    }
}
```

`param` treats a `0` parameter as absent, which is what "default 1" means in the standard —
`CSI 0 H` is `CSI 1 ; 1 H`, not row zero. That is why `param(params, 0, 1) as usize - 1`
can never underflow. `ED` and `EL` pass a default of `0` because their default *is* zero.

Private modes other than `?25` are deliberately ignored, `?1049` included: the scanner owns
that switch. So are mouse reporting (`?1000`–`?1006`), bracketed paste (`?2004`) and the
legacy `?47`/`?1047` — see "out of scope" in the self-review.

- [ ] **Step 4: Make `Parser` a router**

In `crates/vt-core/src/parser.rs`:

1. Add the import: `use crate::alt::AltGrid;`
2. Add two fields to `struct Parser`:

```rust
    alt: Option<AltGrid>,
    saved_style: StyleCode,
```

   and initialise them in `Parser::new` as `alt: None` and `saved_style: StyleCode::DEFAULT`.

3. Add these methods to `impl Parser`:

```rust
    pub fn enter_alt(&mut self, rows: usize) {
        if self.alt.is_some() {
            return;
        }
        self.alt = Some(AltGrid::new(rows, self.width));
        self.saved_style = self.pending_style;
        self.pending_style = StyleCode::DEFAULT;
    }

    pub fn leave_alt(&mut self) {
        self.alt = None;
        self.pending_style = self.saved_style;
    }

    pub fn alt(&self) -> Option<&AltGrid> {
        self.alt.as_ref()
    }

    pub fn resize(&mut self, columns: usize, rows: usize) {
        self.width = columns;
        if let Some(alt) = self.alt.as_mut() {
            alt.resize(rows, columns);
        }
    }
```

   `enter_alt` returning early when a grid already exists is what makes
   `a_repeated_enter_while_already_inside_does_not_blank_the_screen` pass. Real terminals
   ignore a second `1049h`, and an agent CLI that re-sends it on redraw would otherwise
   wipe its own screen.

4. Replace the whole `impl Perform for Parser` block with:

```rust
impl Perform for Parser {
    fn print(&mut self, c: char) {
        let style = self.pending_style;
        match self.alt.as_mut() {
            Some(alt) => alt.print(c, style),
            None => self.write_char(c),
        }
    }

    fn execute(&mut self, byte: u8) {
        if let Some(alt) = self.alt.as_mut() {
            match byte {
                0x08 => alt.move_by(0, -1),
                0x09 => alt.tab(),
                0x0A..=0x0C => alt.line_feed(),
                0x0D => alt.carriage_return(),
                _ => {}
            }
            return;
        }
        match byte {
            0x09 => self.expand_tab(),
            0x0A..=0x0C => self.open_new_row(),
            _ => {}
        }
    }

    fn csi_dispatch(&mut self, params: &Params, intermediates: &[u8], _ignore: bool, c: char) {
        if c == 'm' {
            self.apply_sgr(params);
            return;
        }
        if let Some(alt) = self.alt.as_mut() {
            alt.csi(params, intermediates, c);
        }
    }

    fn esc_dispatch(&mut self, _intermediates: &[u8], _ignore: bool, byte: u8) {
        if let Some(alt) = self.alt.as_mut() {
            alt.esc(byte);
        }
    }
}
```

   **`0x0D` stops being a no-op — but only inside the alternate screen.** In the normal
   buffer it stays one, because an append-only byte stream has no column to return to.
   That asymmetry is deliberate; the test
   `carriage_return_is_still_a_no_op_in_the_normal_buffer` exists so a later reader cannot
   "fix" it by accident.

- [ ] **Step 5: Give `TerminalCore` rows, `resize` and `alt_grid`**

In `crates/vt-core/src/lib.rs`:

1. Add `pub mod alt;` (done in Task 1) and `pub use alt::{AltGrid, Cell};`
2. Add near `CoreError`:

```rust
pub const DEFAULT_ROWS: usize = 24;
```

3. Add a `rows: usize` field to `TerminalCore`, initialised to `DEFAULT_ROWS` in `new`.
   **Do not change `new`'s signature** — see decision D1.
4. Add these methods:

```rust
    pub fn resize(&mut self, columns: usize, rows: usize) {
        let columns = columns.clamp(1, alt::MAX_DIMENSION);
        let rows = rows.clamp(1, alt::MAX_DIMENSION);
        self.rows = rows;
        self.parser.resize(columns, rows);
    }

    pub fn rows(&self) -> usize {
        self.rows
    }

    pub fn alt_grid(&self) -> Option<&alt::AltGrid> {
        self.parser.alt()
    }
```

   `MAX_DIMENSION` is `pub(crate)` in `alt/mod.rs`; leave it that way and reference it as
   `alt::MAX_DIMENSION` from inside the crate.

5. In `feed`, inside the event loop, **immediately after** the existing
   `apply_event(&mut self.parser, &mut self.alt_screen, event);` line, add:

```rust
            match event {
                MarkEvent::AltScreenEnter => self.parser.enter_alt(self.rows),
                MarkEvent::AltScreenLeave => self.parser.leave_alt(),
                _ => {}
            }
```

   `apply_event` consumes `event` by value. `MarkEvent` derives `Clone`
   (`crates/marks/src/event.rs:14`), so take `let switch = event.clone();` on the line
   *before* the `apply_event` call and match on `switch` after it.

   **Order matters and is not arbitrary.** The switch runs *after* `apply_event`, which is
   what keeps `self.alt_screen` (the boolean that freezes marks) and the grid's existence
   flipping in the same step, in the same order they do today.

- [ ] **Step 6: Run everything**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core 2>&1 | tail -30
```

Expected: `alt_routing` passes 14, `alt_grid` passes 41, **and every pre-existing vt-core
suite still passes**. If `terminal_core.rs` or `blocks_from_marks.rs` went red, the
`Perform` rewrite changed normal-buffer behaviour — the likeliest cause is dropping the
`0x0D => {}` arm's *absence* of an effect, or reordering the SGR branch.

- [ ] **Step 7: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/vt-core && git commit -m "feat(terminal): route bytes to the alternate grid while it is active"
```

---

## Task 5: The snapshot, WASM, and the TypeScript core

**Files**
- Fill `packages/terminal/crates/vt-core/src/alt/snapshot.rs`
- Modify `crates/vt-core/src/grid.rs`, `crates/vt-core/src/lib.rs`
- Modify `crates/vt-wasm/src/lib.rs`
- Modify `ts/core/src/types.ts`, `ts/core/src/terminal-core.ts`, `ts/core/src/index.ts`
- Modify `ts/core/src/terminal-core.test.ts`

**Produces:**

```ts
export type AltScreenView = Readonly<{
	rows: number;
	columns: number;
	content: Uint8Array;
	rowRanges: Uint32Array;
	runRanges: Uint32Array;
	stylePairs: Uint32Array;
	cursorRow: number;
	cursorColumn: number;
	cursorVisible: boolean;
}>;
```

with `altScreen: AltScreenView | null` on `TerminalSnapshot`.

This is **deliberately the same wire shape as the block path**: `renderer-dom` already has
a loop driven by `(content, rowRanges, runRanges, stylePairs)` where each style pair is
`(runEndRelativeToRowStart, styleCode)` and the last pair of a row ends at the row's byte
length. Match it exactly — `AttributeMap::runs` at `attribute_map.rs:35` is the reference.

- [ ] **Step 1: Write `crates/vt-core/src/alt/snapshot.rs`**

```rust
use crate::alt::AltGrid;
use crate::style::StyleCode;

pub struct AltSnapshot {
    pub rows: usize,
    pub cols: usize,
    pub content: Vec<u8>,
    pub row_ranges: Vec<(u32, u32)>,
    pub run_ranges: Vec<(u32, u32)>,
    pub style_pairs: Vec<(u32, StyleCode)>,
    pub cursor_row: usize,
    pub cursor_col: usize,
    pub cursor_visible: bool,
}

impl AltGrid {
    pub fn snapshot(&self) -> AltSnapshot {
        let mut content: Vec<u8> = Vec::new();
        let mut row_ranges: Vec<(u32, u32)> = Vec::with_capacity(self.rows());
        let mut run_ranges: Vec<(u32, u32)> = Vec::with_capacity(self.rows());
        let mut style_pairs: Vec<(u32, StyleCode)> = Vec::new();
        let mut buffer = [0u8; 4];

        for row in 0..self.rows() {
            let row_start = content.len() as u32;
            let pair_start = style_pairs.len() as u32;
            let mut run_style: Option<StyleCode> = None;
            for col in 0..self.cols() {
                let cell = self.cell(row, col);
                if cell.ch == '\0' {
                    continue;
                }
                if run_style != Some(cell.style) {
                    if let Some(previous) = run_style {
                        style_pairs.push((content.len() as u32 - row_start, previous));
                    }
                    run_style = Some(cell.style);
                }
                content.extend_from_slice(cell.ch.encode_utf8(&mut buffer).as_bytes());
            }
            let row_end = content.len() as u32;
            if let Some(style) = run_style {
                style_pairs.push((row_end - row_start, style));
            }
            row_ranges.push((row_start, row_end));
            run_ranges.push((pair_start, style_pairs.len() as u32));
        }

        let (cursor_row, cursor_col) = self.cursor();
        AltSnapshot {
            rows: self.rows(),
            cols: self.cols(),
            content,
            row_ranges,
            run_ranges,
            style_pairs,
            cursor_row,
            cursor_col,
            cursor_visible: self.cursor_visible(),
        }
    }
}
```

Restore the `pub use snapshot::AltSnapshot;` line in `alt/mod.rs` that Task 1 commented out.

The `as u32` casts are safe because `MAX_DIMENSION` caps the grid at 1000×1000 cells and a
cell encodes to at most 4 bytes — 4 MB, three orders of magnitude below `u32::MAX`. This is
why decision D4 exists; do not remove the clamp and leave these casts.

- [ ] **Step 2: Carry it on `GridSnapshot`**

In `crates/vt-core/src/grid.rs`, add `pub alt: Option<crate::alt::AltSnapshot>,` to
`GridSnapshot`. `build_snapshot` takes one more parameter, `alt: Option<&AltGrid>`, and sets
the field to `alt.map(|grid| grid.snapshot())`. In `lib.rs`, `TerminalCore::snapshot` passes
`self.parser.alt()`.

- [ ] **Step 3: Add the Rust-side test**

Append to `crates/vt-core/tests/alt_routing.rs`:

```rust
#[test]
fn the_snapshot_carries_the_alt_grid_only_while_it_is_active() {
    let mut c = core();
    assert!(c.snapshot().expect("snapshot").alt.is_none());
    c.feed(b"\x1b[?1049h\x1b[2;3Hhi");
    let snapshot = c.snapshot().expect("snapshot");
    let alt = snapshot.alt.as_ref().expect("alt snapshot");
    assert_eq!(alt.rows, 24);
    assert_eq!(alt.cols, 80);
    assert_eq!(alt.cursor_row, 1);
    assert_eq!(alt.cursor_col, 4);
    let (start, end) = alt.row_ranges[1];
    let text = std::str::from_utf8(&alt.content[start as usize..end as usize]).expect("utf-8");
    assert_eq!(text.trim_end(), "  hi");
}

#[test]
fn every_alt_row_ends_its_style_runs_at_the_row_length() {
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[31mred\x1b[0m tail");
    let snapshot = c.snapshot().expect("snapshot");
    let alt = snapshot.alt.as_ref().expect("alt snapshot");
    for row in 0..alt.rows {
        let (row_start, row_end) = alt.row_ranges[row];
        let (pair_start, pair_end) = alt.run_ranges[row];
        assert!(pair_end > pair_start, "row {row} has no style runs");
        let last = alt.style_pairs[pair_end as usize - 1].0;
        assert_eq!(last, row_end - row_start, "row {row} runs stop short");
    }
}

#[test]
fn the_alt_snapshot_never_grows_past_one_screen() {
    let mut c = core();
    c.resize(10, 3);
    c.feed(b"\x1b[?1049h");
    for i in 0..50 {
        c.feed(format!("line {i}\r\n").as_bytes());
    }
    let snapshot = c.snapshot().expect("snapshot");
    assert_eq!(snapshot.alt.as_ref().expect("alt").row_ranges.len(), 3);
}
```

- [ ] **Step 4: Export it through WASM**

In `crates/vt-wasm/src/lib.rs`:

1. Add to `ExportBuffers`:

```rust
    alt_active: bool,
    alt_rows: u32,
    alt_cols: u32,
    alt_cursor_row: u32,
    alt_cursor_col: u32,
    alt_cursor_visible: bool,
    alt_content: Vec<u8>,
    alt_row_ranges: Vec<u32>,
    alt_run_ranges: Vec<u32>,
    alt_style_pairs: Vec<u32>,
```

2. In `refresh`, clear all four vectors and set `alt_active = false` first, then:

```rust
        if let Some(alt) = snapshot.alt.as_ref() {
            self.alt_active = true;
            self.alt_rows = alt.rows as u32;
            self.alt_cols = alt.cols as u32;
            self.alt_cursor_row = alt.cursor_row as u32;
            self.alt_cursor_col = alt.cursor_col as u32;
            self.alt_cursor_visible = alt.cursor_visible;
            self.alt_content.extend_from_slice(&alt.content);
            for &(start, end) in &alt.row_ranges {
                self.alt_row_ranges.push(start);
                self.alt_row_ranges.push(end);
            }
            for &(start, end) in &alt.run_ranges {
                self.alt_run_ranges.push(start);
                self.alt_run_ranges.push(end);
            }
            for &(end, code) in &alt.style_pairs {
                self.alt_style_pairs.push(end);
                self.alt_style_pairs.push(code.value());
            }
        }
```

3. Add the matching `#[wasm_bindgen]` accessors on `WasmTerminalCore`, following the exact
   naming pattern the block buffers already use: `alt_active() -> bool`,
   `alt_rows() -> u32`, `alt_cols() -> u32`, `alt_cursor_row() -> u32`,
   `alt_cursor_col() -> u32`, `alt_cursor_visible() -> bool`, and
   `alt_content_ptr/len`, `alt_row_ranges_ptr/len`, `alt_run_ranges_ptr/len`,
   `alt_style_pairs_ptr/len`.

4. Add:

```rust
    pub fn resize(&mut self, columns: usize, rows: usize) -> Result<(), JsError> {
        self.core.resize(columns, rows);
        let snapshot = self.core.snapshot().map_err(js_error_from_core)?;
        self.export.refresh(&snapshot)?;
        self.generation = self.generation.wrapping_add(1);
        Ok(())
    }
```

   Bumping the generation is what makes the renderer repaint after a resize. Without it the
   grid reshapes and nothing on screen changes until the next byte arrives.

- [ ] **Step 5: Write the failing TypeScript test**

Append to `ts/core/src/terminal-core.test.ts`:

```ts
it("exposes the alternate grid with a cursor, and nothing when inactive", () => {
	const core = createTerminalCore({ columns: 20, scrollback: 100 });
	core.resize(20, 5);
	expect(core.snapshot().altScreen).toBeNull();
	core.feed(new TextEncoder().encode("\x1b[?1049h\x1b[2;3Hhi"));
	const alt = core.snapshot().altScreen;
	expect(alt).not.toBeNull();
	expect(alt!.rows).toBe(5);
	expect(alt!.columns).toBe(20);
	expect(alt!.cursorRow).toBe(1);
	expect(alt!.cursorColumn).toBe(4);
	expect(alt!.cursorVisible).toBe(true);
	const text = new TextDecoder().decode(
		alt!.content.subarray(alt!.rowRanges[2], alt!.rowRanges[3]),
	);
	expect(text.trimEnd()).toBe("  hi");
	core.dispose();
});

it("reports no scrollback for the alternate buffer", () => {
	const core = createTerminalCore({ columns: 10, scrollback: 5000 });
	core.resize(10, 3);
	core.feed(new TextEncoder().encode("\x1b[?1049h"));
	for (let i = 0; i < 50; i += 1) {
		core.feed(new TextEncoder().encode(`line ${i}\r\n`));
	}
	expect(core.snapshot().altScreen!.rowRanges.length / 2).toBe(3);
	core.dispose();
});

it("drops the alternate view when the program leaves", () => {
	const core = createTerminalCore({ columns: 10, scrollback: 100 });
	core.feed(new TextEncoder().encode("\x1b[?1049hx\x1b[?1049l"));
	expect(core.snapshot().altScreen).toBeNull();
	core.dispose();
});
```

- [ ] **Step 6: Implement the TypeScript side**

`ts/core/src/types.ts`: add `AltScreenView`, add `altScreen: AltScreenView | null` to
`TerminalSnapshot`, and add optional `rows?: number` to `TerminalCoreOptions`.

`ts/core/src/terminal-core.ts`: in `snapshot()`, after the existing views, add

```ts
			altScreen: this.inner.alt_active()
				? {
						rows: this.inner.alt_rows(),
						columns: this.inner.alt_cols(),
						content: u8View(memory, this.inner.alt_content_ptr(), this.inner.alt_content_len()),
						rowRanges: u32View(memory, this.inner.alt_row_ranges_ptr(), this.inner.alt_row_ranges_len()),
						runRanges: u32View(memory, this.inner.alt_run_ranges_ptr(), this.inner.alt_run_ranges_len()),
						stylePairs: u32View(memory, this.inner.alt_style_pairs_ptr(), this.inner.alt_style_pairs_len()),
						cursorRow: this.inner.alt_cursor_row(),
						cursorColumn: this.inner.alt_cursor_col(),
						cursorVisible: this.inner.alt_cursor_visible(),
					}
				: null,
```

and add:

```ts
	resize(columns: number, rows: number): void {
		if (this.disposed) {
			return;
		}
		this.inner.resize(columns, rows);
		for (const listener of this.listeners) {
			listener(this.inner.generation());
		}
	}
```

If `createTerminalCore` accepts `rows`, have it call `resize` once after construction. Find
it with `grep -rn "createTerminalCore" ts/core/src`.

Export `AltScreenView` from `ts/core/src/index.ts`.

- [ ] **Step 7: Build and run**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm && npm test 2>&1 | tail -25
```

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core -p vt-wasm 2>&1 | tail -15
```

Both must be green. **If `npm run build:wasm` fails, stop.** Everything downstream depends
on it and a stale `.wasm` will make the TS tests pass against the old core, which is the
worst possible failure mode here — it looks like success.

- [ ] **Step 8: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates packages/terminal/ts/core && git commit -m "feat(terminal): export the alternate grid on the snapshot"
```

---

## Task 6: Geometry — measure, resize the core, resize the PTY

A terminal that cannot resize is not one, and a PTY that is never told its size makes
`vim` draw for 80×24 in a 200×50 pane. Both halves land here.

**Files**
- Modify `ts/react/src/TerminalSurface.tsx`
- Modify `frontend/src/renderer/components/BlockTerminal.tsx`
- Modify `ts/react/src/TerminalSurface.test.tsx`
- Modify `frontend/src/renderer/components/BlockTerminal.test.tsx`

- [ ] **Step 1: Write the failing tests**

In `ts/react/src/TerminalSurface.test.tsx` — match the file's existing render helper and
mocking style rather than inventing one:

```tsx
it("resizes the core to the measured geometry", () => {
	const { core } = renderSurface();
	const resize = vi.spyOn(core, "resize");
	setHostSize(1000, 500);
	expect(resize).toHaveBeenCalled();
	const [columns, rows] = resize.mock.calls.at(-1)!;
	expect(columns).toBeGreaterThan(0);
	expect(rows).toBeGreaterThan(0);
});

it("does not resize when the measured geometry has not changed", () => {
	const { core } = renderSurface();
	setHostSize(1000, 500);
	const resize = vi.spyOn(core, "resize");
	setHostSize(1000, 500);
	expect(resize).not.toHaveBeenCalled();
});
```

In `frontend/src/renderer/components/BlockTerminal.test.tsx`:

```tsx
it("tells the transport its size so the pty matches the pane", async () => {
	const resize = vi.fn();
	renderTerminal({ transport: { ...transport, resize } });
	await waitFor(() => expect(resize).toHaveBeenCalled());
	const [cols, rows] = resize.mock.calls.at(-1)!;
	expect(cols).toBeGreaterThan(0);
	expect(rows).toBeGreaterThan(0);
});
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run test -w @operator/terminal-react 2>&1 | tail -20
```

```bash
cd /Users/omaraly/development/AI/Operator/frontend && npx vitest run src/renderer/components/BlockTerminal.test.tsx 2>&1 | tail -20
```

- [ ] **Step 3: Implement geometry in `TerminalSurface`**

Add an `onGeometry?: (columns: number, rows: number) => void` prop, and a layout effect
that observes the block host:

```tsx
	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		const renderer = rendererRef.current;
		if (!blockHost || !renderer) {
			return;
		}
		let lastColumns = 0;
		let lastRows = 0;
		const apply = () => {
			const { cellWidth, cellHeight } = renderer.measure();
			if (cellWidth <= 0 || cellHeight <= 0) {
				return;
			}
			const columns = Math.max(1, Math.floor(blockHost.clientWidth / cellWidth));
			const rows = Math.max(1, Math.floor(blockHost.clientHeight / cellHeight));
			if (columns === lastColumns && rows === lastRows) {
				return;
			}
			lastColumns = columns;
			lastRows = rows;
			core.resize(columns, rows);
			onGeometry?.(columns, rows);
		};
		apply();
		if (typeof ResizeObserver !== "function") {
			return;
		}
		const observer = new ResizeObserver(apply);
		observer.observe(blockHost);
		return () => observer.disconnect();
	}, [core, onGeometry]);
```

**No debounce.** `ResizeObserver` already coalesces to one callback per frame, and the
`lastColumns`/`lastRows` guard drops every no-op. A timer here would be §3.5's ownership-
timer anti-pattern wearing a different hat, and `check-no-ownership-timer.mjs` is not
watching this file — the reviewer is.

The `typeof ResizeObserver !== "function"` guard is not defensive padding: jsdom in some
configurations does not provide it, and the initial `apply()` before the guard is what
makes the tests deterministic without one.

- [ ] **Step 4: Wire the PTY in `BlockTerminal`**

```tsx
	const onGeometry = useCallback((columns: number, rows: number) => {
		transportRef.current.resize?.(columns, rows);
	}, []);
```

and pass `onGeometry` in `surfaceProps`.

- [ ] **Step 5: Run**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm test 2>&1 | tail -15
```

```bash
cd /Users/omaraly/development/AI/Operator/frontend && npm run test 2>&1 | tail -15
```

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal frontend/src && git commit -m "feat(terminal): measure the pane and resize both the core and the pty"
```

---

## Task 7: The tmux conformance oracle

Spec §14 Phase 3 requires `vim`, `htop` and `less` to render correctly, "verified by
running them, not by unit tests alone". This task turns that promise into a recorded,
automated diff against a reference implementation.

The reference is **tmux**, which is already a dependency of the shell tests and is a
correct terminal. The trick: run a program under tmux, capture the **raw pane bytes** with
`pipe-pane` *and* tmux's **own rendered grid** with `capture-pane`. Feed the bytes to
`vt-core` and assert our grid matches tmux's, row for row.

**Files**
- Create `packages/terminal/tools/tmux-capture.mjs`
- Create `packages/terminal/protocol/alt-vectors/*.json`
- Create `packages/terminal/crates/vt-core/tests/alt_conformance.rs`

- [ ] **Step 1: Check the oracle exists**

```bash
tmux -V && which vim less htop
```

If `htop` is missing, record the other two and say so — do not install software to satisfy
a plan step. If `tmux` is missing, stop and report; this task cannot be faked.

- [ ] **Step 2: Write `packages/terminal/tools/tmux-capture.mjs`**

It takes a name, a command, rows, cols and a list of keys, and writes one vector JSON. The
shape below was verified by hand: a 40×5 pane running `printf 'AAAA\r\nBBBB'` produced
`capture-pane` output `AAAA` / `BBBB`.

```js
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const outDir = join(root, "protocol", "alt-vectors");

function tmux(...args) {
	return execFileSync("tmux", args, { encoding: "utf8" });
}

function sleep(ms) {
	execFileSync("sleep", [String(ms / 1000)]);
}

export function capture({ name, command, rows, cols, keys = [], settleMs = 700 }) {
	const session = `optcap-${name}-${process.pid}`;
	const rawPath = join("/tmp", `${session}.raw`);
	rmSync(rawPath, { force: true });
	mkdirSync(outDir, { recursive: true });
	try {
		tmux("new-session", "-d", "-s", session, "-x", String(cols), "-y", String(rows), command);
		tmux("pipe-pane", "-t", session, "-o", `cat >> ${rawPath}`);
		sleep(settleMs);
		for (const key of keys) {
			tmux("send-keys", "-t", session, key);
			sleep(300);
		}
		sleep(settleMs);
		const expectedRows = tmux("capture-pane", "-t", session, "-p").replace(/\n$/, "").split("\n");
		const input = readFileSync(rawPath);
		writeFileSync(
			join(outDir, `${name}.json`),
			`${JSON.stringify(
				{ name, rows, cols, command, keys, inputBase64: input.toString("base64"), expectedRows },
				null,
				"\t",
			)}\n`,
		);
		return expectedRows;
	} finally {
		try {
			tmux("kill-session", "-t", session);
		} catch {}
		rmSync(rawPath, { force: true });
	}
}

const cases = [
	{ name: "less-page", command: "less /usr/share/dict/words", rows: 20, cols: 60, keys: ["Space", "Space"] },
	{ name: "vim-open", command: "vim -u NONE -N /etc/hosts", rows: 20, cols: 60, keys: ["G"] },
	{ name: "htop-frame", command: "htop", rows: 24, cols: 80, keys: [] },
];

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	for (const testCase of cases) {
		try {
			capture(testCase);
			console.log(`recorded ${testCase.name}`);
		} catch (error) {
			console.error(`skipped ${testCase.name}: ${error.message}`);
		}
	}
}
```

Record them:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && node tools/tmux-capture.mjs
```

**Commit the recorded vectors, not the recorder's live output.** A test that shells out to
`vim` at CI time is a test that fails for reasons unrelated to the terminal. The recorder is
committed too, so a vector can be re-recorded deliberately — never automatically.

- [ ] **Step 3: Write `crates/vt-core/tests/alt_conformance.rs`**

```rust
use std::fs;
use std::path::PathBuf;

use vt_core::TerminalCore;

struct Vector {
    name: String,
    rows: usize,
    cols: usize,
    input: Vec<u8>,
    expected_rows: Vec<String>,
}

fn vectors_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("protocol")
        .join("alt-vectors")
}

fn load_vectors() -> Vec<Vector> {
    let dir = vectors_dir();
    let mut vectors = Vec::new();
    let entries = match fs::read_dir(&dir) {
        Ok(entries) => entries,
        Err(_) => return vectors,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let raw = fs::read_to_string(&path).expect("vector is readable");
        vectors.push(parse_vector(&raw));
    }
    vectors
}

#[test]
fn at_least_one_vector_is_recorded() {
    assert!(
        !load_vectors().is_empty(),
        "no alt-screen vectors in {:?}; run `node tools/tmux-capture.mjs`",
        vectors_dir()
    );
}

#[test]
fn our_alt_grid_matches_tmux_row_for_row() {
    for vector in load_vectors() {
        let mut core = TerminalCore::new(vector.cols, 100).expect("core");
        core.resize(vector.cols, vector.rows);
        core.feed(&vector.input);
        let alt = core
            .alt_grid()
            .unwrap_or_else(|| panic!("{}: never entered the alternate screen", vector.name));
        for (index, expected) in vector.expected_rows.iter().enumerate() {
            assert_eq!(
                alt.row_text(index).trim_end(),
                expected.trim_end(),
                "{} row {index}",
                vector.name
            );
        }
    }
}
```

`parse_vector` needs a JSON reader and a base64 decoder. `vt-core` has neither as a
dependency. **Do not add `serde_json` or a base64 crate to `vt-core` for a test** — that
puts a dependency in the shipped WASM's dependency graph. Instead add them under
`[dev-dependencies]` in `crates/vt-core/Cargo.toml`:

```toml
[dev-dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
base64 = "0.22"
```

Then verify the WASM artifact did not grow:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm && ls -l ts/core/wasm/*.wasm
```

- [ ] **Step 4: Run it, and expect it to fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test alt_conformance 2>&1 | tail -40
```

**Expect this to fail repeatedly and informatively. That is the task doing its job.** Each
failing row names a sequence Tasks 1–4 got wrong against a real program rather than against
my reading of the standard. Likely culprits, in the order they usually show up:

1. `vim` combines `DECSTBM` with `IL`/`DL` to scroll a window — check that IL/DL clamp to
   the region and not the screen.
2. `htop` toggles cursor visibility mid-frame and repaints with absolute addressing —
   check `?25` and that `H` with omitted parameters means 1;1.
3. `less` uses `ESC M` (reverse index) at the top of the region when scrolling back.
4. Wide characters and box-drawing glyphs in `htop`'s meters — check the `'\0'`
   continuation cell is filtered from `row_text` but still occupies a column.

**Fix the grid, not the vector.** A vector may only be re-recorded if you can show tmux's
own output is what changed, and you must say so explicitly in the commit message.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/tools packages/terminal/protocol/alt-vectors packages/terminal/crates && git commit -m "feat(terminal): diff the alternate grid against tmux for vim, htop and less"
```

---

## Task 8: The raw surface in `renderer-dom`

**Files**
- Create `ts/renderer-dom/src/row-builder.ts`
- Create `ts/renderer-dom/src/alt-surface.ts`
- Create `ts/renderer-dom/src/alt-surface.test.ts`
- Modify `ts/renderer-dom/src/dom-block-renderer.ts`
- Modify `ts/renderer-dom/src/styles.css` **and** `ts/renderer-dom/src/styles.ts`

**Watch the line budget.** `dom-block-renderer.ts` is 561 lines against a 600 limit. Task 8
*removes* lines from it by extracting the row loop, and adds only the fork. If you find
yourself adding the alt renderer inline, stop — that is decision D2's failure mode.

- [ ] **Step 1: Extract the row builder first, changing no behaviour**

Create `ts/renderer-dom/src/row-builder.ts` holding the per-row loop currently inside
`populateBlock` (`dom-block-renderer.ts:484-520`), verbatim except for its inputs:

```ts
import { styleCodeToCssVar } from "./style-code.js";

export const CLASS_ROW = "terminal-row";
export const CLASS_RUN = "terminal-run";

export type RowSource = Readonly<{
	content: Uint8Array;
	rows: Uint32Array;
	runRanges: Uint32Array;
	stylePairs: Uint32Array;
}>;

export function buildRowNode(
	source: RowSource,
	snapshotRowIndex: number,
	label: number,
	decoder: TextDecoder,
): HTMLElement {
	const { content, rows, runRanges, stylePairs } = source;
	const rowsBase = snapshotRowIndex * 2;
	const rowContentStart = rows[rowsBase] ?? 0;
	const rowContentEnd = rows[rowsBase + 1] ?? rowContentStart;
	const rowLength = rowContentEnd - rowContentStart;
	const pairStart = runRanges[rowsBase] ?? 0;
	const pairEnd = runRanges[rowsBase + 1] ?? pairStart;
	const rowNode = document.createElement("div");
	rowNode.dataset.terminalRow = String(label);
	rowNode.className = CLASS_ROW;
	let rowCursor = 0;
	for (let pairIndex = pairStart; pairIndex < pairEnd; pairIndex += 1) {
		const elementIndex = pairIndex * 2;
		const pairRunEnd = stylePairs[elementIndex] ?? rowCursor;
		const styleCode = stylePairs[elementIndex + 1] ?? 255;
		const slice = content.subarray(rowContentStart + rowCursor, rowContentStart + pairRunEnd);
		const run = document.createElement("span");
		run.dataset.terminalRun = String(pairIndex);
		run.className = CLASS_RUN;
		run.style.color = styleCodeToCssVar(styleCode);
		run.textContent = decoder.decode(slice);
		rowNode.append(run);
		rowCursor = pairRunEnd;
	}
	if (rowCursor < rowLength) {
		const tail = content.subarray(rowContentStart + rowCursor, rowContentStart + rowLength);
		rowNode.append(document.createTextNode(decoder.decode(tail)));
	}
	return rowNode;
}
```

Then have `populateBlock` call it, deleting the inlined loop and the now-unused
`CLASS_ROW`/`CLASS_RUN` constants at the top of `dom-block-renderer.ts` (import them from
`row-builder.js` instead).

Run the existing suite. **It must be green with zero test changes** — this step is a pure
refactor and any red means the extraction changed behaviour:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run test -w @operator/terminal-renderer-dom 2>&1 | tail -15
```

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run check:boundaries
```

Commit this on its own so the refactor is separable from the feature:

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom && git commit -m "refactor(terminal): extract the row builder so both surfaces share it"
```

- [ ] **Step 2: Write the failing alt-surface tests**

Create `ts/renderer-dom/src/alt-surface.test.ts`. Build the `AltScreenView` fixtures by hand
(a helper that encodes rows of plain text into `content` / `rowRanges` / `runRanges` /
`stylePairs` with one default-styled run per row) rather than by driving a real core —
this file is a unit test of the DOM, and a WASM dependency here makes failures ambiguous.

```ts
it("renders one row element per grid row, blank rows included", () => {
	const host = mountAlt(3, 10, ["ab", "", "cd"]);
	const rows = host.querySelectorAll("[data-terminal-row]");
	expect(rows.length).toBe(3);
	expect(rows[1]!.textContent).toBe("");
});

it("draws no block chrome in the alternate screen", () => {
	const host = mountAlt(3, 10, ["ab", "", ""]);
	expect(host.querySelector(".terminal-block-header")).toBeNull();
	expect(host.querySelector("[data-terminal-block-id]")).toBeNull();
});

it("places the cursor at the reported cell", () => {
	const host = mountAlt(3, 10, ["abc", "", ""], { cursorRow: 0, cursorColumn: 2 });
	const cursor = host.querySelector("[data-terminal-cursor]") as HTMLElement;
	expect(cursor.dataset.row).toBe("0");
	expect(cursor.dataset.column).toBe("2");
});

it("hides the cursor when the program hid it", () => {
	const host = mountAlt(3, 10, ["abc", "", ""], { cursorVisible: false });
	expect(host.querySelector("[data-terminal-cursor]")).toBeNull();
});

it("does not virtualize: the alternate buffer is one screen and all of it is on screen", () => {
	const host = mountAlt(60, 10, new Array(60).fill("x"));
	expect(host.querySelectorAll("[data-terminal-row]").length).toBe(60);
});

it("reuses row elements across repaints instead of rebuilding the surface", () => {
	const { host, render } = mountAltReusable(3, 10, ["a", "b", "c"]);
	const first = host.querySelector("[data-terminal-row]");
	render(["a", "b", "d"]);
	expect(host.querySelector("[data-terminal-row]")).toBe(first);
});
```

That last test matters more than it looks: an alt surface that calls `replaceChildren` on
the whole grid every frame rebuilds 24–50 rows at whatever rate `htop` refreshes, and that
is the difference between the §9.4 gate passing and not.

- [ ] **Step 3: Write `ts/renderer-dom/src/alt-surface.ts`**

Exports `renderAltSurface(view: AltScreenView, into: HTMLElement, decoder: TextDecoder):
void`. Requirements, each pinned by a test above:

- One `[data-terminal-row]` element per `view.rows`, in order, built with `buildRowNode`.
- Row elements are reused: keep the existing children and update them in place when the row
  count is unchanged; only rebuild when `view.rows` changes.
- A single `[data-terminal-cursor]` element with `dataset.row` / `dataset.column`, present
  only when `view.cursorVisible`. Position it with `transform: translate(calc(var(--cell-w)
  * N), calc(var(--cell-h) * M))` or by appending it inside the target row — either is fine,
  but it must carry the two data attributes.
- No headers, no block sections, no spacers.
- The root element gets `data-terminal-alt-surface` so Task 9 and the smokes can find it.

- [ ] **Step 4: Fork `repaint`**

At the very top of `DomBlockRenderer.repaint`, after the null guards and `core.snapshot()`:

```ts
		const alt = snapshot.altScreen;
		if (alt) {
			container.style.overflow = "hidden";
			container.scrollTop = 0;
			this.ensureAltRoot(container).hidden = false;
			if (this.list) this.list.hidden = true;
			renderAltSurface(alt, this.altRoot!, this.decoder);
			this.lastPaintAt = this.now();
			this.notifyPainted();
			return;
		}
		if (this.altRoot) {
			this.altRoot.hidden = true;
		}
		if (this.list) this.list.hidden = false;
		container.style.overflow = "auto";
```

`container.style.overflow = "hidden"` and `scrollTop = 0` are the no-scrollback rule made
physical — Task 11 asserts it in a real browser.

Keep the block-path branch below untouched. Do **not** reset `stickToBottom` on the way in
or out; the block list's scroll position must survive a TUI running and exiting, and the
existing stickiness logic already does the right thing when the block path resumes.

- [ ] **Step 5: Styles**

Add to `ts/renderer-dom/src/styles.css`:

```css
.terminal-alt-surface {
	position: relative;
	height: 100%;
	width: 100%;
	white-space: pre;
	font-family: var(--terminal-font-family);
	font-size: var(--terminal-font-size);
	font-weight: var(--terminal-font-weight);
	letter-spacing: var(--terminal-letter-spacing);
	line-height: var(--terminal-line-height);
	font-variant-ligatures: var(--terminal-ligatures);
	color: var(--terminal-foreground);
	background: var(--terminal-background);
}

.terminal-alt-cursor {
	position: absolute;
	width: 1ch;
	height: var(--terminal-line-height);
	background: var(--terminal-cursor);
	opacity: 0.8;
}
```

**`styles.ts` is generated verbatim from `styles.css`** and `styles-parity.test.ts` fails on
any drift. Regenerate rather than hand-editing:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom/src && { printf 'export const terminalStyles = `'; sed 's/\\/\\\\/g; s/`/\\`/g; s/\${/\\${/g' styles.css | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'; printf '`;\n'; } > styles.ts.new && mv styles.ts.new styles.ts
```

Then confirm:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run test -w @operator/terminal-renderer-dom 2>&1 | tail -15
```

If the parity test fails, the generator above mangled something — compare with
`git diff ts/renderer-dom/src/styles.ts` and fix by hand rather than editing the test.

- [ ] **Step 6: Run and commit**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm test && npm run check:boundaries
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom && git commit -m "feat(terminal): paint the alternate screen in renderer-dom"
```

---

## Task 9: Input, focus and the hidden editor

Spec §11: *"Input in the alternate screen is raw passthrough... The editor is hidden, not
disabled-in-place."* Those two sentences conflict in the DOM — a hidden element cannot hold
focus — and resolving that conflict is this whole task. See decision D6.

**Files**
- Modify `ts/editor/src/index.ts`
- Modify `ts/react/src/TerminalSurface.tsx`
- Modify `ts/react/src/TerminalSurface.test.tsx`

- [ ] **Step 1: Write the failing tests**

```tsx
it("hides the editor while the alternate screen is active", () => {
	const { container, core } = renderSurface();
	expect(container.querySelector(".terminal-editor-host")?.hasAttribute("hidden")).toBe(false);
	feed(core, "\x1b[?1049h");
	expect(container.querySelector(".terminal-editor-host")?.hasAttribute("hidden")).toBe(true);
});

it("sends alternate-screen keystrokes raw and never as a submitted line", () => {
	const { container, core, onSend, onSendRaw } = renderSurface();
	feed(core, "\x1b[?1049h");
	const surface = container.querySelector(".terminal-host") as HTMLElement;
	surface.dispatchEvent(new KeyboardEvent("keydown", { key: "a", bubbles: true }));
	surface.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
	expect(onSend).not.toHaveBeenCalled();
	expect(onSendRaw).toHaveBeenNthCalledWith(1, "a");
	expect(onSendRaw).toHaveBeenNthCalledWith(2, "\r");
});

it("encodes arrows and control keys the way a tui expects", () => {
	const { container, core, onSendRaw } = renderSurface();
	feed(core, "\x1b[?1049h");
	const surface = container.querySelector(".terminal-host") as HTMLElement;
	surface.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowUp", bubbles: true }));
	expect(onSendRaw).toHaveBeenCalledWith("\x1b[A");
});

it("takes focus when the alternate screen opens and gives it back on leave", () => {
	const { container, core } = renderSurface();
	feed(core, "\x1b[?1049h");
	expect(document.activeElement).toBe(container.querySelector(".terminal-host"));
	feed(core, "\x1b[?1049l");
	expect(container.querySelector(".terminal-editor-host")?.hasAttribute("hidden")).toBe(false);
});

it("returns to the block list when the program leaves the alternate screen", () => {
	const { container, core } = renderSurface();
	feed(core, "\x1b[?1049h");
	expect(container.querySelector("[data-terminal-alt-surface]")).not.toBeNull();
	feed(core, "\x1b[?1049l");
	const surface = container.querySelector("[data-terminal-alt-surface]") as HTMLElement | null;
	expect(surface === null || surface.hidden).toBe(true);
});
```

- [ ] **Step 2: Export the key encoder**

In `ts/editor/src/line-editor.ts`, change `function passthroughFor` to
`export function passthroughFor`, and add to `ts/editor/src/index.ts`:

```ts
export { passthroughFor } from "./line-editor.js";
```

- [ ] **Step 3: Implement in `TerminalSurface`**

- Track alt state from the core, not from a prop:

```tsx
	const [altActive, setAltActive] = useState(false);
	useLayoutEffect(() => {
		const read = () => setAltActive(core.snapshot().altScreen !== null);
		read();
		return core.onChange(read);
	}, [core]);
```

- Give the block host `tabIndex={0}` and a keydown handler active only while `altActive`:

```tsx
	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		if (!blockHost || !altActive) {
			return;
		}
		const onKeyDown = (event: KeyboardEvent) => {
			const command = mapKey(event);
			if (!command) {
				return;
			}
			event.preventDefault();
			onSendRaw(passthroughFor(command));
		};
		blockHost.addEventListener("keydown", onKeyDown);
		blockHost.focus();
		return () => blockHost.removeEventListener("keydown", onKeyDown);
	}, [altActive, onSendRaw]);
```

- Render the editor host with `hidden={altActive}`.

`onSend` is never called in this path. That is not an oversight: there is no line to submit
in the alternate screen, and `Enter` is a raw `\r` the program interprets itself.

- [ ] **Step 4: Run**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm test && npm run check:boundaries
```

`check:boundaries` matters here specifically: `renderer-dom` must still not import `editor`.
If it does, you put the keydown handler in the wrong package.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal && git commit -m "feat(terminal): raw input and a hidden editor in the alternate screen"
```

---

## Task 10: Operator shows it

**Files**
- Modify `frontend/src/renderer/components/BlockTerminal.tsx`
- Modify `frontend/src/renderer/components/BlockTerminal.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
it("takes the alternate-screen signal from the core, not from sniffing bytes", async () => {
	const { core } = renderTerminal();
	emit(encode("\x1b[?1049h"));
	await waitFor(() => expect(core.snapshot().altScreen).not.toBeNull());
	expect(screen.getByTestId("block-terminal")).toHaveAttribute("data-alt-screen", "true");
});

it("still hands the alternate screen to xterm when the flag says so", () => {
	// with VITE_ALT_SCREEN_SURFACE=xterm stubbed
});
```

- [ ] **Step 2: Delete the byte sniffer**

Remove `ALT_SCREEN_ENTER`, `ALT_SCREEN_LEAVE`, the `SOURCE_ID_PATTERN`-adjacent
`text.includes(...)` branches in the `transport.onData` handler, and the `altScreenActive`
`useState`. Replace with a core subscription:

```tsx
	useEffect(() => {
		if (!core) return;
		const read = () => setAltScreenActive(core.snapshot().altScreen !== null);
		read();
		return core.onChange(read);
	}, [core]);
```

Keep `handsAltScreenToXterm` and `handOffAltScreen` exactly as they are — the flag is the
spec-required escape hatch and Task 11 asserts it still works. Update the comment above
`handsAltScreenToXterm` to say the grid has landed, since it currently says the opposite.

Add `data-alt-screen={String(altScreenActive)}` to the root div.

- [ ] **Step 3: Run**

```bash
cd /Users/omaraly/development/AI/Operator/frontend && npm run test && npm run typecheck
```

- [ ] **Step 4: Look at it. This is not optional.**

```bash
cd /Users/omaraly/development/AI/Operator && npm run tauri:dev
```

Open a session and, in order:

1. `vim /etc/hosts` — type, move with arrows, `:q!`. The block list must come back with the
   pre-`vim` blocks intact.
2. `htop` — let it refresh for ten seconds. Nothing should walk upward or leave trails.
3. `less /usr/share/dict/words` — page down, page up, `/search`, `q`.
4. Resize the window while each is running. The program must reflow, which proves Task 6's
   `transport.resize` reached the PTY.
5. Start an agent CLI session. Per §2.8 it enters the alternate screen on its first chunk
   and never leaves.

Then run the same five against the fallback and compare:

```bash
cd /Users/omaraly/development/AI/Operator && VITE_ALT_SCREEN_SURFACE=xterm npm run tauri:dev
```

**Screenshot both.** Unit tests do not tell you whether `htop` looks right. If the daemon
refuses with `identity_mismatch`, a stale daemon is running — find it with
`ps aux | grep -i operator` and stop it before blaming the terminal.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add frontend/src && git commit -m "feat(terminal): show the alternate screen in Operator's own surface"
```

---

## Task 11: Close Phase 3

- [ ] **Step 1: The shred rule, end to end**

Add a Playwright case to the vite smoke (`scripts/smoke-vite.mjs`): feed a marked block,
enter the alternate screen, emit mark-shaped bytes, leave, and assert the rendered block
list is unchanged. The Task 4 unit test proves the core; this proves the pixels.

- [ ] **Step 2: No scrollback, in a real browser**

Add to the vite smoke: while the alternate screen is active, `scrollTop` cannot move.
Set it to 500, read it back, assert 0.

- [ ] **Step 3: The xterm fallback still works**

Assert `VITE_ALT_SCREEN_SURFACE=xterm` still mounts `XtermTerminal` and renders. §14 Phase 3
requires a regression to be one flag away from a working pane.

- [ ] **Step 4: The §9.4 gate**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:terminal -- --renderer dom --scenario vtebench && npm run bench:terminal -- --renderer dom --scenario large-output
```

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:terminal -- --renderer dom --scenario input-latency && npm run bench:terminal -- --renderer dom --scenario input-latency-owned
```

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:gate && npm run bench:scroll
```

Expected: `perf gate passed`. If `input-latency` regressed against Task 0's baseline, the
first suspect is the alt fork in `repaint` adding work to the *block* path — it runs on
every paint, alt screen or not. The gate was made honest in Phase 2; trust it until shown
otherwise, and never re-record a baseline to clear a failure you introduced.

- [ ] **Step 5: Full sweep**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
```

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/go/marks && go test ./...
```

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && node --test shell/zsh.test.mjs shell/bash.test.mjs shell/fish.test.mjs
```

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm test && npm run check:boundaries && npm run smoke:vite && npm run smoke:tauri
```

```bash
cd /Users/omaraly/development/AI/Operator/frontend && npm run typecheck && npm run test
```

- [ ] **Step 6: Update the spec and changelog, then commit**

Mark Phase 3 complete in §14. Note in §11 that the package's grid is now the default surface
and xterm is the flagged fallback.

```bash
cd /Users/omaraly/development/AI/Operator && git add docs && git commit -m "docs: close phase 3 — the alternate screen renders in our own grid"
```

- [ ] **Step 7: Report, do not merge**

Report what passed, what did not, and every place you deviated from this plan. **Do not
merge to `master` and do not push.** The merge is a separate, explicit instruction.

---

## Self-Review

**Spec coverage.** §11's four bullets map to: second fixed grid with saved cursor and no
scrollback → Tasks 1, 3, 4, 5; cursor addressing, scroll regions, erase and line editing →
Tasks 1–4, verified against real programs in Task 7; renderer through the `BlockRenderer`
seam with no block chrome → Task 8; raw input with the editor hidden → Task 9. §11's shred
rule → Task 4 and Task 11 Step 1. §14 Phase 3's six acceptance criteria: vim/htop/less →
Task 7 automated plus Task 10 Step 4 by hand; agent CLI end to end → Task 10 Step 4; blocks
byte-identical across the alt session → Task 4, Task 11 Step 1; no scrollback → Task 5,
Task 11 Step 2; xterm behind a flag → Task 10 Step 2, Task 11 Step 3; §9.4 → Task 11 Step 4.

**What this plan changed from the earlier draft, and why.** Five corrections, each from
reading the code rather than remembering it:

1. Alt entry is a **mark event**, not a `csi_dispatch` branch. The earlier draft would have
   added a second switch racing the scanner's.
2. `TerminalCore::new` keeps two arguments (D1). The earlier draft's third parameter meant
   26 mechanical edits with no behavioural payoff.
3. `transport.resize` is wired (Task 6). The earlier draft never told the PTY its size,
   which would have made every Task 7 vector pass and every real `vim` session wrong.
4. The row builder is extracted before the alt surface is written (Task 8 Step 1), because
   `dom-block-renderer.ts` has 39 lines of headroom against the boundary check.
5. The editor-hiding and focus problem is named and resolved (D6) rather than left as
   "hide the editor", which is not implementable as written.

**Where this will hurt.** Task 7. Tasks 1–4 are written from the standard, and real programs
use the standard in ways no unit test written from memory predicts. Expect the tmux diff to
fail several times. That is the task working. Budget for it, and fix the grid.

**Deliberately out of scope**, each cheap to add later behind the same CSI table: mouse
reporting (`?1000`–`?1006`), bracketed paste (`?2004`), origin mode (`DECOM`), character
sets (`ESC ( B`), sixel, and the legacy `?47`/`?1047` switches. None is needed for vim,
htop, less or an agent CLI. If a Task 7 vector fails *because* of one of these, add it —
and say that you did.

**Type consistency.** `AltGrid`'s surface is fixed in Task 1 and only extended, never
renamed, by Tasks 2, 3 and 5. `AltSnapshot` is defined once in Task 5. `AltScreenView` is
defined once in Task 5 and consumed unchanged by Tasks 8, 9 and 10.

**Known open item carried in.** The perf baseline was still a single lucky draw at the time
of writing and Task 0 Step 3 re-records it. If that re-record does not clear
`input-latency`, the honest reading is that the DOM renderer is marginally slower than
xterm on that scenario and it needs its own investigation — not a third baseline.
