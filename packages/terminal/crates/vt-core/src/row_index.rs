use std::collections::VecDeque;

pub(crate) struct RowRange {
    pub start: u64,
    pub end: u64,
}

pub(crate) struct RowIndex {
    completed: VecDeque<RowRange>,
    open_start: u64,
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

    pub fn trim_to(&mut self, max_total: usize) -> Option<u64> {
        let mut dropped = false;
        while self.completed.len() + 1 > max_total {
            self.completed.pop_front()?;
            dropped = true;
        }
        if dropped {
            Some(self.open_start)
        } else {
            None
        }
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
        let _ = r.trim_to(2);
        assert_eq!(r.completed().len(), 1);
        assert_eq!(r.completed()[0].start, 20);
        assert_eq!(r.completed()[0].end, 30);
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
