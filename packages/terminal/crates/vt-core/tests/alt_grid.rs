use vt_core::alt::AltGrid;
use vt_core::StyleCode;

fn grid() -> AltGrid {
    AltGrid::new(4, 8)
}

fn print(g: &mut AltGrid, text: &str) {
    for ch in text.chars() {
        g.print(ch, StyleCode::DEFAULT);
    }
}

#[test]
fn starts_blank_with_the_cursor_at_the_origin() {
    let g = grid();
    assert_eq!(g.cursor(), (0, 0));
    assert_eq!(g.row_text(0), "        ");
}

#[test]
fn printing_advances_the_cursor_and_lands_in_the_cell() {
    let mut g = grid();
    print(&mut g, "hi");
    assert_eq!(g.cursor(), (0, 2));
    assert_eq!(g.row_text(0), "hi      ");
}

#[test]
fn printing_past_the_right_margin_wraps_to_the_next_row() {
    let mut g = grid();
    print(&mut g, "123456789");
    assert_eq!(g.row_text(0), "12345678");
    assert_eq!(g.row_text(1), "9       ");
    assert_eq!(g.cursor(), (1, 1));
}

#[test]
fn filling_a_row_exactly_does_not_scroll_until_the_next_character() {
    let mut g = AltGrid::new(2, 4);
    print(&mut g, "abcd");
    assert_eq!(g.cursor(), (0, 3));
    assert_eq!(g.row_text(0), "abcd");
    assert_eq!(g.row_text(1), "    ");
}

#[test]
fn carriage_return_moves_to_column_zero_without_erasing() {
    let mut g = grid();
    print(&mut g, "abcd");
    g.carriage_return();
    print(&mut g, "XY");
    assert_eq!(g.row_text(0), "XYcd    ");
}

#[test]
fn cursor_moves_clamp_at_the_edges_instead_of_wrapping_or_panicking() {
    let mut g = grid();
    g.move_by(-5, -5);
    assert_eq!(g.cursor(), (0, 0));
    g.move_by(99, 99);
    assert_eq!(g.cursor(), (3, 7));
}

#[test]
fn move_to_is_absolute_and_clamped() {
    let mut g = grid();
    g.move_to(2, 3);
    assert_eq!(g.cursor(), (2, 3));
    g.move_to(99, 99);
    assert_eq!(g.cursor(), (3, 7));
}

#[test]
fn tab_advances_to_the_next_eight_column_stop() {
    let mut g = AltGrid::new(2, 20);
    print(&mut g, "ab");
    g.tab();
    assert_eq!(g.cursor(), (0, 8));
    g.tab();
    assert_eq!(g.cursor(), (0, 16));
}

#[test]
fn a_wide_character_occupies_two_cells() {
    let mut g = grid();
    g.print('世', StyleCode::DEFAULT);
    assert_eq!(g.cursor(), (0, 2));
    assert_eq!(g.row_text(0), "世      ");
}

#[test]
fn a_wide_character_that_does_not_fit_wraps_rather_than_splitting() {
    let mut g = AltGrid::new(2, 3);
    print(&mut g, "ab");
    g.print('世', StyleCode::DEFAULT);
    assert_eq!(g.row_text(0), "ab ");
    assert_eq!(g.row_text(1), "世 ");
}

#[test]
fn a_zero_width_character_is_dropped_rather_than_consuming_a_cell() {
    let mut g = grid();
    print(&mut g, "a");
    g.print('\u{0301}', StyleCode::DEFAULT);
    assert_eq!(g.cursor(), (0, 1));
}

#[test]
fn printing_keeps_the_style_it_was_given() {
    let mut g = grid();
    g.print('x', StyleCode::ansi(2));
    assert_eq!(g.cell(0, 0).style, StyleCode::ansi(2));
    assert_eq!(g.cell(0, 1).style, StyleCode::DEFAULT);
}

#[test]
fn growing_keeps_content_and_shrinking_drops_what_falls_outside() {
    let mut g = grid();
    print(&mut g, "abcdefgh");
    g.resize(4, 4);
    assert_eq!(g.row_text(0), "abcd");
    g.resize(4, 8);
    assert_eq!(g.row_text(0), "abcd    ");
}

#[test]
fn resize_clamps_a_cursor_that_is_now_outside() {
    let mut g = grid();
    g.move_to(3, 7);
    g.resize(2, 2);
    assert_eq!(g.cursor(), (1, 1));
}

#[test]
fn a_zero_or_absurd_dimension_is_clamped_instead_of_panicking() {
    let mut g = AltGrid::new(0, 0);
    assert_eq!(g.rows(), 1);
    assert_eq!(g.cols(), 1);
    g.resize(100_000, 100_000);
    assert_eq!(g.rows(), 1000);
    assert_eq!(g.cols(), 1000);
}

#[test]
fn saving_and_restoring_the_cursor_round_trips() {
    let mut g = grid();
    g.move_to(2, 5);
    g.save_cursor();
    g.move_to(0, 0);
    g.restore_cursor();
    assert_eq!(g.cursor(), (2, 5));
}

#[test]
fn reset_blanks_everything_and_homes_the_cursor() {
    let mut g = grid();
    print(&mut g, "abc");
    g.move_to(2, 2);
    g.reset();
    assert_eq!(g.cursor(), (0, 0));
    assert_eq!(g.row_text(0), "        ");
}

fn filled() -> AltGrid {
    let mut g = AltGrid::new(3, 4);
    for row in 0..3 {
        g.move_to(row, 0);
        print(&mut g, "abcd");
    }
    g
}

fn labelled(rows: usize) -> AltGrid {
    let mut g = AltGrid::new(rows, 4);
    for (row, text) in ["one", "two", "six"].iter().enumerate().take(rows) {
        g.move_to(row, 0);
        print(&mut g, text);
    }
    g
}

#[test]
fn erase_in_line_right_clears_from_the_cursor_to_the_end() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_line(0);
    assert_eq!(g.row_text(1), "ab  ");
    assert_eq!(g.row_text(0), "abcd");
}

#[test]
fn erase_in_line_left_clears_through_the_cursor_cell() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_line(1);
    assert_eq!(g.row_text(1), "   d");
}

#[test]
fn erase_in_line_all_clears_the_row_and_leaves_the_cursor_put() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_line(2);
    assert_eq!(g.row_text(1), "    ");
    assert_eq!(g.cursor(), (1, 2));
}

#[test]
fn erase_in_display_below_clears_the_rest_of_the_screen() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_display(0);
    assert_eq!(g.row_text(0), "abcd");
    assert_eq!(g.row_text(1), "ab  ");
    assert_eq!(g.row_text(2), "    ");
}

#[test]
fn erase_in_display_above_clears_everything_before_the_cursor() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_display(1);
    assert_eq!(g.row_text(0), "    ");
    assert_eq!(g.row_text(1), "   d");
    assert_eq!(g.row_text(2), "abcd");
}

#[test]
fn erase_in_display_all_clears_everything_and_leaves_the_cursor_put() {
    let mut g = filled();
    g.move_to(1, 2);
    g.erase_in_display(2);
    assert_eq!(g.row_text(0), "    ");
    assert_eq!(g.row_text(2), "    ");
    assert_eq!(g.cursor(), (1, 2));
}

#[test]
fn insert_lines_pushes_rows_down_and_drops_the_bottom() {
    let mut g = labelled(3);
    g.move_to(1, 0);
    g.insert_lines(1);
    assert_eq!(g.row_text(0), "one ");
    assert_eq!(g.row_text(1), "    ");
    assert_eq!(g.row_text(2), "two ");
}

#[test]
fn delete_lines_pulls_rows_up_and_blanks_the_bottom() {
    let mut g = labelled(3);
    g.move_to(0, 0);
    g.delete_lines(1);
    assert_eq!(g.row_text(0), "two ");
    assert_eq!(g.row_text(1), "six ");
    assert_eq!(g.row_text(2), "    ");
}

#[test]
fn insert_chars_shifts_right_within_the_row_only() {
    let mut g = filled();
    g.move_to(1, 1);
    g.insert_chars(2);
    assert_eq!(g.row_text(1), "a  b");
    assert_eq!(g.row_text(2), "abcd");
}

#[test]
fn delete_chars_shifts_left_and_blanks_the_tail() {
    let mut g = filled();
    g.move_to(1, 1);
    g.delete_chars(2);
    assert_eq!(g.row_text(1), "ad  ");
}

#[test]
fn erase_chars_blanks_in_place_without_shifting() {
    let mut g = filled();
    g.move_to(1, 1);
    g.erase_chars(2);
    assert_eq!(g.row_text(1), "a  d");
}

#[test]
fn an_absurd_count_saturates_instead_of_panicking() {
    let mut g = filled();
    g.move_to(1, 1);
    g.delete_chars(usize::MAX);
    g.insert_chars(usize::MAX);
    g.erase_chars(usize::MAX);
    g.insert_lines(usize::MAX);
    g.delete_lines(usize::MAX);
    assert_eq!(g.rows(), 3);
    assert_eq!(g.cursor(), (1, 1));
}

#[test]
fn deleting_every_line_from_the_top_blanks_the_screen_without_underflow() {
    let mut g = labelled(3);
    g.move_to(0, 0);
    g.delete_lines(3);
    assert_eq!(g.row_text(0), "    ");
    assert_eq!(g.row_text(2), "    ");
}

fn numbered(rows: usize) -> AltGrid {
    let mut g = AltGrid::new(rows, 2);
    for row in 0..rows {
        g.move_to(row, 0);
        print(&mut g, &format!("{row}"));
    }
    g
}

#[test]
fn a_line_feed_at_the_bottom_scrolls_the_whole_screen_by_default() {
    let mut g = numbered(3);
    g.move_to(2, 0);
    g.line_feed();
    assert_eq!(g.row_text(0), "1 ");
    assert_eq!(g.row_text(1), "2 ");
    assert_eq!(g.row_text(2), "  ");
    assert_eq!(g.cursor().0, 2);
}

#[test]
fn a_line_feed_elsewhere_just_moves_down_and_keeps_the_column() {
    let mut g = numbered(3);
    g.move_to(0, 1);
    g.line_feed();
    assert_eq!(g.cursor(), (1, 1));
    assert_eq!(g.row_text(0), "0 ");
}

#[test]
fn a_line_feed_at_the_region_bottom_scrolls_only_the_region() {
    let mut g = numbered(4);
    g.set_scroll_region(1, 2);
    g.move_to(2, 0);
    g.line_feed();
    assert_eq!(g.row_text(0), "0 ");
    assert_eq!(g.row_text(1), "2 ");
    assert_eq!(g.row_text(2), "  ");
    assert_eq!(g.row_text(3), "3 ");
}

#[test]
fn reverse_index_at_the_region_top_scrolls_the_region_down() {
    let mut g = numbered(4);
    g.set_scroll_region(1, 2);
    g.move_to(1, 0);
    g.reverse_index();
    assert_eq!(g.row_text(0), "0 ");
    assert_eq!(g.row_text(1), "  ");
    assert_eq!(g.row_text(2), "1 ");
    assert_eq!(g.row_text(3), "3 ");
}

#[test]
fn setting_a_region_homes_the_cursor() {
    let mut g = numbered(4);
    g.move_to(3, 1);
    g.set_scroll_region(1, 2);
    assert_eq!(g.cursor(), (0, 0));
}

#[test]
fn an_inverted_or_out_of_range_region_resets_to_the_full_screen() {
    let mut g = numbered(4);
    g.set_scroll_region(3, 1);
    g.move_to(3, 0);
    g.line_feed();
    assert_eq!(g.row_text(0), "1 ");
}

#[test]
fn insert_lines_outside_the_region_does_nothing() {
    let mut g = numbered(4);
    g.set_scroll_region(1, 2);
    g.move_to(0, 0);
    g.insert_lines(1);
    assert_eq!(g.row_text(0), "0 ");
    assert_eq!(g.row_text(1), "1 ");
}

#[test]
fn next_line_returns_to_column_zero_and_moves_down() {
    let mut g = numbered(3);
    g.move_to(0, 1);
    g.next_line();
    assert_eq!(g.cursor(), (1, 0));
}

#[test]
fn scrolling_by_more_than_the_region_blanks_it_without_underflow() {
    let mut g = numbered(4);
    g.set_scroll_region(1, 2);
    g.scroll_up(99);
    assert_eq!(g.row_text(0), "0 ");
    assert_eq!(g.row_text(1), "  ");
    assert_eq!(g.row_text(2), "  ");
    assert_eq!(g.row_text(3), "3 ");
    g.scroll_down(99);
    assert_eq!(g.row_text(3), "3 ");
}

#[test]
fn resize_resets_the_region_to_the_new_full_screen() {
    let mut g = numbered(4);
    g.set_scroll_region(1, 2);
    g.resize(3, 2);
    g.move_to(2, 0);
    g.line_feed();
    assert_eq!(g.row_text(0), "1 ");
}

#[test]
fn wrapping_at_the_last_row_scrolls_rather_than_overwriting() {
    let mut g = AltGrid::new(2, 2);
    g.move_to(1, 0);
    print(&mut g, "ab");
    print(&mut g, "cd");
    assert_eq!(g.row_text(0), "ab");
    assert_eq!(g.row_text(1), "cd");
}
