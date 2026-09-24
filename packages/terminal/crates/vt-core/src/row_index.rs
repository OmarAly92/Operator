use std::collections::VecDeque;

use unicode_width::UnicodeWidthChar;

use crate::content::Content;
use crate::width::WidthMode;

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

pub(crate) const HOT_ROWS: usize = 2_000;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct StaleRun {
    pub start: usize,
    pub len: usize,
    pub cols: usize,
}

pub(crate) struct RowIndex {
    completed: VecDeque<RowRange>,
    open_start: u64,
    stale: Vec<StaleRun>,
}

impl Clone for RowIndex {
    fn clone(&self) -> Self {
        Self {
            completed: self.completed.clone(),
            open_start: self.open_start,
            stale: self.stale.clone(),
        }
    }
}

impl RowIndex {
    pub fn new(first_offset: u64) -> Self {
        Self {
            completed: VecDeque::new(),
            open_start: first_offset,
            stale: Vec::new(),
        }
    }

    pub fn open_start(&self) -> u64 {
        self.open_start
    }

    #[cfg(test)]
    pub(crate) fn completed_mut(&mut self) -> &mut VecDeque<RowRange> {
        &mut self.completed
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

    pub fn prepend(&mut self, rows: Vec<RowRange>) {
        let count = rows.len();
        for row in rows.into_iter().rev() {
            self.completed.push_front(row);
        }
        for run in self.stale.iter_mut() {
            run.start += count;
        }
    }

    pub fn stale_runs(&self) -> &[StaleRun] {
        &self.stale
    }

    pub fn rewrap_hot(
        &mut self,
        content: &Content,
        cols: usize,
        cut_at: usize,
        mode: WidthMode,
    ) -> Vec<usize> {
        let total = self.completed.len();
        let hot_start = self.line_start_at_or_below(total.saturating_sub(HOT_ROWS));
        if hot_start > 0 {
            self.mark_stale(0, hot_start, cut_at);
        }
        let mut hot = RowIndex {
            completed: self.completed.drain(hot_start..).collect(),
            open_start: self.open_start,
            stale: Vec::new(),
        };
        let hot_map = hot.rewrap(content, cols, mode);
        self.completed.extend(hot.completed);
        let mut map: Vec<usize> = (0..hot_start).collect();
        map.extend(hot_map.iter().map(|new| hot_start + new));
        map
    }

    // Marks EVERY part of [start, end) that no run already covers, not just
    // the band past the last run. A touch splits a run into a head and a tail
    // and leaves the rewrapped middle hot between them; that middle is cut at
    // the width the touch used, so a later width change has to re-mark it.
    // Extending from the last run alone reaches the tail and skips the middle,
    // which then stays cut at that intermediate width forever.
    fn mark_stale(&mut self, start: usize, end: usize, cols: usize) {
        if end <= start {
            return;
        }
        let mut gaps: Vec<(usize, usize)> = Vec::new();
        let mut cursor = start;
        for run in self.stale.iter() {
            if run.start >= end {
                break;
            }
            let run_end = run.start + run.len;
            if run_end <= cursor {
                continue;
            }
            if run.start > cursor {
                gaps.push((cursor, run.start));
            }
            cursor = run_end;
            if cursor >= end {
                break;
            }
        }
        if cursor < end {
            gaps.push((cursor, end));
        }
        for (lo, hi) in gaps {
            self.insert_stale(lo, hi - lo, cols);
        }
    }

    fn insert_stale(&mut self, start: usize, len: usize, cols: usize) {
        if len == 0 {
            return;
        }
        let mut start = start;
        let mut len = len;
        let mut at = self.stale.partition_point(|run| run.start < start);
        if at > 0 {
            let prev = &self.stale[at - 1];
            if prev.cols == cols && prev.start + prev.len == start {
                at -= 1;
                start = prev.start;
                len += prev.len;
                self.stale.remove(at);
            }
        }
        if at < self.stale.len() {
            let next = &self.stale[at];
            if next.cols == cols && start + len == next.start {
                len += next.len;
                self.stale.remove(at);
            }
        }
        self.stale.insert(at, StaleRun { start, len, cols });
    }

    // The nearest row at or below `row` that starts a logical line. A cut
    // taken mid-line hands `push_line` a fragment, which then computes a
    // hanging indent from the middle of a sentence (TERMINAL.md §4.4).
    fn line_start_at_or_below(&self, row: usize) -> usize {
        let mut index = row.min(self.completed.len());
        while index > 0 && self.completed[index - 1].wrapped {
            index -= 1;
        }
        index
    }

    fn line_start_at_or_above(&self, row: usize) -> usize {
        let mut index = row.min(self.completed.len());
        while index > 0 && index < self.completed.len() && self.completed[index - 1].wrapped {
            index += 1;
        }
        index
    }

    pub fn rows_for(
        &mut self,
        content: &Content,
        cols: usize,
        range: std::ops::Range<usize>,
        mode: WidthMode,
    ) -> Option<(Vec<usize>, usize)> {
        let touched: Vec<usize> = self
            .stale
            .iter()
            .enumerate()
            .filter(|(_, run)| run.start < range.end && range.start < run.start + run.len)
            .map(|(index, _)| index)
            .collect();
        if touched.is_empty() {
            return None;
        }
        let before = self.completed.len();
        let mut map: Vec<usize> = (0..before).collect();
        map.push(before);
        let mut lowest = usize::MAX;
        for index in touched.into_iter().rev() {
            let run = self.stale.remove(index);
            let clip_lo = run.start.max(range.start);
            let clip_hi = (run.start + run.len).min(range.end);
            let lo = self.line_start_at_or_below(clip_lo);
            let hi = self.line_start_at_or_above(clip_hi);
            // split_off / extend, never a per-row insert: inserting into a
            // VecDeque is O(len) per row, which at 200k rows and a 2,000-row
            // run is ~4x10^8 element moves — the cost this task exists to
            // remove.
            let mut tail = self.completed.split_off(hi);
            let slice: VecDeque<RowRange> = self.completed.split_off(lo);
            let mut piece = RowIndex {
                completed: slice,
                open_start: self.open_start,
                stale: Vec::new(),
            };
            let piece_map = piece.rewrap(content, cols, mode);
            let added = piece.completed.len();
            self.completed.append(&mut piece.completed);
            self.completed.append(&mut tail);
            let delta = added as isize - (hi - lo) as isize;
            for entry in map.iter_mut() {
                if *entry >= hi {
                    *entry = (*entry as isize + delta) as usize;
                } else if *entry >= lo {
                    let local = *entry - lo;
                    *entry = lo + piece_map.get(local).copied().unwrap_or(0);
                }
            }
            for later in self.stale.iter_mut() {
                if later.start >= hi {
                    later.start = (later.start as isize + delta) as usize;
                }
            }
            if hi < run.start + run.len {
                self.stale.insert(
                    index,
                    StaleRun {
                        start: lo + added,
                        len: (run.start + run.len) - hi,
                        cols: run.cols,
                    },
                );
            }
            if lo > run.start {
                self.stale.insert(
                    index,
                    StaleRun {
                        start: run.start,
                        len: lo - run.start,
                        cols: run.cols,
                    },
                );
            }
            lowest = lowest.min(lo);
        }
        Some((map, lowest))
    }

    pub fn rewrap(&mut self, content: &Content, cols: usize, mode: WidthMode) -> Vec<usize> {
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
            self.push_line(content, line_start, line_end, cols, mode);
            for piece in old.range(first_piece..index) {
                map.push(self.row_holding(piece.start, first_new));
            }
        }
        map.push(self.completed.len());
        map
    }

    fn push_line(&mut self, content: &Content, start: u64, end: u64, cols: usize, mode: WidthMode) {
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
        for cluster in crate::width::clusters(text, mode) {
            let piece = &text[cluster.start..cluster.end];
            let offset = cluster.start;
            if piece.starts_with(' ') && cluster.width == 1 {
                width += 1;
                if word_in_piece {
                    last_break = Some((start + cluster.end as u64, width));
                }
                continue;
            }
            let ch_width = cluster.width;
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
        let mut dropped = 0usize;
        while self.completed.len() + 1 > max_total {
            if self.completed.pop_front().is_none() {
                break;
            }
            dropped += 1;
        }
        if dropped == 0 {
            return None;
        }
        self.stale.retain_mut(|run| {
            if run.start + run.len <= dropped {
                false
            } else if run.start < dropped {
                run.len = run.start + run.len - dropped;
                run.start = 0;
                true
            } else {
                run.start -= dropped;
                true
            }
        });
        Some(self.earliest_retained_start())
    }

    fn earliest_retained_start(&self) -> u64 {
        self.completed
            .front()
            .map_or(self.open_start, |row| row.start)
    }
}

#[cfg(test)]
mod tests;
