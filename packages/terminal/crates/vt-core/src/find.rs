use std::ops::Range;

use memchr::memmem::Finder;
use regex_automata::meta::Regex;

use crate::block::{Block, BlockId};
use crate::block_grid::BlockGrid;
use crate::content::Content;
use crate::row_index::RowIndex;

/// What the caller is searching for. Construction goes through the
/// associated `literal`/`regex` constructors so the variants stay the only
/// legal way to form a query; matching them is an internal detail.
#[derive(Clone)]
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
#[derive(Clone)]
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
    grid: &'a BlockGrid,
    rows: &'a RowIndex,
    content: &'a Content,
    regex: Option<Regex>,
    prepared: PreparedSearch,
    next_block: usize,
    results: Vec<FindMatch>,
    complete: bool,
}

enum PreparedSearch {
    Literal(Finder<'static>),
    Regex,
}

impl<'a> FindCursor<'a> {
    pub(crate) fn new(
        grid: &'a BlockGrid,
        rows: &'a RowIndex,
        content: &'a Content,
        query: FindQuery,
    ) -> Self {
        Self::with_state(grid, rows, content, query, 0, Vec::new(), false)
    }

    pub(crate) fn with_state(
        grid: &'a BlockGrid,
        rows: &'a RowIndex,
        content: &'a Content,
        query: FindQuery,
        next_block: usize,
        results: Vec<FindMatch>,
        complete: bool,
    ) -> Self {
        let (regex, prepared) = match query {
            FindQuery::Literal(needle) => {
                let finder = Finder::new(needle.as_bytes()).into_owned();
                (None, PreparedSearch::Literal(finder))
            }
            FindQuery::Regex(re) => (Some(re), PreparedSearch::Regex),
        };
        Self {
            grid,
            rows,
            content,
            regex,
            prepared,
            next_block,
            results,
            complete,
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
            let Some(block) = self.grid.get(self.next_block) else {
                self.complete = true;
                return;
            };
            self.search_block(block);
            self.next_block += 1;
        }
        if self.grid.get(self.next_block).is_none() {
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

    pub fn next_block(&self) -> usize {
        self.next_block
    }

    pub fn into_parts(self) -> (usize, Vec<FindMatch>, bool) {
        (self.next_block, self.results, self.complete)
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
        match &self.prepared {
            PreparedSearch::Literal(finder) => {
                let mut cursor = 0;
                while let Some(offset) = finder.find(&bytes[cursor..]) {
                    let block_offset = cursor + offset;
                    let absolute = byte_range.start + block_offset as u64;
                    let needle_len = finder.needle().len();
                    self.results.push(FindMatch {
                        block: block.id,
                        row: row_for_offset(absolute, self.rows),
                        byte_range: block_offset..block_offset + needle_len,
                    });
                    cursor = block_offset + needle_len;
                }
            }
            PreparedSearch::Regex => {
                let re = self
                    .regex
                    .as_ref()
                    .expect("regex variant implies regex is Some");
                for m in re.find_iter(&bytes) {
                    let range = m.range();
                    let absolute = byte_range.start + range.start as u64;
                    self.results.push(FindMatch {
                        block: block.id,
                        row: row_for_offset(absolute, self.rows),
                        byte_range: range,
                    });
                }
            }
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

#[cfg(test)]
mod tests {
    use super::*;

    fn grid_with_blocks() -> (BlockGrid, RowIndex, Content) {
        (BlockGrid::new(), RowIndex::new(0), Content::new())
    }

    #[test]
    fn cursor_starts_empty_and_incomplete() {
        let (grid, rows, content) = grid_with_blocks();
        let cursor = FindCursor::new(&grid, &rows, &content, FindQuery::literal("anything"));
        assert!(cursor.results().is_empty());
        assert!(!cursor.is_complete());
        assert_eq!(cursor.next_block(), 0);
    }

    #[test]
    fn empty_needle_is_a_noop() {
        let (grid, rows, content) = grid_with_blocks();
        let mut cursor = FindCursor::new(&grid, &rows, &content, FindQuery::literal(""));
        cursor.step(1);
        assert!(cursor.results().is_empty());
    }

    #[test]
    fn cancelled_cursor_is_a_noop() {
        let (grid, rows, content) = grid_with_blocks();
        let mut cursor = FindCursor::new(&grid, &rows, &content, FindQuery::literal("a"));
        cursor.cancel();
        cursor.step(1000);
        assert!(cursor.is_complete());
        assert!(cursor.results().is_empty());
    }

    #[test]
    fn with_state_resumes_at_saved_offset() {
        let (grid, rows, content) = grid_with_blocks();
        let prior = vec![FindMatch { block: 7, row: 0, byte_range: 0..1 }];
        let cursor = FindCursor::with_state(
            &grid,
            &rows,
            &content,
            FindQuery::literal("a"),
            42,
            prior.clone(),
            false,
        );
        assert_eq!(cursor.next_block(), 42);
        let results = cursor.results();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].block, 7);
        assert_eq!(results[0].row, 0);
        assert_eq!(results[0].byte_range, 0..1);
    }

    #[test]
    fn into_parts_returns_state() {
        let (grid, rows, content) = grid_with_blocks();
        let cursor = FindCursor::with_state(
            &grid,
            &rows,
            &content,
            FindQuery::literal("a"),
            3,
            Vec::new(),
            true,
        );
        let (next, results, complete) = cursor.into_parts();
        assert_eq!(next, 3);
        assert!(results.is_empty());
        assert!(complete);
    }
}
