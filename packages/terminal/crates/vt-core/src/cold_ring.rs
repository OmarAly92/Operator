use std::collections::VecDeque;
use std::ops::Range;

pub const COLD_ROW_OVERHEAD_BYTES: usize = std::mem::size_of::<(u32, u16)>();

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ColdRow {
    pub bytes: Vec<u8>,
    pub cols: usize,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ColdStats {
    pub rows: usize,
    pub bytes: usize,
    pub cap: usize,
    pub first_stable_row: u64,
}

#[derive(Debug, Default)]
pub struct ColdRing {
    cap: usize,
    data: VecDeque<u8>,
    rows: VecDeque<(u32, u16)>,
    first_stable: u64,
}

impl ColdRing {
    pub fn new(cap: usize, first_stable: u64) -> Self {
        Self {
            cap,
            data: VecDeque::new(),
            rows: VecDeque::new(),
            first_stable,
        }
    }

    pub fn is_enabled(&self) -> bool {
        self.cap > 0
    }

    pub fn len(&self) -> usize {
        self.rows.len()
    }

    pub fn is_empty(&self) -> bool {
        self.rows.is_empty()
    }

    pub fn bytes(&self) -> usize {
        self.data.len() + COLD_ROW_OVERHEAD_BYTES * self.rows.len()
    }

    pub fn first_stable(&self) -> u64 {
        self.first_stable
    }

    pub fn end_stable(&self) -> u64 {
        self.first_stable + self.rows.len() as u64
    }

    pub fn stats(&self) -> ColdStats {
        ColdStats {
            rows: self.rows.len(),
            bytes: self.bytes(),
            cap: self.cap,
            first_stable_row: self.first_stable,
        }
    }

    pub fn reset_at(&mut self, stable: u64) {
        self.data.clear();
        self.rows.clear();
        self.first_stable = stable;
    }

    pub fn push(&mut self, stable: u64, row: &ColdRow) {
        if !self.is_enabled() {
            return;
        }
        if stable != self.end_stable() {
            self.reset_at(stable);
        }
        let need = row.bytes.len() + COLD_ROW_OVERHEAD_BYTES;
        if need > self.cap {
            self.reset_at(stable + 1);
            return;
        }
        while self.bytes() + need > self.cap {
            self.pop_front();
        }
        if self.data.capacity() == 0 {
            self.data.reserve_exact(self.cap);
        }
        self.data.extend(row.bytes.iter());
        let cols = u16::try_from(row.cols).unwrap_or(u16::MAX);
        self.rows.push_back((row.bytes.len() as u32, cols));
    }

    fn pop_front(&mut self) {
        if let Some((len, _)) = self.rows.pop_front() {
            self.data.drain(..len as usize);
            self.first_stable += 1;
        }
    }

    pub fn rows(&self, range: Range<u64>) -> Vec<ColdRow> {
        let lo = range.start.max(self.first_stable);
        let hi = range.end.min(self.end_stable());
        if hi <= lo {
            return Vec::new();
        }
        let skip = (lo - self.first_stable) as usize;
        let take = (hi - lo) as usize;
        let mut offset: usize = self
            .rows
            .iter()
            .take(skip)
            .map(|(len, _)| *len as usize)
            .sum();
        let mut out = Vec::with_capacity(take);
        for (len, cols) in self.rows.iter().skip(skip).take(take) {
            let end = offset + *len as usize;
            out.push(ColdRow {
                bytes: self.data.range(offset..end).copied().collect(),
                cols: usize::from(*cols),
            });
            offset = end;
        }
        out
    }

    #[cfg(test)]
    pub(crate) fn data_capacity(&self) -> usize {
        self.data.capacity()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(text: &str) -> ColdRow {
        ColdRow {
            bytes: text.as_bytes().to_vec(),
            cols: text.chars().count(),
        }
    }

    fn texts(rows: &[ColdRow]) -> Vec<String> {
        rows.iter()
            .map(|row| String::from_utf8(row.bytes.clone()).unwrap())
            .collect()
    }

    #[test]
    fn a_ring_with_no_cap_keeps_nothing() {
        let mut ring = ColdRing::new(0, 0);
        ring.push(0, &row("a"));
        assert!(ring.is_empty());
        assert_eq!(ring.bytes(), 0);
    }

    #[test]
    fn rows_come_back_oldest_first_by_stable_row() {
        let mut ring = ColdRing::new(1024, 10);
        for (index, text) in ["ten", "eleven", "twelve"].iter().enumerate() {
            ring.push(10 + index as u64, &row(text));
        }
        assert_eq!(ring.first_stable(), 10);
        assert_eq!(ring.end_stable(), 13);
        assert_eq!(texts(&ring.rows(10..13)), ["ten", "eleven", "twelve"]);
        assert_eq!(texts(&ring.rows(11..12)), ["eleven"]);
        assert_eq!(texts(&ring.rows(0..11)), ["ten"]);
        assert!(ring.rows(13..20).is_empty());
    }

    #[test]
    fn the_oldest_rows_go_first_when_the_cap_is_reached() {
        let per_row = 4 + COLD_ROW_OVERHEAD_BYTES;
        let mut ring = ColdRing::new(per_row * 3, 0);
        for index in 0..5u64 {
            ring.push(index, &row(&format!("r{index:03}")));
        }
        assert_eq!(ring.len(), 3);
        assert_eq!(ring.first_stable(), 2);
        assert_eq!(texts(&ring.rows(0..5)), ["r002", "r003", "r004"]);
        assert!(ring.bytes() <= per_row * 3);
    }

    #[test]
    fn the_byte_count_never_passes_the_cap() {
        let cap = 64 * 1024;
        let mut ring = ColdRing::new(cap, 0);
        for index in 0..20_000u64 {
            let text = "x".repeat((index % 97) as usize);
            ring.push(index, &row(&text));
            assert!(
                ring.bytes() <= cap,
                "{} > {cap} at row {index}",
                ring.bytes()
            );
        }
        assert_eq!(ring.data_capacity(), cap);
    }

    #[test]
    fn a_row_larger_than_the_cap_empties_the_ring() {
        let mut ring = ColdRing::new(16, 0);
        ring.push(0, &row("ab"));
        ring.push(1, &row(&"z".repeat(64)));
        assert!(ring.is_empty());
        assert_eq!(ring.first_stable(), 2);
        ring.push(2, &row("cd"));
        assert_eq!(texts(&ring.rows(0..3)), ["cd"]);
    }

    #[test]
    fn a_gap_in_stable_rows_restarts_the_ring() {
        let mut ring = ColdRing::new(1024, 0);
        ring.push(0, &row("zero"));
        ring.push(5, &row("five"));
        assert_eq!(ring.first_stable(), 5);
        assert_eq!(texts(&ring.rows(0..10)), ["five"]);
    }

    #[test]
    fn a_row_keeps_the_width_it_needs() {
        let mut ring = ColdRing::new(1024, 0);
        ring.push(
            0,
            &ColdRow {
                bytes: b"wide".to_vec(),
                cols: 180,
            },
        );
        assert_eq!(ring.rows(0..1)[0].cols, 180);
    }
}
