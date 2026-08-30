pub mod alt;
pub mod alt_screen;
pub mod attribute_map;
pub mod block;
pub mod block_grid;
pub mod block_selection;
pub mod block_tree;
pub mod content;
pub mod event_bridge;
pub mod find;
pub mod grid;
mod line_editor;
pub mod parser;
pub mod row_index;
mod screen;
pub mod style;

pub mod testing {
    pub use crate::screen::{Cell, ScreenGrid};
}

pub use alt::{AltGrid, Cell};
pub use block::{Block, BlockId, BlockMeta, BlockRecord, BlockSource, BlockState, TextSpan};
pub use block_grid::BlockGrid;
pub use block_selection::{BlockSelection, SelectionPoint};
pub use block_tree::{BlockSummary, BlockTree};
pub use find::{FindCursor, FindMatch, FindQuery};
pub use line_editor::LineEditorState;
pub use style::StyleCode;

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
    mark_decoder: MarkDecoder,
    alt_screen: alt_screen::AltScreen,
    line_editor: line_editor::LineEditorTracker,
    scrollback_rows: usize,
    rows: usize,
}

impl TerminalCore {
    pub fn new(columns: usize, scrollback_rows: usize) -> Result<Self, CoreError> {
        if columns == 0 {
            return Err(CoreError::ZeroColumns);
        }
        if scrollback_rows == 0 {
            return Err(CoreError::ZeroScrollback);
        }
        Ok(Self {
            parser: parser::Parser::new(columns, scrollback_rows),
            vte: VteParser::new(),
            mark_decoder: MarkDecoder::new(),
            alt_screen: alt_screen::AltScreen::new(),
            line_editor: line_editor::LineEditorTracker::default(),
            scrollback_rows,
            rows: DEFAULT_ROWS,
        })
    }

    pub fn feed(&mut self, bytes: &[u8]) {
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
            if upto > parsed {
                self.vte.advance(&mut self.parser, &bytes[parsed..upto]);
                parsed = upto;
            }
            // Re-read the alt-screen state after every event so an
            // `AltScreenEnter` freezes the rest of this chunk's events and a
            // trailing `AltScreenLeave` thaws them.
            if self.alt_screen.is_active() && !matches!(event, MarkEvent::AltScreenLeave) {
                continue;
            }
            match event {
                MarkEvent::InputReady => self.line_editor.on_input_ready(),
                MarkEvent::InputReleased => self.line_editor.on_input_released(),
                MarkEvent::AltScreenEnter => self.line_editor.on_alt_screen_enter(),
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
            self.vte.advance(&mut self.parser, &bytes[parsed..]);
        }
        self.parser.trim_to(self.scrollback_rows);
    }

    pub fn snapshot(&self) -> Result<grid::GridSnapshot, CoreError> {
        grid::build_snapshot(
            self.parser.content(),
            self.parser.rows(),
            self.parser.styles(),
            self.parser.grid(),
            self.line_editor.state(),
            self.parser.alt(),
        )
    }

    pub fn find(&self, query: find::FindQuery) -> find::FindCursor<'_> {
        find::FindCursor::new(
            self.parser.grid(),
            self.parser.rows(),
            self.parser.content(),
            query,
        )
    }

    pub fn alt_screen_active(&self) -> bool {
        self.alt_screen.is_active()
    }

    pub fn line_editor_state(&self) -> LineEditorState {
        self.line_editor.state()
    }

    pub fn resize(&mut self, columns: usize, rows: usize) {
        let columns = columns.clamp(1, alt::MAX_DIMENSION);
        let rows = rows.clamp(1, alt::MAX_DIMENSION);
        self.rows = rows;
        self.parser.resize(columns, rows);
    }

    pub fn rows(&self) -> usize {
        self.rows
    }

    pub fn alt_grid(&self) -> Option<&alt::AltGrid> {
        self.parser.alt()
    }

    pub fn application_cursor_keys(&self) -> bool {
        self.parser.app_cursor()
    }
}

pub use grid::GridSnapshot;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}
