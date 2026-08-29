use unicode_width::UnicodeWidthChar;
use vte::{Params, Perform};

use crate::attribute_map::AttributeMap;
use crate::block_grid::BlockGrid;
use crate::content::Content;
use crate::row_index::RowIndex;
use crate::style::StyleCode;

/// Zero-width scalars attach to the cell before them. A cell accepts at most
/// this many, which is well past any real grapheme cluster and is what stops a
/// stream of combining marks from growing the open row without bound: the open
/// row is never completed, so scrollback trimming can never reclaim it.
const MAX_ZERO_WIDTH_PER_CELL: usize = 8;

pub(crate) struct Parser {
    width: usize,
    column: usize,
    content: Content,
    rows: RowIndex,
    styles: AttributeMap<StyleCode>,
    pending_style: StyleCode,
    zero_width_in_cell: usize,
    grid: BlockGrid,
}

impl Parser {
    pub fn new(width: usize, _scrollback_rows: usize) -> Self {
        Self {
            width,
            column: 0,
            content: Content::new(),
            rows: RowIndex::new(0),
            styles: AttributeMap::new(StyleCode::DEFAULT),
            pending_style: StyleCode::DEFAULT,
            zero_width_in_cell: 0,
            grid: BlockGrid::new(),
        }
    }

    pub fn content(&self) -> &Content {
        &self.content
    }

    pub fn rows(&self) -> &RowIndex {
        &self.rows
    }

    pub fn styles(&self) -> &AttributeMap<StyleCode> {
        &self.styles
    }

    pub fn grid(&self) -> &BlockGrid {
        &self.grid
    }

    pub fn grid_mut(&mut self) -> &mut BlockGrid {
        &mut self.grid
    }

    pub fn open_new_row(&mut self) {
        let end = self.content.end_offset();
        self.rows.complete_row(end);
        self.grid.note_row_completed();
        self.column = 0;
        self.zero_width_in_cell = 0;
    }

    pub fn trim_to(&mut self, max_total: usize) {
        let before = self.rows.completed().len();
        if let Some(new_start) = self.rows.trim_to(max_total) {
            self.content.drop_before(new_start);
            self.styles.drop_before(new_start);
            // Every row the row-index dropped off the front shifts the
            // grid's `first_row` by one. Pass the delta so the block
            // indices and the byte release can never disagree.
            let dropped = before - self.rows.completed().len();
            self.grid.trim_to_first_row(dropped);
        }
    }

    fn write_char(&mut self, c: char) {
        let width = UnicodeWidthChar::width(c).unwrap_or(0);
        if width == 0 {
            if self.zero_width_in_cell >= MAX_ZERO_WIDTH_PER_CELL {
                return;
            }
            self.zero_width_in_cell += 1;
        } else {
            if self.column + width > self.width {
                self.open_new_row();
            }
            self.zero_width_in_cell = 0;
        }
        let offset = self.content.end_offset();
        if self.pending_style != self.styles.tail() {
            self.styles.set_from(offset, self.pending_style);
        }
        let mut buf = [0u8; 4];
        let s = c.encode_utf8(&mut buf);
        self.content.push_char(s);
        self.column += width;
    }

    fn expand_tab(&mut self) {
        let target = ((self.column / 8) + 1) * 8;
        while self.column < target && self.column < self.width {
            let offset = self.content.end_offset();
            if self.pending_style != self.styles.tail() {
                self.styles.set_from(offset, self.pending_style);
            }
            self.content.push_char(" ");
            self.column += 1;
            self.zero_width_in_cell = 0;
        }
        if self.column >= self.width {
            self.open_new_row();
        }
    }

    fn apply_sgr(&mut self, params: &Params) {
        let groups: Vec<Vec<u16>> = params.iter().map(|sub| sub.to_vec()).collect();
        if groups.is_empty() {
            self.pending_style = StyleCode::DEFAULT;
            return;
        }
        let mut index = 0;
        while index < groups.len() {
            let group = &groups[index];
            let code = group.first().copied().unwrap_or(0);
            // A group carrying its own sub-parameters is the colon form
            // (`38:5:196`) and is self-contained. A bare 38/48/58 is the
            // semicolon form, and the parameters that follow belong to it --
            // consuming them is what stops `48;5;31` from being read as SGR 31
            // and repainting the foreground.
            if group.len() == 1 && matches!(code, 38 | 48 | 58) {
                index += extended_colour_length(&groups, index);
                continue;
            }
            match code {
                0 => self.pending_style = StyleCode::DEFAULT,
                30..=37 => self.pending_style = StyleCode::ansi((code - 30) as u8),
                39 => self.pending_style = StyleCode::DEFAULT,
                90..=97 => self.pending_style = StyleCode::ansi((code - 90 + 8) as u8),
                _ => {}
            }
            index += 1;
        }
    }
}

/// Number of parameter groups an extended-colour introducer consumes, itself
/// included: `38;5;n` is three and `38;2;r;g;b` is five. An unrecognised or
/// truncated selector consumes only the introducer so parsing always advances.
fn extended_colour_length(groups: &[Vec<u16>], index: usize) -> usize {
    match groups
        .get(index + 1)
        .and_then(|group| group.first())
        .copied()
    {
        Some(5) => 3.min(groups.len() - index),
        Some(2) => 5.min(groups.len() - index),
        _ => 1,
    }
}

impl Perform for Parser {
    fn print(&mut self, c: char) {
        self.write_char(c);
    }

    fn execute(&mut self, byte: u8) {
        match byte {
            0x09 => self.expand_tab(),
            0x0A..=0x0C => self.open_new_row(),
            0x0D => {}
            _ => {}
        }
    }

    fn csi_dispatch(&mut self, params: &Params, _intermediates: &[u8], _ignore: bool, c: char) {
        if c == 'm' {
            self.apply_sgr(params);
        }
    }
}
