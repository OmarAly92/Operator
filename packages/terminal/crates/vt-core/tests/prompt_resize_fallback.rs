mod common;

use vt_core::{LineEditorState, TerminalCore};

const PROMPT: &str = "\x1b]133;A\x07$ \x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07";

fn renderer(cols: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::new(cols, 1000).unwrap();
    core.set_grapheme_clusters(true);
    core.resize(cols, rows);
    core
}

fn logical_lines(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    let mut lines = vec![String::new()];
    for row in 0..snapshot.row_count() {
        lines.last_mut().unwrap().push_str(snapshot.row_text(row));
        if !snapshot.row_wrapped(row) {
            lines.push(String::new());
        }
    }
    lines
        .iter()
        .map(|line| line.trim_end().to_string())
        .filter(|line| !line.is_empty())
        .collect()
}

#[test]
fn output_below_an_owned_prompt_survives_a_narrower_resize() {
    let mut core = renderer(10, 5);
    core.feed(format!("{PROMPT}\r\nline0-abcd\r\n").as_bytes());
    assert_eq!(core.line_editor_state(), LineEditorState::Owned);
    core.resize(5, 5);
    common::check(&core);
    core.resize(10, 5);
    common::check(&core);
    assert_eq!(logical_lines(&core), vec!["$", "line0-abcd"]);
}

#[test]
fn background_output_below_an_owned_prompt_survives_a_narrower_resize() {
    let mut core = renderer(10, 5);
    let output: String = (0..8).map(|i| format!("bg{i}-abcdef\r\n")).collect();
    core.feed(format!("{PROMPT}\r\n{output}").as_bytes());
    assert_eq!(core.line_editor_state(), LineEditorState::Owned);
    core.resize(5, 5);
    common::check(&core);
    core.resize(10, 5);
    common::check(&core);
    let lines = logical_lines(&core);
    for i in 0..8 {
        let line = format!("bg{i}-abcdef");
        assert_eq!(
            lines.iter().filter(|text| **text == line).count(),
            1,
            "{line} in {lines:?}"
        );
    }
}

#[test]
fn a_typed_command_soft_wrapped_below_the_prompt_is_still_kept_in_place() {
    let mut core = renderer(20, 6);
    core.feed(b"out\r\n");
    core.feed(PROMPT.as_bytes());
    core.feed("x".repeat(30).as_bytes());
    core.resize(10, 6);
    common::check(&core);
    let (row, col, _) = core.export_cursor();
    assert_eq!((row - core.history_rows(), col), (2, 9));
    assert_eq!(logical_lines(&core)[0], "out");
}

#[test]
fn a_line_soft_wrapped_into_the_prompt_row_stays_joined() {
    let mut core = renderer(10, 5);
    core.feed(b"top\r\n0123456789abc");
    core.feed(PROMPT.replace("$ ", "$").as_bytes());
    assert_eq!(core.line_editor_state(), LineEditorState::Owned);
    core.resize(12, 5);
    common::check(&core);
    assert!(
        logical_lines(&core).contains(&"0123456789abc$".to_string()),
        "{:?}",
        logical_lines(&core)
    );
}
