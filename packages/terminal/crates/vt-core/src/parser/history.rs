use crate::block::{Block, BlockMeta, BlockSource, BlockState};
use crate::limits::Limits;
use crate::row_index::RowRange;
use crate::style::CellStyle;

use super::{HistoryBlock, HistoryRow, Parser};

impl Parser {
    pub fn adopt_origin(&mut self, origin: u64) -> bool {
        if self.trimmed_total != 0
            || !self.rows.completed().is_empty()
            || self.screen.frame_rows() != 0
        {
            return false;
        }
        self.trimmed_total = origin;
        self.reset_cold_ring();
        self.grid.advance_origin(origin as usize);
        self.note_mutation();
        true
    }

    pub fn apply_history_chunk(
        &mut self,
        first_stable_row: u64,
        rows: Vec<HistoryRow>,
        blocks: Vec<HistoryBlock>,
    ) -> bool {
        if rows.is_empty() || first_stable_row + rows.len() as u64 != self.trimmed_total {
            return false;
        }
        let mut bytes = Vec::new();
        let mut lengths = Vec::with_capacity(rows.len());
        for row in &rows {
            bytes.extend_from_slice(&row.bytes);
            lengths.push(row.bytes.len() as u64);
        }
        let head = self
            .rows
            .completed()
            .front()
            .map_or(self.rows.open_start(), |row| row.start);
        self.content.trim_front_to(head);
        let base = self.content.prepend(&bytes);
        let mut runs: Vec<(u64, CellStyle)> = Vec::new();
        let mut ranges = Vec::with_capacity(rows.len());
        let mut cursor = base;
        for (row, length) in rows.iter().zip(lengths) {
            for (end, style) in &row.styles {
                runs.push((cursor + u64::from(*end), *style));
            }
            ranges.push(RowRange {
                start: cursor,
                end: cursor + length,
                wrapped: row.wrapped && length > 0,
                indent: row.indent,
            });
            cursor += length;
        }
        self.styles.prepend_runs(&runs);
        let count = ranges.len();
        self.rows.prepend(ranges);
        self.trimmed_total = first_stable_row;
        self.reset_cold_ring();
        self.grid.retreat_origin(count);
        let history_blocks: Vec<Block> = blocks
            .into_iter()
            .map(|block| self.history_block(first_stable_row, block))
            .collect();
        self.grid.prepend_blocks(history_blocks);
        self.history_exported_rows = 0;
        self.mark_full();
        self.note_mutation();
        true
    }

    fn history_block(&mut self, first_stable_row: u64, block: HistoryBlock) -> Block {
        let id = self.grid.next_id();
        self.grid.reserve_id();
        let meta = BlockMeta {
            command: block.command,
            ..BlockMeta::default()
        };
        Block {
            id,
            first_row: (first_stable_row as usize) + block.first_row,
            row_count: block.row_count,
            state: BlockState::Finished,
            source: BlockSource::Extension,
            meta,
        }
    }

    pub(crate) fn mark_history_stale(&mut self, rows: usize, cut_at: usize) {
        self.rows.mark_stale(0, rows, cut_at);
    }

    pub fn trim_to(&mut self, limits: Limits) -> usize {
        let before = self.rows.completed().len();
        loop {
            let completed = self.rows.completed().len();
            let over_rows = completed + 1 > limits.rows;
            let over_bytes = self.content.resident_bytes() + self.styles.byte_len() > limits.bytes;
            if completed == 0 || !(over_rows || over_bytes) {
                break;
            }
            let keep = if over_rows { limits.rows } else { completed };
            let spilled = (completed + 1).saturating_sub(keep).min(completed);
            let first = self.trimmed_total + (before - completed) as u64;
            self.spill_to_cold(first, spilled);
            let Some(new_start) = self.rows.trim_to(keep) else {
                break;
            };
            self.content.drop_before(new_start);
            self.styles.drop_before(new_start);
        }
        let dropped = before - self.rows.completed().len();
        if dropped > 0 {
            let exported_dropped = dropped.min(self.history_exported_rows);
            self.history_exported_rows -= exported_dropped;
            self.pending_trimmed += exported_dropped;
            self.trimmed_total += dropped as u64;
            self.grid.advance_origin(dropped);
        }
        dropped
    }
}
