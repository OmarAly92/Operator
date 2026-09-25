mod common;

use vt_core::{Limits, TerminalCore, OLDER_CHUNK_ROWS};

const OUT: usize = 1 << 20;

fn mirror(cols: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::with_limits(
        cols,
        Limits {
            rows,
            bytes: usize::MAX,
        },
    )
    .expect("core");
    core.set_reflow_on_resize(false);
    core.resize(cols, 3);
    core.set_cold_ring_bytes(1 << 20);
    core
}

fn pane_at(cols: usize, origin: u64) -> TerminalCore {
    let mut core = TerminalCore::with_limits(
        cols,
        Limits {
            rows: 10_000,
            bytes: usize::MAX,
        },
    )
    .expect("core");
    core.resize(cols, 3);
    core.feed(format!("\x1b]7000;v=1;origin={origin}\x1b\\").as_bytes());
    core
}

fn numbered(from: usize, count: usize) -> Vec<u8> {
    let mut out = Vec::new();
    for index in from..from + count {
        out.extend_from_slice(format!("row {index:05}\r\n").as_bytes());
    }
    out
}

fn chunk_rows(bytes: &[u8]) -> Vec<String> {
    let text = String::from_utf8_lossy(bytes);
    let body = &text[text.find("\x1b\\").expect("header") + 2..];
    body.split("\r\n")
        .filter(|row| !row.is_empty())
        .map(|row| row.replace("\x1b[0m", ""))
        .collect()
}

#[test]
fn a_fresh_mirror_serves_nothing_to_a_pane_numbered_past_it() {
    let mut source = mirror(40, 1_000);
    source.feed(&numbered(0, 60));
    assert!(source.older_chunk(399, OLDER_CHUNK_ROWS, OUT).is_none());
    assert!(source.older_chunk(500, OLDER_CHUNK_ROWS, OUT).is_none());
}

#[test]
fn a_chunk_is_labelled_with_the_rows_it_carries() {
    let mut source = mirror(40, 50);
    source.feed(&numbered(0, 200));
    let front = source.first_stable_row();
    let end = front + source.memory_stats().rows as u64;
    for before in [10, front - 3, front, front + 5, end, end + 1, end + 40, 500] {
        let Some(chunk) = source.older_chunk(before, 8, OUT) else {
            continue;
        };
        assert!(before <= end, "served {before} past the mirror's rows");
        assert_eq!(chunk.first_stable_row + chunk.rows as u64, before);
        let expected: Vec<String> = (chunk.first_stable_row..before)
            .map(|row| format!("row {row:05}"))
            .collect();
        assert_eq!(chunk_rows(&chunk.bytes), expected, "before {before}");
    }
}

#[test]
fn repeated_clicks_never_repeat_content_under_a_new_label() {
    let mut source = mirror(40, 1_000);
    source.feed(&numbered(0, 60));
    let mut target = pane_at(40, 500);
    target.feed(b"live\r\n");
    for _ in 0..3 {
        let before = target.first_stable_row();
        if let Some(chunk) = source.older_chunk(before, 8, OUT) {
            target.feed(&chunk.bytes);
        }
    }
    assert_eq!(target.first_stable_row(), 500);
    common::check(&target);
}

#[test]
fn a_process_boundary_forgets_the_older_floor() {
    let mut target = pane_at(40, 399);
    target.feed(b"live\r\n\x1b]7000;v=1;older=0\x1b\\");
    assert_eq!(target.older_state().floor, Some(0));
    let marks = target.older_state().marks;
    target.feed(b"\x1b[?1049l\x1b[0m\x1b]7000;v=1;boundary=0\x07");
    assert_eq!(target.older_state().floor, None);
    assert_ne!(target.older_state().marks, marks);
}

fn wide_lines(from: usize, count: usize) -> Vec<u8> {
    let mut out = Vec::new();
    for index in from..from + count {
        let body = "wide words fill ".repeat(1 + index % 4);
        out.extend_from_slice(format!("{index:04} {body}\r\n").as_bytes());
    }
    out
}

fn wide_source(rows: usize) -> TerminalCore {
    let mut source = mirror(80, 40);
    source.feed(&wide_lines(0, rows));
    source
}

fn load(source: &TerminalCore, target: &mut TerminalCore, rows: usize) {
    if let Some(chunk) = source.older_chunk(target.first_stable_row(), rows, OUT) {
        target.feed(&chunk.bytes);
    }
}

#[test]
fn prepended_wide_rows_survive_a_touch_and_a_resize() {
    let source = wide_source(400);
    let mut target = pane_at(11, source.first_stable_row());
    target.resize(11, 3);
    target.feed(&wide_lines(400, 3));
    target.feed(&wide_lines(403, 3));
    target.feed(&wide_lines(406, 3));
    load(&source, &mut target, 34);
    load(&source, &mut target, 60);
    target.touch_rows(0..8);
    target.resize(76, 4);
    common::check(&target);
}

struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }

    fn below(&mut self, bound: u64) -> usize {
        (self.next() % bound) as usize
    }
}

#[test]
fn random_feeds_loads_resizes_and_touches_keep_the_core_consistent() {
    let source = wide_source(3_000);
    for seed in 1..=64u64 {
        let mut rng = Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1);
        let mut target = pane_at(40, source.first_stable_row());
        let mut next_line = 3_000;
        let mut steps = Vec::new();
        for _ in 0..24 {
            let step = match rng.below(4) {
                0 => {
                    let count = 1 + rng.below(30);
                    target.feed(&wide_lines(next_line, count));
                    next_line += count;
                    format!("Feed({count})")
                }
                1 => {
                    let rows = 1 + rng.below(700);
                    load(&source, &mut target, rows);
                    format!("Load({rows})")
                }
                2 => {
                    let cols = 8 + rng.below(90);
                    let rows = 2 + rng.below(6);
                    target.resize(cols, rows);
                    format!("Resize({cols},{rows})")
                }
                _ => {
                    let start = rng.below(3_000);
                    let len = 1 + rng.below(200);
                    target.touch_rows(start..start + len);
                    format!("Touch({start}..{})", start + len)
                }
            };
            steps.push(step);
            if let Err(error) = target.verify_integrity() {
                panic!("seed {seed}: {error:?} after {steps:?}");
            }
        }
    }
}

#[test]
fn a_row_larger_than_the_answer_budget_does_not_stop_the_load() {
    let mut source = mirror(1_000, 10);
    source.feed(&numbered(0, 5));
    source.feed(format!("{}\x1b[0m\r\n", "\x1b[31mx\x1b[32my".repeat(500)).as_bytes());
    source.feed(&numbered(6, 40));
    let mut target = pane_at(40, source.first_stable_row());
    target.feed(b"live\r\n");
    for _ in 0..8 {
        let before = target.first_stable_row();
        let Some(chunk) = source.older_chunk(before, OLDER_CHUNK_ROWS, 4_096) else {
            break;
        };
        assert!(chunk.bytes.len() <= 4_096, "{}", chunk.bytes.len());
        target.feed(&chunk.bytes);
        assert_eq!(target.first_stable_row(), chunk.first_stable_row);
    }
    assert_eq!(target.first_stable_row(), 0);
    let snapshot = target.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(4), "row 00004");
    assert_eq!(snapshot.row_text(5), "");
    assert_eq!(snapshot.row_text(6), "row 00006");
    common::check(&target);
}
