use crate::screen::{clamp_dimension, Cell, ScreenGrid};

impl ScreenGrid {
    pub(crate) fn resize_keeping_prompt(
        &mut self,
        rows: usize,
        cols: usize,
        prompt_row: Option<usize>,
        owned_rows: usize,
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
        if kept > rows || (top > 0 && self.row_wrapped(top - 1)) {
            return None;
        }
        let mut owned_end = (top + owned_rows).min(bottom);
        while owned_end < bottom && self.row_wrapped(owned_end) {
            owned_end += 1;
        }
        if (owned_end + 1..=bottom).any(|row| self.row_loses_cells(row, cols)) {
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
            for (to, from) in cells[target..target + width]
                .iter_mut()
                .zip(&self.cells[source..source + width])
            {
                *to = from.clone();
            }
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

    fn row_loses_cells(&self, row: usize, cols: usize) -> bool {
        if cols >= self.cols {
            return false;
        }
        let start = self.phys_start(row);
        let cells = &self.cells[start..start + self.cols];
        (cells[cols].ch == '\0' && cells[cols - 1].ch != '\0')
            || cells[cols..].iter().any(|cell| !cell.is_blank())
    }

    pub(crate) fn push_rows_on_top(&mut self, pulled: Vec<(Vec<Cell>, bool)>) {
        let count = pulled.len();
        if count == 0 {
            return;
        }
        debug_assert!(self.max_cursor_row + count < self.rows);
        self.materialize();
        let cols = self.cols;
        self.cells.rotate_right(count * cols);
        self.wrapped.rotate_right(count);
        for (index, (cells, wrapped)) in pulled.into_iter().enumerate() {
            for (col, cell) in cells.into_iter().enumerate() {
                self.cells[index * cols + col] = cell;
            }
            self.wrapped[index] = wrapped;
        }
        self.row += count;
        self.max_cursor_row += count;
        self.mark_all_dirty();
    }
}
