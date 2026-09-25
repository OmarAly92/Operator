pub mod agent;
pub mod alt;
pub mod alt_screen;
mod answer_gate;
pub mod attribute_map;
pub mod block;
pub mod block_grid;
pub mod block_selection;
pub mod block_tree;
pub mod cold_ring;
pub mod content;
mod core_modes;
pub mod delta;
pub mod event_bridge;
pub mod find;
pub mod grid;
mod history;
pub mod hyperlink;
pub mod integrity;
pub mod limits;
mod line_editor;
mod live_output;
pub mod mark_regex;
pub mod older;
pub mod parser;
pub mod program;
pub mod row_index;
mod screen;
mod scrollback;
mod sgr;
pub mod style;
pub mod style_sgr;
pub mod sync;
#[cfg(feature = "trace")]
pub mod trace;
pub mod width;

pub mod testing {
    pub use crate::screen::{Cell, ScreenGrid};
}

pub use alt::{AltGrid, Cell};
pub use block::{Block, BlockId, BlockMeta, BlockRecord, BlockSource, BlockState, TextSpan};
pub use block_grid::BlockGrid;
pub use block_selection::{BlockSelection, SelectionPoint};
pub use block_tree::{BlockSummary, BlockTree};
pub use cold_ring::{ColdRow, ColdStats};
pub use delta::{Delta, DeltaKind};
pub use find::{FindMatch, FindQuery, FindSession, FindUpdate};
pub use grid::{CellSpan, ExportedRow};
pub use hyperlink::{Hyperlink, HyperlinkRegistry, LinkId};
pub use integrity::IntegrityError;
pub use limits::{Limits, MemoryStats};
pub use line_editor::LineEditorState;
pub use older::{OlderChunk, OlderState, OLDER_CHUNK_ROWS};
pub use parser::{HistoryBlock, HistoryRow};
pub use style::{Attrs, CellStyle, StyleCode};
pub use width::{clusters, Cluster, WidthMode};

use std::ops::Range;

use terminal_marks::{MarkDecoder, MarkEvent};
use vte::Parser as VteParser;

use event_bridge::apply_event;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CoreError {
    ZeroColumns,
    ZeroScrollback,
    /// A snapshot offset did not fit the `u32` the export buffers carry.
    OffsetOverflow,
}

pub const DEFAULT_ROWS: usize = 24;

pub struct TerminalCore {
    parser: parser::Parser,
    vte: VteParser,
    answer_gate: answer_gate::AnswerGate,
    mark_decoder: MarkDecoder,
    alt_screen: alt_screen::AltScreen,
    line_editor: line_editor::LineEditorTracker,
    limits: Limits,
    rows: usize,
    fed_total: u64,
    sync: sync::SyncBuffer,
    now_ms: u64,
    history: history::HistoryReceiver,
    replay_ready: bool,
    older: OlderState,
    live_output: u64,
    open_osc_live: u64,
}

impl TerminalCore {
    pub fn new(columns: usize, scrollback_rows: usize) -> Result<Self, CoreError> {
        Self::with_limits(columns, Limits::rows_only(scrollback_rows))
    }

    pub fn with_limits(columns: usize, limits: Limits) -> Result<Self, CoreError> {
        if columns == 0 {
            return Err(CoreError::ZeroColumns);
        }
        if limits.rows == 0 {
            return Err(CoreError::ZeroScrollback);
        }
        Ok(Self {
            parser: parser::Parser::new(columns),
            vte: VteParser::new(),
            answer_gate: answer_gate::AnswerGate::default(),
            mark_decoder: MarkDecoder::new(),
            alt_screen: alt_screen::AltScreen::new(),
            line_editor: line_editor::LineEditorTracker::default(),
            limits,
            rows: DEFAULT_ROWS,
            fed_total: 0,
            sync: sync::SyncBuffer::default(),
            now_ms: 0,
            history: history::HistoryReceiver::new(),
            replay_ready: false,
            older: OlderState::default(),
            live_output: 0,
            open_osc_live: 0,
        })
    }

    pub fn limits(&self) -> Limits {
        self.limits
    }

    pub fn memory_stats(&self) -> MemoryStats {
        MemoryStats {
            content_bytes: self.parser.content().resident_bytes(),
            style_entries: self.parser.styles().len(),
            rows: self.parser.rows().completed().len(),
            blocks: self.parser.grid().len(),
        }
    }

    pub fn feed(&mut self, bytes: &[u8]) {
        let now_ms = self.now_ms;
        self.feed_at(bytes, now_ms);
    }

    pub fn feed_at(&mut self, bytes: &[u8], now_ms: u64) -> bool {
        self.now_ms = now_ms;
        let mut parsed = false;
        if self.sync.is_active() && self.sync.deadline().is_some_and(|d| now_ms >= d) {
            parsed |= self.flush_sync(None);
        }
        let mut rest = bytes;
        while !rest.is_empty() {
            if self.sync.is_active() {
                if self.sync.would_overflow(rest.len()) {
                    self.flush_sync(None);
                    self.feed_raw(rest);
                    parsed = true;
                    rest = &[];
                    continue;
                }
                match self.sync.append(rest, now_ms) {
                    sync::TailScan::Keep => {}
                    sync::TailScan::FlushAll => parsed |= self.flush_sync(None),
                    sync::TailScan::FlushBefore(keep_from) => {
                        parsed |= self.flush_sync(Some(keep_from))
                    }
                }
                rest = &[];
            } else {
                match self.sync.find_bsu(rest) {
                    Some(split) => {
                        if split > 0 {
                            self.feed_raw(&rest[..split]);
                            parsed = true;
                        }
                        self.sync.begin(now_ms);
                        rest = &rest[split..];
                    }
                    None => {
                        self.feed_raw(rest);
                        parsed = true;
                        rest = &[];
                    }
                }
            }
        }
        parsed
    }

    pub fn tick(&mut self, now_ms: u64) -> bool {
        self.now_ms = now_ms;
        if self.sync.is_active() && self.sync.deadline().is_some_and(|d| now_ms >= d) {
            return self.flush_sync(None);
        }
        false
    }

    pub fn synchronized_output(&self) -> bool {
        self.sync.is_active()
    }

    pub fn replay_ready(&self) -> bool {
        self.replay_ready
    }

    pub fn pending_sync_bytes(&self) -> &[u8] {
        &self.sync.bytes
    }

    fn flush_sync(&mut self, keep_from: Option<usize>) -> bool {
        let buffer = self.sync.take();
        let upto = keep_from.unwrap_or(buffer.len());
        let parsed = upto > 0;
        if parsed {
            self.feed_raw(&buffer[..upto]);
        }
        match keep_from {
            Some(from) => self.sync.bytes = buffer[from..].to_vec(),
            None => self.sync.end(),
        }
        parsed
    }

    fn feed_raw(&mut self, bytes: &[u8]) {
        let committed = self.parser.committed_rows();
        self.parser.set_clock(self.now_ms);
        let mut bytes = bytes;
        if self.history.is_active() {
            let consumed = self.history.consume(bytes, self.parser.hyperlinks_mut());
            self.drain_history();
            bytes = &bytes[consumed..];
            if bytes.is_empty() {
                return;
            }
        }
        self.sync.note_parsed(bytes);
        // Marks are decoded separately from `vte` so the block state machine
        // never depends on the parser's callback shape and a split read still
        // produces a complete event list. But the two must be applied in
        // stream order: each event lands only after the bytes before it have
        // been parsed. Applying a whole chunk's events first closes every
        // block before the rows it produced exist, leaving blocks that own
        // nothing and rows that belong to no block.
        let events = self.mark_decoder.feed_with_offsets(bytes);
        let mut parsed = 0usize;
        for (offset, event) in events {
            let upto = offset.min(bytes.len());
            if offset < parsed {
                continue;
            }
            if let MarkEvent::ReplayOrigin(_) = event {
                parsed = self.open_replay_window(bytes, parsed, upto);
            }
            if upto > parsed {
                self.advance_vte(&bytes[parsed..upto]);
                parsed = upto;
            }
            match event {
                MarkEvent::ReplayOrigin(origin) => {
                    if self.parser.adopt_origin(origin) {
                        self.live_output = 0;
                    }
                    parsed = upto;
                    continue;
                }
                MarkEvent::ReplayReady => {
                    self.replay_ready = true;
                    self.parser.program_mut().agent_mut().set_replaying(false);
                    parsed = upto;
                    continue;
                }
                MarkEvent::OlderFloor(floor) => {
                    self.older.note(floor);
                    parsed = upto;
                    continue;
                }
                MarkEvent::HistoryChunk {
                    first_stable_row,
                    rows,
                    cols,
                } => {
                    let cols = self.parser.columns().max(cols.unwrap_or(0));
                    self.history
                        .begin(first_stable_row, rows, cols, self.parser.width_mode());
                    let rest = &bytes[upto..];
                    let consumed = self.history.consume(rest, self.parser.hyperlinks_mut());
                    self.drain_history();
                    parsed = upto + consumed;
                    continue;
                }
                _ => {}
            }
            self.older.observe(&event);
            // Re-read the alt-screen state after every event so an
            // `AltScreenEnter` freezes the rest of this chunk's events and a
            // trailing `AltScreenLeave` thaws them.
            if self.alt_screen.is_active() && !matches!(event, MarkEvent::AltScreenLeave) {
                continue;
            }
            match &event {
                MarkEvent::InputReady => self.line_editor.on_input_ready(),
                MarkEvent::InputReleased => self.line_editor.on_input_released(),
                MarkEvent::AltScreenEnter => self.line_editor.on_alt_screen_enter(),
                MarkEvent::Extension(fields) => {
                    if let Some((_, text)) = fields.pairs.iter().find(|(key, _)| key == "typeahead")
                    {
                        self.line_editor.on_typeahead(text);
                    }
                }
                _ => {}
            }
            let switch = event.clone();
            apply_event(&mut self.parser, &mut self.alt_screen, event);
            match switch {
                MarkEvent::AltScreenEnter => self.parser.enter_alt(self.rows),
                MarkEvent::AltScreenLeave => self.parser.leave_alt(),
                _ => {}
            }
        }
        if parsed < bytes.len() {
            self.advance_vte(&bytes[parsed..]);
        }
        self.note_open_osc();
        self.parser.note_output();
        self.parser.commit_evicted();
        if self.parser.committed_rows() != committed {
            self.parser.trim_to(self.limits);
        }
        self.parser.note_mutation();
        self.debug_check();
    }

    fn advance_vte(&mut self, bytes: &[u8]) {
        let bytes: &[u8] = &self.answer_gate.filter(bytes);
        if !self.parser.program().agent().replaying() {
            self.live_output = self.live_output.wrapping_add(bytes.len() as u64);
        }
        #[cfg(feature = "trace")]
        {
            for byte in bytes {
                self.parser.trace.offset = self.fed_total;
                self.vte
                    .advance(&mut self.parser, std::slice::from_ref(byte));
                self.fed_total += 1;
            }
        }
        #[cfg(not(feature = "trace"))]
        {
            self.vte.advance(&mut self.parser, bytes);
            self.fed_total += bytes.len() as u64;
        }
    }

    #[cfg(feature = "trace")]
    pub fn trace(&mut self) -> &[trace::TraceEntry] {
        self.parser.trace.entries()
    }

    #[cfg(feature = "trace")]
    pub fn clear_trace(&mut self) {
        self.parser.trace.clear();
    }

    pub fn verify_integrity(&self) -> Result<(), IntegrityError> {
        self.parser.verify_integrity()
    }

    #[cfg(debug_assertions)]
    fn debug_check(&self) {
        if let Err(error) = self.parser.verify_integrity() {
            panic!("vt-core integrity violated: {error:?}");
        }
    }

    #[cfg(not(debug_assertions))]
    fn debug_check(&self) {}

    pub fn snapshot(&self) -> Result<grid::GridSnapshot, CoreError> {
        grid::build_snapshot(
            self.parser.content(),
            self.parser.rows(),
            self.parser.styles(),
            self.parser.grid(),
            self.parser.screen(),
            self.line_editor.state(),
            self.parser.alt(),
            self.parser.first_stable_row(),
            self.parser.width_mode(),
            self.parser.hyperlinks(),
        )
    }

    pub fn hyperlink_count(&self) -> usize {
        self.parser.hyperlinks().len()
    }

    pub fn hyperlink_uri(&self, id: LinkId) -> Option<&str> {
        self.parser.hyperlinks().uri(id)
    }

    pub fn generation(&self) -> u64 {
        self.parser.generation()
    }

    pub fn take_delta(&mut self) -> Delta {
        self.parser.take_delta()
    }

    pub fn history_rows(&self) -> usize {
        self.parser.rows().completed().len()
    }

    pub fn touch_rows(&mut self, range: Range<usize>) {
        self.parser.touch_rows(range);
        self.debug_check();
    }

    pub fn stale_row_count(&self) -> usize {
        self.parser.stale_row_count()
    }

    pub fn export_history_rows(&self, range: Range<usize>) -> Vec<ExportedRow> {
        let completed = self.parser.rows().completed();
        range
            .filter_map(|index| completed.get(index))
            .map(|row| {
                grid::export_history_row(
                    self.parser.content(),
                    self.parser.styles(),
                    row,
                    self.parser.width_mode(),
                )
            })
            .collect()
    }

    pub fn export_screen_rows(&self) -> Vec<ExportedRow> {
        let screen = self.parser.screen();
        (0..screen.content_rows())
            .map(|row| grid::export_screen_row(screen, row))
            .collect()
    }

    pub fn export_blocks(
        &self,
        total_rows: usize,
        row_has_bytes: impl Fn(usize) -> bool,
    ) -> Result<(Vec<BlockRecord>, Vec<u8>), CoreError> {
        grid::export_blocks(self.parser.grid(), total_rows, row_has_bytes)
    }

    pub fn export_cursor(&self) -> (usize, usize, bool) {
        let screen = self.parser.screen();
        let (row, col) = screen.cursor();
        (self.history_rows() + row, col, screen.cursor_visible())
    }

    pub fn alt_snapshot(&self) -> Option<alt::AltSnapshot> {
        self.parser.alt().map(|grid| grid.snapshot())
    }

    pub fn first_stable_row(&self) -> u64 {
        self.parser.first_stable_row()
    }

    pub fn adopt_origin(&mut self, origin: u64) -> bool {
        let adopted = self.parser.adopt_origin(origin);
        self.debug_check();
        adopted
    }

    pub fn stable_row(&self, flat: usize) -> u64 {
        self.parser.stable_row(flat)
    }

    pub fn flat_row(&self, stable: u64) -> Option<usize> {
        self.parser.flat_row(stable)
    }

    fn find_view(&self) -> find::FindView<'_> {
        find::FindView {
            content: self.parser.content(),
            rows: self.parser.rows(),
            screen: self.parser.screen(),
            generation: self.parser.generation(),
            first_stable_row: self.parser.first_stable_row(),
        }
    }

    pub fn find_update(&self, session: &mut FindSession, budget_bytes: usize) -> FindUpdate {
        session.update(&self.find_view(), budget_bytes)
    }

    pub fn find_results(&self, session: &FindSession) -> Vec<FindMatch> {
        let total = self.history_rows() + self.parser.screen().content_rows();
        let blocks = grid::export_blocks(self.parser.grid(), total, |_| true)
            .map(|(records, _)| records)
            .unwrap_or_default();
        session.results(&self.find_view(), &blocks)
    }

    pub fn alt_screen_active(&self) -> bool {
        self.alt_screen.is_active()
    }

    pub fn line_editor_state(&self) -> LineEditorState {
        self.line_editor.state()
    }

    pub fn take_typeahead(&mut self) -> Option<String> {
        self.line_editor.take_typeahead()
    }

    pub fn columns(&self) -> usize {
        self.parser.columns()
    }

    pub fn resize(&mut self, columns: usize, rows: usize) {
        self.flush_sync(None);
        let columns = columns.clamp(1, alt::MAX_DIMENSION);
        let rows = rows.clamp(1, alt::MAX_DIMENSION);
        self.rows = rows;
        self.parser.resize(columns, rows);
        self.parser.trim_to(self.limits);
        self.parser.note_mutation();
        self.debug_check();
    }

    // The renderer's resize model evicts the screen into the block stream and
    // reflows; a headless consumer that needs tmux capture-pane semantics
    // (resize preserves the visible screen in place) turns reflow off.
    pub fn set_reflow_on_resize(&mut self, on: bool) {
        self.parser.set_reflow_on_resize(on);
        self.debug_check();
    }

    pub fn set_answers_queries(&mut self, on: bool) {
        self.parser.set_answers_queries(on);
    }

    pub fn take_query_replies(&mut self) -> Vec<u8> {
        self.parser.take_query_replies()
    }

    pub fn set_terminal_identity(&mut self, name: &str) {
        self.parser.set_terminal_identity(name);
    }

    pub fn set_agent_tui_mode(&mut self, on: bool) {
        self.parser.set_agent_tui_mode(on);
        self.debug_check();
    }

    pub fn set_grapheme_clusters(&mut self, on: bool) {
        self.parser.set_width_mode(if on {
            WidthMode::Grapheme
        } else {
            WidthMode::Scalar
        });
    }

    pub fn grapheme_clusters(&self) -> bool {
        self.parser.width_mode() == WidthMode::Grapheme
    }

    pub fn set_block_bookmarked(&mut self, id: crate::block::BlockId, bookmarked: bool) {
        self.parser.grid_mut().set_block_bookmarked(id, bookmarked);
        self.parser.note_mutation();
        self.debug_check();
    }

    pub fn block_bookmarked(&self, id: crate::block::BlockId) -> bool {
        self.parser.grid().block_bookmarked(id)
    }

    pub fn rows(&self) -> usize {
        self.rows
    }

    pub fn alt_grid(&self) -> Option<&alt::AltGrid> {
        self.parser.alt()
    }
}

pub use grid::GridSnapshot;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}
