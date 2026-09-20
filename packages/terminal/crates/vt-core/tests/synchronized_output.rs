mod common;

use vt_core::sync::{SYNC_BUFFER_CAP, SYNC_TIMEOUT_MS};
use vt_core::{BlockSource, TerminalCore};

const BSU: &[u8] = b"\x1b[?2026h";
const ESU: &[u8] = b"\x1b[?2026l";

fn core() -> TerminalCore {
    let mut core = TerminalCore::new(40, 100).unwrap();
    core.resize(40, 5);
    core
}

fn screen(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    let mut rows: Vec<String> = (0..snapshot.row_count())
        .map(|i| snapshot.row_text(i).to_string())
        .collect();
    while rows.last().is_some_and(|row| row.is_empty()) {
        rows.pop();
    }
    rows
}

fn cat(parts: &[&[u8]]) -> Vec<u8> {
    parts.concat()
}

#[test]
fn bytes_inside_a_sync_block_are_invisible_until_esu() {
    let mut core = core();
    core.feed_at(b"one\r\n", 0);
    core.feed_at(&cat(&[BSU, b"two\r\n"]), 10);
    assert_eq!(screen(&core), vec!["one"]);
    assert!(core.synchronized_output());
    core.feed_at(ESU, 20);
    assert_eq!(screen(&core), vec!["one", "two"]);
    assert!(!core.synchronized_output());
    common::check(&core);
}

#[test]
fn a_frame_split_across_three_feeds_snapshots_once() {
    let mut core = core();
    let mut changes = 0;
    let mut last = screen(&core);
    for (bytes, at) in [
        (cat(&[BSU, b"alpha"]), 0u64),
        (b"\r\nbeta".to_vec(), 5),
        (ESU.to_vec(), 10),
    ] {
        core.feed_at(&bytes, at);
        let now = screen(&core);
        if now != last {
            changes += 1;
            last = now;
        }
    }
    assert_eq!(changes, 1);
    assert_eq!(screen(&core), vec!["alpha", "beta"]);
}

#[test]
fn a_mark_inside_a_sync_block_lands_after_the_rows_before_it() {
    let bytes = b"before\r\n\x1b]133;A\x07$ \x1b]133;B\x07";
    let mut plain = core();
    plain.feed_at(bytes, 0);
    let mut synced = core();
    synced.feed_at(BSU, 0);
    synced.feed_at(&bytes[..4], 1);
    synced.feed_at(&bytes[4..], 2);
    synced.feed_at(ESU, 3);
    let describe = |core: &TerminalCore| -> Vec<(u32, u32, BlockSource)> {
        core.snapshot()
            .unwrap()
            .blocks
            .iter()
            .map(|b| (b.first_row, b.row_count, b.source))
            .collect()
    };
    assert_eq!(describe(&synced), describe(&plain));
    assert_eq!(describe(&synced)[1].0, 1, "{:?}", describe(&synced));
    common::check(&synced);
}

#[test]
fn overflow_flushes() {
    let mut core = core();
    core.feed_at(BSU, 0);
    let row = [b"x".repeat(38).as_slice(), b"\r\n"].concat();
    let mut fed = 0usize;
    while fed < SYNC_BUFFER_CAP + row.len() {
        core.feed_at(&row, 0);
        fed += row.len();
    }
    assert!(
        !screen(&core).is_empty(),
        "the cap must force a flush without an ESU"
    );
    common::check(&core);
}

#[test]
fn an_oversized_chunk_starting_with_bsu_is_parsed_plainly() {
    let mut core = core();
    let row = [b"x".repeat(38).as_slice(), b"\r\n"].concat();
    let mut chunk = BSU.to_vec();
    while chunk.len() < SYNC_BUFFER_CAP {
        chunk.extend_from_slice(&row);
    }
    assert!(core.feed_at(&chunk, 0));
    assert!(!core.synchronized_output());
    assert!(!screen(&core).is_empty());
    common::check(&core);
}

#[test]
fn tick_past_deadline_flushes() {
    let mut core = core();
    core.feed_at(&cat(&[BSU, b"late"]), 0);
    assert!(!core.tick(SYNC_TIMEOUT_MS - 1));
    assert!(screen(&core).is_empty());
    assert!(core.tick(SYNC_TIMEOUT_MS));
    assert_eq!(screen(&core), vec!["late"]);
    assert!(!core.synchronized_output());
}

#[test]
fn bsu_inside_a_block_extends_the_deadline() {
    let mut core = core();
    core.feed_at(&cat(&[BSU, b"a"]), 0);
    core.feed_at(&cat(&[BSU, b"b"]), 100);
    assert!(!core.tick(200));
    assert!(screen(&core).is_empty());
    assert!(core.tick(250));
    assert_eq!(screen(&core), vec!["ab"]);
}

#[test]
fn resize_flushes() {
    let mut core = core();
    core.feed_at(&cat(&[BSU, b"x"]), 0);
    core.resize(40, 6);
    assert_eq!(screen(&core), vec!["x"]);
    assert!(!core.synchronized_output());
}

#[test]
fn unknown_private_modes_still_ignored() {
    let mut core = core();
    core.feed_at(b"\x1b[?2027h\x1b[?2026;1hok\x1b[?2026l", 0);
    assert_eq!(screen(&core), vec!["ok"]);
    assert!(!core.synchronized_output());
    assert!(!core.mouse_tracking());
    assert!(!core.bracketed_paste());
}

#[test]
fn a_bsu_split_byte_by_byte_still_buffers() {
    let mut core = core();
    for byte in cat(&[BSU, b"hidden"]) {
        core.feed_at(&[byte], 0);
    }
    assert!(core.synchronized_output());
    assert!(screen(&core).is_empty());
    for byte in ESU {
        core.feed_at(&[*byte], 1);
    }
    assert_eq!(screen(&core), vec!["hidden"]);
    common::check(&core);
}

#[test]
fn a_boundary_mark_inside_a_sync_block_flushes() {
    let mut core = core();
    core.set_agent_tui_mode(true);
    core.feed_at(&cat(&[BSU, b"old"]), 0);
    core.feed_at(b"\x1b]7000;v=1;boundary=0\x07", 1);
    assert!(!core.synchronized_output());
    assert_eq!(screen(&core), vec!["old"]);
    assert_eq!(core.snapshot().unwrap().blocks[0].exit_code, Some(0));
}

#[test]
fn pending_sync_bytes_are_the_unflushed_tail() {
    let mut core = core();
    core.feed_at(b"seen", 0);
    core.feed_at(&cat(&[BSU, b"half"]), 0);
    assert_eq!(core.pending_sync_bytes(), cat(&[BSU, b"half"]).as_slice());
    core.feed_at(ESU, 0);
    assert!(core.pending_sync_bytes().is_empty());
}

#[test]
fn feed_without_a_clock_keeps_the_last_one() {
    let mut core = core();
    core.feed_at(BSU, 40);
    core.feed(b"x");
    assert!(core.synchronized_output());
    assert!(core.tick(40 + SYNC_TIMEOUT_MS));
    assert_eq!(screen(&core), vec!["x"]);
}

#[test]
fn feed_at_reports_whether_anything_was_parsed() {
    let mut core = core();
    assert!(
        core.feed_at(&cat(&[b"a", BSU]), 0),
        "the bytes before a BSU are parsed"
    );
    assert!(!core.feed_at(b"b", 0));
    assert!(core.feed_at(ESU, 0));
    assert!(!core.feed_at(BSU, 0), "a bare BSU parses nothing");
}

#[test]
fn a_bsu_straddling_two_feeds_wins_over_a_later_one_in_the_same_chunk() {
    let mut core = core();
    core.feed_at(&BSU[..3], 0);
    let rest = cat(&[&BSU[3..], b"first", BSU, b"second"]);
    core.feed_at(&rest, 1);
    assert!(core.synchronized_output());
    assert!(screen(&core).is_empty());
    core.feed_at(ESU, 2);
    assert_eq!(screen(&core), vec!["firstsecond"]);
}
