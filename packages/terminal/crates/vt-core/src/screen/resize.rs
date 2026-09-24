use crate::screen::{clamp_dimension, Cell, ScreenGrid};

impl ScreenGrid {
    pub fn resize(&mut self, rows: usize, cols: usize) {
        let rows = clamp_dimension(rows);
        let cols = clamp_dimension(cols);
        if !self.reflow_on_resize {
            self.resize_cells(rows, cols);
            return;
        }
        let before = self.evicted.len();
        for row in 0..self.frame_rows() {
            self.record_eviction(row);
        }
        if self.evicted.len() > before {
            self.reset_cells(rows, cols);
        } else {
            self.resize_cells(rows, cols);
        }
    }

    fn reset_cells(&mut self, rows: usize, cols: usize) {
        self.cells = vec![Cell::BLANK; rows * cols];
        self.wrapped = vec![false; rows];
        self.dirty = vec![true; rows];
        self.first = 0;
        self.rows = rows;
        self.cols = cols;
        self.scroll_top = 0;
        self.scroll_bottom = rows - 1;
        self.row = 0;
        self.col = 0;
        self.max_cursor_row = 0;
        self.pending_wrap = false;
        self.saved = None;
    }

    pub(crate) fn resize_without_reflow(&mut self, rows: usize, cols: usize) {
        self.resize_cells(clamp_dimension(rows), clamp_dimension(cols));
    }

    /// Rows that a height shrink cannot keep come off the bottom first and only
    /// then off the top, which is what `tmux`'s `screen_resize_y` does: it
    /// deletes the lines below the cursor, then pushes the lines above it into
    /// history and walks the cursor up. Dropping only from the bottom would
    /// clamp a cursor that sits below the new last row and leave the screen
    /// frozen several pages behind whatever the application drew next.
    fn shrink_from_top(&self, rows: usize) -> usize {
        let needed = self.rows.saturating_sub(rows);
        let below_cursor = self.rows - 1 - self.row;
        needed.saturating_sub(below_cursor)
    }

    fn resize_cells(&mut self, rows: usize, cols: usize) {
        let dropped = self.shrink_from_top(rows);
        for row in 0..dropped {
            self.record_eviction(row);
        }
        let mut next = vec![Cell::BLANK; rows * cols];
        let mut wrapped = vec![false; rows];
        for row in 0..rows.min(self.rows - dropped) {
            for col in 0..cols.min(self.cols) {
                next[row * cols + col] = self.cells[self.phys_start(row + dropped) + col].clone();
            }
            wrapped[row] = cols == self.cols && self.row_wrapped(row + dropped);
        }
        self.cells = next;
        self.wrapped = wrapped;
        self.dirty = vec![true; rows];
        self.first = 0;
        self.rows = rows;
        self.cols = cols;
        self.scroll_top = 0;
        self.scroll_bottom = rows - 1;
        self.row = self.row.saturating_sub(dropped).min(rows - 1);
        self.max_cursor_row = self.max_cursor_row.saturating_sub(dropped).min(rows - 1);
        self.col = self.col.min(cols - 1);
        self.pending_wrap = false;
        self.saved = None;
    }
}
