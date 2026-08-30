mod dispatch;
mod edit;
mod scroll;
mod snapshot;

pub use snapshot::AltSnapshot;

use unicode_width::UnicodeWidthChar;

use crate::style::StyleCode;

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
/// It is boxed so the common cell stays two words.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Cell {
    pub ch: char,
    pub style: StyleCode,
    extra: Option<Box<String>>,
}

impl Cell {
    pub const BLANK: Self = Self {
        ch: ' ',
        style: StyleCode::DEFAULT,
        extra: None,
    };

    pub const fn new(ch: char, style: StyleCode) -> Self {
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

    pub fn is_blank(&self) -> bool {
        matches!(self.ch, ' ' | '\0') && self.extra.is_none()
    }

    pub(crate) fn push_zerowidth(&mut self, ch: char) {
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

pub struct ScreenGrid {
    rows: usize,
    cols: usize,
    cells: Vec<Cell>,
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
    evicted: Vec<Vec<Cell>>,
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
            evicted: Vec::new(),
        }
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

    pub fn take_evicted(&mut self) -> Vec<Vec<Cell>> {
        std::mem::take(&mut self.evicted)
    }

    pub(crate) fn record_eviction(&mut self, row: usize) {
        if !self.records_eviction || self.scroll_top != 0 || self.scroll_bottom + 1 != self.rows {
            return;
        }
        let start = row * self.cols;
        self.evicted
            .push(self.cells[start..start + self.cols].to_vec());
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

    pub(crate) fn row_has_content(&self, row: usize) -> bool {
        (0..self.cols).any(|col| !matches!(self.cell(row, col).ch, ' ' | '\0'))
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
        self.cells[row * self.cols + col].clone()
    }

    pub(crate) fn cell_ref(&self, row: usize, col: usize) -> Option<&Cell> {
        if row >= self.rows || col >= self.cols {
            return None;
        }
        self.cells.get(row * self.cols + col)
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
        self.max_cursor_row = self.max_cursor_row.max(self.row);
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
            self.attach_zerowidth(ch);
            return;
        }
        if self.pending_wrap || self.col + width > self.cols {
            self.carriage_return();
            self.line_feed();
        }
        self.max_cursor_row = self.max_cursor_row.max(self.row);
        self.set(self.row, self.col, Cell::new(ch, style));
        for offset in 1..width {
            self.set(self.row, self.col + offset, Cell::new('\0', style));
        }
        self.col += width;
        if self.col >= self.cols {
            self.col = self.cols - 1;
            self.pending_wrap = true;
        }
    }

    /// Attaches a zero-width scalar to the cell that owns it. Warp resolves the
    /// same target at `grid/ansi_handler.rs:201-215`: the column before the
    /// cursor unless a wrap is pending, stepping back once more off a
    /// wide-character spacer so the scalar lands on the base cell.
    fn attach_zerowidth(&mut self, ch: char) {
        let mut col = self.col;
        if !self.pending_wrap {
            col = col.saturating_sub(1);
        }
        if self.cell_ref(self.row, col).is_some_and(|cell| cell.ch == '\0') {
            col = col.saturating_sub(1);
        }
        let row = self.row;
        self.max_cursor_row = self.max_cursor_row.max(row);
        if row >= self.rows || col >= self.cols {
            return;
        }
        let index = row * self.cols + col;
        self.cells[index].push_zerowidth(ch);
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
        self.cells.fill(Cell::BLANK);
        self.row = 0;
        self.max_cursor_row = 0;
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
        if !self.reflow_on_resize {
            self.resize_cells(rows, cols);
            return;
        }
        for row in 0..self.content_rows() {
            self.record_eviction(row);
        }
        self.resize_cells(rows, cols);
    }

    pub(crate) fn resize_without_reflow(&mut self, rows: usize, cols: usize) {
        self.resize_cells(clamp_dimension(rows), clamp_dimension(cols));
    }

    fn resize_cells(&mut self, rows: usize, cols: usize) {
        let mut next = vec![Cell::BLANK; rows * cols];
        for row in 0..rows.min(self.rows) {
            for col in 0..cols.min(self.cols) {
                next[row * cols + col] = self.cells[row * self.cols + col].clone();
            }
        }
        self.cells = next;
        self.rows = rows;
        self.cols = cols;
        self.scroll_top = 0;
        self.scroll_bottom = rows - 1;
        self.row = self.row.min(rows - 1);
        self.max_cursor_row = self.max_cursor_row.min(rows - 1);
        self.col = self.col.min(cols - 1);
        self.pending_wrap = false;
        self.saved = None;
    }
}
