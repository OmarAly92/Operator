mod blocks;
mod cold;
mod colour;
mod history;
mod perform;
mod program;
mod resize;
mod unknown;

pub(crate) use colour::read_extended_colour;
pub use unknown::{
    UnknownSequence, UNKNOWN_FEED_BUDGET, UNKNOWN_SEQUENCES_CAP, UNKNOWN_TEXT_BYTES,
};

use vte::Params;

use crate::alt::AltGrid;
use crate::attribute_map::AttributeMap;
use crate::block_grid::BlockGrid;
use crate::content::Content;
use crate::delta::{Delta, DeltaKind};
use crate::hyperlink::HyperlinkRegistry;
use crate::row_index::RowIndex;
use crate::screen::{ClearPolicy, ScreenGrid};
use crate::style::CellStyle;
use crate::width::WidthMode;

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
    width_mode: WidthMode,
    hyperlinks: HyperlinkRegistry,
    program: crate::program::ProgramState,
    cold: crate::cold_ring::ColdRing,
    committed_rows: u64,
    run: Vec<u8>,
    input_mark: Option<(crate::block::BlockId, usize)>,
    pub(crate) unknown: unknown::UnknownRing,
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
            width_mode: WidthMode::default(),
            hyperlinks: HyperlinkRegistry::default(),
            program: crate::program::ProgramState::default(),
            cold: crate::cold_ring::ColdRing::default(),
            committed_rows: 0,
            run: Vec::new(),
            input_mark: None,
            unknown: unknown::UnknownRing::default(),
            #[cfg(feature = "trace")]
            trace: Default::default(),
        }
    }

    pub fn hyperlinks(&self) -> &HyperlinkRegistry {
        &self.hyperlinks
    }

    #[allow(dead_code)]
    pub(crate) fn hyperlinks_mut(&mut self) -> &mut HyperlinkRegistry {
        &mut self.hyperlinks
    }

    pub fn width_mode(&self) -> WidthMode {
        self.width_mode
    }

    pub fn set_width_mode(&mut self, mode: WidthMode) {
        self.width_mode = mode;
        self.screen.set_width_mode(mode);
        if let Some(alt) = self.alt.as_mut() {
            alt.set_width_mode(mode);
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
        alt.set_width_mode(self.width_mode);
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
            2048 => {
                self.note_in_band_resize_mode(set);
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
            2048 => self.program.in_band_resize(),
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
            self.committed_rows += 1;
            self.grid.note_row_completed();
        }
        if std::mem::take(&mut self.rewrap_pending) {
            let cut_at = std::mem::replace(&mut self.last_width, self.width);
            let map = self
                .rows
                .rewrap_hot(&self.content, self.width, cut_at, self.width_mode);
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

    pub fn touch_rows(&mut self, range: std::ops::Range<usize>) {
        let Some((map, lowest)) =
            self.rows
                .rows_for(&self.content, self.width, range, self.width_mode)
        else {
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

    pub(crate) fn committed_rows(&self) -> u64 {
        self.committed_rows
    }

    pub fn stale_row_count(&self) -> usize {
        self.rows.stale_runs().iter().map(|run| run.len).sum()
    }

    fn apply_sgr(&mut self, params: &Params) {
        crate::sgr::apply(&mut self.pending_style, params);
        self.sync_erase_background();
    }

    fn sync_erase_background(&mut self) {
        let bg = self.pending_style.bg;
        self.screen.set_erase_background(bg);
        if let Some(alt) = self.alt.as_mut() {
            alt.set_erase_background(bg);
        }
    }
}

#[cfg(test)]
mod tests;
