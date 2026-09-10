use std::collections::VecDeque;

use unicode_width::UnicodeWidthChar;

use crate::content::Content;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct RowRange {
    pub start: u64,
    pub end: u64,
    pub wrapped: bool,
}

pub(crate) struct RowIndex {
    completed: VecDeque<RowRange>,
    open_start: u64,
}

impl Clone for RowIndex {
    fn clone(&self) -> Self {
        Self {
            completed: self.completed.clone(),
            open_start: self.open_start,
        }
    }
}

impl RowIndex {
    pub fn new(first_offset: u64) -> Self {
        Self {
            completed: VecDeque::new(),
            open_start: first_offset,
        }
    }

    #[cfg(test)]
    pub fn open_start(&self) -> u64 {
        self.open_start
    }

    pub fn complete_row(&mut self, end_offset: u64, wrapped: bool) {
        self.completed.push_back(RowRange {
            start: self.open_start,
            end: end_offset,
            wrapped,
        });
        self.open_start = end_offset;
    }

    pub fn completed(&self) -> &VecDeque<RowRange> {
        &self.completed
    }

    pub fn rewrap(&mut self, content: &Content, cols: usize) -> Vec<usize> {
        let old = std::mem::take(&mut self.completed);
        let mut map = Vec::with_capacity(old.len() + 1);
        let mut index = 0;
        while index < old.len() {
            let line_start = old[index].start;
            let first_piece = index;
            while old[index].wrapped && index + 1 < old.len() {
                index += 1;
            }
            let line_end = old[index].end;
            index += 1;
            let first_new = self.completed.len();
            self.push_line(content, line_start, line_end, cols);
            for piece in old.range(first_piece..index) {
                map.push(self.row_holding(piece.start, first_new));
            }
        }
        map.push(self.completed.len());
        map
    }

    fn push_line(&mut self, content: &Content, start: u64, end: u64, cols: usize) {
        let bytes = content.copy_range(start, end);
        let Ok(text) = std::str::from_utf8(&bytes) else {
            self.completed.push_back(RowRange {
                start,
                end,
                wrapped: false,
            });
            return;
        };
        let mut piece_start = start;
        let mut width = 0;
        for (offset, ch) in text.char_indices() {
            let ch_width = UnicodeWidthChar::width(ch).unwrap_or(0);
            if ch_width > 0 && width > 0 && width + ch_width > cols {
                let cut = start + offset as u64;
                self.completed.push_back(RowRange {
                    start: piece_start,
                    end: cut,
                    wrapped: true,
                });
                piece_start = cut;
                width = 0;
            }
            width += ch_width;
        }
        self.completed.push_back(RowRange {
            start: piece_start,
            end,
            wrapped: false,
        });
    }

    fn row_holding(&self, offset: u64, from: usize) -> usize {
        (from..self.completed.len())
            .find(|&row| {
                let range = &self.completed[row];
                offset < range.end || row + 1 == self.completed.len()
            })
            .unwrap_or(from)
    }

    /// Drops the oldest completed rows until at most `max_total` rows (the open
    /// row included) remain, and returns the monotonic start offset of the
    /// earliest row still referenced by the index.
    ///
    /// The returned offset is what the caller may release. It is the first
    /// retained row's start, never the open row's start: rows between them are
    /// still rendered, and releasing their bytes blanks the scrollback.
    pub fn trim_to(&mut self, max_total: usize) -> Option<u64> {
        let mut dropped = false;
        while self.completed.len() + 1 > max_total {
            if self.completed.pop_front().is_none() {
                break;
            }
            dropped = true;
        }
        if !dropped {
            return None;
        }
        Some(self.earliest_retained_start())
    }

    fn earliest_retained_start(&self) -> u64 {
        self.completed
            .front()
            .map_or(self.open_start, |row| row.start)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn content_of(text: &str) -> Content {
        let mut content = Content::new();
        let mut buffer = [0u8; 4];
        for ch in text.chars() {
            content.push_char(ch.encode_utf8(&mut buffer));
        }
        content
    }

    fn ranges(index: &RowIndex) -> Vec<(u64, u64, bool)> {
        index
            .completed()
            .iter()
            .map(|row| (row.start, row.end, row.wrapped))
            .collect()
    }

    #[test]
    fn trim_to_drops_front_completed_rows() {
        let mut r = RowIndex::new(0);
        r.complete_row(10, false);
        r.complete_row(20, false);
        r.complete_row(30, false);
        let released = r.trim_to(2);
        assert_eq!(r.completed().len(), 1);
        assert_eq!(r.completed()[0].start, 20);
        assert_eq!(r.completed()[0].end, 30);
        assert_eq!(
            released,
            Some(20),
            "must release only up to the first retained row"
        );
    }

    #[test]
    fn trim_to_zero_still_reports_the_release_offset() {
        let mut r = RowIndex::new(0);
        r.complete_row(10, false);
        assert_eq!(r.trim_to(0), Some(10));
        assert_eq!(r.completed().len(), 0);
    }

    #[test]
    fn trim_to_reports_nothing_when_under_the_limit() {
        let mut r = RowIndex::new(0);
        r.complete_row(10, false);
        assert_eq!(r.trim_to(8), None);
        assert_eq!(r.completed().len(), 1);
    }

    #[test]
    fn trim_to_keeps_open_row_in_count() {
        let mut r = RowIndex::new(0);
        r.complete_row(10, false);
        r.complete_row(20, false);
        let open = r.trim_to(1).unwrap();
        assert_eq!(r.completed().len(), 0);
        assert_eq!(open, 20);
    }

    #[test]
    fn rewrap_cuts_a_wide_row_and_flags_every_piece_but_the_last() {
        let content = content_of("abcdefghij");
        let mut r = RowIndex::new(0);
        r.complete_row(10, false);
        let map = r.rewrap(&content, 4);
        assert_eq!(ranges(&r), vec![(0, 4, true), (4, 8, true), (8, 10, false)]);
        assert_eq!(map, vec![0, 3]);
    }

    #[test]
    fn rewrap_joins_flagged_pieces_before_cutting_again() {
        let content = content_of("abcdefghij");
        let mut r = RowIndex::new(0);
        r.complete_row(4, true);
        r.complete_row(8, true);
        r.complete_row(10, false);
        let map = r.rewrap(&content, 20);
        assert_eq!(ranges(&r), vec![(0, 10, false)]);
        assert_eq!(map, vec![0, 0, 0, 1]);
    }

    #[test]
    fn rewrap_maps_each_old_row_to_the_row_holding_its_first_byte() {
        let content = content_of("abcdefghijklmnop");
        let mut r = RowIndex::new(0);
        r.complete_row(8, true);
        r.complete_row(16, false);
        let map = r.rewrap(&content, 6);
        assert_eq!(
            ranges(&r),
            vec![(0, 6, true), (6, 12, true), (12, 16, false)]
        );
        assert_eq!(map, vec![0, 1, 3]);
    }

    #[test]
    fn rewrap_cuts_on_display_width_not_bytes() {
        let content = content_of("a\u{4e16}\u{754c}b");
        let mut r = RowIndex::new(0);
        r.complete_row(content.end_offset(), false);
        r.rewrap(&content, 3);
        assert_eq!(ranges(&r), vec![(0, 4, true), (4, 8, false)]);
    }

    #[test]
    fn rewrap_keeps_an_empty_row() {
        let content = content_of("ab");
        let mut r = RowIndex::new(0);
        r.complete_row(0, false);
        r.complete_row(2, false);
        let map = r.rewrap(&content, 1);
        assert_eq!(ranges(&r), vec![(0, 0, false), (0, 1, true), (1, 2, false)]);
        assert_eq!(map, vec![0, 1, 3]);
    }

    #[test]
    fn rewrap_leaves_the_open_row_start_alone() {
        let content = content_of("abcdef");
        let mut r = RowIndex::new(0);
        r.complete_row(6, false);
        r.rewrap(&content, 2);
        assert_eq!(r.open_start(), 6);
    }
}
