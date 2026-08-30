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
