use std::collections::HashMap;

use vt_core::{FindCursor, FindMatch, FindQuery, GridSnapshot, TerminalCore};
use wasm_bindgen::prelude::*;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

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
    run_ranges: Vec<u32>,
    style_pairs: Vec<u32>,
    blocks: Vec<u32>,
    block_text: Vec<u8>,
    line_editor_state: u32,
    cursor_row: u32,
    cursor_col: u32,
    cursor_visible: bool,
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
        self.run_ranges.clear();
        self.style_pairs.clear();
        self.blocks.clear();
        self.block_text.clear();
        self.line_editor_state = snapshot.line_editor_state;
        self.cursor_row = snapshot.cursor_row;
        self.cursor_col = snapshot.cursor_col;
        self.cursor_visible = snapshot.cursor_visible;
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

        for &(start, end) in &snapshot.run_ranges {
            self.run_ranges.push(start);
            self.run_ranges.push(end);
        }

        for &(end, code) in &snapshot.style_pairs {
            self.style_pairs.push(end);
            self.style_pairs.push(code.value());
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
            for &(end, code) in &alt.style_pairs {
                self.alt_style_pairs.push(end);
                self.alt_style_pairs.push(code.value());
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

#[wasm_bindgen]
pub struct WasmTerminalCore {
    core: TerminalCore,
    export: ExportBuffers,
    generation: u32,
    find_sessions: HashMap<u32, FindSession>,
    find_free_ids: Vec<u32>,
    find_next_id: u32,
    find_results: Vec<u32>,
}

#[wasm_bindgen]
impl WasmTerminalCore {
    #[wasm_bindgen(constructor)]
    pub fn new(columns: usize, scrollback_rows: usize) -> Result<WasmTerminalCore, JsError> {
        let core = TerminalCore::new(columns, scrollback_rows).map_err(js_error_from_core)?;
        let mut export = ExportBuffers::default();
        let snapshot = core.snapshot().map_err(js_error_from_core)?;
        export.refresh(&snapshot)?;
        Ok(WasmTerminalCore {
            core,
            export,
            generation: 0,
            find_sessions: HashMap::new(),
            find_free_ids: Vec::new(),
            find_next_id: 1,
            find_results: Vec::new(),
        })
    }

    pub fn feed(&mut self, bytes: &[u8]) -> Result<(), JsError> {
        self.core.feed(bytes);
        let snapshot = self.core.snapshot().map_err(js_error_from_core)?;
        self.export.refresh(&snapshot)?;
        self.generation = self.generation.wrapping_add(1);
        Ok(())
    }

    pub fn resize(&mut self, columns: usize, rows: usize) -> Result<(), JsError> {
        self.core.resize(columns, rows);
        let snapshot = self.core.snapshot().map_err(js_error_from_core)?;
        self.export.refresh(&snapshot)?;
        self.generation = self.generation.wrapping_add(1);
        Ok(())
    }

    #[wasm_bindgen(js_name = setAgentTuiMode)]
    pub fn set_agent_tui_mode(&mut self, on: bool) {
        self.core.set_agent_tui_mode(on);
    }

    pub fn set_block_bookmarked(&mut self, id_lo: u32, id_hi: u32, bookmarked: bool) -> Result<(), JsError> {
        let id = ((id_hi as u64) << 32) | (id_lo as u64);
        self.core.set_block_bookmarked(id, bookmarked);
        self.refresh_after_mutation()
    }

    pub fn block_bookmarked(&self, id_lo: u32, id_hi: u32) -> bool {
        let id = ((id_hi as u64) << 32) | (id_lo as u32 as u64);
        self.core.block_bookmarked(id)
    }

    fn refresh_after_mutation(&mut self) -> Result<(), JsError> {
        let snapshot = self.core.snapshot().map_err(js_error_from_core)?;
        self.export.refresh(&snapshot)?;
        self.generation = self.generation.wrapping_add(1);
        Ok(())
    }

    pub fn generation(&self) -> u32 {
        self.generation
    }

    pub fn content_ptr(&self) -> *const u8 {
        self.export.content().as_ptr()
    }

    pub fn content_len(&self) -> usize {
        self.export.content().len()
    }

    pub fn rows_ptr(&self) -> *const u32 {
        self.export.rows().as_ptr()
    }

    pub fn rows_len(&self) -> usize {
        self.export.rows().len()
    }

    pub fn run_ranges_ptr(&self) -> *const u32 {
        self.export.run_ranges().as_ptr()
    }

    pub fn run_ranges_len(&self) -> usize {
        self.export.run_ranges().len()
    }

    pub fn style_pairs_ptr(&self) -> *const u32 {
        self.export.style_pairs().as_ptr()
    }

    pub fn style_pairs_len(&self) -> usize {
        self.export.style_pairs().len()
    }

    pub fn blocks_ptr(&self) -> *const u32 {
        self.export.blocks().as_ptr()
    }

    pub fn blocks_len(&self) -> usize {
        self.export.blocks().len()
    }

    pub fn block_text_ptr(&self) -> *const u8 {
        self.export.block_text().as_ptr()
    }

    pub fn block_text_len(&self) -> usize {
        self.export.block_text().len()
    }

    pub fn line_editor_state(&self) -> u32 {
        self.export.line_editor_state()
    }

    pub fn cursor_row(&self) -> u32 {
        self.export.cursor_row()
    }

    pub fn cursor_col(&self) -> u32 {
        self.export.cursor_col()
    }

    pub fn cursor_visible(&self) -> bool {
        self.export.cursor_visible()
    }

    pub fn application_cursor_keys(&self) -> bool {
        self.core.application_cursor_keys()
    }

    pub fn sgr_mouse(&self) -> bool {
        self.core.sgr_mouse()
    }

    pub fn bracketed_paste(&self) -> bool {
        self.core.bracketed_paste()
    }

    pub fn focus_reporting(&self) -> bool {
        self.core.focus_reporting()
    }

    pub fn mouse_tracking(&self) -> bool {
        self.core.mouse_tracking()
    }

    pub fn mouse_tracking_level(&self) -> u8 {
        self.core.mouse_tracking_level()
    }

    pub fn alt_active(&self) -> bool {
        self.export.alt_active()
    }

    pub fn alt_rows(&self) -> u32 {
        self.export.alt_rows()
    }

    pub fn alt_cols(&self) -> u32 {
        self.export.alt_cols()
    }

    pub fn alt_cursor_row(&self) -> u32 {
        self.export.alt_cursor_row()
    }

    pub fn alt_cursor_col(&self) -> u32 {
        self.export.alt_cursor_col()
    }

    pub fn alt_cursor_visible(&self) -> bool {
        self.export.alt_cursor_visible()
    }

    pub fn alt_content_ptr(&self) -> *const u8 {
        self.export.alt_content().as_ptr()
    }

    pub fn alt_content_len(&self) -> usize {
        self.export.alt_content().len()
    }

    pub fn alt_row_ranges_ptr(&self) -> *const u32 {
        self.export.alt_row_ranges().as_ptr()
    }

    pub fn alt_row_ranges_len(&self) -> usize {
        self.export.alt_row_ranges().len()
    }

    pub fn alt_run_ranges_ptr(&self) -> *const u32 {
        self.export.alt_run_ranges().as_ptr()
    }

    pub fn alt_run_ranges_len(&self) -> usize {
        self.export.alt_run_ranges().len()
    }

    pub fn alt_style_pairs_ptr(&self) -> *const u32 {
        self.export.alt_style_pairs().as_ptr()
    }

    pub fn alt_style_pairs_len(&self) -> usize {
        self.export.alt_style_pairs().len()
    }

    pub fn find_open(&mut self, query: &str, is_regex: bool) -> Result<u32, JsError> {
        let parsed = if is_regex {
            FindQuery::regex(query)
                .map_err(|err| JsError::new(&format!("invalid regex: {err}")))?
        } else {
            FindQuery::literal(query)
        };
        let id = if let Some(reused) = self.find_free_ids.pop() {
            reused
        } else {
            let id = self.find_next_id;
            self.find_next_id = self.find_next_id.wrapping_add(1).max(1);
            id
        };
        self.find_sessions
            .insert(id, FindSession::open(parsed));
        self.find_results.clear();
        Ok(id)
    }

    pub fn find_step(&mut self, id: u32, budget: usize) -> Result<(), JsError> {
        let budget = budget.max(1);
        let (query, next_block, results, complete) = {
            let session = self
                .find_sessions
                .get_mut(&id)
                .ok_or_else(|| JsError::new("unknown find session"))?;
            if session.cancelled || session.complete {
                return Ok(());
            }
            (
                session.query.clone(),
                session.next_block,
                std::mem::take(&mut session.results),
                session.complete,
            )
        };
        let mut cursor: FindCursor<'_> =
            self.core
                .find_with_state(query, next_block, results, complete);
        cursor.step(budget);
        let (next_block, results, complete) = cursor.into_parts();
        let session = self
            .find_sessions
            .get_mut(&id)
            .ok_or_else(|| JsError::new("unknown find session"))?;
        session.next_block = next_block;
        session.complete = complete;
        session.results = results;
        let mut flattened = Vec::with_capacity(session.results.len() * FIND_MATCH_WORDS);
        for hit in &session.results {
            checked_u32_from_u64(hit.byte_range.start as u64)
                .map_err(|_| ExportError::FindOffsetOverflow)?;
            checked_u32_from_u64(hit.byte_range.end as u64)
                .map_err(|_| ExportError::FindOffsetOverflow)?;
            flattened.push(hit.block as u32);
            flattened.push((hit.block >> 32) as u32);
            flattened.push(hit.row as u32);
            flattened.push(hit.byte_range.start as u32);
            flattened.push(hit.byte_range.end as u32);
        }
        self.find_results = flattened;
        Ok(())
    }

    pub fn find_results_ptr(&self) -> *const u32 {
        self.find_results.as_ptr()
    }

    pub fn find_results_len(&self) -> usize {
        self.find_results.len()
    }

    pub fn find_is_complete(&self, id: u32) -> Result<bool, JsError> {
        let session = self
            .find_sessions
            .get(&id)
            .ok_or_else(|| JsError::new("unknown find session"))?;
        Ok(session.complete)
    }

    pub fn find_cancel(&mut self, id: u32) -> Result<(), JsError> {
        let session = self
            .find_sessions
            .get_mut(&id)
            .ok_or_else(|| JsError::new("unknown find session"))?;
        session.cancelled = true;
        session.complete = true;
        self.find_free_ids.push(id);
        Ok(())
    }
}

fn js_error_from_core(err: vt_core::CoreError) -> JsError {
    match err {
        vt_core::CoreError::ZeroColumns => JsError::new("terminal core requires columns > 0"),
        vt_core::CoreError::ZeroScrollback => {
            JsError::new("terminal core requires scrollback_rows > 0")
        }
        vt_core::CoreError::OffsetOverflow => JsError::new("snapshot offset overflows u32"),
    }
}

impl From<ExportError> for JsError {
    fn from(err: ExportError) -> Self {
        match err {
            ExportError::OffsetOverflow => JsError::new("offset overflows u32"),
            ExportError::FindOffsetOverflow => JsError::new("find result offset overflows u32"),
        }
    }
}

struct FindSession {
    query: FindQuery,
    next_block: usize,
    complete: bool,
    cancelled: bool,
    results: Vec<FindMatch>,
}

impl FindSession {
    fn open(query: FindQuery) -> Self {
        Self {
            query,
            next_block: 0,
            complete: false,
            cancelled: false,
            results: Vec::new(),
        }
    }
}
