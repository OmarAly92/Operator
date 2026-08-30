use vt_core::TerminalCore;

fn first_row(input: &str, columns: usize) -> String {
    let mut core = TerminalCore::new(columns, 100).unwrap();
    core.resize(columns, 5);
    core.feed(input.as_bytes());
    core.snapshot().unwrap().row_text(0).to_string()
}

#[test]
fn a_combining_mark_stays_with_its_base() {
    assert_eq!(first_row("e\u{301}", 20), "e\u{301}");
}

#[test]
fn a_variation_selector_stays_with_its_base() {
    assert_eq!(first_row("\u{26a0}\u{fe0f}", 20), "\u{26a0}\u{fe0f}");
}

#[test]
fn a_zwj_sequence_stays_in_one_cell() {
    assert_eq!(
        first_row("\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}", 20),
        "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}",
    );
}

#[test]
fn a_combining_mark_attaches_to_the_base_of_a_wide_char() {
    assert_eq!(first_row("\u{754c}\u{301}", 20), "\u{754c}\u{301}");
}

#[test]
fn a_mark_arriving_after_a_wrap_attaches_to_the_last_cell_of_the_row() {
    let mut core = TerminalCore::new(2, 100).unwrap();
    core.resize(2, 5);
    core.feed("ab\u{301}c".as_bytes());
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.row_text(0), "ab\u{301}");
    assert_eq!(snapshot.row_text(1), "c");
}

#[test]
fn a_leading_mark_with_no_base_does_not_panic() {
    assert_eq!(first_row("\u{301}", 20), " \u{301}");
}

#[test]
fn zero_width_content_is_capped_per_cell() {
    let mut input = String::from("e");
    for _ in 0..400 {
        input.push('\u{301}');
    }
    let row = first_row(&input, 20);
    assert!(row.len() <= 256, "grapheme grew to {} bytes", row.len());
    assert!(row.starts_with('e'));
}

#[test]
fn a_grapheme_survives_the_trip_into_scrollback() {
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.resize(20, 2);
    core.feed("e\u{301}\r\nsecond\r\nthird\r\n".as_bytes());
    let snapshot = core.snapshot().unwrap();
    let rows: Vec<String> = (0..snapshot.row_count())
        .map(|i| snapshot.row_text(i).to_string())
        .collect();
    assert!(rows.contains(&"e\u{301}".to_string()), "got {rows:?}");
}

#[test]
fn a_grapheme_survives_the_alternate_screen() {
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.resize(20, 5);
    core.feed(b"\x1b[?1049h");
    core.feed("e\u{301}".as_bytes());
    assert_eq!(core.alt_grid().unwrap().row_text(0).trim_end(), "e\u{301}");
}
