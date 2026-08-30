use crate::alt::AltGrid;

impl AltGrid {
    pub fn line_feed(&mut self) {
        let (row, col) = self.cursor();
        if row + 1 < self.rows() {
            self.move_to(row + 1, col);
        }
    }
}
