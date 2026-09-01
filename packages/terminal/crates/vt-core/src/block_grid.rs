use crate::block::{Block, BlockId, BlockMeta, BlockSource, BlockState};
use crate::block_tree::BlockTree;

/// The state machine that turns a stream of mark events into a list of
/// blocks. It owns a [`BlockTree`] of finished/abandoned blocks, an
/// optional open block, and a monotonic id source; row indices are kept
/// relative to the oldest retained row, which is what makes `trim_to_first_row`
/// a renumber rather than an offset.
pub struct BlockGrid {
    closed: BlockTree,
    open: Option<Block>,
    next_id: BlockId,
    /// Index of the next row to be completed, relative to the oldest
    /// retained row. It is where the next opened block starts, and it is
    /// what stops every block from claiming row 0.
    next_row: usize,
}

impl BlockGrid {
    pub fn new() -> Self {
        Self {
            closed: BlockTree::new(),
            open: None,
            next_id: 0,
            next_row: 0,
        }
    }

    /// Start a new block. If a block was already open, the old one is
    /// closed as [`BlockState::Abandoned`] — the previous prompt exited
    /// without an OSC 133 finish, so its exit code is unknown and the
    /// renderer should not pretend otherwise.
    pub fn open_block(&mut self, source: BlockSource) {
        if let Some(mut prev) = self.open.take() {
            prev.row_count = self.next_row.saturating_sub(prev.first_row);
            let abandoned = Block {
                state: BlockState::Abandoned,
                ..prev
            };
            self.closed.push(abandoned);
        }
        self.open = Some(Block {
            id: self.next_id,
            first_row: self.next_row,
            row_count: 0,
            state: BlockState::Running,
            source,
            meta: BlockMeta::default(),
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
        block.row_count = self.next_row.saturating_sub(block.first_row);
        block.state = BlockState::Finished;
        block.meta.exit_code = exit_code;
        self.closed.push(block);
    }

    pub fn note_row_completed(&mut self) {
        self.next_row += 1;
    }

    pub fn sync_next_row(&mut self, next_row: usize) {
        self.next_row = next_row;
    }

    pub fn remove_row(&mut self, row: usize) {
        let mut closed_blocks = Vec::new();
        while let Some(block) = self.closed.pop_front() {
            closed_blocks.push(block);
        }
        for mut block in closed_blocks {
            rebase_after_row_removal(&mut block, row);
            self.closed.push(block);
        }
        if let Some(block) = self.open.as_mut() {
            rebase_after_row_removal(block, row);
        }
        if row < self.next_row {
            self.next_row -= 1;
        }
    }

    /// Apply a tier-2 extension field to the open block. Unknown keys are
    /// ignored: a malformed or unrecognized payload must not mutate the
    /// block source. Setting any recognised field also upgrades the block
    /// from `Osc133` to `Extension`, so the renderer can tell a
    /// bootstrapped block apart from a raw OSC 133 one.
    pub fn set_meta_field(&mut self, key: &str, value: &str) {
        let Some(block) = self.open.as_mut() else {
            return;
        };
        let recognised = match key {
            "cmd" => {
                block.meta.command = value.to_string();
                true
            }
            "cwd" => {
                block.meta.cwd = value.to_string();
                true
            }
            "branch" => {
                block.meta.git_branch = value.to_string();
                true
            }
            "exit" => {
                if let Ok(code) = value.parse::<i32>() {
                    block.meta.exit_code = Some(code);
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
                    block.meta.started_at_ms = Some(ts);
                }
                // See "exit" above for why a recognised key still
                // upgrades on a parse failure.
                true
            }
            "end_ms" => {
                if let Ok(ts) = value.parse::<u64>() {
                    block.meta.finished_at_ms = Some(ts);
                }
                // See "exit" above for why a recognised key still
                // upgrades on a parse failure.
                true
            }
            _ => false,
        };
        if recognised && block.source == BlockSource::Osc133 {
            // Only `Osc133` upgrades: a `Synthetic` block is already
            // tagged as not-from-the-shell, and rewriting the source would
            // hide that distinction from the renderer. `Extension` is
            // already the richer tag, so there is nothing to upgrade to.
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
        self.closed.set_meta(id, |meta| meta.bookmarked = bookmarked);
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

    /// Drop everything before `first_row` and renumber so the oldest
    /// surviving block starts at row 0. Renumbering every survivor is
    /// O(n); a root-level offset would make it O(log n), but that is a
    /// future perf-gate optimisation and is not justified yet (trimming
    /// runs once per feed, only past the row cap). The deliberate-O(n)
    /// decision is recorded for the CHANGELOG in Task 11.
    pub fn trim_to_first_row(&mut self, first_row: usize) {
        let open_row_count_pre_trim = self
            .open
            .as_ref()
            .map(|block| self.next_row.saturating_sub(block.first_row));
        // The row cursor is relative to the oldest retained row, so it
        // rebases with everything else.
        self.next_row = self.next_row.saturating_sub(first_row);

        let open_first_row_pre_trim = self.open.as_ref().map(|block| block.first_row);

        // Phase 1: pop whole blocks off the front whose row range ends at or
        // before `first_row`. They have no surviving rows, so no
        // renumbering work is owed on them.
        while let Some(front) = self.closed.iter().next() {
            if front.first_row + front.row_count <= first_row {
                self.closed.pop_front();
            } else {
                break;
            }
        }

        // Phase 2: drain the remaining tree, renumber every survivor, and
        // push them back. The cut can land inside the front block; that
        // block is the rebasing reference and lands at `first_row = 0`
        // with its surviving rows only, while every later closed block
        // shifts down by `first_row` to track the new row 0. Special-
        // casing the front block avoids subtracting from its `first_row`
        // when the cut has already moved the row-0 anchor into the
        // middle of it.
        let shift = first_row;
        let mut drained: Vec<Block> = Vec::new();
        while let Some(block) = self.closed.pop_front() {
            drained.push(block);
        }
        let mut first = true;
        for mut block in drained {
            let drop_within = first_row.saturating_sub(block.first_row);
            if first {
                first = false;
                block.first_row = 0;
            } else {
                block.first_row -= shift;
            }
            block.row_count = block.row_count.saturating_sub(drop_within);
            self.closed.push(block);
        }
        if let Some(block) = self.open.as_mut() {
            let open_first_row_pre_trim = open_first_row_pre_trim.unwrap_or_default();
            let drop_within = first_row.saturating_sub(open_first_row_pre_trim);
            block.first_row = open_first_row_pre_trim.saturating_sub(first_row);
            block.row_count = open_row_count_pre_trim
                .unwrap_or_default()
                .saturating_sub(drop_within);
        }
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

fn rebase_after_row_removal(block: &mut Block, row: usize) {
    if row < block.first_row {
        block.first_row -= 1;
    } else if row < block.first_row + block.row_count {
        block.row_count -= 1;
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

        grid.trim_to_first_row(2);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].first_row, 0, "surviving rows renumber from zero");
    }

    #[test]
    fn a_partially_trimmed_block_keeps_its_surviving_rows() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        for _ in 0..5 {
            grid.note_row_completed();
        }
        grid.trim_to_first_row(2);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].first_row, 0);
        assert_eq!(blocks[0].row_count, 3);
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
        grid.trim_to_first_row(2);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 2);
        assert_eq!(blocks[0].first_row, 0);
        assert_eq!(blocks[0].row_count, 3);
        assert_eq!(blocks[1].first_row, 3);
        assert_eq!(blocks[1].row_count, 1);
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
        grid.trim_to_first_row(5);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 1);
        assert_eq!(
            blocks[0].first_row, 0,
            "open block rebases to row 0 after phase 1 empties closed"
        );
        assert_eq!(
            blocks[0].row_count, 3,
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

        grid.trim_to_first_row(5);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].first_row, 0);
        assert_eq!(blocks[0].row_count, 3);
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
}
