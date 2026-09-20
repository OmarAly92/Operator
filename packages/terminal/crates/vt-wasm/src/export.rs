use vt_core::GridSnapshot;

/// Words each `BlockRecord` flattens to in the `blocks` buffer.
///
/// The TypeScript side pins the same constant and strides its `Uint32Array` by
/// it, so the two must never drift apart.
pub const BLOCK_RECORD_WORDS: usize = 14;

pub const FIND_MATCH_WORDS: usize = 5;

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
    run_ranges: Vec<u32>,
    style_pairs: Vec<u32>,
    blocks: Vec<u32>,
    block_text: Vec<u8>,
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
}

impl ExportBuffers {
    pub fn refresh(&mut self, snapshot: &GridSnapshot) -> Result<(), ExportError> {
        self.content.clear();
        self.rows.clear();
        self.row_indents.clear();
        self.run_ranges.clear();
        self.style_pairs.clear();
        self.blocks.clear();
        self.block_text.clear();
        self.line_editor_state = snapshot.line_editor_state;
        self.cursor_row = snapshot.cursor_row;
        self.cursor_col = snapshot.cursor_col;
        self.cursor_visible = snapshot.cursor_visible;
        self.first_stable_row = snapshot.first_stable_row;
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

        checked_u32_from_u64(snapshot.content.len() as u64)?;
        self.content.extend_from_slice(snapshot.content.as_slice());

        for &(start, end) in &snapshot.rows {
            self.rows.push(start);
            self.rows.push(end);
        }
        self.row_indents.extend_from_slice(&snapshot.row_indents);

        for &(start, end) in &snapshot.run_ranges {
            self.run_ranges.push(start);
            self.run_ranges.push(end);
        }

        for &(end, style) in &snapshot.style_pairs {
            self.style_pairs.push(end);
            self.style_pairs.push(style.fg.value());
            self.style_pairs.push(style.bg.value());
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
            }
        }

        for record in &snapshot.blocks {
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

            debug_assert_eq!(self.blocks.len() - before, BLOCK_RECORD_WORDS);
        }

        checked_u32_from_u64(snapshot.block_text.len() as u64)?;
        self.block_text
            .extend_from_slice(snapshot.block_text.as_slice());

        Ok(())
    }

    pub fn content(&self) -> &[u8] {
        &self.content
    }

    pub fn rows(&self) -> &[u32] {
        &self.rows
    }

    pub fn row_indents(&self) -> &[u16] {
        &self.row_indents
    }

    pub fn run_ranges(&self) -> &[u32] {
        &self.run_ranges
    }

    pub fn style_pairs(&self) -> &[u32] {
        &self.style_pairs
    }

    pub fn blocks(&self) -> &[u32] {
        &self.blocks
    }

    pub fn block_text(&self) -> &[u8] {
        &self.block_text
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
}
