mod export;

use std::collections::HashMap;

use vt_core::{FindCursor, FindMatch, FindQuery, TerminalCore};
use wasm_bindgen::prelude::*;

pub use export::{
    checked_u32_from_u64, ExportBuffers, ExportError, BLOCK_RECORD_WORDS, CELL_SPAN_WORDS,
    COMPACTION_DIVISOR, FIND_MATCH_WORDS, STYLE_RUN_WORDS,
};

pub const DIRTY_ROWS_CAP: usize = 4096;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

pub fn memory_stats_words(stats: &vt_core::MemoryStats) -> [u32; 4] {
    [
        stats.content_bytes as u32,
        stats.style_entries as u32,
        stats.rows as u32,
        stats.blocks as u32,
    ]
}

#[wasm_bindgen]
pub struct WasmTerminalCore {
    core: TerminalCore,
    export: ExportBuffers,
    export_window: Option<(usize, usize)>,
    synced_generation: Option<u64>,
    dirty_rows: Vec<u32>,
    dirty_full: bool,
    row_events_trimmed: u32,
    remap: Vec<u32>,
    find_sessions: HashMap<u32, FindSession>,
    find_free_ids: Vec<u32>,
    find_next_id: u32,
    find_results: Vec<u32>,
}

#[wasm_bindgen]
impl WasmTerminalCore {
    #[wasm_bindgen(constructor)]
    pub fn new(
        columns: usize,
        rows_limit: usize,
        bytes_limit: usize,
    ) -> Result<WasmTerminalCore, JsError> {
        let core = TerminalCore::with_limits(
            columns,
            vt_core::Limits {
                rows: rows_limit,
                bytes: bytes_limit,
            },
        )
        .map_err(js_error_from_core)?;
        let mut this = WasmTerminalCore {
            core,
            export: ExportBuffers::default(),
            export_window: None,
            synced_generation: None,
            dirty_rows: Vec::new(),
            dirty_full: true,
            row_events_trimmed: 0,
            remap: Vec::new(),
            find_sessions: HashMap::new(),
            find_free_ids: Vec::new(),
            find_next_id: 1,
            find_results: Vec::new(),
        };
        this.sync()?;
        Ok(this)
    }

    pub fn feed(&mut self, bytes: &[u8], now_ms: f64) -> Result<(), JsError> {
        self.core.feed_at(bytes, clock(now_ms));
        Ok(())
    }

    pub fn tick(&mut self, now_ms: f64) -> Result<bool, JsError> {
        Ok(self.core.tick(clock(now_ms)))
    }

    pub fn synchronized_output(&self) -> bool {
        self.core.synchronized_output()
    }

    pub fn replay_ready(&self) -> bool {
        self.core.replay_ready()
    }

    pub fn resize(&mut self, columns: usize, rows: usize) -> Result<(), JsError> {
        self.core.resize(columns, rows);
        Ok(())
    }

    #[wasm_bindgen(js_name = setAgentTuiMode)]
    pub fn set_agent_tui_mode(&mut self, on: bool) {
        self.core.set_agent_tui_mode(on);
    }

    #[wasm_bindgen(js_name = setGraphemeClusters)]
    pub fn set_grapheme_clusters(&mut self, on: bool) {
        self.core.set_grapheme_clusters(on);
    }

    #[wasm_bindgen(js_name = graphemeClusters)]
    pub fn grapheme_clusters(&self) -> bool {
        self.core.grapheme_clusters()
    }

    pub fn set_block_bookmarked(
        &mut self,
        id_lo: u32,
        id_hi: u32,
        bookmarked: bool,
    ) -> Result<(), JsError> {
        let id = ((id_hi as u64) << 32) | (id_lo as u64);
        self.core.set_block_bookmarked(id, bookmarked);
        Ok(())
    }

    pub fn block_bookmarked(&self, id_lo: u32, id_hi: u32) -> bool {
        let id = ((id_hi as u64) << 32) | (id_lo as u64);
        self.core.block_bookmarked(id)
    }

    pub fn memory_stats(&self) -> Vec<u32> {
        memory_stats_words(&self.core.memory_stats()).to_vec()
    }

    /// The flat history rows the next sync() must have rewrapped. Cleared
    /// by sync(); a window that is never set leaves every cold row cold.
    pub fn set_export_window(&mut self, first_row: u32, last_row: u32) {
        self.export_window = Some((first_row as usize, last_row as usize));
    }

    pub fn sync(&mut self) -> Result<u32, JsError> {
        if let Some((first, last)) = self.export_window.take() {
            if last > first {
                self.core.touch_rows(first..last);
            }
        }
        let generation = self.core.generation();
        if self.synced_generation == Some(generation) {
            return Ok(generation as u32);
        }
        let delta = self.core.take_delta();
        self.export.apply(&self.core, &delta)?;
        self.synced_generation = Some(generation);
        let first_stable = self.export.first_stable_row();
        let history_rows = self.export.history_rows();
        let first_screen = first_stable + history_rows as u64;
        let screen_rows = self.export.rows().len() / 2 - history_rows;
        match delta.kind {
            vt_core::DeltaKind::Full => {
                self.dirty_full = true;
                self.dirty_rows.clear();
            }
            vt_core::DeltaKind::Partial => {
                for row in delta.appended_history.clone() {
                    self.push_dirty(first_stable + row as u64)?;
                }
                for row in &delta.screen_rows {
                    if *row >= screen_rows {
                        continue;
                    }
                    self.push_dirty(first_screen + *row as u64)?;
                }
            }
        }
        self.row_events_trimmed = self
            .row_events_trimmed
            .saturating_add(delta.trimmed_rows as u32);
        if let Some(pairs) = delta.remap {
            self.remap.clear();
            for (old, new) in pairs {
                self.remap.push(checked_u32_from_u64(old)?);
                self.remap.push(checked_u32_from_u64(new)?);
            }
        }
        Ok(generation as u32)
    }

    fn push_dirty(&mut self, stable_row: u64) -> Result<(), JsError> {
        if self.dirty_full {
            return Ok(());
        }
        if self.dirty_rows.len() >= DIRTY_ROWS_CAP {
            self.dirty_full = true;
            self.dirty_rows.clear();
            return Ok(());
        }
        self.dirty_rows.push(checked_u32_from_u64(stable_row)?);
        Ok(())
    }

    pub fn generation(&self) -> u32 {
        self.core.generation() as u32
    }

    pub fn history_rows(&self) -> u32 {
        self.export.history_rows() as u32
    }

    pub fn stale_row_count(&self) -> usize {
        self.core.stale_row_count()
    }

    pub fn dirty_full(&self) -> bool {
        self.dirty_full
    }

    pub fn dirty_rows_ptr(&self) -> *const u32 {
        self.dirty_rows.as_ptr()
    }

    pub fn dirty_rows_len(&self) -> usize {
        self.dirty_rows.len()
    }

    pub fn ack_dirty(&mut self) {
        self.dirty_full = false;
        self.dirty_rows.clear();
    }

    pub fn row_events_trimmed(&self) -> u32 {
        self.row_events_trimmed
    }

    pub fn remap_ptr(&self) -> *const u32 {
        self.remap.as_ptr()
    }

    pub fn remap_len(&self) -> usize {
        self.remap.len()
    }

    pub fn clear_row_events(&mut self) {
        self.row_events_trimmed = 0;
        self.remap.clear();
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

    pub fn span_ranges_ptr(&self) -> *const u32 {
        self.export.span_ranges().as_ptr()
    }

    pub fn span_ranges_len(&self) -> usize {
        self.export.span_ranges().len()
    }

    pub fn cell_spans_ptr(&self) -> *const u32 {
        self.export.cell_spans().as_ptr()
    }

    pub fn cell_spans_len(&self) -> usize {
        self.export.cell_spans().len()
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

    pub fn first_stable_row_lo(&self) -> u32 {
        self.export.first_stable_row() as u32
    }

    pub fn first_stable_row_hi(&self) -> u32 {
        (self.export.first_stable_row() >> 32) as u32
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

    pub fn alt_span_ranges_ptr(&self) -> *const u32 {
        self.export.alt_span_ranges().as_ptr()
    }

    pub fn alt_span_ranges_len(&self) -> usize {
        self.export.alt_span_ranges().len()
    }

    pub fn alt_cell_spans_ptr(&self) -> *const u32 {
        self.export.alt_cell_spans().as_ptr()
    }

    pub fn alt_cell_spans_len(&self) -> usize {
        self.export.alt_cell_spans().len()
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
            flattened
                .push(checked_u32_from_u64(hit.row).map_err(|_| ExportError::FindOffsetOverflow)?);
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
