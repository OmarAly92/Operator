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
    assert_eq!(count, 2, "50 redraws produced {count} rows");
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
    assert_eq!(snapshot.blocks[0].row_count, 1);
}

#[test]
fn rows_scrolled_off_a_three_row_screen_reach_scrollback() {
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.resize(20, 3);
    core.feed(b"one\r\ntwo\r\nthree\r\nfour\r\n");
    assert_eq!(rows(&core), vec!["one", "two", "three", "four"]);
}

#[test]
fn blank_screen_evictions_rebase_an_open_block() {
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.resize(20, 3);
    core.feed(b"\x1b[3;1H\x1b]133;A\x07\x1b]133;C\x07");
    core.feed(b"\x1b[S\x1b[S");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.row_count(), 1);
    assert_eq!(snapshot.blocks.len(), 1);
    assert_eq!(snapshot.blocks[0].first_row, 0);
    assert_eq!(snapshot.blocks[0].row_count, 1);
}

#[test]
fn wide_glyphs_survive_eviction_without_continuation_bytes() {
    let mut core = TerminalCore::new(4, 100).unwrap();
    core.resize(4, 2);
    core.feed("界a\r\nb\r\n界c".as_bytes());

    assert_eq!(rows(&core), vec!["界a", "b", "界c"]);
}

#[test]
fn normal_evictions_commit_before_same_chunk_alt_entry() {
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.resize(20, 2);
    core.feed(b"one\r\ntwo\r\n\x1b[?1049h");

    assert!(core.alt_screen_active());
    assert_eq!(rows(&core), vec!["one", "two"]);
}
