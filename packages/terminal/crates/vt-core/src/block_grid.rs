use crate::block::{Block, BlockId, BlockMeta, BlockSource, BlockState};
use crate::block_tree::BlockTree;

/// The state machine that turns a stream of mark events into a list of
/// blocks. It owns a [`BlockTree`] of finished/abandoned blocks, an
/// optional open block, and a monotonic id source; row indices are stored
/// as stable rows, so a trim advances `origin` instead of renumbering
/// every survivor (wezterm/term/src/screen.rs:30 `stable_row_index_offset`).
///
/// The two surfaces differ. The methods that take or return a bare row —
/// `start_output`, `covered_end`, `next_row`, `sync_next_row`,
/// `push_synthetic`, `clamp_to_rows`, `remap_rows`, `flat_extent` — speak
/// **flat** rows and convert against `origin` here. [`Block::first_row`]
/// itself is **stable**, so everything that reads it straight off a block —
/// `blocks()`, `get()`, and the [`BlockTree`]/`BlockSummary` indexes built
/// from it — is stable too. Use `flat_extent` to cross the seam.
pub struct BlockGrid {
    closed: BlockTree,
    open: Option<Block>,
    next_id: BlockId,
    pending_meta: BlockMeta,
    pending_extension: bool,
    /// Stable index of the next row to be completed. It is where the next
    /// opened block starts, and it is what stops every block from claiming
    /// the first row.
    next_row: usize,
    /// Stable row of flat row 0: the number of rows trimmed off the front
    /// so far (wezterm/term/src/screen.rs:734).
    origin: usize,
    retreat_slack: usize,
    clock_ms: u64,
    trailing_started_at_ms: Option<u64>,
}

impl BlockGrid {
    pub fn new() -> Self {
        Self {
            closed: BlockTree::new(),
            open: None,
            next_id: 0,
            pending_meta: BlockMeta::default(),
            pending_extension: false,
            next_row: 0,
            origin: 0,
            retreat_slack: 0,
            clock_ms: 0,
            trailing_started_at_ms: None,
        }
    }

    pub fn origin(&self) -> usize {
        self.origin
    }

    pub fn set_clock(&mut self, now_ms: u64) {
        self.clock_ms = now_ms;
    }

    pub fn note_output(&mut self) {
        if self.open.is_none() && self.trailing_started_at_ms.is_none() {
            self.trailing_started_at_ms = Some(self.clock_ms);
        }
    }

    pub fn trailing_started_at_ms(&self) -> Option<u64> {
        self.trailing_started_at_ms
    }

    /// Drop `dropped` rows off the front. Only closed blocks whose rows are
    /// wholly gone are popped; the open block always survives, however far
    /// the cut reached into it (wezterm/term/src/screen.rs:523-535).
    pub fn advance_origin(&mut self, dropped: usize) {
        self.origin += dropped;
        while let Some(front) = self.closed.iter().next() {
            if front.first_row + front.row_count <= self.origin {
                self.closed.pop_front();
            } else {
                break;
            }
        }
        self.next_row = self.next_row.max(self.origin);
    }

    pub fn retreat_origin(&mut self, prepended: usize) {
        let underflow = prepended.saturating_sub(self.origin);
        self.origin = self.origin.saturating_sub(prepended);
        self.retreat_slack += underflow;
    }

    pub fn prepend_blocks(&mut self, blocks: Vec<Block>) {
        if blocks.is_empty() {
            return;
        }
        let existing: Vec<Block> = self.closed.iter().cloned().collect();
        self.closed = BlockTree::new();
        for block in blocks.into_iter().chain(existing) {
            self.closed.push(block);
        }
    }

    /// The block's `(first_row, row_count)` in flat rows, clamped to the
    /// origin, so a block that predates a trim reports only its surviving
    /// rows (wezterm/term/src/screen.rs:523-535 `stable_row_to_phys`). An
    /// open block carries no `row_count` until it closes, so its end is
    /// `next_row` — the same end [`BlockGrid::close_block`] will give it.
    pub fn flat_extent(&self, block: &Block) -> (usize, usize) {
        let stable_end = if self.is_open(block) {
            self.next_row.max(block.first_row)
        } else {
            block.first_row + block.row_count
        };
        let first = block.first_row.max(self.origin) - self.origin + self.retreat_slack;
        let end = stable_end.max(self.origin) - self.origin + self.retreat_slack;
        (first, end - first)
    }

    fn is_open(&self, block: &Block) -> bool {
        self.open.as_ref().is_some_and(|open| open.id == block.id)
    }

    /// Start a new block. If a block was already open, the old one is
    /// closed as [`BlockState::Abandoned`] — the previous prompt exited
    /// without an OSC 133 finish, so its exit code is unknown and the
    /// renderer should not pretend otherwise.
    pub fn open_block(&mut self, source: BlockSource) {
        if let Some(mut prev) = self.open.take() {
            prev.first_row = prev.first_row.min(self.next_row);
            prev.row_count = self.next_row - prev.first_row;
            prev.meta.finished_at_ms.get_or_insert(self.clock_ms);
            let abandoned = Block {
                state: BlockState::Abandoned,
                ..prev
            };
            self.closed.push(abandoned);
        }
        let source = if self.pending_extension && source == BlockSource::Osc133 {
            BlockSource::Extension
        } else {
            source
        };
        self.pending_extension = false;
        let mut meta = std::mem::take(&mut self.pending_meta);
        meta.started_at_ms.get_or_insert(self.clock_ms);
        self.trailing_started_at_ms = None;
        self.open = Some(Block {
            id: self.next_id,
            first_row: self.next_row,
            row_count: 0,
            state: BlockState::Running,
            source,
            meta,
        });
        self.next_id += 1;
    }

    /// Close the currently open block with an optional exit code. A close
    /// without an open block is ignored — the stream is allowed to emit an
    /// extra finish, and that must not crash or fabricate a block.
    pub fn close_block(&mut self, exit_code: Option<i32>) {
        let Some(mut block) = self.open.take() else {
            return;
        };
        block.first_row = block.first_row.min(self.next_row);
        block.row_count = self.next_row - block.first_row;
        block.state = BlockState::Finished;
        block.meta.exit_code = exit_code;
        block.meta.finished_at_ms.get_or_insert(self.clock_ms);
        self.closed.push(block);
    }

    pub(crate) fn start_output(&mut self, first_row: usize) {
        if let Some(block) = self.open.as_mut() {
            if !block.meta.command.is_empty() {
                block.first_row = self.origin + first_row;
            }
        }
    }

    pub fn covered_end(&self) -> usize {
        let stable = match (&self.open, self.closed.len()) {
            (Some(block), _) => block.first_row,
            (None, 0) => self.origin,
            (None, len) => self
                .closed
                .get(len - 1)
                .map_or(self.origin, |block| block.first_row + block.row_count),
        };
        stable.max(self.origin) - self.origin
    }

    pub fn next_row(&self) -> usize {
        self.next_row - self.origin
    }

    pub fn has_open_block(&self) -> bool {
        self.open.is_some()
    }

    pub fn next_id(&self) -> BlockId {
        self.next_id
    }

    pub fn reserve_id(&mut self) {
        self.next_id += 1;
    }

    pub fn push_synthetic(
        &mut self,
        first_row: usize,
        end_row: usize,
        state: BlockState,
        exit_code: Option<i32>,
    ) {
        if end_row <= first_row {
            return;
        }
        self.closed.push(Block {
            id: self.next_id,
            first_row: self.origin + first_row,
            row_count: end_row - first_row,
            state,
            source: BlockSource::Synthetic,
            meta: BlockMeta {
                exit_code,
                started_at_ms: self.trailing_started_at_ms.take(),
                finished_at_ms: Some(self.clock_ms),
                ..BlockMeta::default()
            },
        });
        self.next_id += 1;
    }

    pub fn note_row_completed(&mut self) {
        self.next_row += 1;
    }

    pub fn sync_next_row(&mut self, next_row: usize) {
        self.next_row = self.origin + next_row;
    }

    /// Apply a tier-2 extension field to the open block. Unknown keys are
    /// ignored: a malformed or unrecognized payload must not mutate the
    /// block source. Setting any recognised field also upgrades the block
    /// from `Osc133` to `Extension`, so the renderer can tell a
    /// bootstrapped block apart from a raw OSC 133 one.
    pub fn set_meta_field(&mut self, key: &str, value: &str) {
        if self.open.is_none() {
            match key {
                "cwd" => self.pending_meta.cwd = value.to_string(),
                "branch" => self.pending_meta.git_branch = value.to_string(),
                "start_ms" => {
                    if let Ok(ts) = value.parse::<u64>() {
                        self.pending_meta.started_at_ms = Some(ts);
                    }
                }
                _ => return,
            }
            self.pending_extension = true;
            return;
        }
        let Some(block) = self.open.as_mut() else {
            return;
        };
        let meta = &mut block.meta;
        let recognised = match key {
            "cmd" => {
                meta.command = value.to_string();
                true
            }
            "cwd" => {
                meta.cwd = value.to_string();
                true
            }
            "branch" => {
                meta.git_branch = value.to_string();
                true
            }
            "exit" => {
                if let Ok(code) = value.parse::<i32>() {
                    meta.exit_code = Some(code);
                }
                // A recognised key with an unparseable value still
                // upgrades the source: the producer meant to extend the
                // block, the upgrade is the renderer's signal that an
                // extension channel exists, and silently dropping the
                // upgrade on a parse failure would let a malformed exit
                // value hide the channel from the snapshot.
                true
            }
            "start_ms" => {
                if let Ok(ts) = value.parse::<u64>() {
                    meta.started_at_ms = Some(ts);
                }
                // See "exit" above for why a recognised key still
                // upgrades on a parse failure.
                true
            }
            "end_ms" => {
                if let Ok(ts) = value.parse::<u64>() {
                    meta.finished_at_ms = Some(ts);
                }
                // See "exit" above for why a recognised key still
                // upgrades on a parse failure.
                true
            }
            _ => false,
        };
        if recognised && block.source == BlockSource::Osc133 {
            block.source = BlockSource::Extension;
        }
    }

    pub fn set_block_bookmarked(&mut self, id: BlockId, bookmarked: bool) {
        if let Some(block) = self.open.as_mut() {
            if block.id == id {
                block.meta.bookmarked = bookmarked;
                return;
            }
        }
        self.closed
            .set_meta(id, |meta| meta.bookmarked = bookmarked);
    }

    pub fn block_bookmarked(&self, id: BlockId) -> bool {
        if let Some(block) = self.open.as_ref() {
            if block.id == id {
                return block.meta.bookmarked;
            }
        }
        self.closed
            .find(id)
            .map(|block| block.meta.bookmarked)
            .unwrap_or(false)
    }

    pub fn clamp_to_rows(&mut self, total_rows: usize) {
        let limit = self.origin + total_rows;
        self.next_row = self.next_row.min(limit);
        if let Some(block) = self.open.as_mut() {
            block.first_row = block.first_row.min(limit);
        }
        let needs_clamp = self
            .closed
            .iter()
            .any(|block| block.first_row + block.row_count > limit);
        if !needs_clamp {
            return;
        }
        let mut drained: Vec<Block> = Vec::new();
        while let Some(block) = self.closed.pop_front() {
            drained.push(block);
        }
        for mut block in drained {
            block.first_row = block.first_row.min(limit);
            block.row_count = block.row_count.min(limit - block.first_row);
            self.closed.push(block);
        }
    }

    pub fn remap_rows(&mut self, map: &[usize]) {
        let Some((&new_len, old_rows)) = map.split_last() else {
            return;
        };
        let old_len = old_rows.len();
        let origin = self.origin;
        let remap = |stable: usize| -> usize {
            if stable < origin {
                return stable;
            }
            let row = stable - origin;
            let new_row = match map.get(row) {
                Some(&new_row) => new_row,
                None => row - old_len + new_len,
            };
            origin + new_row
        };
        let mut drained: Vec<Block> = Vec::new();
        while let Some(block) = self.closed.pop_front() {
            drained.push(block);
        }
        for mut block in drained {
            let end = remap(block.first_row + block.row_count);
            block.first_row = remap(block.first_row);
            block.row_count = end - block.first_row;
            self.closed.push(block);
        }
        if let Some(block) = self.open.as_mut() {
            block.first_row = remap(block.first_row);
        }
        self.next_row = remap(self.next_row);
    }

    /// Every block, closed and open, in insertion order. The open block
    /// is always the last element when present.
    pub fn blocks(&self) -> impl Iterator<Item = &Block> {
        self.closed.iter().chain(self.open.as_ref())
    }

    pub fn len(&self) -> usize {
        self.closed.len() + usize::from(self.open.is_some())
    }

    pub fn get(&self, index: usize) -> Option<&Block> {
        let closed_len = self.closed.len();
        if index < closed_len {
            return self.closed.get(index);
        }
        if index == closed_len {
            return self.open.as_ref();
        }
        None
    }

    pub fn is_empty(&self) -> bool {
        self.closed.is_empty() && self.open.is_none()
    }
}

impl Default for BlockGrid {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opening_a_block_closes_the_previous_one_as_abandoned() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();
        grid.open_block(BlockSource::Osc133);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 2);
        assert_eq!(blocks[0].state, BlockState::Abandoned);
        assert_eq!(blocks[1].state, BlockState::Running);
    }

    #[test]
    fn closing_records_the_exit_code_and_marks_finished() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        grid.close_block(Some(3));
        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks[0].state, BlockState::Finished);
        assert_eq!(blocks[0].meta.exit_code, Some(3));
    }

    #[test]
    fn closing_with_no_open_block_is_ignored() {
        let mut grid = BlockGrid::new();
        grid.close_block(Some(0));
        assert_eq!(grid.blocks().count(), 0);
    }

    #[test]
    fn trimming_drops_blocks_whose_rows_are_all_gone() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();
        grid.note_row_completed();
        grid.close_block(Some(0));
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();

        grid.advance_origin(2);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 1);
        assert_eq!(
            blocks[0].first_row, 2,
            "the open block keeps its stable row"
        );
        assert_eq!(grid.flat_extent(blocks[0]), (0, 1));
        assert_eq!(grid.origin(), 2);
    }

    #[test]
    fn a_partially_trimmed_block_keeps_its_surviving_rows() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        for _ in 0..5 {
            grid.note_row_completed();
        }
        grid.advance_origin(2);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].first_row, 0);
        assert_eq!(grid.flat_extent(blocks[0]), (0, 3));
    }

    #[test]
    fn extension_fields_upgrade_the_open_block_source() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        grid.set_meta_field("cmd", "git status");
        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks[0].source, BlockSource::Extension);
        assert_eq!(blocks[0].meta.command, "git status");
    }

    #[test]
    fn trim_inside_a_closed_block_does_not_underflow() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        for _ in 0..5 {
            grid.note_row_completed();
        }
        grid.close_block(Some(0));
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();
        grid.advance_origin(2);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 2);
        assert_eq!(grid.flat_extent(blocks[0]), (0, 3));
        assert_eq!(grid.flat_extent(blocks[1]), (3, 1));
    }

    #[test]
    fn trim_after_popping_all_closed_blocks_keeps_open_block_rows() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();
        grid.note_row_completed();
        grid.close_block(Some(0));
        grid.open_block(BlockSource::Osc133);
        for _ in 0..6 {
            grid.note_row_completed();
        }
        grid.advance_origin(5);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 1);
        assert_eq!(
            grid.flat_extent(blocks[0]),
            (0, 3),
            "rows 5..8 of the open block survive (pre-trim pos 2, 6 rows)"
        );
    }

    #[test]
    fn partial_trim_rebases_an_open_block_after_an_unmarked_prefix() {
        let mut grid = BlockGrid::new();
        grid.sync_next_row(2);
        grid.open_block(BlockSource::Osc133);
        for _ in 0..6 {
            grid.note_row_completed();
        }

        grid.advance_origin(5);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 1);
        assert_eq!(grid.flat_extent(blocks[0]), (0, 3));
    }

    #[test]
    fn remapping_rows_moves_every_block_with_the_rows_it_owns() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();
        grid.note_row_completed();
        grid.close_block(Some(0));
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();

        grid.remap_rows(&[0, 3, 4, 6]);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!((blocks[0].first_row, blocks[0].row_count), (0, 4));
        assert_eq!(blocks[1].first_row, 4);
        assert_eq!(grid.next_row, 6);
    }

    #[test]
    fn remapping_rows_shifts_a_block_that_starts_on_the_screen() {
        let mut grid = BlockGrid::new();
        grid.sync_next_row(5);
        grid.open_block(BlockSource::Osc133);

        grid.remap_rows(&[0, 2, 4]);

        assert_eq!(grid.blocks().next().unwrap().first_row, 7);
    }

    #[test]
    fn bookmark_round_trips_through_close() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();
        grid.close_block(Some(0));
        let id = grid.blocks().next().unwrap().id;
        assert!(!grid.block_bookmarked(id), "fresh block is not bookmarked");
        grid.set_block_bookmarked(id, true);
        assert!(grid.block_bookmarked(id), "the close keeps the bookmark");
        grid.set_block_bookmarked(id, false);
        assert!(!grid.block_bookmarked(id), "the bookmark clears");
    }

    #[test]
    fn bookmark_round_trips_through_open() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        let id = grid.open.as_ref().unwrap().id;
        assert!(!grid.block_bookmarked(id));
        grid.set_block_bookmarked(id, true);
        assert!(grid.block_bookmarked(id), "open block can be bookmarked");
    }

    #[test]
    fn bookmark_unknown_id_is_a_no_op() {
        let mut grid = BlockGrid::new();
        grid.set_block_bookmarked(99, true);
        assert!(!grid.block_bookmarked(99));
    }

    #[test]
    fn retreat_origin_keeps_existing_blocks_at_their_stable_rows() {
        let mut grid = BlockGrid::new();
        grid.sync_next_row(4);
        grid.push_synthetic(0, 4, BlockState::Finished, Some(0));
        let stable_before = grid.get(0).expect("block").first_row;
        grid.retreat_origin(3);
        assert_eq!(grid.origin(), 0);
        assert_eq!(grid.get(0).expect("block").first_row, stable_before);
        assert_eq!(grid.flat_extent(grid.get(0).expect("block")), (3, 4));
    }

    #[test]
    fn prepended_blocks_sort_before_the_existing_ones() {
        let mut grid = BlockGrid::new();
        grid.sync_next_row(2);
        grid.push_synthetic(0, 2, BlockState::Finished, Some(0));
        grid.retreat_origin(2);
        grid.prepend_blocks(vec![Block {
            id: 900,
            first_row: 0,
            row_count: 2,
            state: BlockState::Finished,
            source: BlockSource::Synthetic,
            meta: BlockMeta::default(),
        }]);
        let ids: Vec<_> = grid.blocks().map(|block| block.id).collect();
        assert_eq!(ids, vec![900, 0]);
    }
}
