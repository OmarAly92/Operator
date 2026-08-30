use vt_core::{CoreError, StyleCode, TerminalCore};

#[test]
fn parses_utf8_crlf_wrap_and_sgr_into_flat_runs() {
    let mut core = TerminalCore::new(16, 100).unwrap();
    core.feed(b"\x1b[31mred\x1b[0m caf\xc3");
    core.feed(b"\xa9\r\nplain\ttext");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.row_text(0), "red café");
    assert_eq!(snapshot.row_text(1), "plain   text");
    assert_eq!(
        snapshot.row_style_pairs(0),
        &[(3, StyleCode::ansi(1)), (9, StyleCode::DEFAULT),]
    );
    assert_eq!(snapshot.row_style_pairs(1), &[(12, StyleCode::DEFAULT)]);
}

#[test]
fn hard_wraps_wide_text_and_drops_zero_width_scalars() {
    let mut core = TerminalCore::new(4, 100).unwrap();
    core.feed("A界e\u{301}B".as_bytes());
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.row_text(0), "A界e");
    assert_eq!(snapshot.row_text(1), "B");
}

#[test]
fn trims_complete_rows_to_the_scrollback_limit() {
    let mut core = TerminalCore::new(20, 2).unwrap();
    core.resize(20, 1);
    core.feed(b"one\r\ntwo\r\nthree");
    let snapshot = core.snapshot().unwrap();

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
    core.resize(4, 1);
    core.feed(b"\x1b[31mABCD\r\n");
    core.feed(b"EF\x1b[0mG");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.row_count(), 1);
    assert_eq!(snapshot.row_text(0), "EFG");
    assert_eq!(
        snapshot.row_style_pairs(0),
        &[(2, StyleCode::ansi(1)), (3, StyleCode::DEFAULT),]
    );
}

#[test]
fn retained_rows_keep_their_text_after_many_chunks_of_trimming() {
    let mut core = TerminalCore::new(20, 40).unwrap();
    core.resize(20, 1);
    for index in 0..200u32 {
        core.feed(format!("row{index:04}-padpadpad\r\n").as_bytes());
    }
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.row_count(), 40);
    assert_eq!(snapshot.row_text(0), "row0161-padpadpad");
    assert_eq!(snapshot.row_text(38), "row0199-padpadpad");
    assert_eq!(snapshot.row_text(39), "");
}

#[test]
fn trailing_newline_does_not_drop_the_retained_scrollback() {
    let mut core = TerminalCore::new(20, 3).unwrap();
    core.resize(20, 1);
    core.feed(b"alpha\r\nbravo\r\ncharlie\r\n");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.row_count(), 3);
    assert_eq!(snapshot.row_text(0), "bravo");
    assert_eq!(snapshot.row_text(1), "charlie");
    assert_eq!(snapshot.row_text(2), "");
}

#[test]
fn zero_width_scalars_cannot_grow_the_open_row_without_bound() {
    let mut core = TerminalCore::new(8, 4).unwrap();
    let combining = "\u{301}".repeat(1000);
    for _ in 0..20 {
        core.feed(combining.as_bytes());
    }
    let snapshot = core.snapshot().unwrap();

    assert!(
        snapshot.content.len() < 1024,
        "open row grew to {} bytes",
        snapshot.content.len()
    );
}

#[test]
fn extended_colour_parameters_never_leak_into_the_foreground() {
    let mut core = TerminalCore::new(40, 10).unwrap();
    core.feed(b"\x1b[48;5;31mBG\x1b[0m");
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.row_style_pairs(0), &[(2, StyleCode::DEFAULT)]);

    let mut truecolour = TerminalCore::new(40, 10).unwrap();
    truecolour.feed(b"\x1b[31m\x1b[38;2;10;0;0mX");
    let snapshot = truecolour.snapshot().unwrap();
    assert_eq!(
        snapshot.row_style_pairs(0),
        &[(1, StyleCode::rgb(10, 0, 0))]
    );
}

#[test]
fn colon_form_extended_colour_is_self_contained() {
    let mut core = TerminalCore::new(40, 10).unwrap();
    core.feed(b"\x1b[38:5:196m\x1b[32mG");
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.row_style_pairs(0), &[(1, StyleCode::ansi(2))]);
}
