use vt_core::{Limits, LineEditorState, TerminalCore};

use crate::block_marks::{SETTLED_BEGIN, SETTLED_END};
use crate::replay::replay_frame;

const INPUT_READY: &str = "\x1b]7000;v=1;input-ready=1";
const INPUT_RELEASED: &str = "\x1b]7000;v=1;input-released=1";
const TWO_LINE_PROMPT: &str = "~ first line\r\nsecond $ ";
const ZSH_TWO_LINE_REDRAW: &str = "\r\r\x1bM\x1b[J~ first line\r\nsecond $ ";

fn mirror(cols: usize, rows: usize) -> TerminalCore {
    let limits = Limits {
        rows: 1000,
        bytes: u32::MAX as usize,
    };
    let mut core = TerminalCore::with_limits(cols, limits).unwrap();
    core.set_reflow_on_resize(false);
    core.set_answers_queries(true);
    core.resize(cols, rows);
    core
}

fn renderer(cols: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::new(cols, 1000).unwrap();
    core.resize(cols, rows);
    core
}

fn zsh_prompt(id: &str, prompt: &str) -> String {
    format!(
        "\x1b]7000;v=1;id={id};cwd=%2Ftmp;branch=\x1b\\\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m{}\r \r\x1b]133;A\x07{prompt}\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07",
        " ".repeat(79)
    )
}

fn zsh_command(id: &str, prompt: &str, command: &str, output: &str) -> String {
    let encoded = command.replace(' ', "%20");
    format!(
        "{}{command}\r\n\x1b]7000;v=1;id={id};cmd={encoded}\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07{output}\x1b]7000;v=1;id={id};exit=0\x1b\\\x1b]133;D;0\x07",
        zsh_prompt(id, prompt)
    )
}

fn replay(core: &TerminalCore) -> String {
    String::from_utf8(replay_frame(core, 1000).unwrap()).unwrap()
}

fn without_settled_rows(frame: &str) -> String {
    match (frame.find(SETTLED_BEGIN), frame.find(SETTLED_END)) {
        (Some(begin), Some(end)) => {
            format!("{}{}", &frame[..begin], &frame[end + SETTLED_END.len()..])
        }
        _ => frame.to_string(),
    }
}

fn rows_containing(core: &TerminalCore, text: &str) -> usize {
    let snapshot = core.snapshot().unwrap();
    (0..snapshot.row_count())
        .filter(|&row| snapshot.row_text(row).contains(text))
        .count()
}

fn resize_back_and_forth(core: &mut TerminalCore, times: usize) {
    for _ in 0..times {
        core.resize(40, 24);
        core.feed(ZSH_TWO_LINE_REDRAW.as_bytes());
        core.resize(80, 24);
        core.feed(ZSH_TWO_LINE_REDRAW.as_bytes());
    }
}

fn reattached_after_echo() -> TerminalCore {
    let history = zsh_command("t-1", TWO_LINE_PROMPT, "echo one", "one\r\n");
    let mut host = mirror(80, 24);
    host.feed(format!("{history}{}", zsh_prompt("t-2", TWO_LINE_PROMPT)).as_bytes());
    let frame = replay(&host);
    let mut core = renderer(80, 24);
    core.feed(history.as_bytes());
    core.feed(without_settled_rows(&frame).as_bytes());
    core
}

#[test]
fn a_replay_at_an_owned_prompt_hands_the_line_editor_to_a_page_that_fed_durable_history() {
    let core = reattached_after_echo();
    assert_eq!(core.line_editor_state(), LineEditorState::Owned);
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn a_reattached_page_keeps_one_two_line_prompt_over_narrow_and_wide_resizes() {
    let mut original = renderer(80, 24);
    original.feed(
        format!(
            "{}{}",
            zsh_command("t-1", TWO_LINE_PROMPT, "echo one", "one\r\n"),
            zsh_prompt("t-2", TWO_LINE_PROMPT)
        )
        .as_bytes(),
    );
    resize_back_and_forth(&mut original, 4);
    let mut reattached = reattached_after_echo();
    resize_back_and_forth(&mut reattached, 4);
    assert_eq!(rows_containing(&original, "first line"), 2);
    assert_eq!(rows_containing(&reattached, "first line"), 2);
    assert_eq!(rows_containing(&reattached, "second $"), 2);
    assert_eq!(reattached.verify_integrity(), Ok(()));
}

#[test]
fn a_replay_at_an_owned_prompt_marks_the_prompt_outside_the_settled_rows() {
    let mut host = mirror(80, 24);
    host.feed(
        format!(
            "{}{}",
            zsh_command("t-1", TWO_LINE_PROMPT, "echo one", "one\r\n"),
            zsh_prompt("t-2", TWO_LINE_PROMPT)
        )
        .as_bytes(),
    );
    let frame = replay(&host);
    let settled_end = frame.find(SETTLED_END).unwrap();
    let ready = frame.find(INPUT_READY).unwrap();
    let prompt = frame.find("\x1b]133;A").unwrap();
    assert!(settled_end < prompt && prompt < ready, "{frame:?}");
    assert_eq!(frame.matches(INPUT_READY).count(), 1);
    assert!(!frame.contains(INPUT_RELEASED));
    let mut fresh = renderer(80, 24);
    fresh.feed(frame.as_bytes());
    assert_eq!(fresh.line_editor_state(), LineEditorState::Owned);
}

#[test]
fn a_replay_while_a_command_runs_releases_the_line_editor() {
    let mut host = mirror(80, 24);
    host.feed(
        format!(
            "{}{}sleep 9\r\n\x1b]7000;v=1;id=t-2;cmd=sleep%209\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07partial",
            zsh_command("t-1", "$ ", "true", "done\r\n"),
            zsh_prompt("t-2", "$ ")
        )
        .as_bytes(),
    );
    let frame = replay(&host);
    assert!(!frame.contains(INPUT_READY), "{frame:?}");
    assert!(frame.contains(INPUT_RELEASED), "{frame:?}");
    let mut fresh = renderer(80, 24);
    fresh.feed(frame.as_bytes());
    assert_eq!(fresh.line_editor_state(), LineEditorState::Released);
}

#[test]
fn a_replay_without_shell_integration_carries_no_line_editor_marks() {
    let mut host = mirror(80, 24);
    host.feed(b"\x1b[1mClaude Code\x1b[0m\r\n> \x1b[7m \x1b[0m");
    let frame = replay(&host);
    assert!(!frame.contains("input-"), "{frame:?}");
    assert!(!frame.contains("\x1b]133;"), "{frame:?}");
}

#[test]
fn a_replay_never_repeats_a_pending_typeahead_report() {
    let mut host = mirror(80, 24);
    host.feed(format!("{}\x1b]7000;v=1;typeahead=ls\x07", zsh_prompt("t-1", "$ ")).as_bytes());
    let frame = replay(&host);
    assert!(!frame.contains("typeahead"), "{frame:?}");
    let mut fresh = renderer(80, 24);
    fresh.feed(frame.as_bytes());
    assert_eq!(fresh.line_editor_state(), LineEditorState::Owned);
    assert_eq!(fresh.take_typeahead(), None);
}

#[test]
fn an_alternate_screen_replay_carries_no_line_editor_marks() {
    let mut host = mirror(80, 24);
    host.feed(format!("{}\x1b[?1049hvim", zsh_prompt("t-1", "$ ")).as_bytes());
    let frame = replay(&host);
    assert!(!frame.contains("input-"), "{frame:?}");
}

#[test]
fn a_replay_at_a_suppressed_prompt_hands_over_the_line_editor_without_adding_rows() {
    let history = zsh_command("t-1", "", "echo one", "one\r\n");
    let mut host = mirror(80, 24);
    host.feed(format!("{history}{}", zsh_prompt("t-2", "")).as_bytes());
    let mut core = renderer(80, 24);
    core.feed(history.as_bytes());
    core.feed(without_settled_rows(&replay(&host)).as_bytes());
    assert_eq!(core.line_editor_state(), LineEditorState::Owned);
    let snapshot = core.snapshot().unwrap();
    let rows: Vec<&str> = (0..snapshot.row_count())
        .map(|row| snapshot.row_text(row))
        .filter(|text| !text.is_empty())
        .collect();
    assert_eq!(rows, ["echo one", "one"]);
    assert_eq!(core.export_cursor().0, 2);
}

#[test]
fn history_chunks_after_a_replay_at_an_owned_prompt_keep_the_prompt_block_and_the_line_editor() {
    let output: String = (0..40).map(|line| format!("line-{line}\r\n")).collect();
    let mut host = mirror(80, 24);
    host.feed(
        format!(
            "{}{}",
            zsh_command("t-1", TWO_LINE_PROMPT, "seq 40", &output),
            zsh_prompt("t-2", TWO_LINE_PROMPT)
        )
        .as_bytes(),
    );
    let frame = String::from_utf8(replay_frame(&host, 6).unwrap()).unwrap();
    let snapshot = host.snapshot().unwrap();
    let bound = snapshot.row_count() - 6;
    let mut chunk = format!("\x1b]7000;v=1;history=0,{bound}\x1b\\");
    for row in 0..bound {
        chunk.push_str(snapshot.row_text(row));
        chunk.push_str("\r\n");
    }
    let mut core = renderer(80, 24);
    core.feed(frame.as_bytes());
    core.feed(chunk.as_bytes());
    assert_eq!(core.first_stable_row(), 0);
    assert_eq!(core.line_editor_state(), LineEditorState::Owned);
    assert_eq!(core.verify_integrity(), Ok(()));
    resize_back_and_forth(&mut core, 2);
    assert_eq!(rows_containing(&core, "first line"), 2);
    assert_eq!(rows_containing(&core, "line-0"), 1);
    assert_eq!(core.verify_integrity(), Ok(()));
}
