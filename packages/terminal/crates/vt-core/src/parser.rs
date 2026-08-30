use vte::{Params, Perform};

use crate::alt::AltGrid;
use crate::attribute_map::AttributeMap;
use crate::block::BlockSource;
use crate::block_grid::BlockGrid;
use crate::content::Content;
use crate::row_index::RowIndex;
use crate::screen::ScreenGrid;
use crate::style::StyleCode;

pub(crate) struct Parser {
    width: usize,
    content: Content,
    rows: RowIndex,
    styles: AttributeMap<StyleCode>,
    pending_style: StyleCode,
    grid: BlockGrid,
    screen: ScreenGrid,
    alt: Option<AltGrid>,
    saved_style: StyleCode,
    app_cursor: bool,
}

impl Parser {
    pub fn new(width: usize, _scrollback_rows: usize) -> Self {
        let mut screen = ScreenGrid::new(24, width);
        screen.set_records_eviction(true);
        Self {
            width,
            content: Content::new(),
            rows: RowIndex::new(0),
            styles: AttributeMap::new(StyleCode::DEFAULT),
            pending_style: StyleCode::DEFAULT,
            grid: BlockGrid::new(),
            screen,
            alt: None,
            saved_style: StyleCode::DEFAULT,
            app_cursor: false,
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

    pub(crate) fn open_block(&mut self, source: BlockSource) {
        self.commit_evicted();
        let first_row = self
            .rows
            .completed()
            .len()
            .saturating_add(self.screen.content_rows())
            .saturating_sub(1);
        self.grid.sync_next_row(first_row);
        self.grid.open_block(source);
    }

    pub(crate) fn close_block(&mut self, exit_code: Option<i32>) {
        self.commit_evicted();
        let next_row = self.rows.completed().len() + self.screen.content_rows();
        self.grid.sync_next_row(next_row);
        self.grid.close_block(exit_code);
    }

    pub fn screen(&self) -> &ScreenGrid {
        &self.screen
    }

    fn active_screen_mut(&mut self) -> &mut ScreenGrid {
        match self.alt.as_mut() {
            Some(alt) => alt,
            None => &mut self.screen,
        }
    }

    pub fn enter_alt(&mut self, rows: usize) {
        if self.alt.is_some() {
            return;
        }
        self.alt = Some(AltGrid::new(rows, self.width));
        self.saved_style = self.pending_style;
        self.pending_style = StyleCode::DEFAULT;
    }

    pub fn leave_alt(&mut self) {
        self.alt = None;
        self.pending_style = self.saved_style;
    }

    pub fn alt(&self) -> Option<&AltGrid> {
        self.alt.as_ref()
    }

    pub fn app_cursor(&self) -> bool {
        self.app_cursor
    }

    pub fn resize(&mut self, columns: usize, rows: usize) {
        self.width = columns;
        self.screen.resize(rows, columns);
        if let Some(alt) = self.alt.as_mut() {
            alt.resize(rows, columns);
        }
    }

    pub(crate) fn commit_evicted(&mut self) {
        if self.alt.is_some() {
            return;
        }
        for row in self.screen.take_evicted() {
            crate::scrollback::commit_row(
                &row,
                &mut self.content,
                &mut self.rows,
                &mut self.styles,
            );
            self.grid.note_row_completed();
        }
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
            if matches!(code, 38 | 48 | 58) {
                let (colour, consumed) = read_extended_colour(&groups, index);
                if code == 38 {
                    if let Some(style) = colour {
                        self.pending_style = self.pending_style.with_colour(style);
                    }
                }
                index += consumed;
                continue;
            }
            match code {
                0 => self.pending_style = StyleCode::DEFAULT,
                1 => self.pending_style = self.pending_style.with_bold(true),
                2 => self.pending_style = self.pending_style.with_dim(true),
                22 => {
                    self.pending_style = self.pending_style.with_bold(false).with_dim(false);
                }
                30..=37 => {
                    self.pending_style = self
                        .pending_style
                        .with_colour(StyleCode::ansi((code - 30) as u8));
                }
                39 => self.pending_style = self.pending_style.with_colour(StyleCode::DEFAULT),
                90..=97 => {
                    self.pending_style = self
                        .pending_style
                        .with_colour(StyleCode::ansi((code - 90 + 8) as u8));
                }
                _ => {}
            }
            index += 1;
        }
    }
}

/// Reads an extended-colour introducer (`38`/`48`/`58`) and reports how many
/// parameter groups it consumed, itself included.
///
/// Both spellings reach here. The colon form (`38:5:196`) is self-contained in
/// one group; the semicolon form (`38;5;196`) spreads across the groups that
/// follow, and consuming them is what stops `48;5;31` from being read as SGR 31
/// and repainting the foreground. A truncated or unrecognised selector consumes
/// only the introducer, so parsing always advances.
fn read_extended_colour(groups: &[Vec<u16>], index: usize) -> (Option<StyleCode>, usize) {
    let group = &groups[index];
    if group.len() > 1 {
        return (colour_from_subparameters(group), 1);
    }
    let selector = groups.get(index + 1).and_then(|next| next.first()).copied();
    match selector {
        Some(5) => {
            let colour = groups
                .get(index + 2)
                .and_then(|value| value.first())
                .map(|value| StyleCode::indexed(narrow(*value)));
            (colour, 3.min(groups.len() - index))
        }
        Some(2) => {
            let channel = |offset: usize| {
                groups
                    .get(index + offset)
                    .and_then(|value| value.first())
                    .copied()
            };
            let colour = match (channel(2), channel(3), channel(4)) {
                (Some(r), Some(g), Some(b)) => {
                    Some(StyleCode::rgb(narrow(r), narrow(g), narrow(b)))
                }
                _ => None,
            };
            (colour, 5.min(groups.len() - index))
        }
        _ => (None, 1),
    }
}

/// The colon form carries its selector and channels as sub-parameters of one
/// group. Truecolour is often written `38:2::r:g:b`, where the empty
/// colour-space id parses as a zero and shifts the channels along by one.
fn colour_from_subparameters(group: &[u16]) -> Option<StyleCode> {
    match group.get(1)? {
        5 => group.get(2).map(|value| StyleCode::indexed(narrow(*value))),
        2 => {
            let start = if group.len() >= 6 { 3 } else { 2 };
            let r = *group.get(start)?;
            let g = *group.get(start + 1)?;
            let b = *group.get(start + 2)?;
            Some(StyleCode::rgb(narrow(r), narrow(g), narrow(b)))
        }
        _ => None,
    }
}

fn narrow(value: u16) -> u8 {
    value.min(255) as u8
}

impl Perform for Parser {
    fn print(&mut self, c: char) {
        let style = self.pending_style;
        self.active_screen_mut().print(c, style);
    }

    fn execute(&mut self, byte: u8) {
        let screen = self.active_screen_mut();
        match byte {
            0x08 => screen.move_by(0, -1),
            0x09 => screen.tab(),
            0x0A..=0x0C => screen.line_feed(),
            0x0D => screen.carriage_return(),
            _ => {}
        }
    }

    fn csi_dispatch(&mut self, params: &Params, intermediates: &[u8], _ignore: bool, c: char) {
        if c == 'm' {
            self.apply_sgr(params);
            return;
        }
        if intermediates.first() == Some(&b'?')
            && params.iter().next().and_then(|g| g.first().copied()) == Some(1)
        {
            match c {
                'h' => self.app_cursor = true,
                'l' => self.app_cursor = false,
                _ => {}
            }
        }
        self.active_screen_mut().csi(params, intermediates, c);
    }

    fn esc_dispatch(&mut self, _intermediates: &[u8], _ignore: bool, byte: u8) {
        self.active_screen_mut().esc(byte);
    }
}
