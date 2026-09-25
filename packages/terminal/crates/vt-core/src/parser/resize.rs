use crate::line_editor::LineEditorState;

use super::Parser;

impl Parser {
    pub fn resize(&mut self, columns: usize, rows: usize) {
        self.note_width(columns);
        if self.alt.is_some() {
            self.screen.resize_without_reflow(rows, columns);
        } else {
            self.screen.resize(rows, columns);
            self.commit_evicted();
        }
        if let Some(alt) = self.alt.as_mut() {
            alt.resize(rows, columns);
        }
        self.grid
            .clamp_to_rows(self.rows.completed().len() + self.screen.rows());
        self.send_in_band_report();
    }

    pub(crate) fn resize_for(&mut self, columns: usize, rows: usize, editor: LineEditorState) {
        if editor == LineEditorState::Owned
            && self.alt.is_none()
            && self.resize_at_prompt(columns, rows)
        {
            return;
        }
        self.resize(columns, rows);
    }

    fn note_width(&mut self, columns: usize) {
        self.mark_full();
        if columns != self.width {
            self.rewrap_pending = true;
        }
        self.last_width = self.width;
        self.width = columns;
    }

    fn resize_at_prompt(&mut self, columns: usize, rows: usize) -> bool {
        let completed = self.rows.completed().len();
        let prompt_row = self
            .grid
            .open_block_ref()
            .map(|block| self.grid.flat_extent(block).0.saturating_sub(completed));
        if self
            .screen
            .resize_keeping_prompt(rows, columns, prompt_row)
            .is_none()
        {
            return false;
        }
        self.note_width(columns);
        self.commit_evicted();
        self.grid
            .clamp_to_rows(self.rows.completed().len() + self.screen.rows());
        self.send_in_band_report();
        true
    }
}
