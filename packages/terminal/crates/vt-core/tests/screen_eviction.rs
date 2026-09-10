use vt_core::testing::ScreenGrid;
use vt_core::{CellStyle, StyleCode};

#[test]
fn full_screen_scroll_reports_the_evicted_row() {
    let mut screen = ScreenGrid::new(3, 10);
    screen.set_records_eviction(true);
    for ch in "top".chars() {
        screen.print(ch, CellStyle::from_fg(StyleCode::DEFAULT));
    }
    screen.scroll_up(1);
    let evicted = screen.take_evicted();
    assert_eq!(evicted.len(), 1);
    let text: String = evicted[0].cells.iter().map(|cell| cell.ch).collect();
    assert_eq!(text.trim_end(), "top");
    assert!(!evicted[0].wrapped);
}

#[test]
fn a_row_the_printer_wrapped_is_evicted_flagged() {
    let mut screen = ScreenGrid::new(2, 4);
    screen.set_records_eviction(true);
    for ch in "abcdef".chars() {
        screen.print(ch, CellStyle::from_fg(StyleCode::DEFAULT));
    }
    screen.scroll_up(1);
    let evicted = screen.take_evicted();
    let text: String = evicted[0].cells.iter().map(|cell| cell.ch).collect();
    assert_eq!(text, "abcd");
    assert!(evicted[0].wrapped);
}

#[test]
fn blanking_a_row_clears_its_wrap_flag() {
    let mut screen = ScreenGrid::new(2, 4);
    for ch in "abcdef".chars() {
        screen.print(ch, CellStyle::from_fg(StyleCode::DEFAULT));
    }
    assert!(screen.row_wrapped(0));
    screen.move_to(0, 0);
    screen.erase_in_line(2);
    assert!(!screen.row_wrapped(0));
}

#[test]
fn a_scroll_region_evicts_nothing() {
    let mut screen = ScreenGrid::new(5, 10);
    screen.set_records_eviction(true);
    screen.set_scroll_region(1, 3);
    screen.scroll_up(1);
    assert!(screen.take_evicted().is_empty());
}

#[test]
fn a_partial_region_starting_at_top_evicts_nothing() {
    let mut screen = ScreenGrid::new(5, 10);
    screen.set_records_eviction(true);
    screen.set_scroll_region(0, 3);
    screen.scroll_up(1);
    assert!(screen.take_evicted().is_empty());
}

#[test]
fn eviction_is_off_by_default() {
    let mut screen = ScreenGrid::new(3, 10);
    screen.scroll_up(1);
    assert!(screen.take_evicted().is_empty());
}

#[test]
fn take_evicted_drains() {
    let mut screen = ScreenGrid::new(2, 10);
    screen.set_records_eviction(true);
    screen.scroll_up(1);
    assert_eq!(screen.take_evicted().len(), 1);
    assert!(screen.take_evicted().is_empty());
}
