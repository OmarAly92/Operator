use vt_core::{CoreError, StyleCode, TerminalCore};

#[test]
fn parses_utf8_crlf_wrap_and_sgr_into_flat_runs() {
    let mut core = TerminalCore::new(16, 100).unwrap();
    core.feed(b"\x1b[31mred\x1b[0m caf\xc3");
    core.feed(b"\xa9\r\nplain\ttext");
    let snapshot = core.snapshot();

    assert_eq!(snapshot.row_text(0), "red café");
    assert_eq!(snapshot.row_text(1), "plain   text");
    assert_eq!(
        snapshot.row_style_pairs(0),
        &[(3, StyleCode::ansi(1)), (9, StyleCode::DEFAULT),]
    );
    assert_eq!(snapshot.row_style_pairs(1), &[(12, StyleCode::DEFAULT)]);
}

#[test]
fn hard_wraps_wide_and_combining_text_without_splitting_utf8() {
    let mut core = TerminalCore::new(4, 100).unwrap();
    core.feed("A界e\u{301}B".as_bytes());
    let snapshot = core.snapshot();

    assert_eq!(snapshot.row_text(0), "A界e\u{301}");
    assert_eq!(snapshot.row_text(1), "B");
}

#[test]
fn trims_complete_rows_to_the_scrollback_limit() {
    let mut core = TerminalCore::new(20, 2).unwrap();
    core.feed(b"one\ntwo\nthree");
    let snapshot = core.snapshot();

    assert_eq!(snapshot.row_count(), 2);
    assert_eq!(snapshot.row_text(0), "two");
    assert_eq!(snapshot.row_text(1), "three");
}

#[test]
fn zero_columns_is_a_distinct_error() {
    match TerminalCore::new(0, 100) {
        Err(CoreError::ZeroColumns) => {}
        Err(other) => panic!("expected ZeroColumns, got {other:?}"),
        Ok(_) => panic!("expected ZeroColumns, got Ok"),
    }
}

#[test]
fn zero_scrollback_is_a_distinct_error() {
    match TerminalCore::new(20, 0) {
        Err(CoreError::ZeroScrollback) => {}
        Err(other) => panic!("expected ZeroScrollback, got {other:?}"),
        Ok(_) => panic!("expected ZeroScrollback, got Ok"),
    }
}

#[test]
fn surviving_first_row_begins_inside_a_style_run() {
    let mut core = TerminalCore::new(4, 1).unwrap();
    core.feed(b"\x1b[31mABCD\n");
    core.feed(b"EF\x1b[0mG");
    let snapshot = core.snapshot();

    assert_eq!(snapshot.row_count(), 1);
    assert_eq!(snapshot.row_text(0), "EFG");
    assert_eq!(
        snapshot.row_style_pairs(0),
        &[(2, StyleCode::ansi(1)), (3, StyleCode::DEFAULT),]
    );
}
