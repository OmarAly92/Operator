use unicode_width::UnicodeWidthChar;

use crate::screen::{Cell, ScreenGrid};
use crate::style::CellStyle;
use crate::width::{self, WidthMode};

fn printable_ascii(ch: char) -> bool {
    matches!(ch, ' '..='~')
}

impl ScreenGrid {
    pub fn print(&mut self, ch: char, style: CellStyle) {
        if printable_ascii(ch) && !self.pending_wrap && self.ascii_starts_a_cluster() {
            self.put_ascii(ch, style);
            return;
        }
        if self.width_mode == WidthMode::Grapheme && self.join_previous(ch, style) {
            return;
        }
        let width = UnicodeWidthChar::width(ch).unwrap_or(0);
        if width == 0 {
            self.attach_zerowidth(ch);
            return;
        }
        if self.pending_wrap || self.col + width > self.cols {
            self.set_row_wrapped(self.row, true);
            self.carriage_return();
            self.line_feed();
        }
        self.raise_max_cursor_row(self.row);
        self.clear_split_wide(self.row, self.col, self.col + width);
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

    pub fn print_ascii_run(&mut self, run: &[u8], style: CellStyle) {
        let Some((first, rest)) = run.split_first() else {
            return;
        };
        self.print(char::from(*first), style);
        let mut at = 0;
        while at < rest.len() {
            if self.pending_wrap {
                self.set_row_wrapped(self.row, true);
                self.carriage_return();
                self.line_feed();
            }
            let row = self.row;
            self.raise_max_cursor_row(row);
            let take = (self.cols - self.col).min(rest.len() - at);
            self.clear_split_wide(row, self.col, self.col + take);
            let start = self.phys_start(row) + self.col;
            for (cell, byte) in self.cells[start..start + take]
                .iter_mut()
                .zip(&rest[at..at + take])
            {
                *cell = Cell::new(char::from(*byte), style);
            }
            self.col += take;
            at += take;
            if self.col == self.cols {
                self.set_row_wrapped(row, false);
                self.col = self.cols - 1;
                self.pending_wrap = true;
            }
            self.mark_dirty(row);
        }
    }

    fn put_ascii(&mut self, ch: char, style: CellStyle) {
        let row = self.row;
        self.raise_max_cursor_row(row);
        self.clear_split_wide(row, self.col, self.col + 1);
        let index = self.phys_start(row) + self.col;
        self.cells[index] = Cell::new(ch, style);
        if self.col + 1 == self.cols {
            self.set_row_wrapped(row, false);
            self.pending_wrap = true;
        } else {
            self.col += 1;
        }
        self.mark_dirty(row);
    }

    fn clear_split_wide(&mut self, row: usize, start: usize, end: usize) {
        let base = self.phys_start(row);
        let blank = self.erased_cell();
        let mut cleared = false;
        if start > 0 && self.cells[base + start].ch == '\0' {
            self.cells[base + start - 1] = blank.clone();
            cleared = true;
        }
        let mut col = end;
        while col < self.cols && self.cells[base + col].ch == '\0' {
            self.cells[base + col] = blank.clone();
            cleared = true;
            col += 1;
        }
        if cleared {
            self.mark_dirty(row);
        }
    }

    fn ascii_starts_a_cluster(&self) -> bool {
        if self.width_mode == WidthMode::Scalar {
            return true;
        }
        match self.previous_cell() {
            None => true,
            Some((row, col)) => self.cells[self.phys_start(row) + col].is_plain_ascii(),
        }
    }

    fn previous_cell(&self) -> Option<(usize, usize)> {
        let mut col = self.col;
        if !self.pending_wrap {
            col = col.checked_sub(1)?;
        }
        if self
            .cell_ref(self.row, col)
            .is_some_and(|cell| cell.ch == '\0')
        {
            col = col.checked_sub(1)?;
        }
        (self.row < self.rows && col < self.cols).then_some((self.row, col))
    }

    fn cell_width_at(&self, row: usize, col: usize) -> usize {
        1 + (col + 1..self.cols)
            .take_while(|next| {
                self.cell_ref(row, *next)
                    .is_some_and(|cell| cell.ch == '\0')
            })
            .count()
    }

    fn join_previous(&mut self, ch: char, style: CellStyle) -> bool {
        let Some((row, col)) = self.previous_cell() else {
            return false;
        };
        let index = self.phys_start(row) + col;
        let mut buffer = [0u8; 4];
        if !width::joins_previous(self.cells[index].text(&mut buffer), ch) {
            return false;
        }
        let old_width = self.cell_width_at(row, col);
        self.cells[index].append_scalar(ch);
        let new_width = width::cluster_width(self.cells[index].text(&mut buffer));
        if new_width > old_width && col + 1 < self.cols {
            self.clear_split_wide(row, col + 1, col + 2);
            self.set(row, col + 1, Cell::new('\0', style));
            if self.row == row && self.col == col + 1 {
                self.col += 1;
                if self.col >= self.cols {
                    self.col = self.cols - 1;
                    self.pending_wrap = true;
                }
            }
        }
        self.raise_max_cursor_row(row);
        self.mark_dirty(row);
        true
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
        if self
            .cell_ref(self.row, col)
            .is_some_and(|cell| cell.ch == '\0')
        {
            col = col.saturating_sub(1);
        }
        let row = self.row;
        self.raise_max_cursor_row(row);
        if row >= self.rows || col >= self.cols {
            return;
        }
        let index = self.phys_start(row) + col;
        self.cells[index].append_scalar(ch);
        self.mark_dirty(row);
    }
}
