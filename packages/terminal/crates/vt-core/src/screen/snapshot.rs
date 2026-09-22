use crate::grid::CellSpan;
use crate::screen::ScreenGrid;
use crate::style::CellStyle;

pub struct AltSnapshot {
    pub rows: usize,
    pub cols: usize,
    pub content: Vec<u8>,
    pub row_ranges: Vec<(u32, u32)>,
    pub run_ranges: Vec<(u32, u32)>,
    pub style_pairs: Vec<(u32, CellStyle)>,
    pub span_ranges: Vec<(u32, u32)>,
    pub cell_spans: Vec<CellSpan>,
    pub cursor_row: usize,
    pub cursor_col: usize,
    pub cursor_visible: bool,
}

impl ScreenGrid {
    pub fn snapshot(&self) -> AltSnapshot {
        let mut content: Vec<u8> = Vec::new();
        let mut row_ranges: Vec<(u32, u32)> = Vec::with_capacity(self.rows());
        let mut run_ranges: Vec<(u32, u32)> = Vec::with_capacity(self.rows());
        let mut style_pairs: Vec<(u32, CellStyle)> = Vec::new();
        let mut span_ranges: Vec<(u32, u32)> = Vec::with_capacity(self.rows());
        let mut cell_spans: Vec<CellSpan> = Vec::new();
        let mut buffer = [0u8; 4];

        for row in 0..self.rows() {
            let row_start = content.len() as u32;
            let pair_start = style_pairs.len() as u32;
            let span_start = cell_spans.len() as u32;
            let mut run_style: Option<CellStyle> = None;
            for col in 0..self.cols() {
                let cell = self.cell(row, col);
                if cell.ch == '\0' {
                    continue;
                }
                if run_style != Some(cell.style) {
                    if let Some(previous) = run_style {
                        style_pairs.push((content.len() as u32 - row_start, previous));
                    }
                    run_style = Some(cell.style);
                }
                let start = content.len() as u32 - row_start;
                let text = cell.text(&mut buffer);
                content.extend_from_slice(text.as_bytes());
                let spacers = (col + 1..self.cols())
                    .take_while(|next| self.cell(row, *next).ch == '\0')
                    .count();
                let cell_width = 1 + spacers;
                if cell_width != 1 || text.chars().nth(1).is_some() {
                    cell_spans.push(CellSpan {
                        start,
                        end: content.len() as u32 - row_start,
                        width: cell_width as u8,
                    });
                }
            }
            let row_end = content.len() as u32;
            if let Some(style) = run_style {
                style_pairs.push((row_end - row_start, style));
            }
            row_ranges.push((row_start, row_end));
            run_ranges.push((pair_start, style_pairs.len() as u32));
            span_ranges.push((span_start, cell_spans.len() as u32));
        }

        let (cursor_row, cursor_col) = self.cursor();
        AltSnapshot {
            rows: self.rows(),
            cols: self.cols(),
            content,
            row_ranges,
            run_ranges,
            style_pairs,
            span_ranges,
            cell_spans,
            cursor_row,
            cursor_col,
            cursor_visible: self.cursor_visible(),
        }
    }
}
