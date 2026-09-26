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
        if self.screen.cursor().1 == 0
            && self
                .grid
                .repaint_open_prompt(first_row, self.nothing_drawn_below_open_prompt(first_row))
        {
            return;
        }
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
        self.program.reset_for_new_process();
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

    pub(crate) fn erase_saved_lines(&mut self) {
        self.commit_evicted();
        let owned = self
            .grid
            .covered_end()
            .saturating_sub(self.rows.completed().len());
        for row in owned..self.screen.rows() {
            self.screen.blank_row(row);
        }
    }

    pub(crate) fn note_input_ready(&mut self) {
        self.commit_evicted();
        let row = self.block_start_row();
        self.input_mark = self.grid.open_block_ref().and_then(|block| {
            row.checked_sub(self.grid.flat_extent(block).0)
                .map(|offset| (block.id, offset))
        });
    }

    pub(crate) fn note_command_start(&mut self) {
        self.commit_evicted();
        let row = self.block_start_row();
        self.command_start_mark = self.grid.open_block_ref().and_then(|block| {
            row.checked_sub(self.grid.flat_extent(block).0)
                .map(|offset| (block.id, offset))
        });
    }

    fn nothing_drawn_below_open_prompt(&self, first_row: usize) -> bool {
        let Some(block) = self.grid.open_block_ref() else {
            return false;
        };
        let start = self.grid.flat_extent(block).0;
        let drawn_end = match self.command_start_mark {
            Some((id, offset)) if id == block.id => start + offset + 1,
            _ => start,
        };
        first_row <= drawn_end || !self.rows_have_content(drawn_end, first_row)
    }

    pub(crate) fn open_prompt(&self) -> Option<(usize, usize, &crate::block::BlockMeta)> {
        let block = self.grid.open_block_ref()?;
        let first = self.grid.flat_extent(block).0;
        let input = match self.input_mark {
            Some((id, offset)) if id == block.id => first + offset,
            _ => first,
        };
        Some((first, input, &block.meta))
    }

    pub(crate) fn running_command(&self) -> Option<(usize, usize, &crate::block::BlockMeta)> {
        if !self.grid.open_output_started() {
            return None;
        }
        let block = self.grid.open_block_ref()?;
        let output = self.grid.flat_extent(block).0;
        Some((self.grid.closed_end().min(output), output, &block.meta))
    }

    pub(crate) fn start_output(&mut self) {
        self.printed_since_output_start = false;
        self.commit_evicted();
        self.grid.start_output(self.block_start_row());
    }

    pub(crate) fn close_block(&mut self, exit_code: Option<i32>) {
        if self.alt.is_none()
            && self.grid.has_open_block()
            && std::mem::take(&mut self.printed_since_output_start)
            && (self.screen.cursor().1 > 0 || self.screen.pending_wrap())
        {
            self.screen.next_line();
        }
        self.commit_evicted();
        let point = self.alt.is_none().then(|| {
            let (row, col) = self.screen.cursor();
            let col = if self.screen.pending_wrap() {
                col + 1
            } else {
                col
            };
            (self.rows.completed().len() + row, col)
        });
        let (row, _) = self.screen.cursor();
        let continues_above = match row.checked_sub(1) {
            Some(above) => self.screen.row_wrapped(above),
            None => self
                .rows
                .completed()
                .back()
                .is_some_and(|range| range.wrapped),
        };
        self.grid.note_command_end(point, !continues_above);
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
