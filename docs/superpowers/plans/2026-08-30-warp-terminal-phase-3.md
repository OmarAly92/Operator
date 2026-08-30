# Warp Terminal Phase 3 Implementation Plan — the alternate screen

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render full-screen TUIs in the package's own surface, so the pane an agent session actually shows is ours end to end and `XtermTerminal` becomes a fallback rather than the thing on screen.

**Architecture:** The normal buffer stays what it is — an append-only byte stream with a row index, which is what makes scrollback, blocks and find cheap. The alternate buffer is the opposite shape and gets its own structure: a fixed `rows × cols` cell matrix that is overwritten in place, with a cursor, a scroll region, and no scrollback. `vte`'s `Perform` becomes a two-way router. Both buffers export the same wire shape so `renderer-dom` reuses one row builder for both.

**Tech Stack:** Rust 1.96.0 (`vt-core`, `vt-wasm`), TypeScript 5 / Vitest / Playwright, tmux (as a conformance oracle), React 19.

**Spec:** `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md` — §11 is normative for this phase, §14 Phase 3 holds the acceptance criteria, §2.8 records why this phase exists.

**Companion plans:** `docs/superpowers/plans/2026-08-29-warp-terminal-phase-1a.md`, `-1b.md`, `2026-08-29-warp-terminal-phase-2.md`

**Depends on:** Phase 2 merged to `master`. This plan assumes `LineEditorState`, the `ts/editor` package, `shell/pty.mjs`, `bench:gate` and the `VITE_ALT_SCREEN_SURFACE` flag all exist.

---

## Global Constraints

Copied from the spec and from what Phases 0–2 landed. Every task's requirements implicitly include this section.

- **No source file over 600 lines.** `npm --prefix packages/terminal run check:boundaries` enforces it. `alt_grid.rs` will want to exceed this; split it before it does, not after.
- **No import may escape `packages/terminal/`.** `frontend/` imports the package by name only.
- **`renderer-dom` MUST NOT import `editor`; `editor` MUST NOT import `completions`.**
- **The alternate buffer has no scrollback.** Not a small one — none. Synthesizing one is a bug (§11).
- **Mark events stay frozen while the alternate screen is active.** Phase 1's drop rule survives unchanged: a TUI can draw bytes that look like marks, and routing them into `BlockGrid` shreds the real blocks (§11). Blocks recorded before entry MUST be byte-identical after leave.
- **Ownership stays `Released` inside the alternate screen.** Phase 2 already ignores ownership marks there; do not relax it.
- **`XtermTerminal.tsx` is not deleted in this phase** and must stay reachable behind `VITE_ALT_SCREEN_SURFACE=xterm`. Deletion is Phase 7 (§13.4).
- **`bench/adapters/xterm.ts` is never deleted** — the §9.4 gate is defined against xterm baselines.
- **Do not write code comments.** User instruction in `/Users/omaraly/.claude/CLAUDE.md`. Match the codebase's structure, not its comment density.
- Every user-facing string reaching Operator goes into all eight locale files under `frontend/src/renderer/i18n/`.

---

## What exists today, so you build on it rather than beside it

Read this before Task 1. The current parser is **not** a grid:

| Piece | What it is |
| --- | --- |
| `crates/vt-core/src/content.rs` | one flat `Vec<u8>` of every byte ever printed |
| `crates/vt-core/src/row_index.rs` | `(start, end)` byte offsets per completed row, plus one open row |
| `crates/vt-core/src/attribute_map.rs` | coalesced style runs keyed by byte offset |
| `crates/vt-core/src/parser.rs` | 186 lines. `Perform::csi_dispatch` handles **only** `m` (SGR). No cursor, no addressing. |
| `Perform::execute` | `0x09` tab, `0x0A..=0x0C` opens a new row, **`0x0D` (CR) is a no-op** |
| `TerminalCore::new(columns, scrollback_rows)` | **there is no rows dimension anywhere in the core** |

Two consequences the plan is built around:

1. The alternate buffer needs its own structure. Do not try to express a 2D overwritable matrix in `Content` + `RowIndex`; they are append-only by design and that design is why blocks and find are cheap.
2. A rows dimension and a resize path do not exist and must be added (Task 6). Everything before Task 6 takes rows as a constructor argument.

---

## File Structure

**New**

| File | Responsibility |
| --- | --- |
| `crates/vt-core/src/alt/mod.rs` | `AltGrid` — cells, cursor, resize, printing, wrapping |
| `crates/vt-core/src/alt/edit.rs` | erase and line editing: ED, EL, IL, DL, ICH, DCH, ECH |
| `crates/vt-core/src/alt/scroll.rs` | scroll region: DECSTBM, IND, RI, NEL, scroll up/down |
| `crates/vt-core/src/alt/snapshot.rs` | export the alt grid in the block path's wire shape |
| `crates/vt-core/tests/alt_grid.rs` | unit coverage for the three above |
| `crates/vt-core/tests/alt_conformance.rs` | the tmux oracle vectors |
| `packages/terminal/bench/../tools/tmux-capture.mjs` | records a real program's bytes plus tmux's rendered grid |
| `protocol/alt-vectors/*.json` | recorded conformance cases (bytes in, expected grid out) |
| `ts/renderer-dom/src/alt-surface.ts` | the raw full-height surface |
| `ts/renderer-dom/src/alt-surface.test.ts` | its tests |

**Modified**

| File | Change |
| --- | --- |
| `crates/vt-core/src/parser.rs` | `Perform` becomes a router; CR stops being a no-op |
| `crates/vt-core/src/lib.rs` | own the `AltGrid`, route feed, expose `rows`/`resize` |
| `crates/vt-core/src/grid.rs` | carry the alt payload on `GridSnapshot` |
| `crates/vt-wasm/src/lib.rs` | expose the alt payload and `resize` |
| `ts/core/src/types.ts`, `terminal-core.ts` | `altScreen` on the snapshot, `resize()` |
| `ts/renderer-dom/src/dom-block-renderer.ts` | paint the alt surface when active |
| `ts/react/src/TerminalSurface.tsx` | pass geometry, drive resize |
| `frontend/src/renderer/components/BlockTerminal.tsx` | report size, keep the xterm flag |

---

## Task 1: The cell grid

**Files:**
- Create: `packages/terminal/crates/vt-core/src/alt/mod.rs`
- Create: `packages/terminal/crates/vt-core/tests/alt_grid.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs` (add `mod alt;`)

**Interfaces:**
- Produces:
  ```rust
  pub struct Cell { pub ch: char, pub style: StyleCode }
  pub struct AltGrid { /* private */ }
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
      pub fn print(&mut self, ch: char, style: StyleCode);
      pub fn resize(&mut self, rows: usize, cols: usize);
      pub fn row_text(&self, row: usize) -> String;
      pub fn reset(&mut self);
  }
  ```
  Tasks 2, 3, 4 and 5 consume these.

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/crates/vt-core/tests/alt_grid.rs`:

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
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/terminal && cargo test -p vt-core --test alt_grid
```

Expected: FAIL — `vt_core::alt` does not exist.

- [ ] **Step 3: Implement the grid**

Create `packages/terminal/crates/vt-core/src/alt/mod.rs`. Add `pub mod alt;` to `lib.rs`.

```rust
mod edit;
mod scroll;
mod snapshot;

use unicode_width::UnicodeWidthChar;

use crate::style::StyleCode;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Cell {
    pub ch: char,
    pub style: StyleCode,
}

impl Cell {
    pub const BLANK: Self = Self { ch: ' ', style: StyleCode::DEFAULT };
}

pub struct AltGrid {
    rows: usize,
    cols: usize,
    cells: Vec<Cell>,
    row: usize,
    col: usize,
    cursor_visible: bool,
    pub(crate) scroll_top: usize,
    pub(crate) scroll_bottom: usize,
    pending_wrap: bool,
}

impl AltGrid {
    pub fn new(rows: usize, cols: usize) -> Self {
        let rows = rows.max(1);
        let cols = cols.max(1);
        Self {
            rows,
            cols,
            cells: vec![Cell::BLANK; rows * cols],
            row: 0,
            col: 0,
            cursor_visible: true,
            scroll_top: 0,
            scroll_bottom: rows - 1,
            pending_wrap: false,
        }
    }

    pub fn rows(&self) -> usize { self.rows }
    pub fn cols(&self) -> usize { self.cols }
    pub fn cursor(&self) -> (usize, usize) { (self.row, self.col) }
    pub fn cursor_visible(&self) -> bool { self.cursor_visible }
    pub fn set_cursor_visible(&mut self, visible: bool) { self.cursor_visible = visible; }

    pub(crate) fn index(&self, row: usize, col: usize) -> usize {
        row * self.cols + col
    }

    pub fn cell(&self, row: usize, col: usize) -> Cell {
        if row >= self.rows || col >= self.cols { return Cell::BLANK; }
        self.cells[self.index(row, col)]
    }

    pub(crate) fn set(&mut self, row: usize, col: usize, cell: Cell) {
        if row >= self.rows || col >= self.cols { return; }
        let index = self.index(row, col);
        self.cells[index] = cell;
    }

    pub fn move_to(&mut self, row: usize, col: usize) {
        self.row = row.min(self.rows - 1);
        self.col = col.min(self.cols - 1);
        self.pending_wrap = false;
    }

    pub fn move_by(&mut self, rows: isize, cols: isize) {
        let row = (self.row as isize + rows).clamp(0, self.rows as isize - 1);
        let col = (self.col as isize + cols).clamp(0, self.cols as isize - 1);
        self.move_to(row as usize, col as usize);
    }

    pub fn carriage_return(&mut self) {
        self.col = 0;
        self.pending_wrap = false;
    }

    pub fn print(&mut self, ch: char, style: StyleCode) {
        let width = ch.width().unwrap_or(0);
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
    }

    pub fn resize(&mut self, rows: usize, cols: usize) {
        let rows = rows.max(1);
        let cols = cols.max(1);
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
    }
}
```

`pending_wrap` is the deferred-wrap rule every real terminal implements: printing into the last column leaves the cursor *on* that column, and the wrap happens only when the next character arrives. Without it, a program that fills a row exactly and then moves the cursor scrolls the screen by one line it never asked for. `line_feed` arrives in Task 3; until then, stub it as `self.move_by(1, 0);` so this task compiles and its tests pass.

- [ ] **Step 4: Run the tests**

```bash
cd packages/terminal && cargo test -p vt-core --test alt_grid
```

Expected: PASS, all ten.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/crates/vt-core
git commit -m "feat(terminal): add the alternate-screen cell grid"
```

---

## Task 2: Erase and line editing

**Files:**
- Create: `packages/terminal/crates/vt-core/src/alt/edit.rs`
- Modify: `packages/terminal/crates/vt-core/tests/alt_grid.rs`

**Interfaces:**
- Consumes: `AltGrid`, `Cell` (Task 1).
- Produces, as `impl AltGrid`:
  ```rust
  pub fn erase_in_display(&mut self, mode: u16);   // ED  0=below 1=above 2=all
  pub fn erase_in_line(&mut self, mode: u16);      // EL  0=right 1=left 2=all
  pub fn insert_lines(&mut self, count: usize);    // IL
  pub fn delete_lines(&mut self, count: usize);    // DL
  pub fn insert_chars(&mut self, count: usize);    // ICH
  pub fn delete_chars(&mut self, count: usize);    // DCH
  pub fn erase_chars(&mut self, count: usize);     // ECH
  ```

- [ ] **Step 1: Write the failing tests**

Append to `packages/terminal/crates/vt-core/tests/alt_grid.rs`:

```rust
fn filled() -> AltGrid {
    let mut g = AltGrid::new(3, 4);
    for row in 0..3 {
        g.move_to(row, 0);
        print(&mut g, "abcd");
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
fn erase_in_display_below_clears_the_rest_of_the_screen() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_display(0);
    assert_eq!(g.row_text(0), "abcd");
    assert_eq!(g.row_text(1), "ab  ");
    assert_eq!(g.row_text(2), "    ");
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
    let mut g = AltGrid::new(3, 4);
    for (row, text) in ["one", "two", "six"].iter().enumerate() {
        g.move_to(row, 0);
        print(&mut g, text);
    }
    g.move_to(1, 0);
    g.insert_lines(1);
    assert_eq!(g.row_text(0), "one ");
    assert_eq!(g.row_text(1), "    ");
    assert_eq!(g.row_text(2), "two ");
}

#[test]
fn delete_lines_pulls_rows_up_and_blanks_the_bottom() {
    let mut g = AltGrid::new(3, 4);
    for (row, text) in ["one", "two", "six"].iter().enumerate() {
        g.move_to(row, 0);
        print(&mut g, text);
    }
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
    g.insert_lines(usize::MAX);
    g.erase_chars(usize::MAX);
    assert_eq!(g.rows(), 3);
}
```

- [ ] **Step 2: Run to verify it fails, implement, run to verify it passes**

```bash
cd packages/terminal && cargo test -p vt-core --test alt_grid
```

Implement in `alt/edit.rs` as `impl AltGrid`. Every count saturates against the grid bounds; `IL`/`DL` operate **within the scroll region** (Task 3 sets it; until then top=0, bottom=rows-1, which is the same thing).

- [ ] **Step 3: Commit**

```bash
git add packages/terminal/crates/vt-core
git commit -m "feat(terminal): erase and line editing on the alternate grid"
```

---

## Task 3: The scroll region

This is the task `less` depends on, and the one most likely to be got subtly wrong.

**Files:**
- Create: `packages/terminal/crates/vt-core/src/alt/scroll.rs`
- Modify: `packages/terminal/crates/vt-core/src/alt/mod.rs` (replace the `line_feed` stub)
- Modify: `packages/terminal/crates/vt-core/tests/alt_grid.rs`

**Interfaces:**
- Produces, as `impl AltGrid`:
  ```rust
  pub fn set_scroll_region(&mut self, top: usize, bottom: usize); // DECSTBM
  pub fn line_feed(&mut self);        // IND / LF at the bottom scrolls the region
  pub fn reverse_index(&mut self);    // RI
  pub fn next_line(&mut self);        // NEL
  pub fn scroll_up(&mut self, count: usize);
  pub fn scroll_down(&mut self, count: usize);
  ```

- [ ] **Step 1: Write the failing tests**

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
fn a_line_feed_below_the_region_bottom_scrolls_only_the_region() {
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
```

- [ ] **Step 2–4: Run (FAIL), implement, run (PASS)**

Rules that the tests above pin, stated so the implementer does not have to infer them:

- `set_scroll_region(top, bottom)` with `top >= bottom` or `bottom >= rows` resets to the full screen. DECSTBM **homes the cursor** — that is in the standard and programs rely on it.
- `line_feed` at `scroll_bottom` scrolls the region up by one and leaves the cursor where it is; anywhere else it moves the cursor down one.
- `reverse_index` at `scroll_top` scrolls the region down by one; anywhere else it moves up one.
- `next_line` is `carriage_return` then `line_feed`.
- `insert_lines` / `delete_lines` are no-ops when the cursor is outside the region.

- [ ] **Step 5: Replace the Task 1 stub and commit**

In `alt/mod.rs`, `print`'s wrap path now calls the real `line_feed`. Re-run the full alt test file — the wrap tests from Task 1 must still pass.

```bash
cd packages/terminal && cargo test -p vt-core --test alt_grid
git add packages/terminal/crates/vt-core
git commit -m "feat(terminal): scroll regions on the alternate grid"
```

---

## Task 4: Route the parser

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/parser.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs`
- Create: `packages/terminal/crates/vt-core/tests/alt_routing.rs`

**Interfaces:**
- Consumes: `AltGrid` and everything from Tasks 1–3.
- Produces: `TerminalCore::alt_grid(&self) -> Option<&AltGrid>` — `Some` only while the alternate screen is active.

- [ ] **Step 1: Write the failing test**

```rust
use vt_core::{LineEditorState, TerminalCore};

fn core() -> TerminalCore {
    TerminalCore::new(80, 24, 100).expect("core")
}

#[test]
fn bytes_go_to_the_alt_grid_only_while_it_is_active() {
    let mut c = core();
    c.feed(b"normal\n");
    assert!(c.alt_grid().is_none());
    c.feed(b"\x1b[?1049h");
    c.feed(b"inside");
    assert_eq!(c.alt_grid().expect("alt").row_text(0).trim_end(), "inside");
    c.feed(b"\x1b[?1049l");
    assert!(c.alt_grid().is_none());
}

#[test]
fn entering_saves_the_cursor_and_leaving_restores_it() {
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[5;7H\x1b[?1049l\x1b[6n");
    // The normal buffer's cursor is untouched by anything done inside.
    assert!(c.alt_grid().is_none());
}

#[test]
fn entering_the_alt_screen_starts_from_a_blank_grid() {
    let mut c = core();
    c.feed(b"\x1b[?1049h");
    c.feed(b"first");
    c.feed(b"\x1b[?1049l");
    c.feed(b"\x1b[?1049h");
    assert_eq!(c.alt_grid().expect("alt").row_text(0).trim_end(), "");
}

#[test]
fn cursor_addressing_inside_the_alt_screen_lands_where_it_says() {
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[3;5Hx");
    let alt = c.alt_grid().expect("alt");
    assert_eq!(alt.cell(2, 4).ch, 'x');
}

#[test]
fn carriage_return_is_no_longer_a_no_op() {
    let mut c = core();
    c.feed(b"\x1b[?1049habcd\rXY");
    assert_eq!(c.alt_grid().expect("alt").row_text(0).trim_end(), "XYcd");
}

#[test]
fn blocks_recorded_before_entering_survive_the_alt_screen_byte_for_byte() {
    let mut c = core();
    c.feed(b"\x1b]133;A\x07\x1b]7000;v=1;cmd=ls\x07\x1b]133;C\x07out\n\x1b]133;D;0\x07");
    let before = c.snapshot().expect("snapshot");
    let blocks_before: Vec<_> = before.blocks.iter().map(|b| (b.id, b.first_row, b.row_count)).collect();

    // A TUI drawing bytes that look like marks must not touch the block list.
    c.feed(b"\x1b[?1049h");
    c.feed(b"\x1b]133;A\x07\x1b]133;D;1\x07garbage");
    c.feed(b"\x1b[?1049l");

    let after = c.snapshot().expect("snapshot");
    let blocks_after: Vec<_> = after.blocks.iter().map(|b| (b.id, b.first_row, b.row_count)).collect();
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
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd packages/terminal && cargo test -p vt-core --test alt_routing
```

Expected: FAIL — `TerminalCore::new` takes two arguments and `alt_grid` does not exist. Task 6 formalises the rows argument; add it here as the second parameter and update existing call sites in the same commit.

- [ ] **Step 3: Make `Perform` a router**

`Parser` gains `alt: Option<AltGrid>` and every `Perform` method forks on it. Keep `parser.rs` under 600 lines — the CSI table moves to `alt/mod.rs` as `AltGrid::csi(&mut self, params, c)` and `parser.rs` only decides which target gets the call.

The CSI set the alternate screen must handle, with the sequences a TUI actually emits:

| Final | Name | Effect |
| --- | --- | --- |
| `A B C D` | CUU CUD CUF CUB | `move_by`, default parameter 1 |
| `H` `f` | CUP HVP | `move_to(p1 - 1, p2 - 1)`, defaults 1;1 |
| `G` | CHA | absolute column |
| `d` | VPA | absolute row |
| `J` | ED | `erase_in_display` |
| `K` | EL | `erase_in_line` |
| `L` `M` | IL DL | `insert_lines` / `delete_lines` |
| `@` `P` `X` | ICH DCH ECH | the Task 2 methods |
| `S` `T` | SU SD | `scroll_up` / `scroll_down` |
| `r` | DECSTBM | `set_scroll_region(p1 - 1, p2 - 1)` |
| `m` | SGR | the existing `apply_sgr`, applied to the alt grid's pending style |
| `s` `u` | SCP RCP | save / restore cursor |
| `h` `l` with `?` | DEC private | `25` cursor visibility, `1049` / `1047` / `47` screen switch |

And the ESC (`esc_dispatch`) set: `7` DECSC, `8` DECRC, `D` IND, `E` NEL, `M` RI.

**`0x0D` must stop being a no-op.** In the normal buffer it stays one — the append-only model has no column to return to — but in the alternate screen it is `carriage_return()`. That asymmetry is deliberate; write it as an explicit fork, not an accident.

- [ ] **Step 4: Run the routing tests**

```bash
cd packages/terminal && cargo test -p vt-core
```

Expected: PASS, and every pre-existing vt-core test still passes.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/crates/vt-core
git commit -m "feat(terminal): route bytes to the alternate grid while it is active"
```

---

## Task 5: Snapshot, WASM and the TypeScript core

**Files:**
- Create: `packages/terminal/crates/vt-core/src/alt/snapshot.rs`
- Modify: `packages/terminal/crates/vt-core/src/grid.rs`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs`
- Modify: `packages/terminal/ts/core/src/types.ts`, `terminal-core.ts`
- Test: `packages/terminal/ts/core/src/terminal-core.test.ts`

**Interfaces:**
- Produces:
  ```ts
  export type AltScreenView = Readonly<{
      rows: number;
      columns: number;
      content: Uint8Array;      // UTF-8, rows concatenated
      rowRanges: Uint32Array;   // (start, end) per row — same shape as the block path
      runRanges: Uint32Array;
      stylePairs: Uint32Array;
      cursorRow: number;
      cursorColumn: number;
      cursorVisible: boolean;
  }>;
  // on TerminalSnapshot:
  altScreen: AltScreenView | null;
  ```

**Deliberately the same wire shape as the block path.** `renderer-dom` already has a row/run builder driven by `(content, rowRanges, runRanges, stylePairs)`; matching it means Task 8 reuses that code instead of growing a second one that drifts.

- [ ] **Step 1: Write the failing test**

```ts
it("exposes the alternate grid with a cursor, and nothing when inactive", () => {
	const core = createTerminalCore({ columns: 20, rows: 5, scrollback: 100 });
	expect(core.snapshot().altScreen).toBeNull();
	core.feed(new TextEncoder().encode("\x1b[?1049h\x1b[2;3Hhi"));
	const alt = core.snapshot().altScreen;
	expect(alt).not.toBeNull();
	expect(alt!.rows).toBe(5);
	expect(alt!.columns).toBe(20);
	expect(alt!.cursorRow).toBe(1);
	expect(alt!.cursorColumn).toBe(4);
	const text = new TextDecoder().decode(
		alt!.content.subarray(alt!.rowRanges[2], alt!.rowRanges[3]),
	);
	expect(text.trimEnd()).toBe("  hi");
	core.dispose();
});

it("reports no scrollback for the alternate buffer", () => {
	const core = createTerminalCore({ columns: 10, rows: 3, scrollback: 5000 });
	core.feed(new TextEncoder().encode("\x1b[?1049h"));
	for (let i = 0; i < 50; i += 1) core.feed(new TextEncoder().encode(`line ${i}\r\n`));
	const alt = core.snapshot().altScreen!;
	// Three rows, forever. An alternate buffer that grows is not one.
	expect(alt.rowRanges.length / 2).toBe(3);
	core.dispose();
});
```

- [ ] **Step 2–4: Run (FAIL), implement, run (PASS)**

```bash
cd packages/terminal && npm run build:wasm && npm run test -w @operator/terminal-core
```

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/crates packages/terminal/ts/core
git commit -m "feat(terminal): export the alternate grid on the snapshot"
```

---

## Task 6: Rows and resize

The core has no rows dimension. Everything up to here passed rows to a constructor; this task makes it a first-class, changeable property, because a terminal that cannot resize is not one.

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/lib.rs`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs`
- Modify: `packages/terminal/ts/core/src/types.ts`, `terminal-core.ts`
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx`
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx`
- Test: `packages/terminal/crates/vt-core/tests/alt_routing.rs`, `ts/core/src/terminal-core.test.ts`, `ts/react/src/TerminalSurface.test.tsx`

**Interfaces:**
- Produces: `TerminalCoreOptions` gains `rows: number`; `core.resize(columns: number, rows: number): void`.

- [ ] **Step 1: Write the failing tests**

```rust
#[test]
fn resizing_reshapes_the_alt_grid_and_keeps_what_fits() {
    let mut c = core();
    c.feed(b"\x1b[?1049habcdefgh");
    c.resize(4, 24);
    let alt = c.alt_grid().expect("alt");
    assert_eq!(alt.cols(), 4);
    assert_eq!(alt.row_text(0), "abcd");
}

#[test]
fn resizing_outside_the_alt_screen_does_not_resurrect_it() {
    let mut c = core();
    c.resize(40, 10);
    assert!(c.alt_grid().is_none());
}
```

```tsx
it("resizes the core when the surface geometry changes", () => {
	const { core, setSize } = renderSurface({ columns: 80, rows: 24 });
	const resize = vi.spyOn(core, "resize");
	setSize({ columns: 100, rows: 30 });
	expect(resize).toHaveBeenCalledWith(100, 30);
});

it("does not resize on every paint, only when the geometry actually changes", () => {
	const { core, repaint } = renderSurface({ columns: 80, rows: 24 });
	const resize = vi.spyOn(core, "resize");
	repaint();
	repaint();
	expect(resize).not.toHaveBeenCalled();
});
```

- [ ] **Step 2–4: Run (FAIL), implement, run (PASS)**

`TerminalSurface` measures with the renderer's existing `measure()` (cell width and height are already available), derives `columns = floor(hostWidth / cellWidth)` and `rows = floor(hostHeight / cellHeight)`, and calls `core.resize` **only when the pair changes**. Debouncing is not needed and must not be added: a `ResizeObserver` already coalesces, and a timer here is the pattern §3.5 exists to prevent creeping back in a different costume.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal frontend/src
git commit -m "feat(terminal): give the core a rows dimension and a resize path"
```

---

## Task 7: The tmux conformance oracle

Spec §14 Phase 3 says `vim`, `htop` and `less` must render correctly, "verified by running them, not by unit tests alone". This task turns that from a manual promise into a recorded, automated diff against a reference implementation — tmux, which is already a dependency and is a correct terminal.

The trick: run the program under tmux, capture the **raw pane bytes** with `pipe-pane` *and* tmux's **own rendered grid** with `capture-pane`. Feed the bytes to `vt-core` and assert our grid matches tmux's, row for row.

**Files:**
- Create: `packages/terminal/tools/tmux-capture.mjs`
- Create: `packages/terminal/protocol/alt-vectors/*.json`
- Create: `packages/terminal/crates/vt-core/tests/alt_conformance.rs`

**Interfaces:**
- Produces vector files: `{ name, rows, cols, inputBase64, expectedRows: string[] }`.

- [ ] **Step 1: Write the recorder**

`tools/tmux-capture.mjs` takes a command, rows and cols, and a list of keys to send. Verified working shape (this exact approach was tested by hand — a 40x5 pane running `printf 'AAAA\r\nBBBB'` produced `capture-pane` output `AAAA` / `BBBB`):

```js
tmux("new-session", "-d", "-s", session, "-x", String(cols), "-y", String(rows), command);
tmux("pipe-pane", "-t", session, "-o", `cat >> ${rawPath}`);
for (const key of keys) { tmux("send-keys", "-t", session, key); sleep(300); }
const expectedRows = tmux("capture-pane", "-t", session, "-p").split("\n");
```

Record `vim`, `htop` and `less` cases. **Commit the recorded vectors**, not the recorder's live output — a test that shells out to `vim` at CI time is a test that fails for reasons unrelated to the terminal.

- [ ] **Step 2: Write the failing conformance test**

```rust
#[test]
fn our_alt_grid_matches_tmux_row_for_row() {
    for vector in load_alt_vectors() {
        let mut core = TerminalCore::new(vector.cols, vector.rows, 100).expect("core");
        core.feed(&vector.input);
        let alt = core.alt_grid().unwrap_or_else(|| panic!("{}: never entered the alt screen", vector.name));
        for (index, expected) in vector.expected_rows.iter().enumerate() {
            assert_eq!(
                alt.row_text(index).trim_end(),
                expected.trim_end(),
                "{} row {index}",
                vector.name,
            );
        }
    }
}
```

- [ ] **Step 3–5: Run (FAIL), implement until it passes, commit**

Expect this to fail repeatedly and informatively — that is the point. Each failing row names a sequence Tasks 1–4 got wrong. Fix the grid, not the vector. A vector may only be re-recorded if tmux's own output is shown to be the thing that changed.

```bash
cd packages/terminal && cargo test -p vt-core --test alt_conformance
git add packages/terminal/tools packages/terminal/protocol/alt-vectors packages/terminal/crates
git commit -m "feat(terminal): diff the alternate grid against tmux for vim, htop and less"
```

---

## Task 8: The raw surface in `renderer-dom`

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/alt-surface.ts`
- Create: `packages/terminal/ts/renderer-dom/src/alt-surface.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/styles.css` and `styles.ts`

**Interfaces:**
- Consumes: `AltScreenView` (Task 5).
- Produces: `renderAltSurface(view: AltScreenView, into: HTMLElement): void`.

- [ ] **Step 1: Write the failing tests**

```ts
it("renders one row element per grid row, blank rows included", () => {
	const host = mountWithAlt(3, 10, ["ab", "", "cd"]);
	const rows = host.querySelectorAll("[data-terminal-row]");
	expect(rows.length).toBe(3);
	expect(rows[1].textContent).toBe("");
});

it("draws no block chrome in the alternate screen", () => {
	const host = mountWithAlt(3, 10, ["ab"]);
	expect(host.querySelector(".terminal-block-header")).toBeNull();
	expect(host.querySelector("[data-terminal-block-id]")).toBeNull();
});

it("places the cursor at the reported cell", () => {
	const host = mountWithAlt(3, 10, ["abc"], { cursorRow: 0, cursorColumn: 2 });
	const cursor = host.querySelector("[data-terminal-cursor]") as HTMLElement;
	expect(cursor.dataset.row).toBe("0");
	expect(cursor.dataset.column).toBe("2");
});

it("hides the cursor when the program hid it", () => {
	const host = mountWithAlt(3, 10, ["abc"], { cursorVisible: false });
	expect(host.querySelector("[data-terminal-cursor]")).toBeNull();
});

it("does not virtualize: the alternate buffer is one screen and all of it is on screen", () => {
	const host = mountWithAlt(60, 10, new Array(60).fill("x"));
	expect(host.querySelectorAll("[data-terminal-row]").length).toBe(60);
});
```

- [ ] **Step 2–4: Run (FAIL), implement, run (PASS)**

`DomBlockRenderer.repaint` forks at the top: `snapshot.altScreen` non-null renders the alt surface into the container and returns; otherwise the existing block path runs. Reuse the row/run builder — the wire shape is identical by construction (Task 5).

No virtualization here, deliberately: the alternate buffer is exactly one screen, so windowing it adds machinery to save nothing.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts/renderer-dom
git commit -m "feat(terminal): paint the alternate screen in renderer-dom"
```

---

## Task 9: Operator shows it

**Files:**
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx`
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx`
- Test: `packages/terminal/ts/react/src/TerminalSurface.test.tsx`, `frontend/src/renderer/components/BlockTerminal.test.tsx`

Phase 2 already made the package the default alt-screen surface behind `VITE_ALT_SCREEN_SURFACE`. This task makes that default actually correct, and keeps the escape hatch the spec requires.

- [ ] **Step 1: Write the failing tests**

```tsx
it("keeps the editor hidden and input raw while the alternate screen is active", () => {
	const { container, core, onSend, onSendRaw } = renderSurface();
	core.feed(encode("\x1b[?1049h"));
	expect(container.querySelector(".terminal-editor")?.checkVisibility?.() ?? false).toBe(false);
	typeKey(container, "a");
	expect(onSend).not.toHaveBeenCalled();
	expect(onSendRaw).toHaveBeenCalledWith("a");
});

it("returns to the block list when the program leaves the alternate screen", () => {
	const { container, core } = renderSurface();
	core.feed(encode("\x1b[?1049h"));
	expect(container.querySelector("[data-terminal-alt-surface]")).not.toBeNull();
	core.feed(encode("\x1b[?1049l"));
	expect(container.querySelector("[data-terminal-alt-surface]")).toBeNull();
});
```

- [ ] **Step 2–4: Run (FAIL), implement, run (PASS)**

- [ ] **Step 5: Verify it by looking at it**

```bash
npm run tauri:dev
```

Open a session, run `vim`, `htop`, then `less` on a long file. Scroll. Resize the window. Then run the same three with `VITE_ALT_SCREEN_SURFACE=xterm npm run tauri:dev` and compare. **Screenshot both.** Unit tests do not tell you whether `htop` looks right.

- [ ] **Step 6: Commit**

```bash
git add packages/terminal frontend/src
git commit -m "feat(terminal): show the alternate screen in Operator's own surface"
```

---

## Task 10: Close Phase 3

- [ ] **Step 1: The shred rule, end to end**

Beyond the Task 4 unit test, add a Playwright case to the vite smoke: feed a marked block, enter the alternate screen, emit mark-shaped bytes, leave, and assert the rendered block list is unchanged.

- [ ] **Step 2: No scrollback, in a real browser**

Add to the vite smoke: in the alternate screen, `scrollTop` cannot move. Scrolling up in a full-screen TUI moves nothing, matching every other terminal.

- [ ] **Step 3: The xterm fallback still works**

Assert `VITE_ALT_SCREEN_SURFACE=xterm` still mounts `XtermTerminal` and renders. Spec §14 Phase 3 requires a regression to be one flag away from a working pane.

- [ ] **Step 4: The §9.4 gate**

```bash
cd packages/terminal && npm run bench:terminal -- --renderer dom --scenario vtebench
cd packages/terminal && npm run bench:terminal -- --renderer dom --scenario large-output
cd packages/terminal && npm run bench:terminal -- --renderer dom --scenario input-latency
cd packages/terminal && npm run bench:terminal -- --renderer dom --scenario input-latency-owned
cd packages/terminal && npm run bench:gate
```

Expected: `perf gate passed`. If `input-latency` fails, check whether the alt fork in `repaint` added work to the block path before assuming the gate is wrong — it was made honest in Phase 2 and should be trusted until shown otherwise.

- [ ] **Step 5: Full sweep**

```bash
cd packages/terminal && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
cd packages/terminal/go/marks && go test ./...
cd packages/terminal && node --test shell/zsh.test.mjs shell/bash.test.mjs shell/fish.test.mjs
cd packages/terminal && npm test && npm run check:boundaries && node ./scripts/check-no-ownership-timer.mjs && npm run smoke:vite && npm run smoke:tauri
cd frontend && npm run typecheck && npm run test
```

- [ ] **Step 6: Update the changelog and spec phase status, then commit**

---

## Self-Review

**Spec coverage.** §11's four bullets map to Tasks 1–3 (second grid, saved cursor, addressing, scroll regions, erase, line editing), Task 8 (renderer through the `BlockRenderer` seam, no chrome), and Task 9 (raw input passthrough, editor hidden). §11's shred rule is Task 4 Step 1 and Task 10 Step 1. §14 Phase 3's six acceptance criteria: vim/htop/less → Task 7 automated plus Task 9 Step 5 by hand; agent CLI end to end → Task 9 Step 5; one collapsed block and byte-identical prior blocks → Task 4, Task 10 Step 1; no scrollback → Task 5 Step 1, Task 10 Step 2; xterm behind a flag → Task 10 Step 3; §9.4 → Task 10 Step 4.

**Known risk, named.** Task 7 is where this plan will hurt. Tasks 1–4 are written from the standard, and real programs use it in ways no unit test I can write from memory will predict. Expect the tmux diff to fail on things like `vim`'s use of `DECSTBM` with `IL`, or `htop`'s cursor-visibility toggling mid-frame. That is the task doing its job. Budget accordingly, and fix the grid rather than the vector.

**Deliberately out of scope.** Mouse reporting, bracketed paste inside the alternate screen, `DECSET 2004`, sixel, and the `47`/`1047` legacy switches beyond treating them as `1049` without the cursor save. None is needed for vim, htop, less or an agent CLI, and each is cheap to add later behind the same CSI table.

**Type consistency.** `AltGrid` methods are defined in Task 1 and extended by Tasks 2 and 3 with no renames. `AltScreenView` is defined once in Task 5 and consumed unchanged by Tasks 8 and 9. `TerminalCore::new` gains rows in Task 4 and `resize` in Task 6 — Task 4's tests already call the three-argument form, so a Task 4 implementer must update existing call sites in that commit rather than leaving the tree broken for Task 6.

**Dependency to check before starting.** This plan assumes Phase 2 is merged. At the time of writing it is on branch `phase-2` and unmerged, with one open question about re-recording the perf baseline with `--repeat`. If Phase 2 is still unmerged when Task 1 starts, branch from `phase-2` rather than `master` and say so, or Tasks 5, 6 and 9 will conflict on files Phase 2 changed.
