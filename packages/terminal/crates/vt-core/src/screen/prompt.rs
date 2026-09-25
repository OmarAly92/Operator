use crate::screen::{clamp_dimension, Cell, ScreenGrid};

impl ScreenGrid {
    pub(crate) fn resize_keeping_prompt(
        &mut self,
        rows: usize,
        cols: usize,
        prompt_row: Option<usize>,
    ) -> Option<usize> {
        let rows = clamp_dimension(rows);
        let cols = clamp_dimension(cols);
        if !self.reflow_on_resize || !self.records_eviction || !self.region_is_full() {
            return None;
        }
        let top = prompt_row.unwrap_or(self.row).min(self.row);
        let mut bottom = self.max_cursor_row.max(self.row);
        while bottom > self.row && bottom - top >= rows && self.row_is_blank(bottom) {
            bottom -= 1;
        }
        let kept = bottom - top + 1;
        if kept > rows {
            return None;
        }
        let trailing = self.rows - 1 - bottom;
        for row in 0..top {
            self.record_eviction(row);
        }
        let width = cols.min(self.cols);
        let mut cells = vec![Cell::BLANK; rows * cols];
        let mut wrapped = vec![false; rows];
        for (offset, flag) in wrapped.iter_mut().enumerate().take(kept) {
            let source = self.phys_start(top + offset);
            let target = offset * cols;
            cells[target..target + width].clone_from_slice(&self.cells[source..source + width]);
            if width < self.cols
                && self.cells[source + width].ch == '\0'
                && self.cells[source + width - 1].ch != '\0'
            {
                cells[target + width - 1] = Cell::BLANK;
            }
            *flag = cols == self.cols && self.row_wrapped(top + offset);
        }
        let wanted = if rows >= self.rows {
            top + (rows - self.rows)
        } else {
            top - top.min((self.rows - rows).saturating_sub(trailing))
        };
        self.cells = cells;
        self.wrapped = wrapped;
        self.dirty = vec![true; rows];
        self.first = 0;
        self.rows = rows;
        self.cols = cols;
        self.scroll_top = 0;
        self.scroll_bottom = rows - 1;
        self.row -= top;
        self.max_cursor_row = bottom - top;
        self.col = self.col.min(cols - 1);
        self.pending_wrap = false;
        self.saved = None;
        Some(wanted.min(rows - kept))
    }

    pub(crate) fn push_rows_on_top(&mut self, pulled: Vec<(Vec<Cell>, bool)>) {
        let count = pulled.len();
        if count == 0 || self.max_cursor_row + count >= self.rows {
            return;
        }
        self.materialize();
        let cols = self.cols;
        self.cells.rotate_right(count * cols);
        self.wrapped.rotate_right(count);
        for (index, (cells, wrapped)) in pulled.into_iter().enumerate() {
            self.cells[index * cols..(index + 1) * cols].clone_from_slice(&cells);
            self.wrapped[index] = wrapped;
        }
        self.row += count;
        self.max_cursor_row += count;
        self.mark_all_dirty();
    }
}
