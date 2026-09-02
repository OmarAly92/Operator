use vt_core::TerminalCore;

#[test]
fn the_snapshot_reports_where_the_cursor_sits_on_the_primary_screen() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"one\r\ntwo\r\n> hi");
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.cursor_row, 2);
    assert_eq!(snapshot.cursor_col, 4);
    assert!(snapshot.cursor_visible);
}

#[test]
fn the_cursor_row_counts_from_the_top_of_the_scrollback() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 3);
    for line in 0..10 {
        core.feed(format!("line{line}\r\n").as_bytes());
    }
    core.feed(b"tail");
    let snapshot = core.snapshot().unwrap();
    let last = snapshot.row_count() - 1;
    assert_eq!(snapshot.row_text(last).trim_end(), "tail");
    assert_eq!(snapshot.cursor_row as usize, last);
    assert_eq!(snapshot.cursor_col, 4);
}

#[test]
fn hiding_the_cursor_is_reported() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"x\x1b[?25l");
    assert!(!core.snapshot().unwrap().cursor_visible);
    core.feed(b"\x1b[?25h");
    assert!(core.snapshot().unwrap().cursor_visible);
}

// A reflowing resize evicts the whole screen into the block stream and restarts
// at a fresh row, so the cursor lands below the last line it wrote. The renderer
// trims that blank row away and draws no cursor until the next output, which is
// what `dead block height` requires -- the cursor must not resurrect it.
#[test]
fn a_reflowing_resize_moves_the_cursor_to_the_fresh_screen() {
    let mut core = TerminalCore::new(16, 100).unwrap();
    core.resize(16, 24);
    core.feed(b"red\r\nplain");
    assert_eq!(core.snapshot().unwrap().cursor_row, 1);
    core.resize(103, 17);
    let after = core.snapshot().unwrap();
    assert_eq!((after.cursor_row, after.cursor_col), (2, 0));
}
