use super::*;

fn content_of(text: &str) -> Content {
    let mut content = Content::new();
    let mut buffer = [0u8; 4];
    for ch in text.chars() {
        content.push_char(ch.encode_utf8(&mut buffer));
    }
    content
}

#[allow(clippy::type_complexity)]
fn ranges(index: &RowIndex) -> Vec<(u64, u64, bool)> {
    index
        .completed()
        .iter()
        .map(|row| (row.start, row.end, row.wrapped))
        .collect()
}

#[test]
fn trim_to_drops_front_completed_rows() {
    let mut r = RowIndex::new(0);
    r.complete_row(10, false);
    r.complete_row(20, false);
    r.complete_row(30, false);
    let released = r.trim_to(2);
    assert_eq!(r.completed().len(), 1);
    assert_eq!(r.completed()[0].start, 20);
    assert_eq!(r.completed()[0].end, 30);
    assert_eq!(
        released,
        Some(20),
        "must release only up to the first retained row"
    );
}

#[test]
fn trim_to_zero_still_reports_the_release_offset() {
    let mut r = RowIndex::new(0);
    r.complete_row(10, false);
    assert_eq!(r.trim_to(0), Some(10));
    assert_eq!(r.completed().len(), 0);
}

#[test]
fn trim_to_reports_nothing_when_under_the_limit() {
    let mut r = RowIndex::new(0);
    r.complete_row(10, false);
    assert_eq!(r.trim_to(8), None);
    assert_eq!(r.completed().len(), 1);
}

#[test]
fn trim_to_keeps_open_row_in_count() {
    let mut r = RowIndex::new(0);
    r.complete_row(10, false);
    r.complete_row(20, false);
    let open = r.trim_to(1).unwrap();
    assert_eq!(r.completed().len(), 0);
    assert_eq!(open, 20);
}

#[test]
fn rewrap_cuts_a_wide_row_and_flags_every_piece_but_the_last() {
    let content = content_of("abcdefghij");
    let mut r = RowIndex::new(0);
    r.complete_row(10, false);
    let map = r.rewrap(&content, 4, WidthMode::Scalar);
    assert_eq!(ranges(&r), vec![(0, 4, true), (4, 8, true), (8, 10, false)]);
    assert_eq!(map, vec![0, 3]);
}

#[test]
fn rewrap_joins_flagged_pieces_before_cutting_again() {
    let content = content_of("abcdefghij");
    let mut r = RowIndex::new(0);
    r.complete_row(4, true);
    r.complete_row(8, true);
    r.complete_row(10, false);
    let map = r.rewrap(&content, 20, WidthMode::Scalar);
    assert_eq!(ranges(&r), vec![(0, 10, false)]);
    assert_eq!(map, vec![0, 0, 0, 1]);
}

#[test]
fn rewrap_maps_each_old_row_to_the_row_holding_its_first_byte() {
    let content = content_of("abcdefghijklmnop");
    let mut r = RowIndex::new(0);
    r.complete_row(8, true);
    r.complete_row(16, false);
    let map = r.rewrap(&content, 6, WidthMode::Scalar);
    assert_eq!(
        ranges(&r),
        vec![(0, 6, true), (6, 12, true), (12, 16, false)]
    );
    assert_eq!(map, vec![0, 1, 3]);
}

#[test]
fn rewrap_cuts_on_display_width_not_bytes() {
    let content = content_of("a\u{4e16}\u{754c}b");
    let mut r = RowIndex::new(0);
    r.complete_row(content.end_offset(), false);
    r.rewrap(&content, 3, WidthMode::Scalar);
    assert_eq!(ranges(&r), vec![(0, 4, true), (4, 8, false)]);
}

#[test]
fn rewrap_breaks_at_the_last_space_before_the_edge() {
    let content = content_of("the quick brown fox jumps");
    let mut r = RowIndex::new(0);
    r.complete_row(content.end_offset(), false);
    r.rewrap(&content, 9, WidthMode::Scalar);
    assert_eq!(
        ranges(&r),
        vec![(0, 10, true), (10, 20, true), (20, 25, false)]
    );
}

#[test]
fn rewrap_cuts_inside_a_word_only_when_the_word_alone_is_too_wide() {
    let content = content_of("ab cdefghijkl m");
    let mut r = RowIndex::new(0);
    r.complete_row(content.end_offset(), false);
    r.rewrap(&content, 5, WidthMode::Scalar);
    assert_eq!(
        ranges(&r),
        vec![(0, 3, true), (3, 8, true), (8, 14, true), (14, 15, false)]
    );
}

#[test]
fn rewrap_never_breaks_after_a_leading_space() {
    let content = content_of(" abcdefgh");
    let mut r = RowIndex::new(0);
    r.complete_row(content.end_offset(), false);
    r.rewrap(&content, 5, WidthMode::Scalar);
    assert_eq!(ranges(&r), vec![(0, 5, true), (5, 9, false)]);
}

#[test]
fn rewrap_rejoins_a_word_wrapped_line_when_widened() {
    let content = content_of("the quick brown fox jumps");
    let mut r = RowIndex::new(0);
    r.complete_row(content.end_offset(), false);
    r.rewrap(&content, 9, WidthMode::Scalar);
    r.rewrap(&content, 80, WidthMode::Scalar);
    assert_eq!(ranges(&r), vec![(0, 25, false)]);
}

fn indents(index: &RowIndex) -> Vec<u16> {
    index.completed().iter().map(|row| row.indent).collect()
}

#[test]
fn a_bullet_line_hangs_its_continuation_under_the_text() {
    let content = content_of("  - alpha beta gamma delta");
    let mut r = RowIndex::new(0);
    r.complete_row(content.end_offset(), false);
    r.rewrap(&content, 14, WidthMode::Scalar);
    assert_eq!(
        ranges(&r),
        vec![(0, 15, true), (15, 21, true), (21, 26, false)]
    );
    assert_eq!(indents(&r), vec![0, 4, 4]);
}

#[test]
fn a_plain_indented_line_hangs_by_its_leading_spaces() {
    let content = content_of("    alpha beta gamma");
    let mut r = RowIndex::new(0);
    r.complete_row(content.end_offset(), false);
    r.rewrap(&content, 12, WidthMode::Scalar);
    assert_eq!(
        ranges(&r),
        vec![(0, 10, true), (10, 15, true), (15, 20, false)]
    );
    assert_eq!(indents(&r), vec![0, 4, 4]);
}

#[test]
fn hanging_indent_recognises_markers_and_caps_at_half_the_pane() {
    assert_eq!(hanging_indent("- item", 80), 2);
    assert_eq!(hanging_indent("  ● item", 80), 4);
    assert_eq!(hanging_indent("  ⎿  Did 1 search", 80), 5);
    assert_eq!(hanging_indent("12. item", 80), 4);
    assert_eq!(hanging_indent("3) item", 80), 3);
    assert_eq!(hanging_indent("-item", 80), 0);
    assert_eq!(hanging_indent("plain text", 80), 0);
    assert_eq!(hanging_indent("      - deep", 12), 0);
}

#[test]
fn rewrap_keeps_an_empty_row() {
    let content = content_of("ab");
    let mut r = RowIndex::new(0);
    r.complete_row(0, false);
    r.complete_row(2, false);
    let map = r.rewrap(&content, 1, WidthMode::Scalar);
    assert_eq!(ranges(&r), vec![(0, 0, false), (0, 1, true), (1, 2, false)]);
    assert_eq!(map, vec![0, 1, 3]);
}

#[test]
fn rewrap_leaves_the_open_row_start_alone() {
    let content = content_of("abcdef");
    let mut r = RowIndex::new(0);
    r.complete_row(6, false);
    r.rewrap(&content, 2, WidthMode::Scalar);
    assert_eq!(r.open_start(), 6);
}

#[test]
fn rewrap_hot_maps_every_row_and_reports_the_new_total() {
    let total = HOT_ROWS + 500;
    let text: String = "a".repeat(total);
    let content = content_of(&text);
    let mut r = RowIndex::new(0);
    for index in 0..total {
        r.complete_row(index as u64 + 1, false);
    }
    let map = r.rewrap_hot(&content, 80, 80, WidthMode::Scalar);
    assert_eq!(map.len(), total + 1);
    assert_eq!(*map.last().unwrap(), r.completed().len());
    for &new in &map[..total] {
        assert!(new < r.completed().len());
    }
    assert_eq!(r.stale_runs().len(), 1);
    assert_eq!(r.stale_runs()[0].start, 0);
    assert_eq!(r.stale_runs()[0].len, total - HOT_ROWS);
    assert_eq!(r.stale_runs()[0].cols, 80);
}

#[test]
fn rows_for_clips_the_touch_and_leaves_the_remainders_at_the_old_width() {
    let old_cols = 10usize;
    let new_cols = 4usize;
    let lines = 300usize;
    let text = "abcdefghij".repeat(lines);
    let content = content_of(&text);

    let mut r = RowIndex::new(0);
    for index in 0..lines {
        r.complete_row((index as u64 + 1) * old_cols as u64, false);
    }
    r.stale.push(StaleRun {
        start: 0,
        len: lines,
        cols: old_cols,
    });

    let touch = 100..105;
    let (map, lowest) = r
        .rows_for(&content, new_cols, touch.clone(), WidthMode::Scalar)
        .expect("the touch overlaps the stale run");
    assert_eq!(lowest, 100);

    // The touched-and-snapped window is now rewrapped at the new width:
    // each 10-char line breaks into 4, 4, 2.
    let touched_start = map[touch.start];
    assert_eq!(
        ranges(&r)[touched_start],
        (1000, 1004, true),
        "row 100 was not rewrapped to the new width"
    );
    assert_eq!(ranges(&r)[touched_start + 1], (1004, 1008, true));
    assert_eq!(ranges(&r)[touched_start + 2], (1008, 1010, false));

    // A row still inside the original stale run but outside the
    // touched-and-snapped window — the head remainder — stays cut at
    // the OLD width.
    let head_row = map[99];
    assert_eq!(
        ranges(&r)[head_row],
        (990, 1000, false),
        "a row in the untouched head remainder was rewrapped"
    );

    // Likewise the tail remainder, just past the touched window.
    let tail_row = map[105];
    assert_eq!(
        ranges(&r)[tail_row],
        (1050, 1060, false),
        "a row in the untouched tail remainder was rewrapped"
    );

    // Five touched lines (5 rows) became 15 rows (3 each): +10 rows.
    assert_eq!(r.completed().len(), lines + 10);
    assert_eq!(*map.last().unwrap(), r.completed().len());

    // The single stale run split into a head and a tail remainder, both
    // still at the old width, whose lengths plus the touched-and-snapped
    // portion account for the whole original run.
    assert_eq!(r.stale_runs().len(), 2);
    assert_eq!(
        r.stale_runs()[0],
        StaleRun {
            start: 0,
            len: 100,
            cols: old_cols,
        }
    );
    assert_eq!(
        r.stale_runs()[1],
        StaleRun {
            start: 115,
            len: 195,
            cols: old_cols,
        }
    );
    let touched_len = touch.end - touch.start;
    let remainder_len: usize = r.stale_runs().iter().map(|run| run.len).sum();
    assert_eq!(remainder_len + touched_len, lines);
}
