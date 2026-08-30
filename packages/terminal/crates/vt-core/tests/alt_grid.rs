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
