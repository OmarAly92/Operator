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
    open_start_fixed: bool,
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
            open_start_fixed: false,
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
        self.open_start_fixed = meta.started_at_ms.is_some();
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
            if !self.open_start_fixed {
                block.meta.started_at_ms = Some(self.clock_ms);
                self.open_start_fixed = true;
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
                    self.open_start_fixed = true;
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
mod tests;
