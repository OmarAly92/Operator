use crate::screen::ScreenGrid;

impl ScreenGrid {
    pub fn set_scroll_region(&mut self, top: usize, bottom: usize) {
        if top >= bottom || bottom >= self.rows() {
            self.scroll_top = 0;
            self.scroll_bottom = self.rows() - 1;
        } else {
            self.scroll_top = top;
            self.scroll_bottom = bottom;
        }
        self.move_to(0, 0);
    }

    pub fn scroll_up(&mut self, count: usize) {
        if count == 0 {
            return;
        }
        let span = self.scroll_bottom - self.scroll_top + 1;
        if count >= span {
            for r in self.scroll_top..=self.scroll_bottom {
                self.blank_row(r);
            }
            return;
        }
        for r in self.scroll_top..=(self.scroll_bottom - count) {
            self.copy_row(r + count, r);
        }
        for r in (self.scroll_bottom + 1 - count)..=self.scroll_bottom {
            self.blank_row(r);
        }
    }

    pub fn scroll_down(&mut self, count: usize) {
        if count == 0 {
            return;
        }
        let span = self.scroll_bottom - self.scroll_top + 1;
        if count >= span {
            for r in self.scroll_top..=self.scroll_bottom {
                self.blank_row(r);
            }
            return;
        }
        for r in ((self.scroll_top + count)..=self.scroll_bottom).rev() {
            self.copy_row(r - count, r);
        }
        for r in self.scroll_top..(self.scroll_top + count) {
            self.blank_row(r);
        }
    }

    pub fn line_feed(&mut self) {
        let (row, col) = self.cursor();
        if row == self.scroll_bottom {
            self.scroll_up(1);
            self.clear_pending_wrap();
        } else if row + 1 < self.rows() {
            self.move_to(row + 1, col);
        } else {
            self.clear_pending_wrap();
        }
    }

    pub fn reverse_index(&mut self) {
        let (row, col) = self.cursor();
        if row == self.scroll_top {
            self.scroll_down(1);
            self.clear_pending_wrap();
        } else if row > 0 {
            self.move_to(row - 1, col);
        }
    }

    pub fn next_line(&mut self) {
        self.carriage_return();
        self.line_feed();
    }
}
