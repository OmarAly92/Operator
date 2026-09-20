mod common;

use vt_core::{Limits, MemoryStats, TerminalCore};

fn rows_of(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    let mut rows: Vec<String> = (0..snapshot.row_count())
        .map(|i| snapshot.row_text(i).to_string())
        .collect();
    while rows.last().is_some_and(|row| row.is_empty()) {
        rows.pop();
    }
    rows
}

fn feed_numbered(core: &mut TerminalCore, count: usize) {
    for i in 0..count {
        core.feed(format!("row {i:05} xxxxxxxxxx\r\n").as_bytes());
    }
}

#[test]
fn byte_cap_trims_whole_rows_and_keeps_blocks_consistent() {
    let mut core = TerminalCore::with_limits(
        40,
        Limits {
            rows: 100_000,
            bytes: 8_192,
        },
    )
    .unwrap();
    core.resize(40, 3);
    core.feed(b"\x1b]133;A\x07");
    feed_numbered(&mut core, 600);
    let stats = core.memory_stats();
    assert!(
        stats.content_bytes + stats.style_entries * 16 <= 8_192,
        "{stats:?}"
    );
    assert!(stats.rows > 100 && stats.rows < 600, "{stats:?}");
    let rows = rows_of(&core);
    assert!(
        rows[0].starts_with("row "),
        "first retained row is whole: {:?}",
        rows[0]
    );
    assert_eq!(
        rows.last().map(String::as_str),
        Some("row 00599 xxxxxxxxxx")
    );
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.blocks.len(), 1);
    assert_eq!(snapshot.blocks[0].first_row, 0);
    assert_eq!(snapshot.blocks[0].row_count as usize, snapshot.row_count());
    common::check(&core);
}

#[test]
fn row_cap_still_applies() {
    let mut limited = TerminalCore::with_limits(
        40,
        Limits {
            rows: 50,
            bytes: usize::MAX,
        },
    )
    .unwrap();
    let mut legacy = TerminalCore::new(40, 50).unwrap();
    for core in [&mut limited, &mut legacy] {
        core.resize(40, 3);
        feed_numbered(core, 100);
    }
    assert_eq!(limited.memory_stats().rows, 49);
    assert_eq!(rows_of(&limited), rows_of(&legacy));
    assert_eq!(
        legacy.limits(),
        Limits {
            rows: 50,
            bytes: usize::MAX
        }
    );
    common::check(&limited);
}

#[test]
fn memory_stats_match_after_trim() {
    let mut core = TerminalCore::with_limits(
        40,
        Limits {
            rows: 200,
            bytes: usize::MAX,
        },
    )
    .unwrap();
    core.resize(40, 3);
    core.feed(b"\x1b]133;A\x07");
    feed_numbered(&mut core, 400);
    let stats = core.memory_stats();
    let snapshot = core.snapshot().unwrap();
    let history_rows = snapshot.row_count() - 2;
    assert_eq!(stats.rows, history_rows);
    assert_eq!(stats.rows, 199);
    let history_bytes: usize = (0..history_rows).map(|i| snapshot.row_text(i).len()).sum();
    assert!(
        stats.content_bytes >= history_bytes,
        "{stats:?} vs {history_bytes}"
    );
    assert!(
        stats.content_bytes < history_bytes + 4_096,
        "{stats:?} vs {history_bytes}"
    );
    assert_eq!(stats.blocks, 1);
    assert_ne!(stats, MemoryStats::default());
    common::check(&core);
}

#[test]
fn zero_rows_is_rejected() {
    assert!(TerminalCore::with_limits(40, Limits { rows: 0, bytes: 1 }).is_err());
}
