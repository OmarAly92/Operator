use vt_core::{BlockRecord, Delta, DeltaKind, ExportedRow, GridSnapshot, TerminalCore};

/// The buffers are kept between frames and patched rather than rebuilt, after
/// Ghostty's `RenderState` (`src/terminal/render.zig:72`).
pub const COMPACTION_DIVISOR: usize = 4;

/// Words each `BlockRecord` flattens to in the `blocks` buffer.
///
/// The TypeScript side pins the same constant and strides its `Uint32Array` by
/// it, so the two must never drift apart.
pub const BLOCK_RECORD_WORDS: usize = 18;

pub const FIND_MATCH_WORDS: usize = 6;

pub const STYLE_RUN_WORDS: usize = 6;

pub const CELL_SPAN_WORDS: usize = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportError {
    OffsetOverflow,
    FindOffsetOverflow,
}

/// Narrows a byte count to the `u32` the JavaScript views index with.
///
/// `refresh` uses it on the content length: `GridSnapshot` row offsets are
/// already checked `u32`s, but the flat content buffer is a `usize` that the
/// TypeScript side addresses as `u32`, so it needs its own guard.
pub fn checked_u32_from_u64(value: u64) -> Result<u32, ExportError> {
    u32::try_from(value).map_err(|_| ExportError::OffsetOverflow)
}

#[derive(Default)]
pub struct ExportBuffers {
    content: Vec<u8>,
    rows: Vec<u32>,
    row_indents: Vec<u16>,
    row_wrapped: Vec<u8>,
    run_ranges: Vec<u32>,
    style_pairs: Vec<u32>,
    span_ranges: Vec<u32>,
    cell_spans: Vec<u32>,
    blocks: Vec<u32>,
    block_text: Vec<u8>,
    link_text: Vec<u8>,
    link_ranges: Vec<u32>,
    links_exported: usize,
    line_editor_state: u32,
    cursor_row: u32,
    cursor_col: u32,
    cursor_visible: bool,
    first_stable_row: u64,
    alt_active: bool,
    alt_rows: u32,
    alt_cols: u32,
    alt_cursor_row: u32,
    alt_cursor_col: u32,
    alt_cursor_visible: bool,
    alt_content: Vec<u8>,
    alt_row_ranges: Vec<u32>,
    alt_run_ranges: Vec<u32>,
    alt_style_pairs: Vec<u32>,
    alt_span_ranges: Vec<u32>,
    alt_cell_spans: Vec<u32>,
    dead_rows: usize,
    dead_bytes: usize,
    dead_pairs: usize,
    dead_spans: usize,
    history_rows: usize,
    history_end: usize,
    history_pairs: usize,
    history_spans: usize,
}

impl ExportBuffers {
    pub fn refresh(&mut self, snapshot: &GridSnapshot) -> Result<(), ExportError> {
        self.content.clear();
        self.rows.clear();
        self.row_indents.clear();
        self.row_wrapped.clear();
        self.run_ranges.clear();
        self.style_pairs.clear();
        self.span_ranges.clear();
        self.cell_spans.clear();
        self.blocks.clear();
        self.block_text.clear();
        self.link_text.clear();
        self.link_ranges.clear();
        self.line_editor_state = snapshot.line_editor_state;
        self.cursor_row = snapshot.cursor_row;
        self.cursor_col = snapshot.cursor_col;
        self.cursor_visible = snapshot.cursor_visible;
        self.first_stable_row = snapshot.first_stable_row;
        self.clear_alt();

        checked_u32_from_u64(snapshot.content.len() as u64)?;
        self.content.extend_from_slice(snapshot.content.as_slice());

        for &(start, end) in &snapshot.rows {
            self.rows.push(start);
            self.rows.push(end);
        }
        self.row_indents.extend_from_slice(&snapshot.row_indents);
        self.row_wrapped
            .extend(snapshot.row_wrapped.iter().map(|&w| u8::from(w)));

        for &(start, end) in &snapshot.run_ranges {
            self.run_ranges.push(start);
            self.run_ranges.push(end);
        }

        for &(end, style) in &snapshot.style_pairs {
            self.style_pairs.push(end);
            self.style_pairs.push(style.fg.value());
            self.style_pairs.push(style.bg.value());
            self.style_pairs.push(u32::from(style.attrs.bits()));
            self.style_pairs.push(style.underline.value());
            self.style_pairs.push(u32::from(style.link));
        }

        for &(start, end) in &snapshot.span_ranges {
            self.span_ranges.push(start);
            self.span_ranges.push(end);
        }

        for &span in &snapshot.cell_spans {
            self.cell_spans.push(span.start);
            self.cell_spans.push(span.end);
            self.cell_spans.push(u32::from(span.width));
        }

        if let Some(alt) = snapshot.alt.as_ref() {
            self.alt_active = true;
            self.alt_rows = alt.rows as u32;
            self.alt_cols = alt.cols as u32;
            self.alt_cursor_row = alt.cursor_row as u32;
            self.alt_cursor_col = alt.cursor_col as u32;
            self.alt_cursor_visible = alt.cursor_visible;
            self.alt_content.extend_from_slice(&alt.content);
            for &(start, end) in &alt.row_ranges {
                self.alt_row_ranges.push(start);
                self.alt_row_ranges.push(end);
            }
            for &(start, end) in &alt.run_ranges {
                self.alt_run_ranges.push(start);
                self.alt_run_ranges.push(end);
            }
            for &(end, style) in &alt.style_pairs {
                self.alt_style_pairs.push(end);
                self.alt_style_pairs.push(style.fg.value());
                self.alt_style_pairs.push(style.bg.value());
                self.alt_style_pairs.push(u32::from(style.attrs.bits()));
                self.alt_style_pairs.push(style.underline.value());
                self.alt_style_pairs.push(u32::from(style.link));
            }
            for &(start, end) in &alt.span_ranges {
                self.alt_span_ranges.push(start);
                self.alt_span_ranges.push(end);
            }
            for &span in &alt.cell_spans {
                self.alt_cell_spans.push(span.start);
                self.alt_cell_spans.push(span.end);
                self.alt_cell_spans.push(u32::from(span.width));
            }
        }

        self.write_blocks(&snapshot.blocks, &snapshot.block_text)?;

        for &(start, end) in &snapshot.link_ranges {
            self.link_ranges.push(start);
            self.link_ranges.push(end);
        }
        self.link_text.extend_from_slice(&snapshot.link_text);
        self.links_exported = snapshot.link_ranges.len();

        self.dead_rows = 0;
        self.dead_bytes = 0;
        self.dead_pairs = 0;
        self.dead_spans = 0;
        self.history_rows = snapshot.history_rows as usize;
        self.history_end = if self.history_rows == 0 {
            0
        } else {
            self.rows[self.history_rows * 2 - 1] as usize
        };
        self.history_pairs = if self.history_rows == 0 {
            0
        } else {
            self.run_ranges[self.history_rows * 2 - 1] as usize
        };
        self.history_spans = if self.history_rows == 0 {
            0
        } else {
            self.span_ranges[self.history_rows * 2 - 1] as usize
        };

        Ok(())
    }

    pub fn apply(&mut self, core: &TerminalCore, delta: &Delta) -> Result<(), ExportError> {
        if delta.kind == DeltaKind::Full {
            let snapshot = core.snapshot().map_err(|_| ExportError::OffsetOverflow)?;
            return self.refresh(&snapshot);
        }
        self.drop_front(delta.trimmed_rows);
        self.truncate_screen();
        match delta.history_rewritten_from {
            Some(from) => self.rewrite_history_from(core, from)?,
            None => {
                for row in core.export_history_rows(delta.appended_history.clone()) {
                    self.push_row(&row)?;
                    self.history_rows += 1;
                }
            }
        }
        self.history_end = self.content.len();
        self.history_pairs = self.style_pairs.len() / STYLE_RUN_WORDS;
        self.history_spans = self.cell_spans.len() / CELL_SPAN_WORDS;
        for row in core.export_screen_rows() {
            self.push_row(&row)?;
        }
        let total_rows = self.rows.len() / 2 - self.dead_rows;
        let live_rows = &self.rows[self.dead_rows * 2..];
        let (records, text) = core
            .export_blocks(total_rows, |row| {
                live_rows[row * 2 + 1] > live_rows[row * 2]
            })
            .map_err(|_| ExportError::OffsetOverflow)?;
        self.write_blocks(&records, &text)?;
        for id in (self.links_exported + 1)..=core.hyperlink_count() {
            let uri = core.hyperlink_uri(id as u16).unwrap_or("");
            let start = checked_u32_from_u64(self.link_text.len() as u64)?;
            self.link_text.extend_from_slice(uri.as_bytes());
            self.link_ranges.push(start);
            self.link_ranges
                .push(checked_u32_from_u64(self.link_text.len() as u64)?);
        }
        self.links_exported = core.hyperlink_count();
        let (cursor_row, cursor_col, cursor_visible) = core.export_cursor();
        self.cursor_row = checked_u32_from_u64(cursor_row as u64)?;
        self.cursor_col = checked_u32_from_u64(cursor_col as u64)?;
        self.cursor_visible = cursor_visible;
        self.line_editor_state = core.line_editor_state().wire();
        self.first_stable_row = core.first_stable_row();
        self.clear_alt();
        self.maybe_compact();
        Ok(())
    }

    fn drop_front(&mut self, trimmed: usize) {
        if trimmed == 0 {
            return;
        }
        let trimmed = trimmed.min(self.history_rows);
        self.dead_rows += trimmed;
        self.history_rows -= trimmed;
        let first_live = self.dead_rows * 2;
        self.dead_bytes = if self.history_rows > 0 {
            self.rows[first_live] as usize
        } else {
            self.history_end
        };
        self.dead_pairs = if self.history_rows > 0 {
            self.run_ranges[first_live] as usize
        } else {
            self.history_pairs
        };
        self.dead_spans = if self.history_rows > 0 {
            self.span_ranges[first_live] as usize
        } else {
            self.history_spans
        };
    }

    fn rewrite_history_from(
        &mut self,
        core: &TerminalCore,
        from: usize,
    ) -> Result<(), ExportError> {
        let from = from.min(self.history_rows);
        let cut_row = self.dead_rows + from;
        let cut_bytes = if cut_row == 0 {
            0
        } else {
            self.rows[cut_row * 2 - 1] as usize
        };
        let cut_pairs = if cut_row == 0 {
            0
        } else {
            self.run_ranges[cut_row * 2 - 1] as usize
        };
        let cut_spans = if cut_row == 0 {
            0
        } else {
            self.span_ranges[cut_row * 2 - 1] as usize
        };
        self.content.truncate(cut_bytes);
        self.rows.truncate(cut_row * 2);
        self.row_indents.truncate(cut_row);
        self.row_wrapped.truncate(cut_row);
        self.run_ranges.truncate(cut_row * 2);
        self.style_pairs.truncate(cut_pairs * STYLE_RUN_WORDS);
        self.span_ranges.truncate(cut_row * 2);
        self.cell_spans.truncate(cut_spans * CELL_SPAN_WORDS);
        self.history_rows = cut_row - self.dead_rows;
        let core_history_rows = core.history_rows();
        let from = from.min(core_history_rows);
        for row in core.export_history_rows(from..core_history_rows) {
            self.push_row(&row)?;
            self.history_rows += 1;
        }
        Ok(())
    }

    fn truncate_screen(&mut self) {
        let keep_rows = self.dead_rows + self.history_rows;
        self.content.truncate(self.history_end);
        self.rows.truncate(keep_rows * 2);
        self.row_indents.truncate(keep_rows);
        self.row_wrapped.truncate(keep_rows);
        self.run_ranges.truncate(keep_rows * 2);
        self.style_pairs
            .truncate(self.history_pairs * STYLE_RUN_WORDS);
        self.span_ranges.truncate(keep_rows * 2);
        self.cell_spans
            .truncate(self.history_spans * CELL_SPAN_WORDS);
    }

    fn push_row(&mut self, row: &ExportedRow) -> Result<(), ExportError> {
        let content_base = checked_u32_from_u64(self.content.len() as u64)?;
        let content_end = checked_u32_from_u64((self.content.len() + row.bytes.len()) as u64)?;
        self.content.extend_from_slice(&row.bytes);
        self.rows.push(content_base);
        self.rows.push(content_end);
        self.row_indents.push(row.indent);
        self.row_wrapped.push(u8::from(row.wrapped));
        let pair_start = checked_u32_from_u64((self.style_pairs.len() / STYLE_RUN_WORDS) as u64)?;
        for &(end, style) in &row.styles {
            self.style_pairs.push(end);
            self.style_pairs.push(style.fg.value());
            self.style_pairs.push(style.bg.value());
            self.style_pairs.push(u32::from(style.attrs.bits()));
            self.style_pairs.push(style.underline.value());
            self.style_pairs.push(u32::from(style.link));
        }
        let pair_end = checked_u32_from_u64((self.style_pairs.len() / STYLE_RUN_WORDS) as u64)?;
        self.run_ranges.push(pair_start);
        self.run_ranges.push(pair_end);

        let span_start = checked_u32_from_u64((self.cell_spans.len() / CELL_SPAN_WORDS) as u64)?;
        for &span in &row.spans {
            self.cell_spans.push(span.start);
            self.cell_spans.push(span.end);
            self.cell_spans.push(u32::from(span.width));
        }
        let span_end = checked_u32_from_u64((self.cell_spans.len() / CELL_SPAN_WORDS) as u64)?;
        self.span_ranges.push(span_start);
        self.span_ranges.push(span_end);
        Ok(())
    }

    fn clear_alt(&mut self) {
        self.alt_active = false;
        self.alt_rows = 0;
        self.alt_cols = 0;
        self.alt_cursor_row = 0;
        self.alt_cursor_col = 0;
        self.alt_cursor_visible = false;
        self.alt_content.clear();
        self.alt_row_ranges.clear();
        self.alt_run_ranges.clear();
        self.alt_style_pairs.clear();
        self.alt_span_ranges.clear();
        self.alt_cell_spans.clear();
    }

    fn maybe_compact(&mut self) {
        let live_rows = self.rows.len() / 2 - self.dead_rows;
        let live_bytes = self.content.len() - self.dead_bytes;
        if self.dead_rows * COMPACTION_DIVISOR > live_rows.max(1)
            || self.dead_bytes * COMPACTION_DIVISOR > live_bytes.max(1)
        {
            self.compact();
        }
    }

    pub fn compact(&mut self) {
        if self.dead_rows == 0 && self.dead_bytes == 0 {
            return;
        }
        let dead_bytes = self.dead_bytes as u32;
        let dead_pairs = self.dead_pairs as u32;
        let dead_spans = self.dead_spans as u32;
        self.content.drain(..self.dead_bytes);
        self.rows.drain(..self.dead_rows * 2);
        for offset in &mut self.rows {
            *offset -= dead_bytes;
        }
        self.row_indents.drain(..self.dead_rows);
        self.row_wrapped.drain(..self.dead_rows);
        self.run_ranges.drain(..self.dead_rows * 2);
        for index in &mut self.run_ranges {
            *index -= dead_pairs;
        }
        self.style_pairs.drain(..self.dead_pairs * STYLE_RUN_WORDS);
        self.span_ranges.drain(..self.dead_rows * 2);
        for index in &mut self.span_ranges {
            *index -= dead_spans;
        }
        self.cell_spans.drain(..self.dead_spans * CELL_SPAN_WORDS);
        self.history_end -= self.dead_bytes;
        self.history_pairs -= self.dead_pairs;
        self.history_spans -= self.dead_spans;
        self.dead_rows = 0;
        self.dead_bytes = 0;
        self.dead_pairs = 0;
        self.dead_spans = 0;
    }

    pub fn dead_rows(&self) -> usize {
        self.dead_rows
    }

    pub fn history_rows(&self) -> usize {
        self.history_rows
    }

    fn write_blocks(&mut self, records: &[BlockRecord], text: &[u8]) -> Result<(), ExportError> {
        self.blocks.clear();
        self.block_text.clear();

        for record in records {
            let before = self.blocks.len();

            self.blocks.push(record.id as u32);
            self.blocks.push((record.id >> 32) as u32);
            self.blocks.push(record.first_row);
            self.blocks.push(record.row_count);
            // Presence lives in a spare bit of the packed word so the exit word
            // can carry the raw two's-complement i32. Encoding presence as a
            // magic value instead collides with a real exit code and overflows
            // at i32::MAX -- and the exit parameter arrives from untrusted
            // terminal output, so neither is hypothetical.
            let has_exit = u32::from(record.exit_code.is_some());
            let bookmarked = u32::from(record.bookmarked);
            self.blocks.push(
                record.state.as_u32()
                    | (record.source.as_u32() << 8)
                    | (has_exit << 16)
                    | (bookmarked << 17),
            );
            self.blocks.push(record.exit_code.unwrap_or(0) as u32);
            let (duration_lo, duration_hi) = match record.duration_ms {
                None => (u32::MAX, u32::MAX),
                Some(ms) => (ms as u32, (ms >> 32) as u32),
            };
            self.blocks.push(duration_lo);
            self.blocks.push(duration_hi);
            self.blocks.push(record.command.start);
            self.blocks.push(record.command.end);
            self.blocks.push(record.cwd.start);
            self.blocks.push(record.cwd.end);
            self.blocks.push(record.git_branch.start);
            self.blocks.push(record.git_branch.end);
            for stamp in [record.started_at_ms, record.finished_at_ms] {
                let (lo, hi) = match stamp {
                    None => (u32::MAX, u32::MAX),
                    Some(ms) => (ms as u32, (ms >> 32) as u32),
                };
                self.blocks.push(lo);
                self.blocks.push(hi);
            }

            debug_assert_eq!(self.blocks.len() - before, BLOCK_RECORD_WORDS);
        }

        checked_u32_from_u64(text.len() as u64)?;
        self.block_text.extend_from_slice(text);

        Ok(())
    }

    pub fn content(&self) -> &[u8] {
        &self.content
    }

    pub fn rows(&self) -> &[u32] {
        &self.rows[self.dead_rows * 2..]
    }

    pub fn row_indents(&self) -> &[u16] {
        &self.row_indents[self.dead_rows..]
    }

    pub fn row_wrapped(&self) -> &[u8] {
        &self.row_wrapped[self.dead_rows..]
    }

    pub fn run_ranges(&self) -> &[u32] {
        &self.run_ranges[self.dead_rows * 2..]
    }

    pub fn style_pairs(&self) -> &[u32] {
        &self.style_pairs
    }

    pub fn span_ranges(&self) -> &[u32] {
        &self.span_ranges[self.dead_rows * 2..]
    }

    pub fn cell_spans(&self) -> &[u32] {
        &self.cell_spans
    }

    pub fn blocks(&self) -> &[u32] {
        &self.blocks
    }

    pub fn block_text(&self) -> &[u8] {
        &self.block_text
    }

    pub fn link_text(&self) -> &[u8] {
        &self.link_text
    }

    pub fn link_ranges(&self) -> &[u32] {
        &self.link_ranges
    }

    pub fn line_editor_state(&self) -> u32 {
        self.line_editor_state
    }

    pub fn cursor_row(&self) -> u32 {
        self.cursor_row
    }

    pub fn cursor_col(&self) -> u32 {
        self.cursor_col
    }

    pub fn cursor_visible(&self) -> bool {
        self.cursor_visible
    }

    pub fn first_stable_row(&self) -> u64 {
        self.first_stable_row
    }

    pub fn alt_active(&self) -> bool {
        self.alt_active
    }

    pub fn alt_rows(&self) -> u32 {
        self.alt_rows
    }

    pub fn alt_cols(&self) -> u32 {
        self.alt_cols
    }

    pub fn alt_cursor_row(&self) -> u32 {
        self.alt_cursor_row
    }

    pub fn alt_cursor_col(&self) -> u32 {
        self.alt_cursor_col
    }

    pub fn alt_cursor_visible(&self) -> bool {
        self.alt_cursor_visible
    }

    pub fn alt_content(&self) -> &[u8] {
        &self.alt_content
    }

    pub fn alt_row_ranges(&self) -> &[u32] {
        &self.alt_row_ranges
    }

    pub fn alt_run_ranges(&self) -> &[u32] {
        &self.alt_run_ranges
    }

    pub fn alt_style_pairs(&self) -> &[u32] {
        &self.alt_style_pairs
    }

    pub fn alt_span_ranges(&self) -> &[u32] {
        &self.alt_span_ranges
    }

    pub fn alt_cell_spans(&self) -> &[u32] {
        &self.alt_cell_spans
    }
}
