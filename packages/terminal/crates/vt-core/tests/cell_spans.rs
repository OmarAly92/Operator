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

fn overwrite(cols: usize, graphemes: bool, input: &str) -> (String, Vec<(u32, u32, u8)>) {
    let mut core = TerminalCore::new(cols, 100).expect("core");
    core.resize(cols, 3);
    core.set_grapheme_clusters(graphemes);
    core.feed(input.as_bytes());
    common::check(&core);
    let snapshot = core.snapshot().expect("snapshot");
    let spans = snapshot
        .row_cell_spans(0)
        .iter()
        .map(|span| (span.start, span.end, span.width))
        .collect();
    (snapshot.row_text(0).to_string(), spans)
}

#[test]
fn a_wide_character_over_a_continuation_blanks_both_orphaned_halves() {
    for graphemes in [false, true] {
        assert_eq!(
            overwrite(4, graphemes, "\u{65e5}\u{65e5}\x1b[1;2H\u{65e5}"),
            (" \u{65e5}".to_string(), vec![(1, 4, 2)]),
            "graphemes={graphemes}"
        );
    }
}

#[test]
fn a_wide_character_over_a_continuation_blanks_the_lead_before_it() {
    for graphemes in [false, true] {
        assert_eq!(
            overwrite(5, graphemes, "\u{65e5}ab\x1b[1;2H\u{65e5}"),
            (" \u{65e5}b".to_string(), vec![(1, 4, 2)]),
            "graphemes={graphemes}"
        );
    }
}

#[test]
fn a_wide_character_over_a_lead_blanks_the_continuation_after_it() {
    for graphemes in [false, true] {
        assert_eq!(
            overwrite(5, graphemes, "ab\u{65e5}c\x1b[1;2H\u{65e5}"),
            ("a\u{65e5} c".to_string(), vec![(1, 4, 2)]),
            "graphemes={graphemes}"
        );
    }
}

#[test]
fn a_narrow_character_over_a_lead_blanks_the_continuation() {
    for graphemes in [false, true] {
        for narrow in ["x", "\u{e9}"] {
            assert_eq!(
                overwrite(5, graphemes, &format!("\u{65e5}b\x1b[1;1H{narrow}")),
                (format!("{narrow} b"), vec![]),
                "graphemes={graphemes} narrow={narrow}"
            );
        }
    }
}

#[test]
fn a_narrow_character_over_a_continuation_blanks_the_lead() {
    for graphemes in [false, true] {
        for narrow in ["x", "\u{e9}"] {
            assert_eq!(
                overwrite(5, graphemes, &format!("\u{65e5}b\x1b[1;2H{narrow}")),
                (format!(" {narrow}b"), vec![]),
                "graphemes={graphemes} narrow={narrow}"
            );
        }
    }
}

#[test]
fn an_ascii_run_across_two_wide_characters_blanks_the_halves_at_both_ends() {
    for graphemes in [false, true] {
        assert_eq!(
            overwrite(5, graphemes, "\u{65e5}\u{65e5}z\x1b[1;2Hxy"),
            (" xy z".to_string(), vec![]),
            "graphemes={graphemes}"
        );
    }
}

#[test]
fn a_cluster_widened_by_a_selector_blanks_the_continuation_it_orphans() {
    assert_eq!(
        overwrite(5, true, "\u{2764}\u{65e5}z\x1b[1;2H\u{fe0f}"),
        ("\u{2764}\u{fe0f} z".to_string(), vec![(0, 6, 2)]),
    );
}
