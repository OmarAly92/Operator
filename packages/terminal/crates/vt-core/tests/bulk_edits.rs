use vt_core::testing::ScreenGrid;
use vt_core::{CellStyle, StyleCode};

fn grid_with(text: &str, cols: usize) -> ScreenGrid {
    let mut grid = ScreenGrid::new(3, cols);
    for ch in text.chars() {
        grid.print(ch, CellStyle::DEFAULT);
    }
    grid.take_dirty();
    grid
}

fn row(grid: &ScreenGrid, row: usize) -> String {
    (0..grid.cols())
        .map(|col| match grid.cell(row, col).ch {
            '\0' => '_',
            ch => ch,
        })
        .collect()
}

#[test]
fn insert_shifts_right_and_fills_the_gap_with_the_erase_background() {
    let mut grid = grid_with("abcdef", 8);
    grid.set_erase_background(StyleCode::indexed(1));
    grid.move_to(0, 1);
    grid.insert_chars(2);
    assert_eq!(row(&grid, 0), "a  bcdef");
    assert_eq!(grid.cell(0, 1).style.bg, StyleCode::indexed(1));
    assert_eq!(grid.cell(0, 2).style.bg, StyleCode::indexed(1));
    assert_eq!(grid.cell(0, 3).style.bg, StyleCode::DEFAULT_BACKGROUND);
    assert_eq!(grid.take_dirty(), vec![0]);
}

#[test]
fn delete_shifts_left_clamps_its_count_and_fills_the_tail() {
    let mut grid = grid_with("abcdef", 8);
    grid.move_to(0, 2);
    grid.delete_chars(3);
    assert_eq!(row(&grid, 0), "abf     ");
    grid.delete_chars(99);
    assert_eq!(row(&grid, 0), "ab      ");
    assert_eq!(grid.take_dirty(), vec![0]);
}

#[test]
fn erase_chars_and_erase_in_line_touch_only_their_span() {
    let mut grid = grid_with("abcdefgh", 8);
    grid.move_to(0, 2);
    grid.erase_chars(2);
    assert_eq!(row(&grid, 0), "ab  efgh");
    grid.move_to(0, 5);
    grid.erase_in_line(1);
    assert_eq!(row(&grid, 0), "      gh");
    grid.move_to(0, 7);
    grid.erase_in_line(0);
    assert_eq!(row(&grid, 0), "      g ");
}

#[test]
fn a_wrapped_row_stays_wrapped_until_an_edit_reaches_its_last_column() {
    let mut grid = grid_with("abcdef", 4);
    assert!(grid.row_wrapped(0));
    grid.move_to(0, 0);
    grid.erase_chars(1);
    assert!(grid.row_wrapped(0));
    grid.erase_in_line(1);
    assert!(grid.row_wrapped(0));
    grid.move_to(0, 1);
    grid.erase_in_line(0);
    assert!(!grid.row_wrapped(0));
    let mut inserted = grid_with("abcdef", 4);
    inserted.move_to(0, 0);
    inserted.insert_chars(1);
    assert!(!inserted.row_wrapped(0));
    let mut deleted = grid_with("abcdef", 4);
    deleted.move_to(0, 0);
    deleted.delete_chars(1);
    assert!(!deleted.row_wrapped(0));
}

#[test]
fn a_wide_character_moves_with_its_spacer() {
    let mut grid = grid_with("a\u{4e2d}b", 6);
    assert_eq!(row(&grid, 0), "a\u{4e2d}_b  ");
    grid.move_to(0, 0);
    grid.delete_chars(1);
    assert_eq!(row(&grid, 0), "\u{4e2d}_b   ");
    grid.insert_chars(2);
    assert_eq!(row(&grid, 0), "  \u{4e2d}_b ");
}

#[test]
fn a_combined_cell_survives_a_shift_whole() {
    let mut grid = grid_with("xe\u{301}y", 6);
    grid.move_to(0, 0);
    grid.delete_chars(1);
    let mut buffer = [0u8; 4];
    assert_eq!(grid.cell(0, 0).text(&mut buffer), "e\u{301}");
    grid.insert_chars(3);
    assert_eq!(grid.cell(0, 3).text(&mut buffer), "e\u{301}");
    assert_eq!(grid.cell(0, 4).ch, 'y');
}
