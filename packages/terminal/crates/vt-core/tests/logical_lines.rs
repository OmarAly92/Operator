mod common;

use vt_core::TerminalCore;

fn rows_and_flags(core: &TerminalCore) -> Vec<(String, bool)> {
    let snapshot = core.snapshot().expect("snapshot");
    common::check(core);
    (0..snapshot.row_count())
        .map(|index| {
            (
                snapshot.row_text(index).to_string(),
                snapshot.row_wrapped(index),
            )
        })
        .collect()
}

#[test]
fn a_soft_wrapped_screen_row_is_flagged_and_keeps_its_break_space() {
    let mut core = TerminalCore::new(4, 100).expect("core");
    core.resize(4, 3);
    core.feed(b"abc def");
    let rows = rows_and_flags(&core);
    assert_eq!(rows[0], ("abc ".to_string(), true));
    assert_eq!(rows[1], ("def".to_string(), false));
}

#[test]
fn a_hard_newline_is_not_a_wrap() {
    let mut core = TerminalCore::new(10, 100).expect("core");
    core.resize(10, 3);
    core.feed(b"one\r\ntwo");
    let rows = rows_and_flags(&core);
    assert_eq!(rows[0], ("one".to_string(), false));
    assert_eq!(rows[1], ("two".to_string(), false));
}

#[test]
fn a_wrapped_row_keeps_its_flag_when_it_is_evicted_into_scrollback() {
    let mut core = TerminalCore::new(4, 100).expect("core");
    core.resize(4, 2);
    core.feed(b"abc def\r\nx\r\ny\r\n");
    let rows = rows_and_flags(&core);
    let history = core.snapshot().expect("snapshot").history_rows as usize;
    assert!(history >= 2, "the wrapped pair is in scrollback");
    assert_eq!(rows[0], ("abc ".to_string(), true));
    assert_eq!(rows[1], ("def".to_string(), false));
}

#[test]
fn a_rewrap_cut_flags_every_piece_but_the_last() {
    let mut core = TerminalCore::new(40, 100).expect("core");
    core.resize(40, 2);
    core.feed(b"alpha beta gamma delta epsilon zeta\r\nx\r\ny\r\n");
    core.resize(12, 2);
    let rows = rows_and_flags(&core);
    let pieces: Vec<&(String, bool)> = rows.iter().take_while(|(text, _)| text != "x").collect();
    assert!(pieces.len() >= 3, "{pieces:?}");
    for piece in &pieces[..pieces.len() - 1] {
        assert!(
            piece.1,
            "{piece:?} is not the last piece and must be flagged"
        );
    }
    assert!(!pieces[pieces.len() - 1].1, "the last piece is not flagged");
    let joined: String = pieces.iter().map(|(text, _)| text.as_str()).collect();
    assert_eq!(joined, "alpha beta gamma delta epsilon zeta");
}
