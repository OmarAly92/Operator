use std::ops::Range;

use memchr::memmem::Finder;
use regex_automata::meta::{BuildError, Regex};
use regex_automata::util::syntax;
use regex_automata::Input;

use crate::block::{BlockId, BlockRecord};
use crate::content::Content;
use crate::grid::export_screen_row;
use crate::row_index::{RowIndex, RowRange};
use crate::screen::ScreenGrid;

const META_CHARACTERS: &str = "\\.+*?()|[]{}^$#&-~";

#[derive(Clone)]
pub struct FindQuery {
    matcher: Matcher,
}

#[derive(Clone)]
enum Matcher {
    Empty,
    Literal(Box<Finder<'static>>),
    Regex(Regex),
}

impl FindQuery {
    pub fn literal(needle: &str) -> Self {
        let matcher = if needle.is_empty() {
            Matcher::Empty
        } else if has_uppercase(needle) {
            Matcher::Literal(Box::new(Finder::new(needle.as_bytes()).into_owned()))
        } else {
            build_regex(&escape(needle), true).map_or_else(
                |_| Matcher::Literal(Box::new(Finder::new(needle.as_bytes()).into_owned())),
                Matcher::Regex,
            )
        };
        Self { matcher }
    }

    pub fn regex(pattern: &str) -> Result<Self, Box<BuildError>> {
        if pattern.is_empty() {
            return Ok(Self {
                matcher: Matcher::Empty,
            });
        }
        build_regex(pattern, !has_uppercase(pattern)).map(|regex| Self {
            matcher: Matcher::Regex(regex),
        })
    }

    fn next_match(&self, haystack: &[u8], span: Range<usize>) -> Option<Range<usize>> {
        match &self.matcher {
            Matcher::Empty => None,
            Matcher::Literal(finder) => {
                let offset = finder.find(&haystack[span.clone()])?;
                let start = span.start + offset;
                Some(start..start + finder.needle().len())
            }
            Matcher::Regex(regex) => regex
                .find_iter(Input::new(haystack).span(span))
                .find(|found| !found.is_empty())
                .map(|found| found.range()),
        }
    }
}

fn has_uppercase(text: &str) -> bool {
    text.chars().any(char::is_uppercase)
}

fn escape(text: &str) -> String {
    let mut escaped = String::with_capacity(text.len() * 2);
    for ch in text.chars() {
        if META_CHARACTERS.contains(ch) {
            escaped.push('\\');
        }
        escaped.push(ch);
    }
    escaped
}

fn build_regex(pattern: &str, case_insensitive: bool) -> Result<Regex, Box<BuildError>> {
    Regex::builder()
        .syntax(
            syntax::Config::new()
                .case_insensitive(case_insensitive)
                .multi_line(true),
        )
        .build(pattern)
        .map_err(Box::new)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FindMatch {
    pub block: BlockId,
    pub row: u64,
    pub end_row: u64,
    pub start: usize,
    pub end: usize,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FindUpdate {
    pub added: usize,
    pub removed: usize,
    pub complete: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct ScreenHit {
    row: u64,
    start: usize,
    end_row: u64,
    end: usize,
}

pub struct FindSession {
    query: FindQuery,
    history: Vec<Range<u64>>,
    started: bool,
    scanned_from: u64,
    scanned_to: u64,
    bytes_scanned: u64,
    screen: Vec<ScreenHit>,
    screen_generation: Option<u64>,
    screen_scans: u64,
    truncations: u64,
    prepends: u64,
}

pub(crate) struct FindView<'a> {
    pub content: &'a Content,
    pub rows: &'a RowIndex,
    pub screen: &'a ScreenGrid,
    pub generation: u64,
    pub first_stable_row: u64,
}

impl FindSession {
    pub fn new(query: FindQuery) -> Self {
        Self {
            query,
            history: Vec::new(),
            started: false,
            scanned_from: 0,
            scanned_to: 0,
            bytes_scanned: 0,
            screen: Vec::new(),
            screen_generation: None,
            screen_scans: 0,
            truncations: 0,
            prepends: 0,
        }
    }

    pub fn len(&self) -> usize {
        self.history.len() + self.screen.len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn history_bytes_scanned(&self) -> u64 {
        self.bytes_scanned
    }

    pub fn screen_scans(&self) -> u64 {
        self.screen_scans
    }

    pub(crate) fn update(&mut self, view: &FindView<'_>, budget_bytes: usize) -> FindUpdate {
        let mut update = FindUpdate::default();
        let completed = view.rows.completed();
        let settled = settled_rows(completed);
        let history_start = completed
            .front()
            .map_or(view.rows.open_start(), |row| row.start);
        let settled_end = if settled == 0 {
            history_start
        } else {
            completed[settled - 1].end
        };
        if let Some(cut) = view.content.lowest_cut_since(self.truncations) {
            let floor = line_start(completed, cut);
            let kept = self.history.partition_point(|hit| hit.end <= floor);
            update.removed += self.history.len() - kept;
            self.history.truncate(kept);
            self.scanned_to = self.scanned_to.min(floor);
        }
        self.truncations = view.content.truncations();
        let prepended = view.content.prepends() != self.prepends;
        self.prepends = view.content.prepends();
        if !self.started
            || prepended
            || history_start < self.scanned_from
            || settled_end < self.scanned_to
        {
            update.removed += self.history.len();
            self.history.clear();
            self.started = true;
            self.scanned_from = history_start;
            self.scanned_to = history_start;
        }
        if history_start > self.scanned_from {
            let dropped = self
                .history
                .partition_point(|hit| hit.start < history_start);
            self.history.drain(..dropped);
            update.removed += dropped;
            self.scanned_from = history_start;
            self.scanned_to = self.scanned_to.max(history_start);
        }
        if self.scanned_to < settled_end {
            update.added += self.scan_history(view, settled, budget_bytes);
        }
        if self.screen_generation != Some(view.generation) {
            let fresh = self.search_screen(view, settled);
            if fresh != self.screen {
                update.removed += self.screen.len();
                update.added += fresh.len();
                self.screen = fresh;
            }
            self.screen_generation = Some(view.generation);
            self.screen_scans += 1;
        }
        update.complete = self.scanned_to >= settled_end;
        update
    }

    fn scan_history(&mut self, view: &FindView<'_>, settled: usize, budget_bytes: usize) -> usize {
        let completed = view.rows.completed();
        let first = completed.partition_point(|row| row.start < self.scanned_to);
        if first >= settled {
            self.scanned_to = completed[settled - 1].end;
            return 0;
        }
        let budget = budget_bytes.max(1) as u64;
        let from = completed[first].start;
        let mut last = first;
        while last < settled {
            let row = &completed[last];
            last += 1;
            if !row.wrapped && row.end - from >= budget {
                break;
            }
        }
        let to = completed[last - 1].end;
        let bytes = view.content.copy_range(from, to);
        let mut haystack = Haystack::default();
        for row in completed.range(first..last) {
            let slice = &bytes[(row.start - from) as usize..(row.end - from) as usize];
            haystack.push(slice, row.start, row.wrapped);
        }
        haystack.close();
        let before = self.history.len();
        scan(&self.query, &haystack, |found| {
            if let Some((head, tail)) = haystack.locate(&found) {
                let start = head.key + (found.start - head.at) as u64;
                let end = tail.key + (found.end - tail.at) as u64;
                self.history.push(start..end);
            }
        });
        self.bytes_scanned += to - from;
        self.scanned_to = to;
        self.history.len() - before
    }

    fn search_screen(&self, view: &FindView<'_>, settled: usize) -> Vec<ScreenHit> {
        let completed = view.rows.completed();
        let mut haystack = Haystack::default();
        for (index, row) in completed.iter().enumerate().skip(settled) {
            let bytes = view.content.copy_range(row.start, row.end);
            haystack.push(&bytes, view.first_stable_row + index as u64, row.wrapped);
        }
        for row in 0..view.screen.content_rows() {
            let exported = export_screen_row(view.screen, row);
            let stable = view.first_stable_row + (completed.len() + row) as u64;
            haystack.push(&exported.bytes, stable, exported.wrapped);
        }
        haystack.close();
        let mut hits = Vec::new();
        scan(&self.query, &haystack, |found| {
            if let Some((head, tail)) = haystack.locate(&found) {
                hits.push(ScreenHit {
                    row: head.key,
                    start: found.start - head.at,
                    end_row: tail.key,
                    end: found.end - tail.at,
                });
            }
        });
        hits
    }

    pub(crate) fn results(&self, view: &FindView<'_>, blocks: &[BlockRecord]) -> Vec<FindMatch> {
        let completed = view.rows.completed();
        let mut out = Vec::with_capacity(self.len());
        for hit in &self.history {
            let first = completed.partition_point(|row| row.end <= hit.start);
            let last = completed.partition_point(|row| row.end < hit.end);
            let (Some(head), Some(tail)) = (completed.get(first), completed.get(last)) else {
                continue;
            };
            if hit.start < head.start || hit.end < tail.start {
                continue;
            }
            out.push(FindMatch {
                block: block_at(blocks, first),
                row: view.first_stable_row + first as u64,
                end_row: view.first_stable_row + last as u64,
                start: (hit.start - head.start) as usize,
                end: (hit.end - tail.start) as usize,
            });
        }
        for hit in &self.screen {
            let Some(flat) = hit.row.checked_sub(view.first_stable_row) else {
                continue;
            };
            out.push(FindMatch {
                block: block_at(blocks, flat as usize),
                row: hit.row,
                end_row: hit.end_row,
                start: hit.start,
                end: hit.end,
            });
        }
        out
    }
}

fn settled_rows(completed: &std::collections::VecDeque<RowRange>) -> usize {
    let mut settled = completed.len();
    while settled > 0 && completed[settled - 1].wrapped {
        settled -= 1;
    }
    settled
}

fn line_start(completed: &std::collections::VecDeque<RowRange>, cut: u64) -> u64 {
    let mut first = completed.partition_point(|row| row.end <= cut);
    while first > 0 && completed[first - 1].wrapped {
        first -= 1;
    }
    completed.get(first).map_or(cut, |row| row.start.min(cut))
}

fn block_at(blocks: &[BlockRecord], flat: usize) -> BlockId {
    let index = blocks.partition_point(|block| block.first_row as usize <= flat);
    index
        .checked_sub(1)
        .and_then(|found| blocks.get(found))
        .or_else(|| blocks.first())
        .map_or(0, |block| block.id)
}

struct Piece {
    at: usize,
    len: usize,
    key: u64,
}

#[derive(Default)]
struct Haystack {
    bytes: Vec<u8>,
    lines: Vec<Range<usize>>,
    pieces: Vec<Piece>,
    open: Option<usize>,
}

impl Haystack {
    fn push(&mut self, piece: &[u8], key: u64, continues: bool) {
        let at = self.bytes.len();
        if self.open.is_none() {
            self.open = Some(at);
        }
        self.bytes.extend_from_slice(piece);
        self.pieces.push(Piece {
            at,
            len: piece.len(),
            key,
        });
        if !continues {
            self.close();
        }
    }

    fn close(&mut self) {
        if let Some(start) = self.open.take() {
            self.lines.push(start..self.bytes.len());
            self.bytes.push(b'\n');
        }
    }

    fn locate(&self, found: &Range<usize>) -> Option<(&Piece, &Piece)> {
        let head = self
            .pieces
            .partition_point(|piece| piece.at + piece.len <= found.start);
        let tail = self
            .pieces
            .partition_point(|piece| piece.at + piece.len < found.end);
        Some((self.pieces.get(head)?, self.pieces.get(tail)?))
    }
}

fn scan(query: &FindQuery, haystack: &Haystack, mut visit: impl FnMut(Range<usize>)) {
    let bytes = &haystack.bytes;
    let mut from = 0;
    while from < bytes.len() {
        let Some(found) = query.next_match(bytes, from..bytes.len()) else {
            return;
        };
        let line = haystack
            .lines
            .partition_point(|bounds| bounds.end < found.start);
        let Some(bounds) = haystack.lines.get(line).cloned() else {
            return;
        };
        if found.end <= bounds.end {
            from = found.end;
            visit(found);
            continue;
        }
        if found.start < bounds.end {
            if let Some(inner) = query.next_match(bytes, found.start..bounds.end) {
                from = inner.end;
                visit(inner);
                continue;
            }
        }
        from = bounds.end + 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn found(query: &FindQuery, lines: &[&str]) -> Vec<String> {
        let mut haystack = Haystack::default();
        for (index, line) in lines.iter().enumerate() {
            haystack.push(line.as_bytes(), index as u64, false);
        }
        let mut out = Vec::new();
        scan(query, &haystack, |range| {
            out.push(String::from_utf8(haystack.bytes[range].to_vec()).unwrap());
        });
        out
    }

    #[test]
    fn every_meta_character_is_literal_in_a_literal_query() {
        for ch in META_CHARACTERS.chars() {
            let needle = format!("a{ch}b");
            let hits = found(
                &FindQuery::literal(&needle),
                &[&format!("x {needle} y"), "axb"],
            );
            assert_eq!(hits, vec![needle.clone()], "meta character {ch:?}");
        }
    }

    #[test]
    fn a_match_that_crosses_a_line_is_searched_again_inside_the_line() {
        let query = FindQuery::regex("x[^y]*z").unwrap();
        assert_eq!(found(&query, &["ab xz", "zz"]), vec!["xz".to_string()]);
    }

    #[test]
    fn a_match_that_starts_on_the_separator_is_skipped() {
        let query = FindQuery::regex(r"\s+b").unwrap();
        assert!(found(&query, &["a", "b c"]).is_empty());
    }

    #[test]
    fn a_zero_width_pattern_yields_only_non_empty_hits() {
        let query = FindQuery::regex("x*").unwrap();
        assert!(found(&query, &["abc"]).is_empty());
        assert_eq!(found(&query, &["axxb"]), vec!["xx".to_string()]);
    }

    #[test]
    fn an_empty_query_finds_nothing() {
        assert!(found(&FindQuery::literal(""), &["abc"]).is_empty());
        assert!(found(&FindQuery::regex("").unwrap(), &["abc"]).is_empty());
    }

    #[test]
    fn anchors_match_at_every_line() {
        let query = FindQuery::regex("^b").unwrap();
        assert_eq!(found(&query, &["ab", "bc", "b"]).len(), 2);
    }

    #[test]
    fn a_cut_inside_a_soft_wrapped_line_rescans_from_the_line_start() {
        let row = |start, end, wrapped| RowRange {
            start,
            end,
            wrapped,
            indent: 0,
        };
        let rows =
            std::collections::VecDeque::from([row(0, 4, false), row(4, 8, true), row(8, 12, true)]);
        assert_eq!(line_start(&rows, 12), 4);
        assert_eq!(line_start(&rows, 8), 4);
        assert_eq!(line_start(&rows, 4), 4);
        assert_eq!(line_start(&rows, 20), 4);
        assert_eq!(line_start(&rows, 2), 0);
        assert_eq!(line_start(&rows, 6), 4);
        assert_eq!(line_start(&rows.range(..1).cloned().collect(), 4), 4);
    }

    #[test]
    fn a_soft_wrapped_line_is_one_line_to_the_search() {
        let mut haystack = Haystack::default();
        haystack.push(b"hello nee", 0, true);
        haystack.push(b"dle there", 1, false);
        let mut hits = Vec::new();
        scan(&FindQuery::literal("needle"), &haystack, |range| {
            let (head, tail) = haystack.locate(&range).unwrap();
            hits.push((
                head.key,
                range.start - head.at,
                tail.key,
                range.end - tail.at,
            ));
        });
        assert_eq!(hits, vec![(0, 6, 1, 3)]);
    }
}
