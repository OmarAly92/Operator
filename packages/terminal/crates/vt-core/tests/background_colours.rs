use vt_core::{CellStyle, StyleCode, TerminalCore};

fn alt_style(bytes: &[u8]) -> CellStyle {
    let mut core = TerminalCore::new(40, 100).expect("core");
    core.resize(40, 10);
    core.feed(b"\x1b[?1049h");
    core.feed(bytes);
    core.alt_grid().expect("alt").cell(0, 0).style
}

#[test]
fn an_indexed_background_survives_to_the_cell() {
    let style = alt_style(b"\x1b[48;5;237mA");
    assert_eq!(style.bg, StyleCode::indexed(237));
    assert_eq!(style.fg, StyleCode::DEFAULT);
}

#[test]
fn a_truecolour_background_survives_to_the_cell() {
    let style = alt_style(b"\x1b[48;2;55;55;55mA");
    assert_eq!(style.bg, StyleCode::rgb(55, 55, 55));
}

#[test]
fn the_basic_and_bright_background_codes_map_to_ansi_slots() {
    assert_eq!(alt_style(b"\x1b[41mA").bg, StyleCode::ansi(1));
    assert_eq!(alt_style(b"\x1b[107mA").bg, StyleCode::ansi(15));
    assert_eq!(
        alt_style(b"\x1b[41m\x1b[49mA").bg,
        StyleCode::DEFAULT_BACKGROUND
    );
    assert_eq!(
        alt_style(b"\x1b[41m\x1b[0mA").bg,
        StyleCode::DEFAULT_BACKGROUND
    );
}

#[test]
fn a_background_and_a_foreground_coexist() {
    let style = alt_style(b"\x1b[48;5;237m\x1b[38;5;231mA");
    assert_eq!(style.bg, StyleCode::indexed(237));
    assert_eq!(style.fg.colour(), StyleCode::indexed(231));
}

#[test]
fn reverse_video_swaps_the_two_colours_and_keeps_bold() {
    let style = alt_style(b"\x1b[1m\x1b[31m\x1b[44m\x1b[7mA");
    assert_eq!(style.fg.colour(), StyleCode::ansi(4));
    assert_eq!(style.bg, StyleCode::ansi(1));
    assert!(style.fg.is_bold());
    assert!(!style.fg.is_reverse());
}

#[test]
fn reverse_video_on_an_unstyled_cell_swaps_the_two_defaults() {
    let style = alt_style(b"\x1b[7mA");
    assert_eq!(style.fg.colour(), StyleCode::DEFAULT_BACKGROUND);
    assert_eq!(style.bg, StyleCode::DEFAULT);
}

#[test]
fn cancelling_reverse_video_restores_the_original_order() {
    let style = alt_style(b"\x1b[31m\x1b[44m\x1b[7m\x1b[27mA");
    assert_eq!(style.fg.colour(), StyleCode::ansi(1));
    assert_eq!(style.bg, StyleCode::ansi(4));
}

#[test]
fn trailing_spaces_carrying_a_background_are_not_trimmed_from_the_row() {
    let mut core = TerminalCore::new(40, 20).unwrap();
    core.feed(b"\x1b[48;5;237m\xe2\x9d\xaf hi          \x1b[0m");
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.row_text(0), "\u{276f} hi          ");
    let pairs = snapshot.row_style_pairs(0);
    assert_eq!(pairs.len(), 1);
    assert_eq!(pairs[0].1.bg, StyleCode::indexed(237));
}

#[test]
fn trailing_spaces_with_no_background_are_still_trimmed() {
    let mut core = TerminalCore::new(40, 20).unwrap();
    core.feed(b"hi          ");
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.row_text(0), "hi");
}

#[test]
fn erase_in_line_paints_the_current_background() {
    let mut core = TerminalCore::new(40, 100).unwrap();
    core.resize(40, 10);
    core.feed(b"\x1b[?1049h");
    core.feed(b"abcde\x1b[1;3H\x1b[41m\x1b[K");
    let alt = core.alt_grid().expect("alt");
    assert_eq!(alt.cell(0, 1).style.bg, StyleCode::DEFAULT_BACKGROUND);
    assert_eq!(alt.cell(0, 2).style.bg, StyleCode::ansi(1));
    assert_eq!(alt.cell(0, 9).style.bg, StyleCode::ansi(1));
}

#[test]
fn erase_ignores_reverse_video_the_way_warp_does() {
    let mut core = TerminalCore::new(40, 100).unwrap();
    core.resize(40, 10);
    core.feed(b"\x1b[?1049h");
    core.feed(b"abcde\x1b[1;3H\x1b[41m\x1b[7m\x1b[K");
    let alt = core.alt_grid().expect("alt");
    assert_eq!(alt.cell(0, 3).style.bg, StyleCode::ansi(1));
    assert_eq!(alt.cell(0, 3).style.fg, StyleCode::DEFAULT);
}
