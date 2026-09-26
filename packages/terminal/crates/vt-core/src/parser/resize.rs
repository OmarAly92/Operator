use crate::attribute_map::AttributeMap;
use crate::content::Content;
use crate::line_editor::LineEditorState;
use crate::row_index::{RowIndex, RowRange};
use crate::screen::Cell;
use crate::style::CellStyle;
use crate::width::clusters;

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
        let before = self.content.end_offset();
        let completed = self.rows.completed().len();
        let prompt_row = self
            .grid
            .open_block_ref()
            .map(|block| self.grid.flat_extent(block).0.saturating_sub(completed));
        let Some(wanted) = self.screen.resize_keeping_prompt(rows, columns, prompt_row) else {
            return false;
        };
        self.note_width(columns);
        self.commit_evicted();
        self.pull_back(wanted, before);
        self.grid
            .clamp_to_rows(self.rows.completed().len() + self.screen.rows());
        self.send_in_band_report();
        true
    }

    fn pull_back(&mut self, wanted: usize, before: u64) {
        let stale_end = self
            .rows
            .stale_runs()
            .iter()
            .map(|run| run.start + run.len)
            .max()
            .unwrap_or(0);
        let mut pulled = Vec::new();
        while pulled.len() < wanted && self.rows.completed().len() > stale_end {
            let Some(row) = self.rows.completed().back().cloned() else {
                break;
            };
            let Some(cells) = self.row_cells(&row) else {
                break;
            };
            self.rows.pop_completed();
            self.content.truncate_to(row.start);
            self.styles.truncate_to(row.start);
            pulled.push((cells, row.wrapped));
        }
        if pulled.is_empty() {
            return;
        }
        let cut = self.content.end_offset();
        if cut < before {
            self.content.note_reuse(cut);
        }
        pulled.reverse();
        self.screen.push_rows_on_top(pulled);
        let completed = self.rows.completed().len();
        self.history_exported_rows = self.history_exported_rows.min(completed);
        self.pending_rewritten_from = Some(
            self.pending_rewritten_from
                .unwrap_or(usize::MAX)
                .min(completed),
        );
    }

    fn row_cells(&self, row: &RowRange) -> Option<Vec<Cell>> {
        if row.indent != 0 {
            return None;
        }
        let bytes = self.content.copy_range(row.start, row.end);
        let text = std::str::from_utf8(&bytes).ok()?;
        let runs = self.styles.runs(row.start, row.end);
        let cols = self.screen.cols();
        let mut cells = Vec::with_capacity(cols);
        let mut run = 0usize;
        for cluster in clusters(text, self.width_mode) {
            if cluster.width == 0 {
                return None;
            }
            while runs
                .get(run)
                .is_some_and(|(end, _)| *end as usize <= cluster.start)
            {
                run += 1;
            }
            let style = runs
                .get(run)
                .map_or(CellStyle::DEFAULT, |(_, style)| *style);
            let mut scalars = text[cluster.start..cluster.end].chars();
            let mut cell = Cell::new(scalars.next()?, style);
            for scalar in scalars {
                cell.append_scalar(scalar);
            }
            cells.push(cell);
            for _ in 1..cluster.width.min(2) {
                cells.push(Cell::new('\0', style));
            }
        }
        if cells.len() > cols {
            return None;
        }
        cells.resize(cols, Cell::BLANK);
        let mut content = Content::with_base(0);
        let mut index = RowIndex::new(0);
        let mut styles = AttributeMap::with_base(CellStyle::DEFAULT, 0);
        crate::scrollback::commit_row(&cells, row.wrapped, &mut content, &mut index, &mut styles);
        let end = content.end_offset();
        (content.copy_range(0, end) == bytes && styles.runs(0, end) == runs).then_some(cells)
    }
}
