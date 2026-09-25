mod dispatch;
mod edit;
mod print;
mod resize;
mod scroll;
mod snapshot;

pub use snapshot::AltSnapshot;

use crate::style::{CellStyle, StyleCode};
use crate::width::WidthMode;

pub const MAX_DIMENSION: usize = 1000;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ClearPolicy {
    Scroll,
    ClearInPlace,
}

/// The byte cap on one cell's accumulated grapheme, matching Warp's
/// `MAX_GRAPHEME_BYTES` (`grid/cell.rs:33`). A cell that reaches it silently
/// drops further zero-width scalars rather than growing without bound.
pub const MAX_GRAPHEME_BYTES: usize = 256;

/// A grid cell. `extra` carries the base scalar followed by every zero-width
/// scalar attached to it, held together so a read never has to join them --
/// the shape of Warp's `CellExtra::cell_with_zero_width` (`grid/cell.rs:114`).
/// It is boxed so the common cell stays small.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Cell {
    pub ch: char,
    pub style: CellStyle,
    #[allow(clippy::box_collection)]
    extra: Option<Box<String>>,
}

impl Cell {
    pub const BLANK: Self = Self {
        ch: ' ',
        style: CellStyle::DEFAULT,
        extra: None,
    };

    pub const fn blank_with_background(bg: StyleCode) -> Self {
        Self {
            ch: ' ',
            style: CellStyle::new(StyleCode::DEFAULT, bg),
            extra: None,
        }
    }

    pub const fn new(ch: char, style: CellStyle) -> Self {
        Self {
            ch,
            style,
            extra: None,
        }
    }

    pub fn text<'a>(&'a self, buffer: &'a mut [u8; 4]) -> &'a str {
        match self.extra.as_deref() {
            Some(text) => text,
            None => self.ch.encode_utf8(buffer),
        }
    }

    pub(crate) fn is_plain_ascii(&self) -> bool {
        self.ch.is_ascii() && self.extra.is_none()
    }

    pub fn is_blank(&self) -> bool {
        matches!(self.ch, ' ' | '\0') && self.extra.is_none() && self.style.is_default_paint()
    }

    pub(crate) fn append_scalar(&mut self, ch: char) {
        match self.extra.as_deref_mut() {
            Some(text) => {
                if text.len() + ch.len_utf8() > MAX_GRAPHEME_BYTES {
                    return;
                }
                text.push(ch);
            }
            None => self.extra = Some(Box::new(format!("{}{}", self.ch, ch))),
        }
    }
}

pub struct EvictedRow {
    pub cells: Vec<Cell>,
    pub wrapped: bool,
}

pub struct ScreenGrid {
    rows: usize,
    cols: usize,
    cells: Vec<Cell>,
    wrapped: Vec<bool>,
    first: usize,
    row: usize,
    max_cursor_row: usize,
    col: usize,
    cursor_visible: bool,
    pending_wrap: bool,
    saved: Option<(usize, usize)>,
    pub(crate) scroll_top: usize,
    pub(crate) scroll_bottom: usize,
    records_eviction: bool,
    reflow_on_resize: bool,
    clear_policy: ClearPolicy,
    erase_background: StyleCode,
    evicted: Vec<EvictedRow>,
    dirty: Vec<bool>,
    width_mode: WidthMode,
}

fn clamp_dimension(value: usize) -> usize {
    value.clamp(1, MAX_DIMENSION)
}

impl ScreenGrid {
    pub fn new(rows: usize, cols: usize) -> Self {
        let rows = clamp_dimension(rows);
        let cols = clamp_dimension(cols);
        Self {
            rows,
            cols,
            cells: vec![Cell::BLANK; rows * cols],
            wrapped: vec![false; rows],
            first: 0,
            row: 0,
            max_cursor_row: 0,
            col: 0,
            cursor_visible: true,
            pending_wrap: false,
            saved: None,
            scroll_top: 0,
            scroll_bottom: rows - 1,
            records_eviction: false,
            reflow_on_resize: true,
            clear_policy: ClearPolicy::Scroll,
            erase_background: StyleCode::DEFAULT_BACKGROUND,
            evicted: Vec::new(),
            dirty: vec![false; rows],
            width_mode: WidthMode::default(),
        }
    }

    pub fn set_width_mode(&mut self, mode: WidthMode) {
        self.width_mode = mode;
    }

    pub fn set_erase_background(&mut self, bg: StyleCode) {
        self.erase_background = bg;
    }

    pub(crate) fn erased_cell(&self) -> Cell {
        Cell::blank_with_background(self.erase_background)
    }

    pub fn set_records_eviction(&mut self, on: bool) {
        self.records_eviction = on;
    }

    pub fn set_reflow_on_resize(&mut self, on: bool) {
        self.reflow_on_resize = on;
    }

    pub fn set_clear_policy(&mut self, policy: ClearPolicy) {
        self.clear_policy = policy;
    }

    pub fn take_evicted(&mut self) -> Vec<EvictedRow> {
        std::mem::take(&mut self.evicted)
    }

    pub(crate) fn record_eviction(&mut self, row: usize) {
        if !self.records_eviction || self.scroll_top != 0 || self.scroll_bottom + 1 != self.rows {
            return;
        }
        let start = self.phys_start(row);
        self.evicted.push(EvictedRow {
            cells: self.cells[start..start + self.cols].to_vec(),
            wrapped: self.wrapped[self.phys_row(row)],
        });
    }

    pub fn row_wrapped(&self, row: usize) -> bool {
        row < self.rows && self.wrapped[self.phys_row(row)]
    }

    fn set_row_wrapped(&mut self, row: usize, wrapped: bool) {
        if row >= self.rows {
            return;
        }
        let index = self.phys_row(row);
        self.wrapped[index] = wrapped;
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

    pub fn content_rows(&self) -> usize {
        self.max_cursor_row + 1
    }

    pub(crate) fn frame_rows(&self) -> usize {
        (0..self.content_rows())
            .rev()
            .find(|&row| !self.row_is_blank(row))
            .map_or(0, |row| row + 1)
    }

    fn row_is_blank(&self, row: usize) -> bool {
        (0..self.cols).all(|col| self.cell_ref(row, col).is_none_or(Cell::is_blank))
    }

    pub(crate) fn row_has_content(&self, row: usize) -> bool {
        (0..self.cols).any(|col| !matches!(self.cell(row, col).ch, ' ' | '\0'))
    }

    pub fn cursor_visible(&self) -> bool {
        self.cursor_visible
    }

    pub fn set_cursor_visible(&mut self, visible: bool) {
        if self.cursor_visible == visible {
            return;
        }
        self.cursor_visible = visible;
        let row = self.row;
        self.mark_dirty(row);
    }

    fn mark_dirty(&mut self, row: usize) {
        if let Some(flag) = self.dirty.get_mut(row) {
            *flag = true;
        }
    }

    fn mark_all_dirty(&mut self) {
        self.dirty.fill(true);
    }

    pub fn take_dirty(&mut self) -> Vec<usize> {
        let exported = self.rows;
        let mut rows = Vec::new();
        for row in 0..exported {
            if self.dirty[row] {
                self.dirty[row] = false;
                rows.push(row);
            }
        }
        rows
    }

    fn raise_max_cursor_row(&mut self, row: usize) {
        if row > self.max_cursor_row {
            for new_row in self.max_cursor_row + 1..=row {
                self.mark_dirty(new_row);
            }
            self.max_cursor_row = row;
        }
    }

    pub fn cell(&self, row: usize, col: usize) -> Cell {
        if row >= self.rows || col >= self.cols {
            return Cell::BLANK;
        }
        self.cells[self.phys_start(row) + col].clone()
    }

    pub(crate) fn cell_ref(&self, row: usize, col: usize) -> Option<&Cell> {
        if row >= self.rows || col >= self.cols {
            return None;
        }
        self.cells.get(self.phys_start(row) + col)
    }

    pub(crate) fn set(&mut self, row: usize, col: usize, cell: Cell) {
        if row >= self.rows || col >= self.cols {
            return;
        }
        let index = self.phys_start(row) + col;
        self.cells[index] = cell;
        if col + 1 == self.cols {
            self.set_row_wrapped(row, false);
        }
        self.mark_dirty(row);
    }

    pub(crate) fn blank_row(&mut self, row: usize) {
        if row >= self.rows {
            return;
        }
        let start = self.phys_start(row);
        let blank = self.erased_cell();
        self.cells[start..start + self.cols].fill(blank);
        self.set_row_wrapped(row, false);
        self.mark_dirty(row);
    }

    #[inline]
    fn phys_row(&self, row: usize) -> usize {
        (row + self.first) % self.rows
    }

    // Logical row -> physical byte offset. The grid is a ring of rows: a
    // full-screen scroll advances `first` instead of moving cells, so a
    // newline costs O(cols) (one blanked row) rather than O(rows * cols).
    #[inline]
    fn phys_start(&self, row: usize) -> usize {
        self.phys_row(row) * self.cols
    }

    // Partial scroll regions still move cells; the ring must be unwound first
    // so the region is contiguous. Rotating whole rows never clones a Cell.
    fn materialize(&mut self) {
        if self.first != 0 {
            let shift = self.first * self.cols;
            self.cells.rotate_left(shift);
            self.wrapped.rotate_left(self.first);
            self.first = 0;
        }
    }

    fn region_is_full(&self) -> bool {
        self.scroll_top == 0 && self.scroll_bottom + 1 == self.rows
    }

    pub(crate) fn rotate_region_up(&mut self, count: usize) {
        self.mark_all_dirty();
        if self.region_is_full() {
            self.first = (self.first + count) % self.rows;
            return;
        }
        self.materialize();
        let start = self.scroll_top * self.cols;
        let end = (self.scroll_bottom + 1) * self.cols;
        self.cells[start..end].rotate_left(count * self.cols);
        self.wrapped[self.scroll_top..=self.scroll_bottom].rotate_left(count);
    }

    pub(crate) fn rotate_region_down(&mut self, count: usize) {
        self.mark_all_dirty();
        if self.region_is_full() {
            self.first = (self.first + self.rows - count) % self.rows;
            return;
        }
        self.materialize();
        let start = self.scroll_top * self.cols;
        let end = (self.scroll_bottom + 1) * self.cols;
        self.cells[start..end].rotate_right(count * self.cols);
        self.wrapped[self.scroll_top..=self.scroll_bottom].rotate_right(count);
    }

    pub(crate) fn copy_row(&mut self, from: usize, to: usize) {
        if from == to {
            return;
        }
        for col in 0..self.cols {
            let cell = self.cell(from, col);
            self.set(to, col, cell);
        }
        let wrapped = self.row_wrapped(from);
        self.set_row_wrapped(to, wrapped);
    }

    pub(crate) fn clear_pending_wrap(&mut self) {
        self.pending_wrap = false;
    }

    pub fn move_to(&mut self, row: usize, col: usize) {
        let previous = self.row;
        self.row = row.min(self.rows - 1);
        if self.row != previous {
            self.mark_dirty(previous);
            self.mark_dirty(self.row);
        }
        self.raise_max_cursor_row(self.row);
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

    pub fn row_text(&self, row: usize) -> String {
        let mut out = String::new();
        let mut buffer = [0u8; 4];
        for col in 0..self.cols {
            let Some(cell) = self.cell_ref(row, col) else {
                continue;
            };
            if cell.ch == '\0' {
                continue;
            }
            out.push_str(cell.text(&mut buffer));
        }
        out
    }

    pub fn reset(&mut self) {
        self.mark_all_dirty();
        self.cells.fill(Cell::BLANK);
        self.wrapped.fill(false);
        self.row = 0;
        self.max_cursor_row = 0;
        self.col = 0;
        self.scroll_top = 0;
        self.scroll_bottom = self.rows - 1;
        self.pending_wrap = false;
        self.cursor_visible = true;
        self.saved = None;
    }
}
