# Normal-Buffer Screen Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `vt-core`'s normal buffer a real cursor-addressable screen, so an inline TUI that redraws with cursor-up overwrites its previous frame instead of appending a new copy of it to scrollback.

**Architecture:** Port Warp's two-tier storage. A fixed `rows × cols` **screen** holds every row the cursor can still reach; an append-only **scrollback** (`Content` + `RowIndex` + `AttributeMap`) holds rows that have scrolled off the top and can never be addressed again. A row index below `scrollback.len()` resolves to scrollback, at or above it to the screen — Warp's `storage_row()`/`StorageRow` split. `AltGrid` already implements every sequence the screen needs, so it is generalised into `ScreenGrid` and used for both buffers; the only difference between them is what happens to a row evicted off the top (the normal buffer commits it to scrollback, the alternate buffer discards it — which is what "the alternate buffer has no scrollback" means).

**Tech Stack:** Rust (`vt-core`, `vt-wasm`), `vte` parser, wasm-bindgen, TypeScript (`ts/core`, `ts/renderer-dom`), vitest, cargo test.

**Spec:** `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md` (§6.2 cell storage, §6.3 blockgrid, §11 alt screen)

## Why this plan exists

Measured on 2026-08-30, against `8440751e6`:

- Feeding `"alpha\r\nbravo\r\ncharlie\r\n"` then `ESC[2A CR "REWRITTEN" ESC[K` produces **five** rows (`alpha`, `bravo`, `charlie`, `REWRITTEN`, empty). A real terminal produces three, with `bravo` replaced. The cursor-up is discarded and the text appended.
- `parser.rs:296` `csi_dispatch` handles `m` and `?1` and then delegates to `alt` **only if the alternate grid exists**. In the normal buffer `CSI A/B/C/D/H/G/d/J/K/L/M/@/P/X/S/T/r` are all dropped.
- Claude Code redraws with CUU + CR + EL continuously (5 CUU in 7 idle seconds, measured identically at 12 and 100 columns), emits **no OSC 133 marks**, and **never enters the alternate screen** (no `?1049` in the capture at all). Every redraw frame is therefore appended to one ever-growing block.
- Replaying 30 real captured frames produced **841 rows where a real terminal shows 28** — ~30× scrollback inflation. Scrolling back shows stale duplicate frames instead of history.

The scroll container itself is healthy: an identical Chromium harness run against `695223617` (before the colour/width/UTF-8 fixes) and against `8440751e6` holds `scrollTop` at 0 and at 200 in both. There is no scrolling regression to find — the scrollback is full of redraw garbage.

## Verified against Warp's own implementation

Read on 2026-08-30 at `/Users/omaraly/development/AI/warp`. Four decisions confirmed, four corrected.

**Confirmed.**

1. **The two-tier split.** `grid_handler.rs:419` holds both `flat_storage: FlatStorage` and `GridStorage`; `storage_row()` (`:2399-2409`) resolves an index by `row_idx.checked_sub(self.flat_storage.total_rows())`. `flat_storage/mod.rs:11-17` rules out `Insert`, suiting only rows "that cannot be accessed via the cursor". Our `Content`/`RowIndex` is the `FlatStorage` tier; `ScreenGrid` is `GridStorage`.
2. **Only a scroll whose region starts at the top evicts.** `grid_storage.rs:379` guards on `region.start != VisibleRow(0)`. Task 2's `scroll_top != 0` rule is the same condition.
3. **Trailing blanks are trimmed per row**, via `rightmost_visible_nonempty_cell_in_row` (`grid_handler.rs:2653`). Task 3 trims.
4. **The alternate buffer never reaches flat storage.** `resize_storage` (`resize.rs:63`) notes "there's no flat storage for the alt screen". Task 5 pins it.

**Corrected — each of these was wrong in the first draft of this plan.**

- **C1. Grid extent is a cursor high-water mark, not a blank scan.** `content_len()` (`grid_handler.rs:2640`) falls back to `max_cursor_point.row + history_size() + 1`, and `max_cursor_point` is updated on every cursor move (`grid_storage.rs:265-268`). Scanning for the last non-blank cell is Warp's *opt-in trimming* refinement, not its notion of extent. A blank scan makes rows vanish when a program clears its lower half, and costs `rows × cols` reads per snapshot. Task 4 uses the high-water mark (cycle B).
- **C2. `ED All` on the primary screen needs a policy.** `ansi_handler.rs:852-862` branches three ways: alt screen clears the region in place; primary with `FullGridClearBehavior::Clear` calls `clear_visible_rows_in_place`; primary with `Scroll` calls `clear_viewport`, which pushes the visible rows into scrollback. Delegating to the alternate screen's `erase_in_display` would make a shell's `clear` destroy scrollback. Task 6 implements both paths.
- **C3. Resize must not reflow an agent TUI.** `resize.rs:57-66` skips reflow when the alt screen is active **or** `full_grid_clear_behavior == Clear`, with the comment: "We also do this for CLI agent TUIs so pane resizes don't append old frames into block scrollback before the app redraws (GH #9838)." That is this bug, in Warp's own tracker. Task 7 covers it.
- **C4. The three settings above are one mode, switched by an explicit signal.** `view.rs:13456-13460` flips the active block on `CLIAgentSessionsModelEvent::Started`: `enable_full_grid_clear_behavior()` plus `set_trim_trailing_blank_rows(true)`, which also sets `set_track_content_length(true)` (`blockgrid.rs:306-313`). Warp does not sniff the byte stream; it is told. We have the same signal — the daemon knows the provider, and `TerminalPane.tsx:878` already branches on it. Task 8 wires it.

## Global Constraints

- **No code comments.** The user's global instruction. Doc comments (`///`) explaining *why* a structure exists are the existing house style in `vt-core` and are kept; inline `//` narration is not.
- **`no_std`-friendly, zero WASM-specific code in `vt-core`** (spec §6.1). WASM lives in `vt-wasm`.
- **Never materialise a JS object per cell** (spec §6.2). The renderer reads typed-array slices; snapshots stay `(offset, value)` pair arrays.
- **The alternate buffer has no scrollback** (spec §11). Synthesising one is a bug.
- **`XtermTerminal.tsx` stays present and reachable behind the host flag.** Its deletion is Phase 7.
- **The §11 shred rule:** blocks recorded before entering the alternate screen must be byte-identical after leaving it.
- `MAX_DIMENSION` is 1000; all grid dimensions clamp to `1..=1000`.
- Rust toolchain is pinned: `rustc 1.96.0`, `wasm-bindgen 0.2.127`, target `wasm32-unknown-unknown`.
- After any Rust change, `npm run build:wasm` then `npm run build:ts` before running TypeScript tests. `npm test` runs `build:wasm` but **not** `build:ts`; stale `ts/core/dist` silently produces green tests against an old core.

## File Structure

| File | Responsibility after this plan |
|---|---|
| `crates/vt-core/src/screen.rs` | **Create.** `ScreenGrid` — the fixed `rows × cols` cursor-addressable grid. Moved from `alt/mod.rs`, with `EvictionPolicy` added. |
| `crates/vt-core/src/screen/{dispatch,edit,scroll,snapshot}.rs` | **Move** from `crates/vt-core/src/alt/`. Unchanged logic. |
| `crates/vt-core/src/alt.rs` | **Shrink** to a re-export shim so `alt::AltGrid`, `alt::AltSnapshot`, `alt::Cell`, `alt::MAX_DIMENSION` keep resolving. |
| `crates/vt-core/src/parser.rs` | Owns `screen: ScreenGrid` for the normal buffer plus `alt: Option<ScreenGrid>`. Routes every CSI/ESC to the active screen. Commits evicted rows to scrollback. |
| `crates/vt-core/src/row_index.rs` | Unchanged. Still the immutable scrollback index. |
| `crates/vt-core/src/content.rs` | Unchanged. Still append-only. |
| `crates/vt-core/src/block_grid.rs` | Open block's `row_count` derived from the unified row total instead of accumulated by `note_row_completed`. |
| `crates/vt-core/src/grid.rs` | `build_snapshot` emits scrollback rows followed by screen rows as one contiguous row list. |
| `crates/vt-core/tests/screen_normal.rs` | **Create.** Cursor addressing in the normal buffer. |
| `crates/vt-core/tests/redraw_conformance.rs` | **Create.** Replays a captured agent-CLI redraw and pins the row count. |
| `crates/vt-core/src/scrollback.rs` | **Create.** `commit_row` — screen cells to scrollback bytes. Unit-tested inline. |
| `crates/vt-core/tests/clear_policy.rs` | **Create.** `ED All` scrolls history away on the primary screen, clears in place on the alternate. |
| `crates/vt-core/tests/resize_policy.rs` | **Create.** A resize in agent-TUI mode appends no frame to scrollback. |

`AltGrid` keeps its name as an alias so the ~40 existing call sites and `alt_conformance.rs` / `alt_grid.rs` / `alt_routing.rs` do not churn in the same commit as a behaviour change.

---

### Task 1: Extract `ScreenGrid` from `AltGrid` with no behaviour change

A pure move. The alternate screen must behave identically afterwards, which the existing suite already pins.

**Files:**
- Create: `crates/vt-core/src/screen.rs` (moved from `crates/vt-core/src/alt/mod.rs`)
- Create: `crates/vt-core/src/screen/dispatch.rs`, `screen/edit.rs`, `screen/scroll.rs`, `screen/snapshot.rs` (moved from `alt/`)
- Create: `crates/vt-core/src/alt.rs` (re-export shim)
- Delete: `crates/vt-core/src/alt/` directory and `crates/vt-core/src/alt_screen.rs`'s stale doc reference
- Modify: `crates/vt-core/src/lib.rs` (add `mod screen;`)

**Interfaces:**
- Consumes: nothing.
- Produces: `pub struct ScreenGrid` with exactly today's `AltGrid` API — `new(rows, cols)`, `rows()`, `cols()`, `cursor()`, `cursor_visible()`, `set_cursor_visible(bool)`, `cell(row, col) -> Cell`, `move_to(usize, usize)`, `move_by(isize, isize)`, `carriage_return()`, `tab()`, `save_cursor()`, `restore_cursor()`, `print(char, StyleCode)`, `row_text(usize) -> String`, `reset()`, `resize(rows, cols)`, `csi(&Params, &[u8], char)`, `esc(u8)`, plus the `edit.rs` and `scroll.rs` methods. `pub type AltGrid = ScreenGrid;` and `pub use screen::{Cell, MAX_DIMENSION};` in `alt.rs`.

- [ ] **Step 1: Move the files**

```bash
cd packages/terminal/crates/vt-core/src
mkdir screen
git mv alt/dispatch.rs screen/dispatch.rs
git mv alt/edit.rs screen/edit.rs
git mv alt/scroll.rs screen/scroll.rs
git mv alt/snapshot.rs screen/snapshot.rs
git mv alt/mod.rs screen.rs
```

- [ ] **Step 2: Rename the type inside the moved files**

In `screen.rs`, `screen/dispatch.rs`, `screen/edit.rs`, `screen/scroll.rs`, `screen/snapshot.rs`, replace `AltGrid` with `ScreenGrid` and `crate::alt::` with `crate::screen::`. In `screen.rs` the module declarations become:

```rust
mod dispatch;
mod edit;
mod scroll;
mod snapshot;

pub use snapshot::AltSnapshot;
```

- [ ] **Step 3: Write the re-export shim**

Create `crates/vt-core/src/alt.rs`:

```rust
pub use crate::screen::{AltSnapshot, Cell, MAX_DIMENSION, ScreenGrid as AltGrid};
```

- [ ] **Step 4: Register the module**

In `crates/vt-core/src/lib.rs`, alongside the existing `mod alt;`, add:

```rust
mod screen;
```

- [ ] **Step 5: Verify the move changed nothing**

Run: `cargo test -p vt-core`
Expected: PASS, with `alt_conformance`, `alt_grid` and `alt_routing` all green and no test edited.

- [ ] **Step 6: Commit**

```bash
git add -A packages/terminal/crates/vt-core/src
git commit -m "refactor(terminal): extract ScreenGrid from AltGrid with no behaviour change"
```

---

### Task 2: Give `ScreenGrid` an eviction hook

`scroll_up` is the single point where a row leaves the top of the screen. Today it is overwritten and lost — correct for the alternate buffer, wrong for the normal one. The hook reports the evicted row so the caller can decide.

Only a scroll of the **whole** screen evicts. A scroll region (`DECSTBM` with `scroll_top > 0`) moves rows within the region and pushes nothing to scrollback, which is what every real terminal does and what `less` depends on.

**Files:**
- Modify: `crates/vt-core/src/screen.rs`
- Modify: `crates/vt-core/src/screen/scroll.rs:15-31`
- Test: `crates/vt-core/tests/screen_eviction.rs` (create)

**Interfaces:**
- Consumes: `ScreenGrid` from Task 1.
- Produces: `ScreenGrid::take_evicted(&mut self) -> Vec<Vec<Cell>>` draining rows evicted since the last call, oldest first. `ScreenGrid::set_records_eviction(&mut self, on: bool)` — off by default, so the alternate buffer keeps discarding.

- [ ] **Step 1: Write the failing test**

Create `crates/vt-core/tests/screen_eviction.rs`:

```rust
use vt_core::testing::ScreenGrid;

#[test]
fn full_screen_scroll_reports_the_evicted_row() {
    let mut screen = ScreenGrid::new(3, 10);
    screen.set_records_eviction(true);
    for ch in "top".chars() {
        screen.print(ch, Default::default());
    }
    screen.scroll_up(1);
    let evicted = screen.take_evicted();
    assert_eq!(evicted.len(), 1);
    let text: String = evicted[0].iter().map(|cell| cell.ch).collect();
    assert_eq!(text.trim_end(), "top");
}

#[test]
fn a_scroll_region_evicts_nothing() {
    let mut screen = ScreenGrid::new(5, 10);
    screen.set_records_eviction(true);
    screen.set_scroll_region(1, 3);
    screen.scroll_up(1);
    assert!(screen.take_evicted().is_empty());
}

#[test]
fn eviction_is_off_by_default() {
    let mut screen = ScreenGrid::new(3, 10);
    screen.scroll_up(1);
    assert!(screen.take_evicted().is_empty());
}

#[test]
fn take_evicted_drains() {
    let mut screen = ScreenGrid::new(2, 10);
    screen.set_records_eviction(true);
    screen.scroll_up(1);
    assert_eq!(screen.take_evicted().len(), 1);
    assert!(screen.take_evicted().is_empty());
}
```

Add to `crates/vt-core/src/lib.rs` so the test can reach the type:

```rust
pub mod testing {
    pub use crate::screen::{Cell, ScreenGrid};
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p vt-core --test screen_eviction`
Expected: FAIL — `no method named set_records_eviction`.

- [ ] **Step 3: Implement**

In `crates/vt-core/src/screen.rs`, add to the struct and `new`:

```rust
pub struct ScreenGrid {
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
    records_eviction: bool,
    evicted: Vec<Vec<Cell>>,
}
```

with `records_eviction: false` and `evicted: Vec::new()` in `new`, and:

```rust
pub fn set_records_eviction(&mut self, on: bool) {
    self.records_eviction = on;
}

pub fn take_evicted(&mut self) -> Vec<Vec<Cell>> {
    std::mem::take(&mut self.evicted)
}

fn record_eviction(&mut self, row: usize) {
    if !self.records_eviction || self.scroll_top != 0 {
        return;
    }
    let start = row * self.cols;
    self.evicted.push(self.cells[start..start + self.cols].to_vec());
}
```

In `crates/vt-core/src/screen/scroll.rs`, `scroll_up` records before overwriting:

```rust
pub fn scroll_up(&mut self, count: usize) {
    if count == 0 {
        return;
    }
    let span = self.scroll_bottom - self.scroll_top + 1;
    if count >= span {
        for r in self.scroll_top..=self.scroll_bottom {
            self.record_eviction(r);
        }
        for r in self.scroll_top..=self.scroll_bottom {
            self.blank_row(r);
        }
        return;
    }
    for r in self.scroll_top..(self.scroll_top + count) {
        self.record_eviction(r);
    }
    for r in self.scroll_top..=(self.scroll_bottom - count) {
        self.copy_row(r + count, r);
    }
    for r in (self.scroll_bottom + 1 - count)..=self.scroll_bottom {
        self.blank_row(r);
    }
}
```

`record_eviction` is `pub(crate)` on the `ScreenGrid` impl in `screen.rs`; `scroll.rs` is the same crate so it resolves.

- [ ] **Step 4: Run tests**

Run: `cargo test -p vt-core`
Expected: PASS, all four new tests plus the untouched alt suite.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/crates/vt-core
git commit -m "feat(terminal): let a screen report the rows it scrolls off the top"
```

---

### Task 3: A pure `commit_row` that turns screen cells into scrollback bytes

The one genuinely independent piece of the seam. It needs no `Parser` field and no
snapshot change, so it can be driven directly and its test is discriminating: the
function does not exist yet.

**Files:**
- Create: `crates/vt-core/src/scrollback.rs`
- Modify: `crates/vt-core/src/lib.rs` (add `mod scrollback;`)

**Interfaces:**
- Consumes: `screen::Cell` from Task 1.
- Produces: `pub(crate) fn commit_row(cells: &[Cell], content: &mut Content, rows: &mut RowIndex, styles: &mut AttributeMap<StyleCode>)`.

**Two facts verified in the code on 2026-08-30 — an earlier draft of this task got both wrong:**

- `AttributeMap` has **`set_from(offset, value)`**, not `set_range`. It is a tail-setting
  run map: writing a value at an offset makes it hold from that offset onward until the
  next `set_from`. Style must therefore be set **before** the character bytes are pushed.
- `open_new_row` (`parser.rs:97-103`) does **not** push a newline byte. It calls
  `complete_row(content.end_offset())` and nothing else, so a row's byte range excludes
  any terminator and `row_text` slices it directly. `commit_row` must not push `"\n"`
  either, or every committed row gains a stray byte and every `row_text` assertion in the
  suite breaks.

- [ ] **Step 1: Write the failing test**

Create `crates/vt-core/src/scrollback.rs` with the tests but no implementation:

```rust
#[cfg(test)]
mod tests {
    use super::commit_row;
    use crate::attribute_map::AttributeMap;
    use crate::content::Content;
    use crate::row_index::RowIndex;
    use crate::screen::Cell;
    use crate::style::StyleCode;

    fn row(text: &str, width: usize) -> Vec<Cell> {
        let mut cells = vec![Cell::BLANK; width];
        for (index, ch) in text.chars().enumerate() {
            cells[index] = Cell { ch, style: StyleCode::DEFAULT };
        }
        cells
    }

    fn commit(cells: &[Cell]) -> (Content, RowIndex, AttributeMap<StyleCode>) {
        let mut content = Content::new();
        let mut rows = RowIndex::new(0);
        let mut styles = AttributeMap::new(StyleCode::DEFAULT);
        commit_row(cells, &mut content, &mut rows, &mut styles);
        (content, rows, styles)
    }

    #[test]
    fn trailing_blanks_are_dropped() {
        let (content, rows, _) = commit(&row("hi", 40));
        let range = rows.completed().front().expect("one committed row");
        assert_eq!(content.copy_range(range.start, range.end), b"hi");
    }

    #[test]
    fn no_terminator_byte_is_written() {
        let (content, _, _) = commit(&row("hi", 40));
        assert_eq!(content.end_offset(), 2);
    }

    #[test]
    fn an_all_blank_row_commits_as_an_empty_range() {
        let (_, rows, _) = commit(&row("", 40));
        assert_eq!(rows.completed().len(), 0);
        assert_eq!(rows.open_start(), 0);
    }

    #[test]
    fn interior_blanks_survive() {
        let (content, rows, _) = commit(&row("a b", 40));
        let range = rows.completed().front().expect("one committed row");
        assert_eq!(content.copy_range(range.start, range.end), b"a b");
    }

    #[test]
    fn style_runs_follow_the_cells() {
        let mut cells = row("ab", 40);
        cells[0].style = StyleCode::ansi(1);
        let (content, _, styles) = commit(&cells);
        let runs = styles.runs(0, content.end_offset());
        assert_eq!(runs.first().map(|(_, style)| *style), Some(StyleCode::ansi(1)));
    }

    #[test]
    fn a_multibyte_glyph_commits_whole() {
        let (content, rows, _) = commit(&row("\u{2500}", 40));
        let range = rows.completed().front().expect("one committed row");
        assert_eq!(content.copy_range(range.start, range.end), "\u{2500}".as_bytes());
    }
}
```

`an_all_blank_row_commits_as_an_empty_range` pins the behaviour that `RowIndex::complete_row`
already has — it ignores a zero-length row (`row_index.rs:25-33`) — so a blank screen row
does not manufacture scrollback entries.

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p vt-core scrollback`
Expected: FAIL to compile — `cannot find function commit_row in this scope`. Paste the error.

- [ ] **Step 3: Implement**

At the top of `crates/vt-core/src/scrollback.rs`:

```rust
use crate::attribute_map::AttributeMap;
use crate::content::Content;
use crate::row_index::RowIndex;
use crate::screen::Cell;
use crate::style::StyleCode;

pub(crate) fn commit_row(
    cells: &[Cell],
    content: &mut Content,
    rows: &mut RowIndex,
    styles: &mut AttributeMap<StyleCode>,
) {
    let width = cells
        .iter()
        .rposition(|cell| cell.ch != ' ')
        .map_or(0, |index| index + 1);
    for cell in &cells[..width] {
        styles.set_from(content.end_offset(), cell.style);
        let mut buffer = [0u8; 4];
        content.push_char(cell.ch.encode_utf8(&mut buffer));
    }
    rows.complete_row(content.end_offset());
}
```

Add `mod scrollback;` to `crates/vt-core/src/lib.rs`.

- [ ] **Step 4: Run tests**

Run: `cargo test -p vt-core`
Expected: PASS. Nothing outside `scrollback.rs` changed, so the rest of the suite is untouched.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/crates/vt-core
git commit -m "feat(terminal): turn a screen row into scrollback bytes"
```

---

### Task 4: Make the normal buffer a screen — the atomic seam

**This task is deliberately large, and it may not be split.** The write target, the commit
path and the snapshot row space are one seam: routing `print` to a screen without also
teaching `build_snapshot` to emit screen rows makes every row currently on screen
**invisible**, and committing evicted rows is unobservable until both of those land. An
earlier draft of this plan split them into three tasks; Task 3 was found unimplementable
in isolation, because `build_snapshot` (`grid.rs:84-88`) emits only `rows.completed()`
plus the open row.

Work through the three cycles below in order, each with its own RED evidence, then make
**one** commit.

**Files:**
- Modify: `crates/vt-core/src/parser.rs` — struct, `new`, `resize`, `Perform`
- Modify: `crates/vt-core/src/screen.rs` — `max_cursor_row`, `content_rows`
- Modify: `crates/vt-core/src/grid.rs:64-96` — `build_snapshot`
- Modify: `crates/vt-core/src/lib.rs` — `feed` calls `commit_evicted`, `snapshot` passes the screen
- Modify: `crates/vt-core/src/block_grid.rs:68-79`
- Modify: `crates/vt-core/tests/terminal_core.rs`, `block_contract.rs`, `blocks_from_marks.rs` — expectations only
- Test: `crates/vt-core/tests/screen_normal.rs` (create)

**Interfaces:**
- Consumes: `commit_row` (Task 3), `take_evicted`/`set_records_eviction` (Task 2).
- Produces: `Parser::screen(&self) -> &ScreenGrid`, `Parser::active_screen_mut(&mut self) -> &mut ScreenGrid`, `ScreenGrid::content_rows(&self) -> usize`, and `build_snapshot(..., screen: &ScreenGrid, alt: Option<&AltGrid>)`.

#### Cycle A — cursor addressing reaches the normal buffer

- [ ] **Step 1: Write the failing test**

Create `crates/vt-core/tests/screen_normal.rs`:

```rust
use vt_core::TerminalCore;

fn rows(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    (0..snapshot.row_count())
        .map(|i| snapshot.row_text(i).trim_end().to_string())
        .collect()
}

#[test]
fn cursor_up_rewrites_in_place_instead_of_appending() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"alpha\r\nbravo\r\ncharlie\r\n");
    core.feed(b"\x1b[2A\rREWRITTEN\x1b[K");
    let text = rows(&core);
    assert_eq!(text[0], "alpha");
    assert_eq!(text[1], "REWRITTEN");
    assert_eq!(text[2], "charlie");
}

#[test]
fn erase_in_line_clears_to_the_end() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"abcdefgh\r\x1b[3C\x1b[K");
    assert_eq!(rows(&core)[0], "abc");
}

#[test]
fn absolute_cursor_addressing_lands_on_the_right_row() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"one\r\ntwo\r\nthree");
    core.feed(b"\x1b[1;1HX");
    assert_eq!(rows(&core)[0], "Xne");
}

#[test]
fn a_repeated_redraw_does_not_grow_the_row_count() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"\x1b[2J\x1b[H");
    for _ in 0..50 {
        core.feed(b"\x1b[Hframe line one\x1b[K\r\nframe line two\x1b[K");
    }
    let count = rows(&core).len();
    assert!(count <= 24, "50 redraws produced {count} rows");
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p vt-core --test screen_normal`
Expected: FAIL. `cursor_up_rewrites_in_place_instead_of_appending` reports `text[1] == "bravo"`;
`a_repeated_redraw_does_not_grow_the_row_count` reports about 100 rows. Paste both.

- [ ] **Step 3: Implement the routing**

In `crates/vt-core/src/parser.rs`, add `screen: ScreenGrid` to the struct, built in `new` as:

```rust
let mut screen = ScreenGrid::new(24, width);
screen.set_records_eviction(true);
```

and:

```rust
pub fn screen(&self) -> &ScreenGrid {
    &self.screen
}

fn active_screen_mut(&mut self) -> &mut ScreenGrid {
    match self.alt.as_mut() {
        Some(alt) => alt,
        None => &mut self.screen,
    }
}
```

`resize` sizes both:

```rust
pub fn resize(&mut self, columns: usize, rows: usize) {
    self.width = columns;
    self.screen.resize(rows, columns);
    if let Some(alt) = self.alt.as_mut() {
        alt.resize(rows, columns);
    }
}
```

`Perform` collapses its two branches into one:

```rust
fn print(&mut self, c: char) {
    let style = self.pending_style;
    self.active_screen_mut().print(c, style);
}

fn execute(&mut self, byte: u8) {
    let screen = self.active_screen_mut();
    match byte {
        0x08 => screen.move_by(0, -1),
        0x09 => screen.tab(),
        0x0A..=0x0C => screen.line_feed(),
        0x0D => screen.carriage_return(),
        _ => {}
    }
}

fn csi_dispatch(&mut self, params: &Params, intermediates: &[u8], _ignore: bool, c: char) {
    if c == 'm' {
        self.apply_sgr(params);
        return;
    }
    if intermediates.first() == Some(&b'?')
        && params.iter().next().and_then(|g| g.first().copied()) == Some(1)
    {
        match c {
            'h' => self.app_cursor = true,
            'l' => self.app_cursor = false,
            _ => {}
        }
    }
    self.active_screen_mut().csi(params, intermediates, c);
}

fn esc_dispatch(&mut self, _intermediates: &[u8], _ignore: bool, byte: u8) {
    self.active_screen_mut().esc(byte);
}
```

`write_char`, `open_new_row` and `expand_tab` lose their callers here. Leave them in place
for this cycle; delete them in Cycle C once nothing references them, and let the compiler
tell you rather than guessing.

#### Cycle B — the snapshot spans scrollback and screen

- [ ] **Step 4: Confirm Cycle A's tests still fail, for a new reason**

Run: `cargo test -p vt-core --test screen_normal`
Expected: still FAIL, now because the snapshot shows no screen content at all. This is the
entanglement this task exists to resolve — do not stop here.

- [ ] **Step 5: Implement the row space**

In `crates/vt-core/src/screen.rs`, track the cursor high-water mark (correction **C1**;
do **not** scan for the last non-blank cell). Add `max_cursor_row: usize`, initialised to
`0`, updated wherever `self.row` is assigned — read `move_to` and `print`'s wrap handling
and cover both:

```rust
pub fn content_rows(&self) -> usize {
    self.max_cursor_row + 1
}
```

`scroll_up` lowers it by the scroll distance (`self.max_cursor_row.saturating_sub(count)`);
`reset()` sets it to `0`; `resize` clamps it to `rows - 1`.

In `crates/vt-core/src/parser.rs`:

```rust
fn commit_evicted(&mut self) {
    if self.alt.is_some() {
        return;
    }
    for row in self.screen.take_evicted() {
        crate::scrollback::commit_row(&row, &mut self.content, &mut self.rows, &mut self.styles);
        self.grid.note_row_completed();
    }
}
```

Call it from `TerminalCore::feed` (`lib.rs:70`) after the parser has consumed the chunk and
before `trim_to`.

In `crates/vt-core/src/grid.rs`, `build_snapshot` gains a `screen: &ScreenGrid` parameter
and replaces the lone `append_row(open_start, end)` call:

```rust
for row in rows.completed() {
    append_row(&mut ctx, content, styles, row.start, row.end)?;
}

for row in 0..screen.content_rows() {
    append_screen_row(&mut ctx, screen, row)?;
}
```

`append_screen_row` pushes the row's text into `all_content` after trimming trailing
blanks, records the `(start, end)` range, and emits one `(end_offset, StyleCode)` pair per
style run, coalescing equal neighbours — the same shape `append_row` produces, so the
renderer's one-span-per-run contract (spec §6.2) is unchanged. `open_start`/`end` and the
`RowIndex` open row are no longer part of the snapshot; the screen holds that row now.

#### Cycle C — block row counts, and the expectations this invalidates

- [ ] **Step 6: Write the failing test**

Append to `crates/vt-core/tests/screen_normal.rs`:

```rust
#[test]
fn the_open_block_counts_scrollback_and_screen_rows_together() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 3);
    core.feed(b"\x1b]133;A\x07\x1b]133;C\x07");
    core.feed(b"one\r\ntwo\r\nthree\r\nfour\r\n");
    let snapshot = core.snapshot().unwrap();
    let total: usize = snapshot.blocks.iter().map(|b| b.row_count as usize).sum();
    assert_eq!(total, snapshot.row_count());
}

#[test]
fn clearing_the_lower_half_does_not_shrink_the_row_count() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 24);
    for _ in 0..10 {
        core.feed(b"x\r\n");
    }
    let before = core.snapshot().unwrap().row_count();
    core.feed(b"\x1b[6;1H\x1b[J");
    assert_eq!(
        core.snapshot().unwrap().row_count(),
        before,
        "the cursor high-water mark, not a blank scan, decides extent",
    );
}

#[test]
fn a_redraw_does_not_inflate_the_open_block() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"\x1b]133;A\x07\x1b]133;C\x07");
    for _ in 0..50 {
        core.feed(b"\x1b[Hline\x1b[K");
    }
    let snapshot = core.snapshot().unwrap();
    assert!(snapshot.blocks[0].row_count <= 24, "got {}", snapshot.blocks[0].row_count);
}

#[test]
fn rows_scrolled_off_a_three_row_screen_reach_scrollback() {
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.resize(20, 3);
    core.feed(b"one\r\ntwo\r\nthree\r\nfour\r\n");
    let text = rows(&core);
    assert!(text.contains(&"one".to_string()), "got {text:?}");
    assert!(text.contains(&"four".to_string()), "got {text:?}");
}
```

- [ ] **Step 7: Implement**

In `crates/vt-core/src/block_grid.rs`, `note_row_completed` stops advancing the open
block's `row_count`. `build_snapshot` computes the last block's count as
`row_ranges.len() - block.first_row`; blocks closed by `close_block` keep the count frozen
at close time.

Delete `write_char`, `open_new_row` and `expand_tab` from `parser.rs` if the compiler
reports them unused. If anything still calls them, say so in your report rather than
leaving dead code.

- [ ] **Step 8: Repair the expectations this invalidates**

`terminal_core.rs`, `block_contract.rs` and `blocks_from_marks.rs` contain assertions of
the form "N lines fed produce N rows", true only while N is under the screen height. Give
each such test an explicit `core.resize(cols, rows)` tall enough for its fixture.

**Do not change what any test asserts about content, and do not relax an assertion to make
it pass.** If a test cannot be repaired that way, it has found a real defect — stop and
report it instead of editing it.

- [ ] **Step 9: Run the full suite**

Run: `cargo test -p vt-core`
Expected: PASS. Paste the count.

- [ ] **Step 10: Commit**

```bash
git add packages/terminal
git commit -m "feat(terminal): give the normal buffer a cursor-addressable screen"
```

### Task 5: Preserve the alternate-screen contract

Entering the alternate buffer must still freeze the block list and leave recorded blocks byte-identical (spec §11 shred rule), and the alternate buffer must still have no scrollback. Task 4 made both screens share one code path, so this is the task that proves the sharing did not leak.

**Files:**
- Modify: `crates/vt-core/src/parser.rs` (`enter_alt`, `leave_alt`)
- Test: `crates/vt-core/tests/alt_routing.rs` (add)

**Interfaces:**
- Consumes: `active_screen_mut` from Task 4.
- Produces: no new API.

- [ ] **Step 1: Write the failing test**

Append to `crates/vt-core/tests/alt_routing.rs`:

```rust
#[test]
fn the_alternate_buffer_never_commits_to_scrollback() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 3);
    core.feed(b"before\r\n");
    let before = core.snapshot().unwrap().row_count();
    core.feed(b"\x1b[?1049h");
    for _ in 0..20 {
        core.feed(b"tui\r\n");
    }
    core.feed(b"\x1b[?1049l");
    assert_eq!(core.snapshot().unwrap().row_count(), before);
}

#[test]
fn rows_written_before_the_alternate_screen_survive_it_byte_for_byte() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 5);
    core.feed(b"keep me\r\n");
    let before: Vec<String> = {
        let s = core.snapshot().unwrap();
        (0..s.row_count()).map(|i| s.row_text(i).to_string()).collect()
    };
    core.feed(b"\x1b[?1049hgarbage\x1b[2J\x1b[?1049l");
    let after: Vec<String> = {
        let s = core.snapshot().unwrap();
        (0..s.row_count()).map(|i| s.row_text(i).to_string()).collect()
    };
    assert_eq!(before, after);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p vt-core --test alt_routing`
Expected: FAIL if `enter_alt` left `records_eviction` on for the alternate grid, or if the normal screen's contents were disturbed by the alternate buffer's writes.

- [ ] **Step 3: Implement**

`enter_alt` builds the alternate grid at the current screen's dimensions and leaves `records_eviction` false; the normal `screen` is untouched while `alt` is `Some`, so leaving simply drops the alternate grid:

```rust
pub fn enter_alt(&mut self, rows: usize) {
    if self.alt.is_some() {
        return;
    }
    let mut alt = ScreenGrid::new(rows, self.width);
    alt.set_records_eviction(false);
    self.alt = Some(alt);
    self.saved_style = self.pending_style;
    self.pending_style = StyleCode::DEFAULT;
}
```

- [ ] **Step 4: Run the full suite**

Run: `cargo test -p vt-core`
Expected: PASS, including the existing `alt_conformance` vectors for `vim`, `less` and `htop`.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/crates/vt-core
git commit -m "test(terminal): pin the alt-screen contract across the shared screen"
```

---

### Task 6: Give `ED All` on the primary screen the two behaviours Warp has

Correction **C2**. `CSI 2 J` means different things in the two buffers, and two different things in the primary buffer depending on mode. Warp branches three ways at `ansi_handler.rs:852-862`. Getting this wrong makes a shell's `clear` destroy scrollback, which is a worse bug than the one this plan fixes.

**Files:**
- Modify: `crates/vt-core/src/screen.rs` (add `ClearPolicy`), `crates/vt-core/src/screen/edit.rs:4-32` (`erase_in_display`)
- Modify: `crates/vt-core/src/parser.rs`
- Test: `crates/vt-core/tests/clear_policy.rs` (create)

**Interfaces:**
- Consumes: `commit_evicted` and `content_rows` (Task 4).
- Produces: `ScreenGrid::set_clear_policy(&mut self, policy: ClearPolicy)` where `pub enum ClearPolicy { Scroll, ClearInPlace }`, defaulting to `Scroll` for the normal buffer and `ClearInPlace` for the alternate buffer.

- [ ] **Step 1: Write the failing test**

Create `crates/vt-core/tests/clear_policy.rs`:

```rust
use vt_core::TerminalCore;

#[test]
fn clear_on_the_primary_screen_pushes_the_viewport_into_scrollback() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 5);
    core.feed(b"keep me\r\n");
    core.feed(b"\x1b[2J\x1b[H");
    let snapshot = core.snapshot().unwrap();
    let found = (0..snapshot.row_count()).any(|i| snapshot.row_text(i).trim_end() == "keep me");
    assert!(found, "clear must scroll history away, not destroy it");
}

#[test]
fn clear_on_the_alternate_screen_destroys_nothing_and_saves_nothing() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 5);
    core.feed(b"before\r\n");
    let before = core.snapshot().unwrap().row_count();
    core.feed(b"\x1b[?1049htui text\x1b[2J\x1b[?1049l");
    assert_eq!(core.snapshot().unwrap().row_count(), before);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p vt-core --test clear_policy`
Expected: FAIL on the first test — `keep me` is gone, because `erase_in_display` blanks cells in place and the row never reaches scrollback.

- [ ] **Step 3: Implement**

In `crates/vt-core/src/screen.rs`:

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ClearPolicy {
    Scroll,
    ClearInPlace,
}
```

Add `clear_policy: ClearPolicy` to the struct, defaulting to `ClearPolicy::Scroll`. In `screen/edit.rs`, the `mode == 2` arm of `erase_in_display` becomes:

```rust
2 => match self.clear_policy {
    ClearPolicy::Scroll => self.scroll_up(self.content_rows()),
    ClearPolicy::ClearInPlace => {
        for row in 0..self.rows() {
            self.blank_row(row);
        }
        self.max_cursor_row = 0;
    }
},
```

`scroll_up` already records evictions when `scroll_top == 0`, so the `Scroll` path reaches scrollback through the Task 3 machinery with no new code.

In `parser.rs`, `enter_alt` sets `alt.set_clear_policy(ClearPolicy::ClearInPlace)` alongside `set_records_eviction(false)`.

- [ ] **Step 4: Run the full suite**

Run: `cargo test -p vt-core`
Expected: PASS, `alt_conformance` included.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/crates/vt-core
git commit -m "feat(terminal): make clear scroll history away on the primary screen"
```

---

### Task 7: Do not reflow or evict on a resize in agent-TUI mode

Correction **C3**. Warp's `resize.rs:57-66` skips reflow for the alternate screen *and* for agent TUIs, because a pane resize otherwise appends the pre-resize frame into scrollback before the program has redrawn — Warp GH #9838, which is this plan's bug arriving by a second route.

**Files:**
- Modify: `crates/vt-core/src/screen.rs` (`resize`)
- Modify: `crates/vt-core/src/parser.rs` (`resize`)
- Test: `crates/vt-core/tests/resize_policy.rs` (create)

**Interfaces:**
- Consumes: `ClearPolicy` (Task 6), `set_records_eviction` (Task 2).
- Produces: `ScreenGrid::set_reflow_on_resize(&mut self, on: bool)`, default `true`.

- [ ] **Step 1: Write the failing test**

Create `crates/vt-core/tests/resize_policy.rs`:

```rust
use vt_core::TerminalCore;

#[test]
fn resizing_an_agent_tui_appends_no_frame_to_scrollback() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.set_agent_tui_mode(true);
    core.feed(b"\x1b[Hframe one\x1b[K");
    let before = core.snapshot().unwrap().row_count();
    core.resize(100, 30);
    core.resize(80, 24);
    assert_eq!(
        core.snapshot().unwrap().row_count(),
        before,
        "a resize must not push the pre-resize frame into scrollback",
    );
}

#[test]
fn resizing_a_shell_still_keeps_its_scrollback() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 3);
    core.feed(b"one\r\ntwo\r\nthree\r\nfour\r\n");
    let before = core.snapshot().unwrap().row_count();
    core.resize(80, 5);
    assert!(core.snapshot().unwrap().row_count() >= before);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p vt-core --test resize_policy`
Expected: FAIL — `no method named set_agent_tui_mode`.

- [ ] **Step 3: Implement**

`ScreenGrid::resize` gains an early branch: when `reflow_on_resize` is false, adjust the cell buffer to the new dimensions without evicting anything, and clamp `max_cursor_row` and the cursor into the new bounds. When it is true, keep today's behaviour.

`TerminalCore::set_agent_tui_mode(on: bool)` in `lib.rs` sets, on the normal screen: `set_reflow_on_resize(!on)` and `set_clear_policy(if on { ClearInPlace } else { Scroll })`.

- [ ] **Step 4: Run the full suite**

Run: `cargo test -p vt-core`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/crates/vt-core
git commit -m "feat(terminal): stop a resize appending the pre-resize frame to scrollback"
```

---

### Task 8: Switch agent-TUI mode from the provider the daemon already knows

Correction **C4**. Warp does not sniff the byte stream to decide a pane is an agent TUI — `view.rs:13456` flips the active block on `CLIAgentSessionsModelEvent::Started`. We have the same signal already: `TerminalPane.tsx:878` branches on `provider` today for wheel routing.

Trailing-blank trimming rides along here, because Warp enables it in the same handler and behind a flag (`FeatureFlag::TrimTrailingBlankLines`); ours is the `agentTui` boolean.

**Files:**
- Modify: `crates/vt-core/src/lib.rs`, `crates/vt-wasm/src/lib.rs`
- Modify: `ts/core/src/terminal-core.ts`, `ts/core/src/types.ts`
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx`, `frontend/src/renderer/components/TerminalPane.tsx`
- Test: `frontend/src/renderer/components/BlockTerminal.test.tsx`

**Interfaces:**
- Consumes: `set_agent_tui_mode` (Task 7).
- Produces: `TerminalCore.setAgentTuiMode(on: boolean)` in TypeScript; a `agentTui?: boolean` prop on `BlockTerminal`.

- [ ] **Step 1: Write the failing test**

Add to `frontend/src/renderer/components/BlockTerminal.test.tsx`:

```tsx
it("puts the core in agent-tui mode when the pane runs an agent", () => {
	const setAgentTuiMode = vi.fn();
	renderTerminal({ agentTui: true, coreOverrides: { setAgentTuiMode } });
	expect(setAgentTuiMode).toHaveBeenCalledWith(true);
});

it("leaves a plain shell pane out of agent-tui mode", () => {
	const setAgentTuiMode = vi.fn();
	renderTerminal({ agentTui: false, coreOverrides: { setAgentTuiMode } });
	expect(setAgentTuiMode).toHaveBeenCalledWith(false);
});
```

Match `renderTerminal`'s real signature in that file; add a `coreOverrides` option to the helper if it has none.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npx vitest run src/renderer/components/BlockTerminal.test.tsx`
Expected: FAIL — `setAgentTuiMode` is never called.

- [ ] **Step 3: Implement**

Export `set_agent_tui_mode` through `vt-wasm` as `setAgentTuiMode`, surface it on `TerminalCore`, and have `BlockTerminal` call it in the effect that creates the core and whenever `agentTui` changes. `TerminalPane` passes `agentTui={terminalTarget?.kind === "session"}` — a session pane runs an agent, a shell pane does not.

- [ ] **Step 4: Run the suites**

```bash
cd packages/terminal && npm run build:wasm && npm run build:ts && npm test
cd ../frontend && npm test
```

Expected: PASS. Report the counts you actually read.

- [ ] **Step 5: Commit**

```bash
git add -A packages/terminal frontend
git commit -m "feat(terminal): put agent panes in the tui redraw mode Warp uses"
```

---

### Task 9: Pin the real agent-CLI redraw as a conformance vector

The bug arrived from a real program. The regression test replays that program's real bytes, in the same shape the existing `protocol/alt-vectors/` fixtures use.

**Files:**
- Create: `packages/terminal/protocol/redraw-vectors/agent-cli-idle.json`
- Create: `crates/vt-core/tests/redraw_conformance.rs`

**Interfaces:**
- Consumes: the unified row space from Task 4.
- Produces: no new API.

- [ ] **Step 1: Record the vector**

```bash
tmux kill-session -t rec 2>/dev/null
tmux new-session -d -s rec -x 100 -y 30 'claude'
tmux set-option -t rec status off
tmux pipe-pane -t rec -O 'cat >> /tmp/agent.raw'
sleep 10
tmux kill-session -t rec
```

Store the capture as `{"columns": 100, "rows": 30, "bytes": [ ... ]}` with the raw bytes as a decimal array, matching the existing alt-vector shape.

- [ ] **Step 2: Write the failing test**

Create `crates/vt-core/tests/redraw_conformance.rs`:

```rust
use vt_core::TerminalCore;

#[test]
fn thirty_replays_of_an_agent_redraw_stay_within_the_screen() {
    let raw = include_str!("../../../protocol/redraw-vectors/agent-cli-idle.json");
    let vector: serde_json::Value = serde_json::from_str(raw).unwrap();
    let bytes: Vec<u8> = vector["bytes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|value| value.as_u64().unwrap() as u8)
        .collect();

    let mut core = TerminalCore::new(100, 5000).unwrap();
    core.resize(100, 30);
    for _ in 0..30 {
        core.feed(&bytes);
    }

    let rows = core.snapshot().unwrap().row_count();
    assert!(
        rows < 300,
        "30 replays produced {rows} rows; before the screen grid this was 841",
    );
}
```

- [ ] **Step 3: Run test to verify it fails against the old core**

Run: `git stash && cargo test -p vt-core --test redraw_conformance; git stash pop`
Expected: FAIL with ~841 rows, matching the number measured on 2026-08-30.

- [ ] **Step 4: Run against the new core**

Run: `cargo test -p vt-core --test redraw_conformance`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/protocol/redraw-vectors packages/terminal/crates/vt-core/tests/redraw_conformance.rs
git commit -m "test(terminal): pin a real agent redraw against scrollback inflation"
```

---

### Task 10: Rebuild the WASM boundary and verify in a browser

`vt-wasm` exports the snapshot; the row space changed shape but not type, so this is a rebuild plus an end-to-end check that the renderer still paints and scrolls.

**Files:**
- Modify: `crates/vt-wasm/src/lib.rs` if `build_snapshot`'s new parameter reaches it
- Test: `ts/renderer-dom/src/dom-block-renderer.test.ts` (add)

**Interfaces:**
- Consumes: everything above.
- Produces: no new TypeScript API.

- [ ] **Step 1: Rebuild**

```bash
cd packages/terminal
npm run build:wasm
npm run build:ts
```

Both are required. `npm test` runs only the first, and a stale `ts/core/dist` makes TypeScript tests pass against the old core.

- [ ] **Step 2: Write the failing test**

Add to `ts/renderer-dom/src/dom-block-renderer.test.ts`:

```ts
it("keeps a redrawing program inside one screen of rows", () => {
	const { core } = mountRenderer({ columns: 80, rows: 24 });
	const encoder = new TextEncoder();
	for (let frame = 0; frame < 40; frame += 1) {
		core.feed(encoder.encode("\x1b[Hstatus line\x1b[K"));
	}
	expect(core.snapshot().rows.length / 2).toBeLessThanOrEqual(24);
});
```

Match `mountRenderer`'s real helper name and signature in that file rather than the placeholder above.

- [ ] **Step 3: Run the suites**

```bash
cd packages/terminal && npm test
cd ../../frontend && npm test
```

Expected: PASS. Report the actual counts; do not claim a number you did not read.

- [ ] **Step 4: Verify in the real app**

```bash
npm run tauri:dev
```

Check, by running them: an agent CLI redraws in place and scrolling back reaches real history rather than duplicate frames; `vim`, `htop` and `less` still render, resize, and scroll; entering and leaving a full-screen TUI leaves one collapsed block with the prior blocks unchanged.

- [ ] **Step 5: Commit**

```bash
git add -A packages/terminal frontend
git commit -m "feat(terminal): rebuild the wasm boundary on the unified row space"
```

---

### Task 11: Record the design in the spec

The spec's §6.2 describes Warp's `flat_storage` without noting that Warp itself does not use it for cursor-addressable rows. That omission is what let Phase 3 ship an append-only normal buffer.

**Files:**
- Modify: `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md` §6.2, §11, and the Phase 3 entry in §14

- [ ] **Step 1: Amend §6.2**

Record that `FlatStorage` is Warp's **scrollback** tier and its own doc comment rules out `Insert`, being suited to "grids that are immutable, or the portion of a grid that cannot be accessed via the cursor"; that the cursor-addressable rows live in `GridStorage`, a mutable circular buffer of `Row`s; and that `grid_handler.rs`'s `storage_row()` resolves a row index across the two by comparing against `flat_storage.total_rows()`. Cite `flat_storage/mod.rs:11-17` and `grid_handler.rs:2399-2409`.

- [ ] **Step 2: Amend §11**

State that cursor addressing, scroll regions, erase and line editing apply to **both** buffers, since both are `ScreenGrid`, and that the only difference is eviction policy. Note that Warp models the same distinction as `FullGridClearBehavior::{Clear, Scroll}` (`grid_handler.rs:405`).

- [ ] **Step 3: Correct the Phase 3 record in §14**

Note that the accept criterion "an agent CLI (Claude Code) runs end to end in the package's own surface" was signed off on the assumption that Claude Code drives the alternate screen, that a capture on 2026-08-30 showed it emits no `?1049` and no OSC 133 and redraws inline with CUU, and that this plan closes the gap.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md
git commit -m "spec: record the two-tier storage the normal buffer needs"
```

---

## Self-Review

**Warp fidelity.** Every design decision now cites a file and line in `/Users/omaraly/development/AI/warp`, listed in "Verified against Warp's own implementation" above: four confirmed, four corrected after the first draft. The corrections are load-bearing — C2 alone was a scrollback-destroying bug, and C3 is a Warp issue number.

**Spec coverage.** §6.2 storage shape — Tasks 3 and 5 keep `Content`/`AttributeMap`/`RowIndex` as the scrollback tier and preserve the run-per-span export. §6.3 blockgrid — Task 5. §11 alt screen — Task 6. The §11 shred rule and "no scrollback in the alternate buffer" both get named tests. Phase 3's accept criteria are re-verified in Task 8 Step 4. §6.1's "no WASM-specific code in `vt-core`" holds: nothing added here is WASM-aware.

**Placeholders.** Two steps deliberately point at the real code instead of quoting it — Task 3 Step 3's `AttributeMap` setter and Task 8 Step 2's `mountRenderer` helper — because inventing a signature that does not match would be worse than telling the implementer to read the neighbouring call. Both name the exact call site to copy. Task 7 Step 1 records a fresh capture rather than embedding several KB of bytes.

**Type consistency.** `ScreenGrid` is the type throughout; `AltGrid` is an alias declared in Task 1 and used unchanged by existing tests. `take_evicted`/`set_records_eviction`/`record_eviction` (Task 2) are consumed under those names in Tasks 3 and 6. `occupied_rows` (Task 5) is defined before its use in `build_snapshot`. `commit_evicted` (Task 3) is called from `feed` in Task 4.

**Ordering risk, and the reason Task 4 is large.** An earlier draft split the seam into three tasks. A subagent found Task 3 unimplementable in isolation and stopped rather than fake it: its integration tests passed 3/3 against the old append-only core, and its `commit_evicted` referenced a `Parser::screen` field that a later task introduced. Verifying that showed the entanglement runs deeper still — `build_snapshot` emits only `rows.completed()` plus the open row, so routing `print` to a screen without changing the snapshot makes on-screen content invisible. Write target, commit path and row space are one seam and now land as one task, with three internal RED/GREEN cycles. Task 3 was re-cut as the one piece that genuinely is independent: a pure `commit_row` with no `Parser` dependency.

**Type consistency, second pass.** `content_rows()` replaced the first draft's `occupied_rows()` everywhere (Task 4 defines it, Task 6's `ED All` arm calls it). `ClearPolicy` is defined in Task 6 and consumed in Task 7's `set_agent_tui_mode`. `set_agent_tui_mode` is defined in Task 7 and reaches TypeScript as `setAgentTuiMode` in Task 8. `max_cursor_row` is introduced in Task 4 and mutated in Task 6's `ClearInPlace` arm.

**Regression accepted during execution, and it must be recorded in Task 11.** `ScreenGrid::Cell`
holds a single `char`, so the normal buffer no longer keeps the zero-width scalars the
append-only path carried (it allowed up to `MAX_ZERO_WIDTH_PER_CELL = 8`). Measured at
`4ce87cfc6`: `e`+U+0301 renders `e`, `\u{26a0}`+U+FE0F renders the text-presentation
glyph, and a ZWJ family sequence renders as three separate people. Skin-tone modifiers
survive. The alternate screen already behaved this way, so TUIs are unaffected; this is
new for normal output. Warp does not have this limitation — it stores graphemes
(`flat_storage/grapheme.rs`, `grid/grapheme_cursor.rs`), which is the shape a fix should
take. `terminal_core.rs`'s `hard_wraps_wide_text_and_drops_zero_width_scalars` was renamed
and its assertion changed to match; that is the one place in this plan where a test's
content assertion was relaxed rather than repaired, and it is a follow-up, not a
completed item.

**Known limits, deliberately out of scope.** Column-change reflow of existing scrollback rows is not implemented — rows already committed keep the width they were written at, which is what `flat_storage.set_columns` guards against in Warp (`resize.rs:70-77`) rather than solving. Agent panes take the no-reflow path (Task 7) so this is invisible there; a shell pane resized narrower will show rows that do not re-wrap. If that matters, it is a follow-up plan, not a task here.
