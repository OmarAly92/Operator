use unicode_width::UnicodeWidthStr;
use vt_core::{StyleCode, TerminalCore};

fn rows(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    (0..snapshot.row_count())
        .map(|i| snapshot.row_text(i).to_string())
        .collect()
}

fn widest(core: &TerminalCore) -> usize {
    rows(core)
        .iter()
        .map(|row| UnicodeWidthStr::width(row.as_str()))
        .max()
        .unwrap_or(0)
}

fn scroll_off(core: &mut TerminalCore, lines: usize) {
    for _ in 0..lines {
        core.feed(b"\r\n");
    }
}

#[test]
fn a_scrollback_row_wider_than_the_new_pane_wraps_to_fit() {
    let mut core = TerminalCore::new(100, 1000).unwrap();
    core.resize(100, 3);
    let long = "x".repeat(95);
    core.feed(format!("{long}\r\nshort\r\n").as_bytes());
    scroll_off(&mut core, 3);
    core.resize(40, 3);
    let rows = rows(&core);
    assert_eq!(
        &rows[..4],
        &[
            "x".repeat(40),
            "x".repeat(40),
            "x".repeat(15),
            "short".to_string()
        ]
    );
    assert!(widest(&core) <= 40);
}

#[test]
fn widening_the_pane_rejoins_the_rows_the_shrink_split() {
    let mut core = TerminalCore::new(100, 1000).unwrap();
    core.resize(100, 3);
    let long = "x".repeat(95);
    core.feed(format!("{long}\r\nshort\r\n").as_bytes());
    scroll_off(&mut core, 3);
    let before = rows(&core);
    core.resize(40, 3);
    core.resize(100, 3);
    assert_eq!(rows(&core), before);
}

#[test]
fn a_wide_character_that_does_not_fit_moves_whole_to_the_next_row() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 2);
    core.feed("abc\u{4e16}\u{754c}\r\n".as_bytes());
    scroll_off(&mut core, 2);
    core.resize(4, 2);
    let rows = rows(&core);
    assert_eq!(&rows[..2], &["abc", "\u{4e16}\u{754c}"]);
}

#[test]
fn a_line_the_screen_soft_wrapped_rejoins_when_the_pane_widens() {
    let mut core = TerminalCore::new(40, 1000).unwrap();
    core.resize(40, 4);
    let long: String = (0..100)
        .map(|i| char::from(b'a' + (i % 26) as u8))
        .collect();
    core.feed(format!("{long}\r\nnext\r\n").as_bytes());
    scroll_off(&mut core, 4);
    assert_eq!(rows(&core)[0].len(), 40);
    core.resize(120, 4);
    let rows = rows(&core);
    assert_eq!(&rows[..2], &[long, "next".to_string()]);
}

#[test]
fn an_agent_tui_transcript_rewraps_too() {
    let mut core = TerminalCore::new(100, 1000).unwrap();
    core.resize(100, 3);
    core.set_agent_tui_mode(true);
    let long = "y".repeat(90);
    core.feed(format!("{long}\r\n").as_bytes());
    scroll_off(&mut core, 3);
    core.resize(50, 3);
    let rows = rows(&core);
    assert_eq!(&rows[..2], &["y".repeat(50), "y".repeat(40)]);
    assert!(widest(&core) <= 50);
}

#[test]
fn styles_follow_the_text_across_a_wrap() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 2);
    core.feed(b"plain\x1b[31mred\x1b[0m\r\n");
    scroll_off(&mut core, 2);
    core.resize(6, 2);
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.row_text(0), "plainr");
    assert_eq!(snapshot.row_text(1), "ed");
    let pairs = snapshot.row_style_pairs(1);
    assert_eq!(pairs.len(), 1);
    assert_eq!(pairs[0].1.fg.colour(), StyleCode::ansi(1));
}

#[test]
fn blocks_keep_their_rows_across_a_rewrap() {
    let mut core = TerminalCore::new(100, 1000).unwrap();
    core.resize(100, 3);
    core.feed(b"\x1b]133;A\x07");
    core.feed(format!("{}\r\n", "a".repeat(90)).as_bytes());
    core.feed(b"\x1b]133;D;0\x07");
    core.feed(b"\x1b]133;A\x07");
    core.feed(format!("{}\r\n", "b".repeat(70)).as_bytes());
    core.feed(b"\x1b]133;D;0\x07");
    scroll_off(&mut core, 3);
    core.resize(40, 3);
    let snapshot = core.snapshot().unwrap();
    let text = |index: usize| -> Vec<String> {
        let block = &snapshot.blocks[index];
        (block.first_row..block.first_row + block.row_count)
            .map(|row| snapshot.row_text(row as usize).to_string())
            .collect()
    };
    assert_eq!(
        text(0),
        vec!["a".repeat(40), "a".repeat(40), "a".repeat(10)]
    );
    assert_eq!(text(1), vec!["b".repeat(40), "b".repeat(30)]);
}

#[test]
fn a_rewrapped_line_breaks_between_words() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 2);
    core.feed(b"new 2nm A20 Pro chip, variable-aperture main camera\r\n");
    scroll_off(&mut core, 2);
    core.resize(30, 2);
    let rows = rows(&core);
    assert_eq!(
        &rows[..3],
        &[
            "new 2nm A20 Pro chip, ",
            "variable-aperture main camera",
            ""
        ]
    );
}

#[test]
fn a_height_only_resize_leaves_the_rows_alone() {
    let mut core = TerminalCore::new(40, 1000).unwrap();
    core.resize(40, 4);
    core.feed(b"one\r\ntwo\r\n");
    scroll_off(&mut core, 4);
    let before = rows(&core);
    core.resize(40, 8);
    assert_eq!(rows(&core), before);
}
