use std::ops::Range;

use regex_automata::meta::Regex;

use crate::block::{Block, BlockId};
use crate::block_grid::BlockGrid;
use crate::content::Content;
use crate::row_index::RowIndex;

/// What the caller is searching for. Construction goes through the
/// associated `literal`/`regex` constructors so the variants stay the only
/// legal way to form a query; matching them is an internal detail.
pub enum FindQuery {
    Literal(String),
    Regex(Regex),
}

impl FindQuery {
    /// Substring search: every byte of the haystack that is exactly the
    /// pattern, with no metacharacters. Use this for the common case where
    /// the user is typing plain text into a find box.
    pub fn literal(needle: &str) -> Self {
        Self::Literal(needle.to_string())
    }

    /// Compile a regex. An unparseable pattern — for example, a user typing
    /// `(unclosed` into a find box — is an `Err`, never a panic, so a
    /// half-typed query can never take the terminal down.
    pub fn regex(pattern: &str) -> Result<Self, Box<regex_automata::meta::BuildError>> {
        Regex::new(pattern).map(Self::Regex).map_err(Box::new)
    }
}

/// A single hit inside a block. `byte_range` is relative to the block's own
/// bytes (the concatenation of its rows), so the renderer can re-anchor it
/// to the block's first byte without knowing the content offset.
pub struct FindMatch {
    pub block: BlockId,
    pub row: usize,
    pub byte_range: Range<usize>,
}

/// The walker that hands the search back to the caller a budget at a time.
/// The budget is in blocks, not rows, because the block grid is the cursor's
/// unit of progress; a block is the renderer's primary object and the find
/// results are bucketed by block anyway.
pub struct FindCursor<'a> {
    blocks: Vec<Block>,
    rows: &'a RowIndex,
    content: &'a Content,
    query: FindQuery,
    next_block: usize,
    results: Vec<FindMatch>,
    complete: bool,
}

impl<'a> FindCursor<'a> {
    pub(crate) fn new(
        grid: &'a BlockGrid,
        rows: &'a RowIndex,
        content: &'a Content,
        query: FindQuery,
    ) -> Self {
        let blocks = grid.blocks().cloned().collect();
        Self {
            blocks,
            rows,
            content,
            query,
            next_block: 0,
            results: Vec::new(),
            complete: false,
        }
    }

    /// Search up to `budget_blocks` more blocks. A cancelled cursor is a
    /// no-op: cancellation is the caller's signal that the user moved on,
    /// and any further results would just be thrown away.
    pub fn step(&mut self, budget_blocks: usize) {
        if self.complete {
            return;
        }
        for _ in 0..budget_blocks {
            if self.next_block >= self.blocks.len() {
                self.complete = true;
                return;
            }
            // Clone to release the borrow on `self.blocks` before the
            // `search_block` call, which needs `&mut self` to push into
            // `results`. The block is small enough that the allocation is
            // not worth restructuring around.
            let block = self.blocks[self.next_block].clone();
            self.search_block(&block);
            self.next_block += 1;
        }
        if self.next_block >= self.blocks.len() {
            self.complete = true;
        }
    }

    pub fn results(&self) -> &[FindMatch] {
        &self.results
    }

    pub fn is_complete(&self) -> bool {
        self.complete
    }

    /// Freeze the cursor. `step` becomes a no-op and `results` returns the
    /// set of matches already collected, in walk order.
    pub fn cancel(&mut self) {
        self.complete = true;
    }

    fn search_block(&mut self, block: &Block) {
        let byte_range = match block_byte_range(self.rows, block) {
            Some(range) => range,
            None => return,
        };
        let bytes = self.content.copy_range(byte_range.start, byte_range.end);
        if bytes.is_empty() {
            return;
        }
        match &self.query {
            FindQuery::Literal(needle) => search_literal(
                &bytes,
                needle,
                block,
                byte_range.start,
                self.rows,
                &mut self.results,
            ),
            FindQuery::Regex(re) => search_regex(
                re,
                &bytes,
                block,
                byte_range.start,
                self.rows,
                &mut self.results,
            ),
        }
    }
}

/// Byte range of a block's rows in the content buffer.
///
/// Every block owns the rows its command produced, so this is a plain lookup:
/// there is no fallback for a zero-row block, because a closed block with no
/// rows is a bug in mark/parse ordering rather than a case to paper over.
fn block_byte_range(rows: &RowIndex, block: &Block) -> Option<Range<u64>> {
    if block.row_count == 0 {
        return None;
    }
    let completed = rows.completed();
    let first = block.first_row;
    let last = block.first_row + block.row_count - 1;
    let first_row = completed.get(first)?;
    let last_row = completed.get(last)?;
    Some(first_row.start..last_row.end)
}

fn search_literal(
    bytes: &[u8],
    needle: &str,
    block: &Block,
    content_byte_start: u64,
    rows: &RowIndex,
    out: &mut Vec<FindMatch>,
) {
    let needle_bytes = needle.as_bytes();
    if needle_bytes.is_empty() {
        return;
    }
    let mut cursor = 0;
    while let Some(offset) = find_subslice(&bytes[cursor..], needle_bytes) {
        let block_offset = cursor + offset;
        let absolute = content_byte_start + block_offset as u64;
        out.push(FindMatch {
            block: block.id,
            row: row_for_offset(absolute, rows),
            byte_range: block_offset..block_offset + needle_bytes.len(),
        });
        cursor = block_offset + needle_bytes.len();
    }
}

fn search_regex(
    re: &Regex,
    bytes: &[u8],
    block: &Block,
    content_byte_start: u64,
    rows: &RowIndex,
    out: &mut Vec<FindMatch>,
) {
    for m in re.find_iter(bytes) {
        let range = m.range();
        let absolute = content_byte_start + range.start as u64;
        out.push(FindMatch {
            block: block.id,
            row: row_for_offset(absolute, rows),
            byte_range: range,
        });
    }
}

/// `memchr::memmem::Finder` would do this faster, but pulling in `memchr`
/// for a single substring search is not worth the dependency. The naive
/// scan is plenty fast for a find box sized in kilobytes.
fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.len() > haystack.len() {
        return None;
    }
    haystack.windows(needle.len()).position(|w| w == needle)
}

/// The row index that contains `absolute` (a content-space offset). Used
/// by both the literal and the regex paths so they agree on what "row"
/// means for a hit that lands on a row boundary.
fn row_for_offset(absolute: u64, rows: &RowIndex) -> usize {
    for (i, range) in rows.completed().iter().enumerate() {
        if absolute < range.end {
            return i;
        }
    }
    rows.completed().len().saturating_sub(1)
}
