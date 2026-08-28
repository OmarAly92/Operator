use unicode_width::UnicodeWidthChar;
use vte::{Params, Perform};

use crate::attribute_map::AttributeMap;
use crate::content::Content;
use crate::row_index::RowIndex;
use crate::style::StyleCode;

pub(crate) struct Parser {
    width: usize,
    column: usize,
    content: Content,
    rows: RowIndex,
    styles: AttributeMap<StyleCode>,
    pending_style: StyleCode,
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

    pub fn open_new_row(&mut self) {
        let end = self.content.end_offset();
        self.rows.complete_row(end);
        self.column = 0;
    }

    pub fn trim_to(&mut self, max_total: usize) {
        if let Some(new_start) = self.rows.trim_to(max_total) {
            self.content.drop_before(new_start);
            self.styles.drop_before(new_start);
        }
    }

    fn write_char(&mut self, c: char) {
        let width = UnicodeWidthChar::width(c).unwrap_or(0);
        if width > 0 && self.column >= self.width {
            self.open_new_row();
        }
        if width > 0 && self.column + width > self.width {
            self.open_new_row();
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
        }
        if self.column >= self.width {
            self.open_new_row();
        }
    }

    fn apply_sgr(&mut self, params: &Params) {
        let bytes: Vec<u16> = params
            .iter()
            .map(|sub| sub.iter().next().copied().unwrap_or(0))
            .collect();
        let mut iter = bytes.iter().copied().peekable();
        if iter.peek().is_none() {
            self.pending_style = StyleCode::DEFAULT;
            return;
        }
        for p in iter {
            match p {
                0 => self.pending_style = StyleCode::DEFAULT,
                30..=37 => self.pending_style = StyleCode::ansi((p - 30) as u8),
                39 => self.pending_style = StyleCode::DEFAULT,
                90..=97 => self.pending_style = StyleCode::ansi((p - 90 + 8) as u8),
                _ => {}
            }
        }
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
