mod common;

use vt_core::{CellSpan, TerminalCore};

const FAMILY: &str = "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}";

fn spans_of(input: &str, graphemes: bool) -> Vec<(u32, u32, u8)> {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.set_grapheme_clusters(graphemes);
    core.feed(input.as_bytes());
    let snapshot = core.snapshot().expect("snapshot");
    common::check(&core);
    snapshot
        .row_cell_spans(0)
        .iter()
        .map(|span| (span.start, span.end, span.width))
        .collect()
}

#[test]
fn an_ascii_row_lists_no_spans() {
    assert!(spans_of("plain text", false).is_empty());
}

#[test]
fn wide_and_joined_clusters_are_listed_with_their_bytes_and_cells() {
    assert_eq!(spans_of("a\u{6f22}b", false), vec![(1, 4, 2)]);
    assert_eq!(spans_of("e\u{301}x", false), vec![(0, 3, 1)]);
    assert_eq!(spans_of("\u{301}", false), vec![(0, 3, 1)]);
    assert_eq!(spans_of("a\u{6f22}", false), vec![(1, 4, 2)]);
}

#[test]
fn a_family_is_three_spans_in_scalar_mode_and_one_in_grapheme_mode() {
    assert_eq!(
        spans_of(FAMILY, false),
        vec![(0, 7, 2), (7, 14, 2), (14, 18, 2)]
    );
    assert_eq!(spans_of(FAMILY, true), vec![(0, 18, 2)]);
    assert_eq!(spans_of("\u{2764}\u{fe0f}", true), vec![(0, 6, 2)]);
    assert_eq!(spans_of("\u{2764}\u{fe0f}", false), vec![(0, 6, 1)]);
}

#[test]
fn a_row_committed_to_scrollback_keeps_the_same_spans_it_had_on_screen() {
    for graphemes in [false, true] {
        let mut core = TerminalCore::new(20, 100).expect("core");
        core.resize(20, 2);
        core.set_grapheme_clusters(graphemes);
        core.feed(format!("a\u{6f22}{FAMILY}e\u{301}").as_bytes());
        let on_screen: Vec<CellSpan> = core
            .snapshot()
            .expect("snapshot")
            .row_cell_spans(0)
            .to_vec();
        assert!(!on_screen.is_empty());
        core.feed(b"\r\nsecond\r\nthird\r\n");
        let snapshot = core.snapshot().expect("snapshot");
        common::check(&core);
        let row = (0..snapshot.row_count())
            .find(|index| snapshot.row_text(*index).starts_with('a'))
            .expect("row committed");
        assert!(
            row < snapshot.history_rows as usize,
            "the row is in scrollback"
        );
        assert_eq!(
            snapshot.row_cell_spans(row),
            on_screen.as_slice(),
            "graphemes={graphemes}"
        );
    }
}

#[test]
fn the_alternate_screen_exports_spans_too() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.feed(b"\x1b[?1049h");
    core.feed("x\u{6f22}".as_bytes());
    let alt = core
        .snapshot()
        .expect("snapshot")
        .alt
        .expect("alt snapshot");
    assert_eq!(alt.span_ranges[0], (0, 1));
    assert_eq!(
        alt.cell_spans[0],
        CellSpan {
            start: 1,
            end: 4,
            width: 2
        }
    );
}
