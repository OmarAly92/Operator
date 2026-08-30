use vt_core::TerminalCore;

fn rows(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    (0..snapshot.row_count())
        .map(|i| snapshot.row_text(i).trim_end().to_string())
        .collect()
}

#[test]
fn cursor_up_rewrites_in_place_instead_of_appending() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"alpha\r\nbravo\r\ncharlie\r\n");
    core.feed(b"\x1b[2A\rREWRITTEN\x1b[K");
    let text = rows(&core);
    assert_eq!(text[0], "alpha");
    assert_eq!(text[1], "REWRITTEN");
    assert_eq!(text[2], "charlie");
}

#[test]
fn erase_in_line_clears_to_the_end() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"abcdefgh\r\x1b[3C\x1b[K");
    assert_eq!(rows(&core)[0], "abc");
}

#[test]
fn absolute_cursor_addressing_lands_on_the_right_row() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"one\r\ntwo\r\nthree");
    core.feed(b"\x1b[1;1HX");
    assert_eq!(rows(&core)[0], "Xne");
}

#[test]
fn a_repeated_redraw_does_not_grow_the_row_count() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"\x1b[2J\x1b[H");
    for _ in 0..50 {
        core.feed(b"\x1b[Hframe line one\x1b[K\r\nframe line two\x1b[K");
    }
    let count = rows(&core).len();
    assert!(count <= 24, "50 redraws produced {count} rows");
}

#[test]
fn the_open_block_counts_scrollback_and_screen_rows_together() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 3);
    core.feed(b"\x1b]133;A\x07\x1b]133;C\x07");
    core.feed(b"one\r\ntwo\r\nthree\r\nfour\r\n");
    let snapshot = core.snapshot().unwrap();
    let total: usize = snapshot.blocks.iter().map(|b| b.row_count as usize).sum();
    assert_eq!(total, snapshot.row_count());
}

#[test]
fn clearing_the_lower_half_does_not_shrink_the_row_count() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 24);
    for _ in 0..10 {
        core.feed(b"x\r\n");
    }
    let before = core.snapshot().unwrap().row_count();
    core.feed(b"\x1b[6;1H\x1b[J");
    assert_eq!(
        core.snapshot().unwrap().row_count(),
        before,
        "the cursor high-water mark, not a blank scan, decides extent",
    );
}

#[test]
fn a_redraw_does_not_inflate_the_open_block() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"\x1b]133;A\x07\x1b]133;C\x07");
    for _ in 0..50 {
        core.feed(b"\x1b[Hline\x1b[K");
    }
    let snapshot = core.snapshot().unwrap();
    assert!(
        snapshot.blocks[0].row_count <= 24,
        "got {}",
        snapshot.blocks[0].row_count
    );
}

#[test]
fn rows_scrolled_off_a_three_row_screen_reach_scrollback() {
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.resize(20, 3);
    core.feed(b"one\r\ntwo\r\nthree\r\nfour\r\n");
    let text = rows(&core);
    assert!(text.contains(&"one".to_string()), "got {text:?}");
    assert!(text.contains(&"four".to_string()), "got {text:?}");
}
