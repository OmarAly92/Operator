mod common;

use vt_core::{Limits, TerminalCore};

fn core() -> TerminalCore {
    let mut core = TerminalCore::with_limits(40, Limits::rows_only(6)).unwrap();
    core.resize(40, 2);
    core
}

fn feed_lines(core: &mut TerminalCore, lines: &[&str]) {
    for line in lines {
        core.feed(format!("{line}\r\n").as_bytes());
    }
}

#[test]
fn stable_row_survives_trim() {
    let mut core = core();
    feed_lines(&mut core, &["1", "2", "3", "4"]);
    assert_eq!(core.first_stable_row(), 0);
    assert_eq!(core.stable_row(2), 2);
    assert_eq!(core.snapshot().unwrap().row_text(2), "3");
    feed_lines(&mut core, &["5", "6", "7"]);
    assert_eq!(core.first_stable_row(), 1);
    let flat = core.flat_row(2).expect("row 3 is still retained");
    assert_eq!(flat, 1);
    assert_eq!(core.stable_row(flat), 2);
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.first_stable_row, 1);
    assert_eq!(snapshot.row_text(flat), "3");
    common::check(&core);
}

#[test]
fn flat_row_is_none_after_trim() {
    let mut core = core();
    feed_lines(&mut core, &["1", "2", "3", "4", "5", "6", "7"]);
    assert_eq!(core.first_stable_row(), 1);
    assert_eq!(core.flat_row(0), None);
    assert_eq!(core.flat_row(1), Some(0));
    common::check(&core);
}

#[test]
fn blocks_keep_rows_across_trim() {
    let mut core = core();
    feed_lines(&mut core, &["1", "2"]);
    core.feed(b"\x1b]133;A\x07");
    let before = core.snapshot().unwrap();
    assert_eq!(before.blocks.len(), 2);
    assert_eq!(before.blocks[1].first_row, 2);
    assert_eq!(core.stable_row(before.blocks[1].first_row as usize), 2);
    feed_lines(&mut core, &["3", "4", "5", "6", "7"]);
    let after = core.snapshot().unwrap();
    assert_eq!(after.first_stable_row, 1);
    assert_eq!(after.blocks.len(), 2);
    assert_eq!(after.blocks[0].first_row, 0);
    assert_eq!(after.blocks[0].row_count, 1);
    assert_eq!(after.blocks[1].first_row, 1);
    assert_eq!(core.stable_row(after.blocks[1].first_row as usize), 2);
    assert_eq!(after.row_text(after.blocks[1].first_row as usize), "3");
    common::check(&core);
}
