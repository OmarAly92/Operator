mod common;

use vt_core::{CellStyle, Limits, TerminalCore, OLDER_CHUNK_ROWS};

const RING: usize = 1 << 20;
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
    core.set_cold_ring_bytes(RING);
    core
}

fn pane(cols: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::with_limits(
        cols,
        Limits {
            rows,
            bytes: usize::MAX,
        },
    )
    .expect("core");
    core.resize(cols, 3);
    core.set_grapheme_clusters(true);
    core
}

fn texts(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().expect("snapshot");
    let mut rows: Vec<String> = (0..snapshot.row_count())
        .map(|index| snapshot.row_text(index).to_string())
        .collect();
    while rows.last().is_some_and(|row| row.is_empty()) {
        rows.pop();
    }
    rows
}

fn styles(core: &TerminalCore, row: usize) -> Vec<(u32, CellStyle)> {
    core.snapshot()
        .expect("snapshot")
        .row_style_pairs(row)
        .to_vec()
}

fn numbered(count: usize) -> Vec<u8> {
    let mut out = Vec::new();
    for index in 0..count {
        if index % 3 == 0 {
            out.extend_from_slice(format!("\x1b[31;1mrow {index:05}\x1b[0m plain\r\n").as_bytes());
        } else {
            out.extend_from_slice(format!("row {index:05} plain\r\n").as_bytes());
        }
    }
    out
}

fn load_all_older(source: &TerminalCore, target: &mut TerminalCore) {
    loop {
        let before = target.first_stable_row();
        let Some(chunk) = source.older_chunk(before, OLDER_CHUNK_ROWS, OUT) else {
            break;
        };
        target.feed(&chunk.bytes);
        if target.first_stable_row() != chunk.first_stable_row {
            break;
        }
    }
    target.feed(&source.older_mark().expect("ring is on"));
}

#[test]
fn evicted_rows_land_in_the_ring_in_order_with_their_styles() {
    let mut core = mirror(40, 10);
    core.feed(&numbered(30));
    let stats = core.cold_stats();
    assert_eq!(
        core.first_stable_row(),
        stats.first_stable_row + stats.rows as u64
    );
    assert_eq!(stats.first_stable_row, 0);
    let chunk = core
        .older_chunk(core.first_stable_row(), OLDER_CHUNK_ROWS, OUT)
        .expect("older rows exist");
    let text = String::from_utf8(chunk.bytes).expect("utf-8");
    let first = text.find("row 00000").expect("oldest row present");
    let second = text.find("row 00001").expect("second row present");
    let last = text
        .find(&format!("row {:05}", stats.rows - 1))
        .expect("newest evicted row present");
    assert!(first < second && second < last, "{text:?}");
    assert!(
        text.contains("\x1b[0m\x1b[1;31mrow 00000\x1b[0m plain"),
        "{text:?}"
    );
    assert_eq!(chunk.first_stable_row, 0);
    assert_eq!(chunk.rows, stats.rows);
    common::check(&core);
}

#[test]
fn the_ring_never_grows_past_its_cap_and_drops_the_oldest() {
    let cap = 4 * 1024;
    let mut core = TerminalCore::with_limits(
        40,
        Limits {
            rows: 20,
            bytes: usize::MAX,
        },
    )
    .expect("core");
    core.resize(40, 3);
    core.set_cold_ring_bytes(cap);
    for index in 0..2_000 {
        core.feed(format!("line {index:05}\r\n").as_bytes());
        let stats = core.cold_stats();
        assert!(stats.bytes <= cap, "{stats:?}");
    }
    let stats = core.cold_stats();
    assert!(stats.first_stable_row > 0, "{stats:?}");
    assert_eq!(core.cold_floor(), Some(stats.first_stable_row));
    assert_eq!(
        stats.first_stable_row + stats.rows as u64,
        core.first_stable_row()
    );
    let chunk = core
        .older_chunk(core.first_stable_row(), OLDER_CHUNK_ROWS, OUT)
        .expect("rows");
    let text = String::from_utf8(chunk.bytes).expect("utf-8");
    assert!(!text.contains("line 00000"), "the oldest row was dropped");
}

#[test]
fn a_chunk_reads_rows_oldest_to_newest_ending_at_before() {
    let mut core = mirror(40, 10);
    core.feed(&numbered(40));
    let chunk = core.older_chunk(20, 5, OUT).expect("rows 15..20");
    assert_eq!(chunk.first_stable_row, 15);
    assert_eq!(chunk.rows, 5);
    let text = String::from_utf8(chunk.bytes).expect("utf-8");
    assert!(
        text.starts_with("\x1b]7000;v=1;history=15,5;cols=15\x1b\\"),
        "{text:?}"
    );
    let order: Vec<usize> = (15..20)
        .map(|index| text.find(&format!("row {index:05}")).expect("row"))
        .collect();
    assert!(order.windows(2).all(|pair| pair[0] < pair[1]), "{text:?}");
    assert_eq!(text.matches("\r\n").count(), 5);
}

#[test]
fn nothing_older_than_the_floor_returns_no_chunk() {
    let mut core = mirror(40, 10);
    core.feed(&numbered(30));
    let floor = core.cold_floor().expect("ring is on");
    assert!(core.older_chunk(floor, OLDER_CHUNK_ROWS, OUT).is_none());
    assert_eq!(
        core.older_mark().expect("ring is on"),
        format!("\x1b]7000;v=1;older={floor}\x1b\\").into_bytes()
    );
}

#[test]
fn a_core_without_a_ring_offers_nothing_older() {
    let mut core = TerminalCore::new(40, 10).expect("core");
    core.feed(&numbered(30));
    assert_eq!(core.cold_floor(), None);
    assert_eq!(core.older_mark(), None);
    assert!(core
        .older_chunk(core.first_stable_row(), OLDER_CHUNK_ROWS, OUT)
        .is_none());
}

#[test]
fn evicted_rows_load_back_with_their_text_and_styles() {
    let bytes = numbered(120);
    let mut reference = TerminalCore::new(40, 10_000).expect("core");
    reference.resize(40, 3);
    reference.feed(&bytes);
    let mut source = mirror(40, 50);
    source.feed(&bytes);
    let mut target = pane(40, 50);
    target.feed(&bytes);
    assert_eq!(target.first_stable_row(), source.first_stable_row());
    let before = target.first_stable_row() as usize;

    load_all_older(&source, &mut target);

    assert_eq!(target.first_stable_row(), 0);
    assert_eq!(texts(&target), texts(&reference));
    for row in 0..before {
        assert_eq!(styles(&target, row), styles(&reference, row), "row {row}");
    }
    assert_eq!(target.older_state().floor, Some(0));
    common::check(&target);
}

#[test]
fn wide_characters_and_graphemes_survive_the_ring() {
    let lines = [
        "漢字かな交じり文",
        "family 👨‍👩‍👧 heart ❤️ flag 🇪🇬",
        "e\u{301}cole café",
        "plain ascii",
    ];
    let mut bytes = Vec::new();
    for line in lines {
        bytes.extend_from_slice(format!("{line}\r\n").as_bytes());
    }
    bytes.extend_from_slice(&numbered(20));
    let mut source = mirror(60, 10);
    source.feed(&bytes);
    let mut target = pane(60, 10);
    target.feed(&bytes);
    load_all_older(&source, &mut target);
    let rows = texts(&target);
    for (index, line) in lines.iter().enumerate() {
        assert_eq!(rows[index], *line);
    }
    common::check(&target);
}

#[test]
fn a_wide_chunk_lands_whole_in_a_narrow_pane_and_rewraps_when_touched() {
    let long = "abcdefghij".repeat(6);
    let mut bytes = Vec::new();
    for index in 0..40 {
        bytes.extend_from_slice(format!("{index:02}{long}\r\n").as_bytes());
    }
    let mut source = mirror(80, 20);
    source.feed(&bytes);
    let chunk = source
        .older_chunk(source.first_stable_row(), 4, OUT)
        .expect("rows");
    assert!(String::from_utf8_lossy(&chunk.bytes).contains(";cols=62\x1b\\"));

    let mut target = pane(20, 10_000);
    target.feed(b"\x1b]7000;v=1;origin=");
    target.feed(format!("{}\x1b\\", source.first_stable_row()).as_bytes());
    target.feed(b"live\r\n");
    target.feed(&chunk.bytes);
    assert_eq!(target.first_stable_row(), chunk.first_stable_row);
    let snapshot = target.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0).len(), 62);
    assert!(target.stale_row_count() >= 4);

    target.touch_rows(0..usize::MAX);
    assert_eq!(target.stale_row_count(), 0);
    let joined: String = texts(&target)
        .iter()
        .take_while(|row| *row != "live")
        .cloned()
        .collect();
    let expected: String = (chunk.first_stable_row..chunk.first_stable_row + 4)
        .map(|index| format!("{index:02}{long}"))
        .collect();
    assert_eq!(joined, expected);
    common::check(&target);
}

#[test]
fn loaded_rows_stay_until_the_next_committed_row() {
    let bytes = numbered(100);
    let mut source = mirror(40, 50);
    source.feed(&bytes);
    let mut target = pane(40, 50);
    target.feed(&bytes);
    let front = target.first_stable_row();
    let chunk = source
        .older_chunk(front, OLDER_CHUNK_ROWS, OUT)
        .expect("rows");
    target.feed(&chunk.bytes);
    assert_eq!(target.first_stable_row(), front - chunk.rows as u64);
    target.feed(b"typing");
    assert_eq!(target.first_stable_row(), front - chunk.rows as u64);
    target.feed(b"\r\n");
    assert!(
        target.first_stable_row() > front,
        "the next committed row trims back to the cap"
    );
    assert_eq!(target.memory_stats().rows, 49);
    common::check(&target);
}

#[test]
fn an_older_mark_records_the_floor_and_counts_every_mark() {
    let mut core = pane(40, 50);
    assert_eq!(core.older_state().floor, None);
    assert_eq!(core.older_state().marks, 0);
    core.feed(b"\x1b]7000;v=1;older=12\x1b\\");
    core.feed(b"\x1b]7000;v=1;older=12\x1b\\");
    assert_eq!(core.older_state().floor, Some(12));
    assert_eq!(core.older_state().marks, 2);
    assert!(texts(&core).is_empty(), "the mark prints nothing");
}

#[test]
fn a_history_prepend_restarts_the_ring_at_the_new_front() {
    let mut core = mirror(40, 1_000);
    core.feed(b"\x1b]7000;v=1;origin=500\x1b\\live\r\n");
    core.feed(b"\x1b]7000;v=1;history=498,2\x1b\\one\r\ntwo\r\n");
    assert_eq!(core.first_stable_row(), 498);
    assert_eq!(core.cold_floor(), Some(498));
    assert_eq!(core.cold_stats().rows, 0);
}

#[test]
fn rows_the_mirror_still_holds_are_served_when_the_pane_is_ahead() {
    let mut source = mirror(40, 100);
    source.feed(&numbered(30));
    assert_eq!(source.first_stable_row(), 0);
    let chunk = source.older_chunk(10, 4, OUT).expect("history rows 6..10");
    assert_eq!(chunk.first_stable_row, 6);
    let text = String::from_utf8(chunk.bytes).expect("utf-8");
    assert!(
        text.contains("row 00006") && text.contains("row 00009"),
        "{text:?}"
    );
    assert!(!text.contains("row 00010"), "{text:?}");
}

#[test]
fn a_chunk_keeps_to_its_byte_budget_newest_rows_first() {
    let mut core = mirror(40, 10);
    core.feed(&numbered(60));
    let before = core.first_stable_row();
    let chunk = core
        .older_chunk(before, OLDER_CHUNK_ROWS, 200)
        .expect("rows");
    assert!(chunk.bytes.len() <= 200, "{}", chunk.bytes.len());
    assert!(chunk.rows < 20);
    assert_eq!(chunk.first_stable_row + chunk.rows as u64, before);
}

#[test]
fn a_chunk_of_very_wide_rows_keeps_the_receivers_screen_small() {
    let mut core = mirror(1000, 10);
    let row = "w".repeat(1000);
    for _ in 0..600 {
        core.feed(format!("{row}\r\n").as_bytes());
    }
    let chunk = core
        .older_chunk(core.first_stable_row(), OLDER_CHUNK_ROWS, 4 << 20)
        .expect("rows");
    assert!(chunk.rows * 1000 <= vt_core::older::OLDER_CELL_BUDGET);
    assert!(chunk.rows >= 100);
}

#[test]
fn a_hyperlink_in_an_evicted_row_still_resolves_after_loading() {
    let mut bytes =
        b"see \x1b]8;;https://example.com/doc\x1b\\the docs\x1b]8;;\x1b\\ now\r\n".to_vec();
    bytes.extend_from_slice(&numbered(20));
    let mut source = mirror(40, 10);
    source.feed(&bytes);
    let mut target = pane(40, 10);
    target.feed(&bytes);
    load_all_older(&source, &mut target);
    let snapshot = target.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "see the docs now");
    let link = snapshot
        .row_style_pairs(0)
        .iter()
        .map(|(_, style)| style.link)
        .find(|link| *link != 0)
        .expect("a linked run");
    assert_eq!(snapshot.link_uri(link), Some("https://example.com/doc"));
}

#[test]
fn a_full_older_chunk_lands_every_row_with_its_text() {
    let mut bytes = Vec::new();
    for line in 1..=6_000 {
        bytes.extend_from_slice(format!("{line}\r\n").as_bytes());
    }
    let mut source = mirror(88, 1_000);
    source.feed(&bytes);
    let mut target = pane(88, 1_000);
    target.feed(&bytes);
    let before = target.first_stable_row();
    assert_eq!(before, source.first_stable_row());

    let chunk = source
        .older_chunk(before, OLDER_CHUNK_ROWS, OUT)
        .expect("rows");
    assert_eq!(chunk.rows, OLDER_CHUNK_ROWS);
    target.feed(&chunk.bytes);

    assert_eq!(target.first_stable_row(), chunk.first_stable_row);
    let rows = texts(&target);
    let first = chunk.first_stable_row as usize + 1;
    for (index, row) in rows.iter().take(OLDER_CHUNK_ROWS + 10).enumerate() {
        assert_eq!(row, &(first + index).to_string(), "row {index}");
    }
    common::check(&target);
}
