use crate::block::{BlockSource, BlockState};
use crate::style::CellStyle;

use super::Parser;

impl Parser {
    pub(crate) fn set_clock(&mut self, now_ms: u64) {
        self.grid.set_clock(now_ms);
    }

    pub(crate) fn note_output(&mut self) {
        self.grid.note_output();
    }

    pub(crate) fn open_block(&mut self, source: BlockSource) {
        self.commit_evicted();
        let first_row = self.block_start_row();
        self.materialize_uncovered_rows(first_row, BlockState::Abandoned, None);
        self.grid.sync_next_row(first_row);
        self.grid.open_block(source);
    }

    pub(crate) fn process_boundary(&mut self, exit_code: Option<i32>) {
        self.mark_full();
        if self.alt.is_some() {
            self.leave_alt();
        }
        self.commit_evicted();
        let end_row = self.rows.completed().len() + self.screen.frame_rows();
        if self.grid.has_open_block() {
            self.grid.sync_next_row(end_row);
            self.grid.close_block(exit_code);
        } else {
            self.materialize_uncovered_rows(end_row, BlockState::Finished, exit_code);
        }
        self.screen.evict_frame();
        self.commit_evicted();
        self.grid.sync_next_row(self.rows.completed().len());
        self.pending_style = CellStyle::DEFAULT;
        self.sync_erase_background();
    }

    fn materialize_uncovered_rows(
        &mut self,
        end_row: usize,
        state: BlockState,
        exit_code: Option<i32>,
    ) {
        if self.grid.has_open_block() {
            return;
        }
        let first_row = self.grid.covered_end();
        if end_row > first_row && self.rows_have_content(first_row, end_row) {
            self.grid
                .push_synthetic(first_row, end_row, state, exit_code);
        }
    }

    fn rows_have_content(&self, first_row: usize, end_row: usize) -> bool {
        let completed = self.rows.completed();
        (first_row..end_row).any(|row| match completed.get(row) {
            Some(range) => range.end > range.start,
            None => self.screen.row_has_content(row - completed.len()),
        })
    }

    pub(crate) fn start_output(&mut self) {
        self.commit_evicted();
        self.grid.start_output(self.block_start_row());
    }

    pub(crate) fn close_block(&mut self, exit_code: Option<i32>) {
        self.commit_evicted();
        let next_row = self.block_end_row();
        self.grid.sync_next_row(next_row);
        self.grid.close_block(exit_code);
    }

    fn block_start_row(&self) -> usize {
        let screen_rows = self.screen.content_rows();
        self.rows.completed().len() + self.screen.cursor().0.min(screen_rows)
    }

    fn block_end_row(&self) -> usize {
        let screen_rows = self.screen.content_rows();
        let cursor_row = self.screen.cursor().0.min(screen_rows);
        let visible_cursor_row =
            usize::from(cursor_row < screen_rows && self.screen.row_has_content(cursor_row));
        self.rows.completed().len() + (cursor_row + visible_cursor_row).min(screen_rows)
    }
}
