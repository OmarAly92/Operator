pub mod attribute_map;
pub mod block;
pub mod content;
pub mod grid;
pub mod parser;
pub mod row_index;
pub mod style;

pub use block::{Block, BlockId, BlockMeta, BlockRecord, BlockSource, BlockState, TextSpan};
pub use style::StyleCode;

use vte::Parser as VteParser;

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
            scrollback_rows,
        })
    }

    pub fn feed(&mut self, bytes: &[u8]) {
        self.vte.advance(&mut self.parser, bytes);
        self.parser.trim_to(self.scrollback_rows);
    }

    pub fn snapshot(&self) -> Result<grid::GridSnapshot, CoreError> {
        grid::build_snapshot(
            self.parser.content(),
            self.parser.rows(),
            self.parser.styles(),
        )
    }
}

pub use grid::GridSnapshot;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}
