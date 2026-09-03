use vt_core::TerminalCore;

fn content(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    (0..snapshot.row_count())
        .map(|i| snapshot.row_text(i).trim_end().to_string())
        .filter(|row| !row.is_empty())
        .collect()
}

#[test]
fn resizing_an_agent_tui_appends_no_frame_to_scrollback() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.set_agent_tui_mode(true);
    core.feed(b"\x1b[Hframe one\x1b[K");
    let before = core.snapshot().unwrap().row_count();
    core.resize(100, 30);
    core.resize(80, 24);
    assert_eq!(
        core.snapshot().unwrap().row_count(),
        before,
        "a resize must not push the pre-resize frame into scrollback",
    );
}

#[test]
fn resizing_a_shell_reflows_the_frame_into_scrollback() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"\x1b[Hframe one\x1b[K");
    core.resize(100, 30);
    core.resize(80, 24);
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.row_count(), 2);
    assert_eq!(snapshot.row_text(0).trim_end(), "frame one");
    let copies = (0..snapshot.row_count())
        .filter(|row| snapshot.row_text(*row).trim_end() == "frame one")
        .count();
    assert_eq!(
        copies, 1,
        "a resize moves the frame to scrollback, it does not copy it"
    );
}

#[test]
fn resizing_a_shell_repeatedly_does_not_grow_the_row_space() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"\x1b[Hframe one\x1b[K");
    core.resize(100, 30);
    let after_first = core.snapshot().unwrap().row_count();
    for _ in 0..8 {
        core.resize(90, 26);
        core.resize(100, 30);
    }
    assert_eq!(core.snapshot().unwrap().row_count(), after_first);
}

#[test]
fn leaving_agent_tui_mode_restores_clear_and_resize_reflow() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.set_agent_tui_mode(true);
    core.feed(b"\x1b[Hagent frame\x1b[K\x1b[2J");
    assert_eq!(core.snapshot().unwrap().row_text(0), "");
    core.feed(b"\x1b[Hshell frame\x1b[K");
    core.set_agent_tui_mode(false);
    core.resize(100, 30);
    core.resize(80, 24);
    assert_eq!(core.snapshot().unwrap().row_count(), 2);
    core.feed(b"\x1b[2J");
    let snapshot = core.snapshot().unwrap();
    assert!((0..snapshot.row_count()).any(|row| snapshot.row_text(row) == "shell frame"));
}

#[test]
fn a_resize_moves_the_frame_to_scrollback_without_copying_it() {
    let mut core = TerminalCore::new(16, 100).unwrap();
    core.feed("\x1b[31mred\x1b[0m caf\u{e9}\r\nplain".as_bytes());
    core.resize(46, 17);
    assert_eq!(content(&core), vec!["red café", "plain"]);
}

#[test]
fn repeated_resizes_do_not_multiply_history() {
    let mut core = TerminalCore::new(16, 100).unwrap();
    core.feed("\x1b[31mred\x1b[0m caf\u{e9}\r\nplain".as_bytes());
    core.resize(46, 17);
    core.resize(50, 20);
    core.resize(46, 17);
    core.resize(80, 24);
    assert_eq!(content(&core), vec!["red café", "plain"]);
}

#[test]
fn a_resize_after_more_output_keeps_every_line_once() {
    let mut core = TerminalCore::new(40, 100).unwrap();
    core.feed(b"one\r\ntwo\r\n");
    core.resize(60, 20);
    core.feed(b"three\r\n");
    core.resize(40, 10);
    assert_eq!(content(&core), vec!["one", "two", "three"]);
}

#[test]
fn shrinking_height_keeps_the_cursor_row_instead_of_the_top_rows() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.set_reflow_on_resize(false);
    core.resize(80, 24);
    core.feed(b"\x1b[?1049h\x1b[24;1H");
    for line in 0..40u32 {
        core.feed(format!("line {line}\r\n").as_bytes());
    }
    core.resize(60, 20);
    let alt = core.alt_grid().expect("alt grid");
    assert_eq!(alt.row_text(0).trim_end(), "line 21");
    assert_eq!(alt.row_text(18).trim_end(), "line 39");
}

#[test]
fn shrinking_height_below_the_cursor_still_drops_from_the_bottom() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.set_reflow_on_resize(false);
    core.resize(80, 24);
    core.feed(b"\x1b[?1049h\x1b[1;1Hkeep me\x1b[2;1Hsecond");
    core.resize(80, 20);
    let alt = core.alt_grid().expect("alt grid");
    assert_eq!(alt.row_text(0).trim_end(), "keep me");
    assert_eq!(alt.row_text(1).trim_end(), "second");
}
