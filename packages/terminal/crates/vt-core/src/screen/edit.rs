use crate::screen::{ClearPolicy, ScreenGrid};

impl ScreenGrid {
    fn fill_cells(&mut self, row: usize, from: usize, to: usize) {
        if from >= to {
            return;
        }
        let start = self.phys_start(row);
        let blank = self.erased_cell();
        self.cells[start + from..start + to].fill(blank);
        if to == self.cols() {
            self.set_row_wrapped(row, false);
        }
        self.mark_dirty(row);
    }

    fn erase_cells(&mut self, row: usize, from: usize, to: usize) {
        if from < to {
            self.clear_split_wide(row, from, to);
        }
        self.fill_cells(row, from, to);
    }

    fn shift_cells(&mut self, row: usize, from: usize, to: usize, by: isize) {
        let start = self.phys_start(row);
        let span = &mut self.cells[start + from..start + to];
        if by > 0 {
            span.rotate_right(by.unsigned_abs());
        } else {
            span.rotate_left(by.unsigned_abs());
        }
        self.set_row_wrapped(row, false);
        self.mark_dirty(row);
    }

    pub fn erase_in_display(&mut self, mode: u16) {
        let (row, col) = self.cursor();
        let rows = self.rows();
        let cols = self.cols();
        match mode {
            0 => {
                self.erase_cells(row, col, cols);
                for r in (row + 1)..rows {
                    self.blank_row(r);
                }
            }
            1 => {
                for r in 0..row {
                    self.blank_row(r);
                }
                self.erase_cells(row, 0, col + 1);
            }
            2 => match self.clear_policy {
                ClearPolicy::Scroll => {
                    self.scroll_up(self.frame_rows());
                    self.max_cursor_row = 0;
                }
                ClearPolicy::ClearInPlace => {
                    for r in 0..rows {
                        self.blank_row(r);
                    }
                    self.max_cursor_row = 0;
                }
            },
            _ => {
                for r in 0..rows {
                    self.blank_row(r);
                }
            }
        }
    }

    pub fn evict_frame(&mut self) {
        let frame = self.frame_rows();
        let (top, bottom) = (self.scroll_top, self.scroll_bottom);
        self.scroll_top = 0;
        self.scroll_bottom = self.rows() - 1;
        self.scroll_up(frame);
        self.scroll_top = top;
        self.scroll_bottom = bottom;
        self.max_cursor_row = 0;
        self.move_to(0, 0);
        self.pending_wrap = false;
    }

    pub fn erase_in_line(&mut self, mode: u16) {
        let (row, col) = self.cursor();
        let cols = self.cols();
        match mode {
            0 => self.erase_cells(row, col, cols),
            1 => self.erase_cells(row, 0, col + 1),
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
        self.clear_split_wide(row, col, col);
        self.clear_split_wide(row, cols - count, cols - count);
        self.shift_cells(row, col, cols, count as isize);
        self.fill_cells(row, col, col + count);
    }

    pub fn delete_chars(&mut self, count: usize) {
        let (row, col) = self.cursor();
        let cols = self.cols();
        let count = count.min(cols - col);
        if count == 0 {
            return;
        }
        self.clear_split_wide(row, col, col + count);
        self.shift_cells(row, col, cols, -(count as isize));
        self.fill_cells(row, cols - count, cols);
    }

    pub fn erase_chars(&mut self, count: usize) {
        let (row, col) = self.cursor();
        let cols = self.cols();
        let count = count.min(cols - col);
        self.erase_cells(row, col, col + count);
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
