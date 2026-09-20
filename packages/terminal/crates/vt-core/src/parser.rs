use vte::{Params, Perform};

use crate::alt::AltGrid;
use crate::attribute_map::AttributeMap;
use crate::block::{Block, BlockMeta, BlockSource, BlockState};
use crate::block_grid::BlockGrid;
use crate::content::Content;
use crate::delta::{Delta, DeltaKind};
use crate::limits::Limits;
use crate::row_index::{RowIndex, RowRange};
use crate::screen::{ClearPolicy, ScreenGrid};
use crate::style::{CellStyle, StyleCode};

pub struct HistoryRow {
    pub bytes: Vec<u8>,
    pub wrapped: bool,
    pub indent: u16,
    pub styles: Vec<(u32, CellStyle)>,
}

pub struct HistoryBlock {
    pub first_row: usize,
    pub row_count: usize,
    pub command: String,
    pub exit_code: Option<i32>,
}

const MAX_QUERY_REPLY_BYTES: usize = 4096;

pub(crate) struct Parser {
    width: usize,
    content: Content,
    rows: RowIndex,
    styles: AttributeMap<CellStyle>,
    pending_style: CellStyle,
    grid: BlockGrid,
    screen: ScreenGrid,
    alt: Option<AltGrid>,
    saved_style: CellStyle,
    app_cursor: bool,
    sgr_mouse: bool,
    bracketed_paste: bool,
    focus_reporting: bool,
    mouse_tracking: u8,
    rewrap_pending: bool,
    query_replies: Option<Vec<u8>>,
    terminal_identity: String,
    trimmed_total: u64,
    generation: u64,
    history_exported_rows: usize,
    pending_full: bool,
    pending_trimmed: usize,
    pending_remap: Option<Vec<(u64, u64)>>,
    pending_rewritten_from: Option<usize>,
    last_width: usize,
    #[cfg(feature = "trace")]
    pub(crate) trace: crate::trace::Trace,
}

impl Parser {
    pub fn new(width: usize) -> Self {
        let mut screen = ScreenGrid::new(24, width);
        screen.set_records_eviction(true);
        Self {
            width,
            content: Content::with_base(crate::content::CONTENT_BASE),
            rows: RowIndex::new(crate::content::CONTENT_BASE),
            styles: AttributeMap::with_base(CellStyle::DEFAULT, crate::content::CONTENT_BASE),
            pending_style: CellStyle::DEFAULT,
            grid: BlockGrid::new(),
            screen,
            alt: None,
            saved_style: CellStyle::DEFAULT,
            app_cursor: false,
            sgr_mouse: false,
            bracketed_paste: false,
            focus_reporting: false,
            mouse_tracking: 0,
            rewrap_pending: false,
            query_replies: None,
            terminal_identity: String::new(),
            trimmed_total: 0,
            generation: 0,
            history_exported_rows: 0,
            pending_full: true,
            pending_trimmed: 0,
            pending_remap: None,
            pending_rewritten_from: None,
            last_width: width,
            #[cfg(feature = "trace")]
            trace: Default::default(),
        }
    }

    pub fn content(&self) -> &Content {
        &self.content
    }

    pub fn rows(&self) -> &RowIndex {
        &self.rows
    }

    pub fn styles(&self) -> &AttributeMap<CellStyle> {
        &self.styles
    }

    /// The stable id of flat row 0 — the number of rows trimmed off the
    /// front so far (wezterm/term/src/screen.rs:30 `stable_row_index_offset`).
    pub fn first_stable_row(&self) -> u64 {
        self.trimmed_total
    }

    pub(crate) fn trimmed_total(&self) -> u64 {
        self.trimmed_total
    }

    pub(crate) fn note_mutation(&mut self) {
        self.generation = self.generation.wrapping_add(1);
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }

    pub(crate) fn history_exported_rows(&self) -> usize {
        self.history_exported_rows
    }

    fn mark_full(&mut self) {
        self.pending_full = true;
    }

    fn note_remap(&mut self, map: &[usize]) {
        let Some((_, old_rows)) = map.split_last() else {
            return;
        };
        let origin = self.trimmed_total;
        let pairs: Vec<(u64, u64)> = old_rows
            .iter()
            .enumerate()
            .map(|(old, &new)| (old as u64 + origin, new as u64 + origin))
            .collect();
        self.pending_remap = Some(match self.pending_remap.take() {
            None => pairs,
            Some(previous) => previous
                .into_iter()
                .map(|(first, mid)| {
                    let last = mid
                        .checked_sub(origin)
                        .and_then(|index| old_rows.get(index as usize))
                        .map_or(mid, |&new| new as u64 + origin);
                    (first, last)
                })
                .collect(),
        });
    }

    pub fn take_delta(&mut self) -> Delta {
        let completed = self.rows.completed().len();
        let full = std::mem::take(&mut self.pending_full) || self.alt.is_some();
        let screen_rows = if full {
            self.screen.take_dirty();
            (0..self.screen.content_rows()).collect()
        } else {
            self.screen.take_dirty()
        };
        let delta = Delta {
            generation: self.generation,
            kind: if full {
                DeltaKind::Full
            } else {
                DeltaKind::Partial
            },
            trimmed_rows: std::mem::take(&mut self.pending_trimmed),
            appended_history: self.history_exported_rows.min(completed)..completed,
            screen_rows,
            remap: self.pending_remap.take(),
            history_rewritten_from: self.pending_rewritten_from.take(),
        };
        self.history_exported_rows = completed;
        delta
    }

    pub fn stable_row(&self, flat: usize) -> u64 {
        flat as u64 + self.trimmed_total
    }

    /// The flat index of a stable row, or `None` once that row has been
    /// trimmed away (wezterm/term/src/screen.rs:523-535).
    pub fn flat_row(&self, stable: u64) -> Option<usize> {
        stable
            .checked_sub(self.trimmed_total)
            .map(|flat| flat as usize)
    }

    pub fn grid(&self) -> &BlockGrid {
        &self.grid
    }

    pub fn grid_mut(&mut self) -> &mut BlockGrid {
        &mut self.grid
    }

    #[cfg(test)]
    pub(crate) fn rows_mut(&mut self) -> &mut RowIndex {
        &mut self.rows
    }

    #[cfg(test)]
    pub(crate) fn styles_mut(&mut self) -> &mut AttributeMap<CellStyle> {
        &mut self.styles
    }

    pub(crate) fn open_block(&mut self, source: BlockSource) {
        self.commit_evicted();
        let first_row = self.block_start_row();
        self.materialize_uncovered_rows(first_row, BlockState::Abandoned, None);
        self.grid.sync_next_row(first_row);
        self.grid.open_block(source);
    }

    pub(crate) fn process_boundary(&mut self, exit_code: Option<i32>) {
        self.mark_full();
        if self.alt.is_some() {
            self.leave_alt();
        }
        self.commit_evicted();
        let end_row = self.rows.completed().len() + self.screen.frame_rows();
        if self.grid.has_open_block() {
            self.grid.sync_next_row(end_row);
            self.grid.close_block(exit_code);
        } else {
            self.materialize_uncovered_rows(end_row, BlockState::Finished, exit_code);
        }
        self.screen.evict_frame();
        self.commit_evicted();
        self.grid.sync_next_row(self.rows.completed().len());
        self.pending_style = CellStyle::DEFAULT;
        self.sync_erase_background();
    }

    fn materialize_uncovered_rows(
        &mut self,
        end_row: usize,
        state: BlockState,
        exit_code: Option<i32>,
    ) {
        if self.grid.has_open_block() {
            return;
        }
        let first_row = self.grid.covered_end();
        if end_row > first_row && self.rows_have_content(first_row, end_row) {
            self.grid
                .push_synthetic(first_row, end_row, state, exit_code);
        }
    }

    fn rows_have_content(&self, first_row: usize, end_row: usize) -> bool {
        let completed = self.rows.completed();
        (first_row..end_row).any(|row| match completed.get(row) {
            Some(range) => range.end > range.start,
            None => self.screen.row_has_content(row - completed.len()),
        })
    }

    pub(crate) fn start_output(&mut self) {
        self.commit_evicted();
        self.grid.start_output(self.block_start_row());
    }

    pub(crate) fn close_block(&mut self, exit_code: Option<i32>) {
        self.commit_evicted();
        let next_row = self.block_end_row();
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
        self.mark_full();
        self.commit_evicted();
        let mut alt = ScreenGrid::new(rows, self.width);
        alt.set_records_eviction(false);
        alt.set_clear_policy(ClearPolicy::ClearInPlace);
        self.alt = Some(alt);
        self.saved_style = self.pending_style;
        self.pending_style = CellStyle::DEFAULT;
        self.sync_erase_background();
    }

    pub fn leave_alt(&mut self) {
        self.mark_full();
        self.alt = None;
        self.pending_style = self.saved_style;
        self.sync_erase_background();
    }

    pub fn alt(&self) -> Option<&AltGrid> {
        self.alt.as_ref()
    }

    pub fn app_cursor(&self) -> bool {
        self.app_cursor
    }

    pub fn sgr_mouse(&self) -> bool {
        self.sgr_mouse
    }

    pub fn bracketed_paste(&self) -> bool {
        self.bracketed_paste
    }

    pub fn focus_reporting(&self) -> bool {
        self.focus_reporting
    }

    pub fn mouse_tracking(&self) -> bool {
        self.mouse_tracking != 0
    }

    pub fn mouse_tracking_level(&self) -> u8 {
        self.mouse_tracking
    }

    /// Records the DEC private modes that decide how a wheel event must be
    /// encoded. Warp gates the same decision on `SGR_MOUSE` plus any of the
    /// tracking modes (`alt_screen/mod.rs:11-25`); without both, a wheel falls
    /// back to arrow keys.
    fn note_private_mode(&mut self, mode: u16, set: bool) {
        let bit = match mode {
            1006 => {
                self.sgr_mouse = set;
                return;
            }
            // A program that asks for bracketed paste is telling us it can tell
            // pasted bytes from typed ones. Sending a paste unwrapped to one
            // that asked runs every newline in it as a command.
            2004 => {
                self.bracketed_paste = set;
                return;
            }
            1004 => {
                self.focus_reporting = set;
                return;
            }
            1000 => 0b001,
            1002 => 0b010,
            1003 => 0b100,
            _ => return,
        };
        if set {
            self.mouse_tracking |= bit;
        } else {
            self.mouse_tracking &= !bit;
        }
    }

    pub fn set_reflow_on_resize(&mut self, on: bool) {
        self.screen.set_reflow_on_resize(on);
    }

    pub fn set_answers_queries(&mut self, on: bool) {
        self.query_replies = if on { Some(Vec::new()) } else { None };
    }

    pub fn set_terminal_identity(&mut self, name: &str) {
        self.terminal_identity = name.chars().filter(|ch| !ch.is_control()).collect();
    }

    fn push_reply(&mut self, reply: &[u8]) {
        if let Some(replies) = self.query_replies.as_mut() {
            replies.extend_from_slice(reply);
            if replies.len() > MAX_QUERY_REPLY_BYTES {
                replies.drain(..replies.len() - MAX_QUERY_REPLY_BYTES);
            }
        }
    }

    fn answer_xtversion(&mut self) {
        if self.query_replies.is_none() || self.terminal_identity.is_empty() {
            return;
        }
        let reply = format!("\x1bP>|{}\x1b\\", self.terminal_identity);
        self.push_reply(reply.as_bytes());
    }

    pub fn take_query_replies(&mut self) -> Vec<u8> {
        self.query_replies
            .as_mut()
            .map(std::mem::take)
            .unwrap_or_default()
    }

    fn private_mode_status(&self, mode: u16) -> u8 {
        let set = match mode {
            1 => self.app_cursor,
            25 => self.screen.cursor_visible(),
            1000 => self.mouse_tracking & 0b001 != 0,
            1002 => self.mouse_tracking & 0b010 != 0,
            1003 => self.mouse_tracking & 0b100 != 0,
            1004 => self.focus_reporting,
            1006 => self.sgr_mouse,
            1049 => self.alt.is_some(),
            2004 => self.bracketed_paste,
            2026 => false,
            _ => return 0,
        };
        if set {
            1
        } else {
            2
        }
    }

    fn answer_decrqm(&mut self, params: &Params) {
        if self.query_replies.is_none() {
            return;
        }
        for group in params.iter() {
            let Some(mode) = group.first().copied() else {
                continue;
            };
            let status = self.private_mode_status(mode);
            self.push_reply(format!("\x1b[?{mode};{status}$y").as_bytes());
        }
    }

    pub fn set_agent_tui_mode(&mut self, on: bool) {
        self.screen.set_reflow_on_resize(!on);
        self.screen.set_clear_policy(if on {
            ClearPolicy::ClearInPlace
        } else {
            ClearPolicy::Scroll
        });
    }

    pub fn columns(&self) -> usize {
        self.width
    }

    pub fn resize(&mut self, columns: usize, rows: usize) {
        self.mark_full();
        if columns != self.width {
            self.rewrap_pending = true;
        }
        self.last_width = self.width;
        self.width = columns;
        if self.alt.is_some() {
            self.screen.resize_without_reflow(rows, columns);
        } else {
            self.screen.resize(rows, columns);
            self.commit_evicted();
        }
        if let Some(alt) = self.alt.as_mut() {
            alt.resize(rows, columns);
        }
        self.grid
            .clamp_to_rows(self.rows.completed().len() + self.screen.rows());
    }

    pub(crate) fn commit_evicted(&mut self) {
        if self.alt.is_some() {
            return;
        }
        for row in self.screen.take_evicted() {
            crate::scrollback::commit_row(
                &row.cells,
                row.wrapped,
                &mut self.content,
                &mut self.rows,
                &mut self.styles,
            );
            self.grid.note_row_completed();
        }
        if std::mem::take(&mut self.rewrap_pending) {
            let cut_at = std::mem::replace(&mut self.last_width, self.width);
            let map = self.rows.rewrap_hot(&self.content, self.width, cut_at);
            self.grid.remap_rows(&map);
            self.note_remap(&map);
            self.history_exported_rows = self
                .history_exported_rows
                .min(self.rows.completed().len())
                .min(
                    self.rows
                        .completed()
                        .len()
                        .saturating_sub(crate::row_index::HOT_ROWS),
                );
            self.pending_rewritten_from = Some(
                self.pending_rewritten_from.unwrap_or(usize::MAX).min(
                    self.rows
                        .completed()
                        .len()
                        .saturating_sub(crate::row_index::HOT_ROWS),
                ),
            );
        }
        self.grid
            .sync_next_row(self.rows.completed().len() + self.screen.content_rows());
    }

    fn block_start_row(&self) -> usize {
        let screen_rows = self.screen.content_rows();
        self.rows.completed().len() + self.screen.cursor().0.min(screen_rows)
    }

    fn block_end_row(&self) -> usize {
        let screen_rows = self.screen.content_rows();
        let cursor_row = self.screen.cursor().0.min(screen_rows);
        let visible_cursor_row =
            usize::from(cursor_row < screen_rows && self.screen.row_has_content(cursor_row));
        self.rows.completed().len() + (cursor_row + visible_cursor_row).min(screen_rows)
    }

    pub fn adopt_origin(&mut self, origin: u64) -> bool {
        if self.trimmed_total != 0
            || !self.rows.completed().is_empty()
            || self.screen.frame_rows() != 0
        {
            return false;
        }
        self.trimmed_total = origin;
        self.grid.advance_origin(origin as usize);
        self.note_mutation();
        true
    }

    pub fn apply_history_chunk(
        &mut self,
        first_stable_row: u64,
        rows: Vec<HistoryRow>,
        blocks: Vec<HistoryBlock>,
    ) -> bool {
        if rows.is_empty() || first_stable_row + rows.len() as u64 != self.trimmed_total {
            return false;
        }
        let mut bytes = Vec::new();
        let mut lengths = Vec::with_capacity(rows.len());
        for row in &rows {
            bytes.extend_from_slice(&row.bytes);
            lengths.push(row.bytes.len() as u64);
        }
        let base = self.content.prepend(&bytes);
        let mut runs: Vec<(u64, CellStyle)> = Vec::new();
        let mut ranges = Vec::with_capacity(rows.len());
        let mut cursor = base;
        for (row, length) in rows.iter().zip(lengths) {
            for (end, style) in &row.styles {
                runs.push((cursor + u64::from(*end), *style));
            }
            ranges.push(RowRange {
                start: cursor,
                end: cursor + length,
                wrapped: row.wrapped && length > 0,
                indent: row.indent,
            });
            cursor += length;
        }
        self.styles.prepend_runs(&runs);
        let count = ranges.len();
        self.rows.prepend(ranges);
        self.trimmed_total = first_stable_row;
        self.grid.retreat_origin(count);
        let history_blocks: Vec<Block> = blocks
            .into_iter()
            .map(|block| self.history_block(first_stable_row, block))
            .collect();
        self.grid.prepend_blocks(history_blocks);
        self.history_exported_rows = 0;
        self.mark_full();
        self.note_mutation();
        true
    }

    fn history_block(&mut self, first_stable_row: u64, block: HistoryBlock) -> Block {
        let id = self.grid.next_id();
        self.grid.reserve_id();
        let meta = BlockMeta {
            command: block.command,
            ..BlockMeta::default()
        };
        Block {
            id,
            first_row: (first_stable_row as usize) + block.first_row,
            row_count: block.row_count,
            state: BlockState::Finished,
            source: BlockSource::Extension,
            meta,
        }
    }

    pub fn trim_to(&mut self, limits: Limits) -> usize {
        let before = self.rows.completed().len();
        loop {
            let completed = self.rows.completed().len();
            let over_rows = completed + 1 > limits.rows;
            let over_bytes = self.content.resident_bytes() + self.styles.byte_len() > limits.bytes;
            if completed == 0 || !(over_rows || over_bytes) {
                break;
            }
            let keep = if over_rows { limits.rows } else { completed };
            let Some(new_start) = self.rows.trim_to(keep) else {
                break;
            };
            self.content.drop_before(new_start);
            self.styles.drop_before(new_start);
        }
        let dropped = before - self.rows.completed().len();
        if dropped > 0 {
            let exported_dropped = dropped.min(self.history_exported_rows);
            self.history_exported_rows -= exported_dropped;
            self.pending_trimmed += exported_dropped;
            self.trimmed_total += dropped as u64;
            self.grid.advance_origin(dropped);
        }
        dropped
    }

    pub fn touch_rows(&mut self, range: std::ops::Range<usize>) {
        let Some((map, lowest)) = self.rows.rows_for(&self.content, self.width, range) else {
            return;
        };
        self.grid.remap_rows(&map);
        self.note_remap(&map);
        self.history_exported_rows = self.history_exported_rows.min(lowest);
        self.pending_rewritten_from = Some(
            self.pending_rewritten_from
                .unwrap_or(usize::MAX)
                .min(lowest),
        );
        self.note_mutation();
    }

    pub fn stale_row_count(&self) -> usize {
        self.rows.stale_runs().iter().map(|run| run.len).sum()
    }

    fn apply_sgr(&mut self, params: &Params) {
        let groups: Vec<Vec<u16>> = params.iter().map(|sub| sub.to_vec()).collect();
        if groups.is_empty() {
            self.set_pending_style(CellStyle::DEFAULT);
            return;
        }
        let mut index = 0;
        while index < groups.len() {
            let group = &groups[index];
            let code = group.first().copied().unwrap_or(0);
            if matches!(code, 38 | 48 | 58) {
                let (colour, consumed) = read_extended_colour(&groups, index);
                if let Some(style) = colour {
                    match code {
                        38 => self.pending_style.fg = self.pending_style.fg.with_colour(style),
                        48 => self.pending_style.bg = style,
                        _ => {}
                    }
                }
                index += consumed;
                continue;
            }
            match code {
                0 => self.set_pending_style(CellStyle::DEFAULT),
                1 => self.pending_style.fg = self.pending_style.fg.with_bold(true),
                2 => self.pending_style.fg = self.pending_style.fg.with_dim(true),
                7 => self.pending_style.fg = self.pending_style.fg.with_reverse(true),
                22 => {
                    self.pending_style.fg = self.pending_style.fg.with_bold(false).with_dim(false);
                }
                27 => self.pending_style.fg = self.pending_style.fg.with_reverse(false),
                30..=37 => {
                    self.pending_style.fg = self
                        .pending_style
                        .fg
                        .with_colour(StyleCode::ansi((code - 30) as u8));
                }
                39 => {
                    self.pending_style.fg = self.pending_style.fg.with_colour(StyleCode::DEFAULT);
                }
                40..=47 => self.pending_style.bg = StyleCode::ansi((code - 40) as u8),
                49 => self.pending_style.bg = StyleCode::DEFAULT_BACKGROUND,
                90..=97 => {
                    self.pending_style.fg = self
                        .pending_style
                        .fg
                        .with_colour(StyleCode::ansi((code - 90 + 8) as u8));
                }
                100..=107 => self.pending_style.bg = StyleCode::ansi((code - 100 + 8) as u8),
                _ => {}
            }
            index += 1;
        }
        self.sync_erase_background();
    }

    fn set_pending_style(&mut self, style: CellStyle) {
        self.pending_style = style;
    }

    fn sync_erase_background(&mut self) {
        let bg = self.pending_style.bg;
        self.screen.set_erase_background(bg);
        if let Some(alt) = self.alt.as_mut() {
            alt.set_erase_background(bg);
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
pub(crate) fn read_extended_colour(
    groups: &[Vec<u16>],
    index: usize,
) -> (Option<StyleCode>, usize) {
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
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Print(c));
        let style = self.pending_style.resolved();
        self.active_screen_mut().print(c, style);
    }

    fn execute(&mut self, byte: u8) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Execute(byte));
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
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Csi {
            params: params.iter().map(|group| group.to_vec()).collect(),
            intermediates: intermediates.to_vec(),
            action: c,
        });
        if c == 'm' {
            self.apply_sgr(params);
            return;
        }
        if intermediates == b"?$" && c == 'p' {
            self.answer_decrqm(params);
            return;
        }
        if intermediates.is_empty()
            && c == 'c'
            && params
                .iter()
                .next()
                .and_then(|g| g.first().copied())
                .unwrap_or(0)
                == 0
        {
            self.push_reply(b"\x1b[?62;22c");
            return;
        }
        if intermediates == b">"
            && c == 'q'
            && params
                .iter()
                .next()
                .and_then(|g| g.first().copied())
                .unwrap_or(0)
                == 0
        {
            self.answer_xtversion();
            return;
        }
        if intermediates.first() == Some(&b'?') && matches!(c, 'h' | 'l') {
            let set = c == 'h';
            for group in params.iter() {
                match group.first().copied() {
                    Some(1) => self.app_cursor = set,
                    Some(mode) => self.note_private_mode(mode, set),
                    None => {}
                }
            }
        }
        self.active_screen_mut().csi(params, intermediates, c);
    }

    fn esc_dispatch(&mut self, intermediates: &[u8], _ignore: bool, byte: u8) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Esc {
            intermediates: intermediates.to_vec(),
            byte,
        });
        #[cfg(not(feature = "trace"))]
        let _ = intermediates;
        self.active_screen_mut().esc(byte);
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], _bell_terminated: bool) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Osc(
            params.iter().map(|p| p.to_vec()).collect(),
        ));
        #[cfg(not(feature = "trace"))]
        let _ = params;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use vte::Parser as VteParser;

    #[test]
    fn mouse_tracking_level_distinguishes_the_three_modes() {
        let mut p = Parser::new(80);
        let mut vte = VteParser::new();
        assert_eq!(p.mouse_tracking_level(), 0);
        vte.advance(&mut p, b"\x1b[?1000h");
        assert_eq!(p.mouse_tracking_level(), 0b001);
        vte.advance(&mut p, b"\x1b[?1002h");
        assert_eq!(p.mouse_tracking_level(), 0b011);
        vte.advance(&mut p, b"\x1b[?1003h");
        assert_eq!(p.mouse_tracking_level(), 0b111);
        vte.advance(&mut p, b"\x1b[?1002l");
        assert_eq!(p.mouse_tracking_level(), 0b101);
        assert!(p.mouse_tracking());
        vte.advance(&mut p, b"\x1b[?1000l");
        vte.advance(&mut p, b"\x1b[?1003l");
        assert_eq!(p.mouse_tracking_level(), 0);
        assert!(!p.mouse_tracking());
    }

    #[test]
    fn focus_reporting_mode_is_tracked() {
        let mut p = Parser::new(80);
        let mut vte = VteParser::new();
        assert!(!p.focus_reporting());
        vte.advance(&mut p, b"\x1b[?1004h");
        assert!(p.focus_reporting());
        vte.advance(&mut p, b"\x1b[?1004l");
        assert!(!p.focus_reporting());
    }

    #[test]
    fn apply_history_chunk_prepends_rows_below_the_adopted_origin() {
        let mut p = Parser::new(20);
        assert!(p.adopt_origin(2));
        let rows = vec![
            HistoryRow {
                bytes: b"a\r\n".to_vec(),
                wrapped: false,
                indent: 0,
                styles: Vec::new(),
            },
            HistoryRow {
                bytes: b"b\r\n".to_vec(),
                wrapped: false,
                indent: 0,
                styles: Vec::new(),
            },
        ];
        assert!(p.apply_history_chunk(0, rows, Vec::new()));
        assert_eq!(p.trimmed_total(), 0);
        assert_eq!(p.rows().completed().len(), 2);
    }
}
