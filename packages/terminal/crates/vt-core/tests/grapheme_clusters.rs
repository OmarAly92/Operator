use vt_core::TerminalCore;

const FAMILY: &str = "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}";

fn core(columns: usize, rows: usize, graphemes: bool) -> TerminalCore {
    let mut core = TerminalCore::new(columns, 100).expect("core");
    core.resize(columns, rows);
    core.set_grapheme_clusters(graphemes);
    core
}

fn cursor_after(input: &str, graphemes: bool) -> u32 {
    let mut core = core(20, 5, graphemes);
    core.feed(input.as_bytes());
    core.snapshot().expect("snapshot").cursor_col
}

fn alt_cell(input: &str, col: usize, graphemes: bool) -> char {
    let mut core = core(20, 5, graphemes);
    core.feed(b"\x1b[?1049h");
    core.feed(input.as_bytes());
    core.alt_grid().expect("alt").cell(0, col).ch
}

#[test]
fn the_mode_defaults_off_and_is_reported() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    assert!(!core.grapheme_clusters());
    core.set_grapheme_clusters(true);
    assert!(core.grapheme_clusters());
}

#[test]
fn a_zwj_family_occupies_two_cells_with_clusters_on_and_six_off() {
    assert_eq!(cursor_after(FAMILY, true), 2);
    assert_eq!(cursor_after(FAMILY, false), 6);
    assert_eq!(alt_cell(FAMILY, 1, true), '\0');
    assert_eq!(alt_cell(FAMILY, 2, true), ' ');
}

#[test]
fn vs16_widens_a_text_presentation_heart() {
    assert_eq!(cursor_after("\u{2764}\u{fe0f}x", true), 3);
    assert_eq!(cursor_after("\u{2764}\u{fe0f}x", false), 2);
    assert_eq!(alt_cell("\u{2764}\u{fe0f}x", 1, true), '\0');
    assert_eq!(alt_cell("\u{2764}\u{fe0f}x", 2, true), 'x');
}

#[test]
fn a_skin_tone_modifier_joins_its_base() {
    assert_eq!(cursor_after("\u{1f44b}\u{1f3fd}", true), 2);
    assert_eq!(cursor_after("\u{1f44b}\u{1f3fd}", false), 4);
}

#[test]
fn a_regional_indicator_pair_is_one_wide_cell() {
    assert_eq!(cursor_after("\u{1f1ea}\u{1f1ec}", true), 2);
    assert_eq!(alt_cell("\u{1f1ea}\u{1f1ec}", 1, true), '\0');
    assert_eq!(alt_cell("\u{1f1ea}\u{1f1ec}", 1, false), '\u{1f1ec}');
}

#[test]
fn a_combining_mark_still_attaches_and_a_leading_mark_still_lands_on_a_blank() {
    {
        let mut core = core(20, 5, true);
        core.feed("e\u{301}\u{301}".as_bytes());
        let snapshot = core.snapshot().expect("snapshot");
        assert_eq!(snapshot.row_text(0), "e\u{301}\u{301}");
        assert_eq!(snapshot.cursor_col, 1);
    }
    let mut core = core(20, 5, true);
    core.feed("\u{301}".as_bytes());
    assert_eq!(core.snapshot().expect("snapshot").row_text(0), " \u{301}");
}

#[test]
fn widening_in_the_last_column_keeps_the_cell_narrow() {
    let mut core = core(3, 5, true);
    core.feed("ab\u{2764}\u{fe0f}".as_bytes());
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "ab\u{2764}\u{fe0f}");
    assert_eq!(snapshot.row_count(), 1);
    assert_eq!(snapshot.cursor_col, 2);
}

#[test]
fn rewrap_measures_a_family_as_two_cells_with_clusters_on() {
    for (graphemes, rows) in [(true, 1), (false, 2)] {
        let mut core = core(20, 2, graphemes);
        core.feed(format!("xxxx{FAMILY}yy\r\nsecond\r\nthird\r\n").as_bytes());
        core.resize(10, 2);
        let snapshot = core.snapshot().expect("snapshot");
        let family_rows = (0..snapshot.row_count())
            .filter(|index| {
                snapshot.row_text(*index).contains("xxxx")
                    || snapshot.row_text(*index).contains("yy")
            })
            .count();
        assert_eq!(family_rows, rows, "graphemes={graphemes}");
        assert_eq!(core.verify_integrity(), Ok(()));
    }
}

#[test]
fn a_combining_mark_after_a_space_stays_with_the_space_on_rewrap_in_both_modes() {
    for graphemes in [false, true] {
        let mut core = core(8, 2, graphemes);
        core.feed("ab \u{301}cdef\r\nsecond\r\nthird\r\n".as_bytes());
        core.resize(3, 2);
        let snapshot = core.snapshot().expect("snapshot");
        for index in 0..snapshot.row_count() {
            assert!(
                !snapshot.row_text(index).starts_with('\u{301}'),
                "graphemes={graphemes} row {index}"
            );
        }
    }
}

#[test]
fn a_history_chunk_is_laid_out_in_the_cores_width_mode() {
    for (graphemes, rows) in [(true, 2), (false, 1)] {
        let mut core = TerminalCore::new(20, 10_000).expect("core");
        core.set_grapheme_clusters(graphemes);
        core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\live\r\n");
        core.feed(b"\x1b]7000;v=1;history=999,1\x1b\\");
        core.feed("\u{2764}\u{fe0f}x\r\n".as_bytes());
        core.resize(2, 24);
        let snapshot = core.snapshot().expect("snapshot");
        let heart_rows = (0..snapshot.row_count())
            .filter(|index| {
                let text = snapshot.row_text(*index);
                text.contains('\u{2764}') || text == "x"
            })
            .count();
        assert_eq!(heart_rows, rows, "graphemes={graphemes}");
    }
}
