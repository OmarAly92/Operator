use proptest::prelude::*;
use vt_core::testing::ScreenGrid;
use vt_core::{CellStyle, StyleCode, TerminalCore, WidthMode};

const SPECIALS: [&str; 10] = [
    "\u{4e2d}",
    "e\u{301}",
    "\u{1f44d}\u{1f3fd}",
    "\u{1f468}\u{200d}\u{1f469}",
    "\u{600}",
    "\u{7f}",
    "\u{fe0f}",
    "\u{1f1ea}\u{1f1ec}",
    "\u{200b}",
    "\u{1100}\u{1161}",
];

fn grid(rows: usize, cols: usize, mode: WidthMode) -> ScreenGrid {
    let mut grid = ScreenGrid::new(rows, cols);
    grid.set_width_mode(mode);
    grid
}

#[derive(Debug, PartialEq)]
struct GridState {
    cells: Vec<String>,
    cursor: (usize, usize),
    wrapped: Vec<bool>,
    content_rows: usize,
    dirty: Vec<usize>,
}

fn state(grid: &mut ScreenGrid) -> GridState {
    let mut cells = Vec::new();
    let mut buffer = [0u8; 4];
    for row in 0..grid.rows() {
        for col in 0..grid.cols() {
            let cell = grid.cell(row, col);
            cells.push(format!("{}|{:?}", cell.text(&mut buffer), cell.style));
        }
    }
    GridState {
        cells,
        cursor: grid.cursor(),
        wrapped: (0..grid.rows()).map(|row| grid.row_wrapped(row)).collect(),
        content_rows: grid.content_rows(),
        dirty: grid.take_dirty(),
    }
}

fn per_char(grid: &mut ScreenGrid, text: &str, style: CellStyle) {
    for ch in text.chars() {
        grid.print(ch, style);
    }
}

fn by_runs(grid: &mut ScreenGrid, text: &str, style: CellStyle) {
    let mut run = Vec::new();
    for ch in text.chars() {
        if matches!(ch, ' '..='~') {
            run.push(ch as u8);
            continue;
        }
        grid.print_ascii_run(&run, style);
        run.clear();
        grid.print(ch, style);
    }
    grid.print_ascii_run(&run, style);
}

fn segment() -> impl Strategy<Value = String> {
    prop_oneof![
        "[ -~]{0,30}",
        (0..SPECIALS.len()).prop_map(|index| SPECIALS[index].to_string()),
    ]
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 512, ..ProptestConfig::default() })]

    #[test]
    fn an_ascii_run_lands_exactly_where_printing_it_one_char_at_a_time_does(
        rows in 1usize..6,
        cols in 1usize..12,
        graphemes in any::<bool>(),
        start_col in 0usize..12,
        segments in prop::collection::vec(segment(), 1..12),
    ) {
        let mode = if graphemes { WidthMode::Grapheme } else { WidthMode::Scalar };
        let text: String = segments.concat();
        let style = CellStyle::new(StyleCode::ansi(2), StyleCode::DEFAULT_BACKGROUND);
        let mut one = grid(rows, cols, mode);
        let mut runs = grid(rows, cols, mode);
        one.move_to(0, start_col);
        runs.move_to(0, start_col);
        per_char(&mut one, &text, style);
        by_runs(&mut runs, &text, style);
        prop_assert_eq!(state(&mut one), state(&mut runs));
    }
}

fn screen_text(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().expect("snapshot");
    (0..snapshot.row_count())
        .map(|row| snapshot.row_text(row).to_string())
        .collect()
}

fn core(cols: usize, graphemes: bool) -> TerminalCore {
    let mut core = TerminalCore::new(cols, 100).expect("core");
    core.resize(cols, 5);
    core.set_grapheme_clusters(graphemes);
    core
}

#[test]
fn an_ascii_letter_after_a_prepend_mark_joins_it_and_the_next_letter_does_not() {
    let mut core = core(10, true);
    core.feed("\u{600}ab".as_bytes());
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "\u{600}ab");
    let spans: Vec<(u32, u32, u8)> = snapshot
        .row_cell_spans(0)
        .iter()
        .map(|span| (span.start, span.end, span.width))
        .collect();
    assert_eq!(spans, vec![(0, 3, 2)]);
    assert_eq!(snapshot.cursor_col, 3);
}

#[test]
fn a_run_split_at_every_byte_matches_the_run_fed_whole() {
    let input = "plain \x1b[31mred\x1b[0m wide \u{4e2d}\u{6587} e\u{301} tail that wraps past the edge\r\nnext";
    for graphemes in [false, true] {
        let mut whole = core(12, graphemes);
        whole.feed(input.as_bytes());
        let mut split = core(12, graphemes);
        for byte in input.as_bytes() {
            split.feed(std::slice::from_ref(byte));
        }
        assert_eq!(screen_text(&whole), screen_text(&split));
        let (a, b) = (whole.snapshot().expect("a"), split.snapshot().expect("b"));
        assert_eq!((a.cursor_row, a.cursor_col), (b.cursor_row, b.cursor_col));
        for row in 0..a.row_count() {
            assert_eq!(a.row_style_pairs(row), b.row_style_pairs(row));
            assert_eq!(a.row_wrapped(row), b.row_wrapped(row));
        }
    }
}

#[test]
fn a_run_takes_the_style_in_force_when_it_was_printed() {
    let mut core = core(20, true);
    core.feed(b"ab\x1b[1mcd\x1b[0mef");
    let snapshot = core.snapshot().expect("snapshot");
    let pairs = snapshot.row_style_pairs(0);
    assert_eq!(pairs.len(), 3);
    assert_eq!(pairs[0].0, 2);
    assert!(pairs[1].1.fg.is_bold());
    assert_eq!(pairs[1].0, 4);
    assert!(!pairs[2].1.fg.is_bold());
}

#[test]
fn a_run_that_reaches_the_last_column_wraps_only_when_the_next_character_arrives() {
    let mut core = core(4, false);
    core.feed(b"abcd");
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(screen_text(&core), vec!["abcd".to_string()]);
    assert_eq!((snapshot.cursor_row, snapshot.cursor_col), (0, 3));
    core.feed(b"e");
    assert_eq!(
        screen_text(&core),
        vec!["abcd".to_string(), "e".to_string()]
    );
    assert!(core.snapshot().expect("snapshot").row_wrapped(0));
}

#[test]
fn invalid_utf8_inside_a_run_prints_a_replacement_character() {
    let mut core = core(20, true);
    core.feed(b"ab\xffcd");
    assert_eq!(screen_text(&core), vec!["ab\u{fffd}cd".to_string()]);
    let mut split = self::core(20, true);
    split.feed(b"ab\xe4\xb8");
    split.feed(b"\xadcd");
    assert_eq!(screen_text(&split), vec!["ab\u{4e2d}cd".to_string()]);
}

#[test]
fn a_delete_byte_inside_a_run_is_still_not_a_cell() {
    let mut core = core(20, false);
    core.feed(b"ab\x7fcd");
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.cursor_col, 4);
}

#[test]
fn a_run_right_before_a_boundary_mark_lands_in_the_block_the_mark_closes() {
    let mut core = core(20, false);
    core.feed(b"hello\x1b]7000;v=1;boundary=0\x07next");
    assert_eq!(
        screen_text(&core),
        vec!["hello".to_string(), "next".to_string()]
    );
    let snapshot = core.snapshot().expect("snapshot");
    let blocks: Vec<(u32, u32)> = snapshot
        .blocks
        .iter()
        .map(|block| (block.first_row, block.row_count))
        .collect();
    assert_eq!(blocks, vec![(0, 1), (1, 1)]);
}

#[test]
fn a_run_right_before_the_alternate_screen_opens_stays_on_the_primary_screen() {
    let mut core = core(20, false);
    core.feed(b"abc\x1b[?1049hdef");
    assert_eq!(
        core.alt_grid()
            .map(|grid| grid.row_text(0).trim_end().to_string()),
        Some("def".to_string())
    );
    assert_eq!(core.snapshot().expect("snapshot").row_text(0), "abc");
    core.feed(b"\x1b[?1049lghi");
    assert_eq!(screen_text(&core), vec!["abcghi".to_string()]);
}
