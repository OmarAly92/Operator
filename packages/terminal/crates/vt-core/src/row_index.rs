use std::collections::VecDeque;

use unicode_width::UnicodeWidthChar;

use crate::content::Content;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct RowRange {
    pub start: u64,
    pub end: u64,
    pub wrapped: bool,
    pub indent: u16,
}

const BULLETS: &[char] = &[
    '-', '*', '+', '>', '•', '●', '○', '◦', '▪', '▸', '▹', '►', '·', '⎿', '└', '├', '│',
];

pub(crate) fn hanging_indent(text: &str, cols: usize) -> usize {
    let leading = text.chars().take_while(|&ch| ch == ' ').count();
    let rest = &text[leading..];
    let marker = marker_width(rest);
    let after_marker = &rest[marker.1..];
    let gap = after_marker.chars().take_while(|&ch| ch == ' ').count();
    let indent = if marker.0 > 0 && gap > 0 {
        leading + marker.0 + gap
    } else {
        leading
    };
    if indent * 2 > cols {
        0
    } else {
        indent
    }
}

fn marker_width(rest: &str) -> (usize, usize) {
    let mut chars = rest.chars();
    let Some(first) = chars.next() else {
        return (0, 0);
    };
    if BULLETS.contains(&first) {
        return (
            UnicodeWidthChar::width(first).unwrap_or(0),
            first.len_utf8(),
        );
    }
    let digits = rest.chars().take_while(char::is_ascii_digit).count();
    if (1..=3).contains(&digits) && matches!(rest[digits..].chars().next(), Some('.' | ')')) {
        return (digits + 1, digits + 1);
    }
    (0, 0)
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
            indent: 0,
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
                indent: 0,
            });
            return;
        };
        let hang = hanging_indent(text, cols);
        let mut piece_start = start;
        let mut limit = cols;
        let mut width = 0;
        let mut word_in_piece = false;
        let mut last_break: Option<(u64, usize)> = None;
        for (offset, ch) in text.char_indices() {
            if ch == ' ' {
                width += 1;
                if word_in_piece {
                    last_break = Some((start + offset as u64 + 1, width));
                }
                continue;
            }
            let ch_width = UnicodeWidthChar::width(ch).unwrap_or(0);
            if ch_width > 0 && width > 0 && width + ch_width > limit {
                let (cut, cut_width) = last_break.unwrap_or((start + offset as u64, width));
                self.completed.push_back(RowRange {
                    start: piece_start,
                    end: cut,
                    wrapped: true,
                    indent: if piece_start == start { 0 } else { hang as u16 },
                });
                piece_start = cut;
                limit = cols - hang;
                width -= cut_width;
                word_in_piece = width > 0;
                last_break = None;
            }
            width += ch_width;
            word_in_piece |= ch_width > 0;
        }
        self.completed.push_back(RowRange {
            start: piece_start,
            end,
            wrapped: false,
            indent: if piece_start == start { 0 } else { hang as u16 },
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

    #[allow(clippy::type_complexity)]
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
    fn rewrap_breaks_at_the_last_space_before_the_edge() {
        let content = content_of("the quick brown fox jumps");
        let mut r = RowIndex::new(0);
        r.complete_row(content.end_offset(), false);
        r.rewrap(&content, 9);
        assert_eq!(
            ranges(&r),
            vec![(0, 10, true), (10, 20, true), (20, 25, false)]
        );
    }

    #[test]
    fn rewrap_cuts_inside_a_word_only_when_the_word_alone_is_too_wide() {
        let content = content_of("ab cdefghijkl m");
        let mut r = RowIndex::new(0);
        r.complete_row(content.end_offset(), false);
        r.rewrap(&content, 5);
        assert_eq!(
            ranges(&r),
            vec![(0, 3, true), (3, 8, true), (8, 14, true), (14, 15, false)]
        );
    }

    #[test]
    fn rewrap_never_breaks_after_a_leading_space() {
        let content = content_of(" abcdefgh");
        let mut r = RowIndex::new(0);
        r.complete_row(content.end_offset(), false);
        r.rewrap(&content, 5);
        assert_eq!(ranges(&r), vec![(0, 5, true), (5, 9, false)]);
    }

    #[test]
    fn rewrap_rejoins_a_word_wrapped_line_when_widened() {
        let content = content_of("the quick brown fox jumps");
        let mut r = RowIndex::new(0);
        r.complete_row(content.end_offset(), false);
        r.rewrap(&content, 9);
        r.rewrap(&content, 80);
        assert_eq!(ranges(&r), vec![(0, 25, false)]);
    }

    fn indents(index: &RowIndex) -> Vec<u16> {
        index.completed().iter().map(|row| row.indent).collect()
    }

    #[test]
    fn a_bullet_line_hangs_its_continuation_under_the_text() {
        let content = content_of("  - alpha beta gamma delta");
        let mut r = RowIndex::new(0);
        r.complete_row(content.end_offset(), false);
        r.rewrap(&content, 14);
        assert_eq!(
            ranges(&r),
            vec![(0, 15, true), (15, 21, true), (21, 26, false)]
        );
        assert_eq!(indents(&r), vec![0, 4, 4]);
    }

    #[test]
    fn a_plain_indented_line_hangs_by_its_leading_spaces() {
        let content = content_of("    alpha beta gamma");
        let mut r = RowIndex::new(0);
        r.complete_row(content.end_offset(), false);
        r.rewrap(&content, 12);
        assert_eq!(
            ranges(&r),
            vec![(0, 10, true), (10, 15, true), (15, 20, false)]
        );
        assert_eq!(indents(&r), vec![0, 4, 4]);
    }

    #[test]
    fn hanging_indent_recognises_markers_and_caps_at_half_the_pane() {
        assert_eq!(hanging_indent("- item", 80), 2);
        assert_eq!(hanging_indent("  ● item", 80), 4);
        assert_eq!(hanging_indent("  ⎿  Did 1 search", 80), 5);
        assert_eq!(hanging_indent("12. item", 80), 4);
        assert_eq!(hanging_indent("3) item", 80), 3);
        assert_eq!(hanging_indent("-item", 80), 0);
        assert_eq!(hanging_indent("plain text", 80), 0);
        assert_eq!(hanging_indent("      - deep", 12), 0);
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
