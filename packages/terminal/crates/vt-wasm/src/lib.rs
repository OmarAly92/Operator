mod export;

use std::collections::HashMap;

use vt_core::{FindCursor, FindMatch, FindQuery, TerminalCore};
use wasm_bindgen::prelude::*;

pub use export::{
    checked_u32_from_u64, ExportBuffers, ExportError, BLOCK_RECORD_WORDS, FIND_MATCH_WORDS,
};

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
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

    pub fn feed(&mut self, bytes: &[u8], now_ms: f64) -> Result<(), JsError> {
        if self.core.feed_at(bytes, clock(now_ms)) {
            self.refresh_after_mutation()?;
        }
        Ok(())
    }

    pub fn tick(&mut self, now_ms: f64) -> Result<bool, JsError> {
        if !self.core.tick(clock(now_ms)) {
            return Ok(false);
        }
        self.refresh_after_mutation()?;
        Ok(true)
    }

    pub fn synchronized_output(&self) -> bool {
        self.core.synchronized_output()
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

    pub fn set_block_bookmarked(
        &mut self,
        id_lo: u32,
        id_hi: u32,
        bookmarked: bool,
    ) -> Result<(), JsError> {
        let id = ((id_hi as u64) << 32) | (id_lo as u64);
        self.core.set_block_bookmarked(id, bookmarked);
        self.refresh_after_mutation()
    }

    pub fn block_bookmarked(&self, id_lo: u32, id_hi: u32) -> bool {
        let id = ((id_hi as u64) << 32) | (id_lo as u64);
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

    pub fn row_indents_ptr(&self) -> *const u16 {
        self.export.row_indents().as_ptr()
    }

    pub fn row_indents_len(&self) -> usize {
        self.export.row_indents().len()
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
            FindQuery::regex(query).map_err(|err| JsError::new(&format!("invalid regex: {err}")))?
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
        self.find_sessions.insert(id, FindSession::open(parsed));
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
        let mut cursor: FindCursor<'_> = self
            .core
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

fn clock(now_ms: f64) -> u64 {
    if now_ms.is_finite() && now_ms > 0.0 {
        now_ms as u64
    } else {
        0
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
