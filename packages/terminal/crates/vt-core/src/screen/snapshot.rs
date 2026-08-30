use crate::screen::ScreenGrid;
use crate::style::StyleCode;

pub struct AltSnapshot {
    pub rows: usize,
    pub cols: usize,
    pub content: Vec<u8>,
    pub row_ranges: Vec<(u32, u32)>,
    pub run_ranges: Vec<(u32, u32)>,
    pub style_pairs: Vec<(u32, StyleCode)>,
    pub cursor_row: usize,
    pub cursor_col: usize,
    pub cursor_visible: bool,
}

impl ScreenGrid {
    pub fn snapshot(&self) -> AltSnapshot {
        let mut content: Vec<u8> = Vec::new();
        let mut row_ranges: Vec<(u32, u32)> = Vec::with_capacity(self.rows());
        let mut run_ranges: Vec<(u32, u32)> = Vec::with_capacity(self.rows());
        let mut style_pairs: Vec<(u32, StyleCode)> = Vec::new();
        let mut buffer = [0u8; 4];

        for row in 0..self.rows() {
            let row_start = content.len() as u32;
            let pair_start = style_pairs.len() as u32;
            let mut run_style: Option<StyleCode> = None;
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
                content.extend_from_slice(cell.text(&mut buffer).as_bytes());
            }
            let row_end = content.len() as u32;
            if let Some(style) = run_style {
                style_pairs.push((row_end - row_start, style));
            }
            row_ranges.push((row_start, row_end));
            run_ranges.push((pair_start, style_pairs.len() as u32));
        }

        let (cursor_row, cursor_col) = self.cursor();
        AltSnapshot {
            rows: self.rows(),
            cols: self.cols(),
            content,
            row_ranges,
            run_ranges,
            style_pairs,
            cursor_row,
            cursor_col,
            cursor_visible: self.cursor_visible(),
        }
    }
}
