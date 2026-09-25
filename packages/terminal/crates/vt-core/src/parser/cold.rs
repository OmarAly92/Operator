use crate::cold_ring::{ColdRing, ColdRow, ColdStats};
use crate::row_index::RowRange;
use crate::width::{clusters, WidthMode};

use super::Parser;

impl Parser {
    pub fn set_cold_ring_bytes(&mut self, cap: usize) {
        self.cold = ColdRing::new(cap, self.trimmed_total);
    }

    pub fn cold_stats(&self) -> ColdStats {
        self.cold.stats()
    }

    pub fn cold_floor(&self) -> Option<u64> {
        if !self.cold.is_enabled() {
            return None;
        }
        if self.cold.is_empty() {
            Some(self.trimmed_total)
        } else {
            Some(self.cold.first_stable())
        }
    }

    pub(crate) fn reset_cold_ring(&mut self) {
        self.cold.reset_at(self.trimmed_total);
    }

    pub(crate) fn spill_to_cold(&mut self, first_stable: u64, count: usize) {
        if !self.cold.is_enabled() {
            return;
        }
        for index in 0..count {
            let Some(range) = self.rows.completed().get(index) else {
                return;
            };
            let row = self.cold_row(range);
            self.cold.push(first_stable + index as u64, &row);
        }
    }

    pub(crate) fn older_rows(&self, before: u64, max_rows: usize) -> Vec<ColdRow> {
        let front = self.trimmed_total;
        let completed = self.rows.completed();
        let bound = before.min(front + completed.len() as u64);
        if bound > front {
            let hi = (bound - front) as usize;
            let lo = hi.saturating_sub(max_rows);
            return (lo..hi)
                .filter_map(|index| completed.get(index))
                .map(|range| self.cold_row(range))
                .collect();
        }
        let hi = before.min(self.cold.end_stable());
        self.cold.rows(hi.saturating_sub(max_rows as u64)..hi)
    }

    fn cold_row(&self, range: &RowRange) -> ColdRow {
        let bytes = self.content.copy_range(range.start, range.end);
        let pairs = if bytes.is_empty() {
            Vec::new()
        } else {
            self.styles.runs(range.start, range.end)
        };
        let indent = usize::from(range.indent);
        let text = std::str::from_utf8(&bytes).unwrap_or("");
        let mut out = String::with_capacity(indent + bytes.len() + 8);
        out.extend(std::iter::repeat_n(' ', indent));
        let links = &self.hyperlinks;
        crate::style_sgr::write_styled_row_with(&mut out, &bytes, &pairs, &|id| links.uri(id), "");
        ColdRow {
            bytes: out.into_bytes(),
            cols: indent + text_cols(text),
        }
    }
}

fn text_cols(text: &str) -> usize {
    if text.is_ascii() {
        return text.len();
    }
    let width = |mode| clusters(text, mode).iter().map(|c| c.width).sum::<usize>();
    width(WidthMode::Scalar).max(width(WidthMode::Grapheme))
}
