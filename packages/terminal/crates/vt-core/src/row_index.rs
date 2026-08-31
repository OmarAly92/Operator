use std::collections::VecDeque;

#[derive(Clone)]
pub(crate) struct RowRange {
    pub start: u64,
    pub end: u64,
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

    pub fn open_start(&self) -> u64 {
        self.open_start
    }

    pub fn complete_row(&mut self, end_offset: u64) {
        if end_offset > self.open_start {
            self.completed.push_back(RowRange {
                start: self.open_start,
                end: end_offset,
            });
        }
        self.open_start = end_offset;
    }

    pub fn completed(&self) -> &VecDeque<RowRange> {
        &self.completed
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

    #[test]
    fn trim_to_drops_front_completed_rows() {
        let mut r = RowIndex::new(0);
        r.complete_row(10);
        r.complete_row(20);
        r.complete_row(30);
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
        r.complete_row(10);
        assert_eq!(r.trim_to(0), Some(10));
        assert_eq!(r.completed().len(), 0);
    }

    #[test]
    fn trim_to_reports_nothing_when_under_the_limit() {
        let mut r = RowIndex::new(0);
        r.complete_row(10);
        assert_eq!(r.trim_to(8), None);
        assert_eq!(r.completed().len(), 1);
    }

    #[test]
    fn trim_to_keeps_open_row_in_count() {
        let mut r = RowIndex::new(0);
        r.complete_row(10);
        r.complete_row(20);
        let open = r.trim_to(1).unwrap();
        assert_eq!(r.completed().len(), 0);
        assert_eq!(open, 20);
    }
}
