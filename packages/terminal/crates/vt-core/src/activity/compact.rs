use regex_automata::dfa::sparse::DFA;
use regex_automata::dfa::Automaton;
use regex_automata::Input;
use std::collections::HashMap;
use std::sync::OnceLock;

use crate::TerminalCore;

include!("compact_sources.rs");

pub const COMPACT_REDRAW_LOOKBACK: usize = 256;
pub const COMPACT_MIN_REDRAW_LINES: usize = 3;

static SPINNER_AUTOMATON: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/spinner_line.dfa"));

fn spinner() -> &'static DFA<&'static [u8]> {
    static SPINNER: OnceLock<DFA<&'static [u8]>> = OnceLock::new();
    SPINNER.get_or_init(|| {
        DFA::from_bytes(SPINNER_AUTOMATON)
            .expect("spinner line automaton")
            .0
    })
}

pub fn is_spinner_line(line: &str) -> bool {
    let input = Input::new(line).earliest(true);
    matches!(spinner().try_search_fwd(&input), Ok(Some(_)))
}

pub fn compact_lines<S: AsRef<str>>(lines: &[S]) -> Vec<String> {
    let mut normalized: Vec<String> = Vec::new();
    for raw in lines {
        let line = raw.as_ref().trim_end();
        if is_spinner_line(line) {
            continue;
        }
        if line.is_empty() && normalized.last().is_none_or(|last| last.is_empty()) {
            continue;
        }
        if !line.is_empty() && normalized.last().is_some_and(|last| last == line) {
            continue;
        }
        normalized.push(line.to_string());
    }
    let mut kept: Vec<String> = Vec::new();
    let mut seen: HashMap<String, Vec<usize>> = HashMap::new();
    let mut index = 0;
    while index < normalized.len() {
        let line = normalized[index].clone();
        let repeated = if line.is_empty() {
            0
        } else {
            repeated_run(&normalized, index, &kept, seen.get(&line))
        };
        if repeated > 0 {
            index += repeated;
            continue;
        }
        if !line.is_empty() {
            seen.entry(line.clone()).or_default().push(kept.len());
        }
        kept.push(line);
        index += 1;
    }
    while kept.last().is_some_and(|line| line.is_empty()) {
        kept.pop();
    }
    kept
}

fn repeated_run(
    lines: &[String],
    at: usize,
    kept: &[String],
    positions: Option<&Vec<usize>>,
) -> usize {
    let Some(positions) = positions else {
        return 0;
    };
    let floor = kept.len().saturating_sub(COMPACT_REDRAW_LOOKBACK);
    let mut best = 0;
    for &start in positions.iter().rev() {
        if start < floor {
            break;
        }
        let length = kept.len() - start;
        if length <= best || at + length > lines.len() {
            continue;
        }
        let mut visible = 0;
        let mut offset = 0;
        while offset < length && lines[at + offset] == kept[start + offset] {
            if !lines[at + offset].is_empty() {
                visible += 1;
            }
            offset += 1;
        }
        if offset == length && visible >= COMPACT_MIN_REDRAW_LINES {
            best = length;
        }
    }
    best
}

pub fn cap_lines<S: AsRef<str>>(lines: &[S], max_lines: usize) -> Vec<String> {
    if max_lines == 0 {
        return Vec::new();
    }
    let owned = || lines.iter().map(|line| line.as_ref().to_string());
    if lines.len() <= max_lines {
        return owned().collect();
    }
    let head = (max_lines - 1).div_ceil(2);
    let tail = max_lines - 1 - head;
    let omitted = lines.len() - head - tail;
    let mut out: Vec<String> = owned().take(head).collect();
    out.push(format!("… {omitted} lines omitted …"));
    out.extend(owned().skip(lines.len() - tail));
    out
}

impl TerminalCore {
    pub fn tail_output(&self, rows: usize, compact: bool, max_lines: usize) -> String {
        let Ok(snapshot) = self.snapshot() else {
            return String::new();
        };
        let mut lines: Vec<String> = Vec::new();
        if let Some(alt) = &snapshot.alt {
            let skip = alt.row_ranges.len().saturating_sub(rows);
            for (start, end) in alt.row_ranges.iter().skip(skip) {
                lines.push(
                    String::from_utf8_lossy(&alt.content[*start as usize..*end as usize])
                        .into_owned(),
                );
            }
        } else {
            let total = snapshot.row_count();
            let mut first = total.saturating_sub(rows);
            while first > 0 && first < total && snapshot.row_wrapped(first - 1) {
                first -= 1;
            }
            let mut line = String::new();
            for index in first..total {
                line.push_str(snapshot.row_text(index));
                if !(snapshot.row_wrapped(index) && index + 1 < total) {
                    lines.push(std::mem::take(&mut line));
                }
            }
        }
        let lines = if compact {
            compact_lines(&lines)
        } else {
            while lines.last().is_some_and(|line| line.trim().is_empty()) {
                lines.pop();
            }
            lines
        };
        cap_lines(&lines, max_lines).join("\n")
    }
}
