use vte::Params;

use crate::screen::ScreenGrid;

fn param(params: &Params, index: usize, default: u16) -> u16 {
    params
        .iter()
        .nth(index)
        .and_then(|group| group.first().copied())
        .filter(|value| *value != 0)
        .unwrap_or(default)
}

impl ScreenGrid {
    pub(crate) fn csi(&mut self, params: &Params, intermediates: &[u8], c: char) {
        if intermediates.first() == Some(&b'?') {
            match (param(params, 0, 0), c) {
                (25, 'h') => self.set_cursor_visible(true),
                (25, 'l') => self.set_cursor_visible(false),
                _ => {}
            }
            return;
        }
        if !intermediates.is_empty() {
            return;
        }
        match c {
            'A' => self.move_by(-(param(params, 0, 1) as isize), 0),
            'B' | 'e' => self.move_by(param(params, 0, 1) as isize, 0),
            'C' | 'a' => self.move_by(0, param(params, 0, 1) as isize),
            'D' => self.move_by(0, -(param(params, 0, 1) as isize)),
            'H' | 'f' => {
                let row = param(params, 0, 1) as usize - 1;
                let col = param(params, 1, 1) as usize - 1;
                self.move_to(row, col);
            }
            'G' | '`' => {
                let row = self.cursor().0;
                self.move_to(row, param(params, 0, 1) as usize - 1);
            }
            'd' => {
                let col = self.cursor().1;
                self.move_to(param(params, 0, 1) as usize - 1, col);
            }
            'E' => {
                let row = self.cursor().0 + param(params, 0, 1) as usize;
                self.move_to(row, 0);
            }
            'F' => {
                let row = self.cursor().0.saturating_sub(param(params, 0, 1) as usize);
                self.move_to(row, 0);
            }
            'J' => self.erase_in_display(param(params, 0, 0)),
            'K' => self.erase_in_line(param(params, 0, 0)),
            'L' => self.insert_lines(param(params, 0, 1) as usize),
            'M' => self.delete_lines(param(params, 0, 1) as usize),
            '@' => self.insert_chars(param(params, 0, 1) as usize),
            'P' => self.delete_chars(param(params, 0, 1) as usize),
            'X' => self.erase_chars(param(params, 0, 1) as usize),
            'S' => self.scroll_up(param(params, 0, 1) as usize),
            'T' => self.scroll_down(param(params, 0, 1) as usize),
            'r' => {
                let top = param(params, 0, 1) as usize - 1;
                let bottom = param(params, 1, self.rows() as u16) as usize - 1;
                self.set_scroll_region(top, bottom);
            }
            's' => self.save_cursor(),
            'u' => self.restore_cursor(),
            _ => {}
        }
    }

    pub(crate) fn esc(&mut self, byte: u8) {
        match byte {
            b'7' => self.save_cursor(),
            b'8' => self.restore_cursor(),
            b'D' => self.line_feed(),
            b'E' => self.next_line(),
            b'M' => self.reverse_index(),
            b'c' => self.reset(),
            _ => {}
        }
    }
}
