pub mod alt_screen;
pub mod attribute_map;
pub mod block;
pub mod block_grid;
pub mod block_selection;
pub mod block_tree;
pub mod content;
pub mod event_bridge;
pub mod grid;
pub mod parser;
pub mod row_index;
pub mod style;

pub use block::{Block, BlockId, BlockMeta, BlockRecord, BlockSource, BlockState, TextSpan};
pub use block_grid::BlockGrid;
pub use block_selection::{BlockSelection, SelectionPoint};
pub use block_tree::{BlockSummary, BlockTree};
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

pub struct TerminalCore {
    parser: parser::Parser,
    vte: VteParser,
    mark_decoder: MarkDecoder,
    alt_screen: alt_screen::AltScreen,
    scrollback_rows: usize,
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
            scrollback_rows,
        })
    }

    pub fn feed(&mut self, bytes: &[u8]) {
        // Decode marks independently of `vte` so the block state machine
        // never depends on the parser's callback shape, and so a split-read
        // across two feeds still produces a complete event list. Order
        // matters: the protocol's events are pre-vte bytes that the parser
        // would otherwise see as OSC payload and swallow.
        let events = self.mark_decoder.feed(bytes);
        for event in events {
            // Re-read the alt-screen state after every event so a single
            // `feed` call's `AltScreenEnter` correctly freezes the rest of
            // the event list, and a trailing `AltScreenLeave` correctly
            // thaws it. Snapshotting once before the loop would let an
            // enter-then-marks-in-the-same-feed shred the block list.
            let in_alt = self.alt_screen.is_active();
            if in_alt && !matches!(event, MarkEvent::AltScreenLeave) {
                continue;
            }
            apply_event(&mut self.parser, &mut self.alt_screen, event);
        }
        self.vte.advance(&mut self.parser, bytes);
        self.parser.trim_to(self.scrollback_rows);
    }

    pub fn snapshot(&self) -> Result<grid::GridSnapshot, CoreError> {
        grid::build_snapshot(
            self.parser.content(),
            self.parser.rows(),
            self.parser.styles(),
            self.parser.grid(),
        )
    }

    pub fn alt_screen_active(&self) -> bool {
        self.alt_screen.is_active()
    }
}

pub use grid::GridSnapshot;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}
