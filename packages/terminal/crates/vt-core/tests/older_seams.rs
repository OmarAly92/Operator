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
