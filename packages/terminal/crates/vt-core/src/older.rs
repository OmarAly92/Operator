use terminal_marks::MarkEvent;

use crate::cold_ring::ColdStats;
use crate::TerminalCore;

pub const OLDER_CHUNK_ROWS: usize = 2_048;

pub const OLDER_CELL_BUDGET: usize = OLDER_CHUNK_ROWS * 128;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct OlderState {
    pub floor: Option<u64>,
    pub marks: u32,
}

impl OlderState {
    pub(crate) fn note(&mut self, floor: u64) {
        self.floor = Some(floor);
        self.marks = self.marks.wrapping_add(1);
    }

    pub(crate) fn observe(&mut self, event: &MarkEvent) {
        let MarkEvent::Extension(fields) = event else {
            return;
        };
        if fields.pairs.iter().any(|(key, _)| key == "boundary") {
            self.floor = None;
            self.marks = self.marks.wrapping_add(1);
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OlderChunk {
    pub first_stable_row: u64,
    pub rows: usize,
    pub bytes: Vec<u8>,
}

impl TerminalCore {
    pub fn set_cold_ring_bytes(&mut self, cap: usize) {
        self.parser.set_cold_ring_bytes(cap);
    }

    pub fn cold_stats(&self) -> ColdStats {
        self.parser.cold_stats()
    }

    pub fn cold_floor(&self) -> Option<u64> {
        self.parser.cold_floor()
    }

    pub fn older_mark(&self) -> Option<Vec<u8>> {
        let floor = self.parser.cold_floor()?;
        Some(format!("\x1b]7000;v=1;older={floor}\x1b\\").into_bytes())
    }

    pub fn older_chunk(
        &self,
        before: u64,
        max_rows: usize,
        max_bytes: usize,
    ) -> Option<OlderChunk> {
        let mut rows = self.parser.older_rows(before, max_rows.max(1));
        if let Some(newest) = rows.last_mut() {
            if 64 + newest.bytes.len() + 2 > max_bytes {
                newest.bytes.clear();
                newest.cols = 0;
            }
        }
        let mut taken = 0usize;
        let mut cols = 1usize;
        let mut size = 64usize;
        let limit = usize::try_from(before).unwrap_or(usize::MAX);
        for row in rows.iter().rev().take(limit) {
            let next_cols = cols.max(row.cols);
            let next_size = size + row.bytes.len() + 2;
            if next_size > max_bytes || (taken > 0 && (taken + 1) * next_cols > OLDER_CELL_BUDGET) {
                break;
            }
            taken += 1;
            cols = next_cols;
            size = next_size;
        }
        if taken == 0 {
            return None;
        }
        let first_stable_row = before - taken as u64;
        let mut bytes = Vec::with_capacity(size);
        bytes.extend_from_slice(
            format!("\x1b]7000;v=1;history={first_stable_row},{taken};cols={cols}\x1b\\")
                .as_bytes(),
        );
        for row in &rows[rows.len() - taken..] {
            bytes.extend_from_slice(&row.bytes);
            bytes.extend_from_slice(b"\r\n");
        }
        Some(OlderChunk {
            first_stable_row,
            rows: taken,
            bytes,
        })
    }

    pub fn older_state(&self) -> OlderState {
        self.older
    }
}
