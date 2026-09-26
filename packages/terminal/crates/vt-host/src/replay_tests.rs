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

fn zsh_precmd_prompt(id: &str, prompt: &str) -> String {
    format!(
        "\x1b]7000;v=1;id={id};cwd=%2Ftmp;branch=\x1b\\\x1b]133;A\x07\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m{}\r \r{prompt}\x1b]7000;v=1;input-ready=1\x07",
        " ".repeat(79)
    )
}

fn zsh_precmd_command(id: &str, prompt: &str, command: &str, output: &str) -> String {
    format!(
        "{}{command}\r\n\x1b]7000;v=1;id={id};cmd={}\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07{output}\x1b]7000;v=1;id={id};exit=0\x1b\\\x1b]133;D;0\x07",
        zsh_precmd_prompt(id, prompt),
        command.replace(' ', "%20")
    )
}

fn bash_command(id: &str, command: &str, output: &str) -> String {
    format!(
        "{}{command}\r\n\x1b]7000;v=1;id={id};cmd={}\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07{output}\x1b]7000;v=1;id={id};exit=0\x1b\\\x1b]133;D;0\x07",
        bash_prompt(id),
        command.replace(' ', "%20")
    )
}

fn bash_prompt(id: &str) -> String {
    format!("\x1b]7000;v=1;id={id};cwd=%2Ftmp;branch=\x1b\\\x1b]133;A\x07$ \x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07")
}

fn row_texts(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    let mut rows: Vec<String> = (0..snapshot.row_count())
        .map(|row| snapshot.row_text(row).trim_end().to_string())
        .collect();
    while rows.last().is_some_and(|row| row.is_empty()) {
        rows.pop();
    }
    rows
}

fn live_and_reattached(
    host: &mut TerminalCore,
    durable: &str,
    rest: &str,
    cols: usize,
) -> (TerminalCore, TerminalCore) {
    host.feed(rest.as_bytes());
    let mut live = renderer(cols, 24);
    live.feed(format!("{durable}{rest}").as_bytes());
    let mut reattached = renderer(cols, 24);
    reattached.feed(durable.as_bytes());
    reattached.feed(without_settled_rows(&replay(host)).as_bytes());
    (live, reattached)
}

fn reattach(durable: &str, rest: &str) -> (TerminalCore, TerminalCore) {
    let mut host = mirror(80, 24);
    host.feed(durable.as_bytes());
    live_and_reattached(&mut host, durable, rest, 80)
}

#[test]
fn a_reattached_prompt_starts_below_output_that_ended_without_a_newline() {
    let durable = zsh_precmd_command("t-1", "$ ", "printf x", "x");
    let (live, reattached) = reattach(&durable, &zsh_precmd_prompt("t-2", "$ "));
    assert_eq!(row_texts(&live), ["$ printf x", "x%", "$"]);
    assert_eq!(row_texts(&reattached), row_texts(&live));
    assert_eq!(reattached.export_cursor(), live.export_cursor());
    assert_eq!(reattached.line_editor_state(), LineEditorState::Owned);
}

#[test]
fn the_next_command_at_a_reattached_suppressed_prompt_keeps_output_that_ended_without_a_newline() {
    let durable = zsh_precmd_command("t-1", "", "printf x", "x");
    let (mut live, mut reattached) = reattach(&durable, &zsh_precmd_prompt("t-2", ""));
    let next = "echo hi\r\n\x1b]7000;v=1;id=t-2;cmd=echo%20hi\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07hi\r\n";
    live.feed(next.as_bytes());
    reattached.feed(next.as_bytes());
    assert_eq!(row_texts(&live), ["printf x", "x%", "echo hi", "hi"]);
    assert_eq!(row_texts(&reattached), row_texts(&live));
    assert_eq!(reattached.verify_integrity(), Ok(()));
}

#[test]
fn a_reattached_bash_prompt_that_shares_the_output_row_is_drawn_once() {
    let durable = bash_command("t-1", "printf x", "x");
    let (live, reattached) = reattach(&durable, &bash_prompt("t-2"));
    assert_eq!(row_texts(&live), ["$ printf x", "x$"]);
    assert_eq!(row_texts(&reattached), row_texts(&live));
    assert_eq!(reattached.export_cursor(), live.export_cursor());
}

#[test]
fn a_reattached_bash_prompt_after_styled_wide_output_keeps_the_cells_and_their_styles() {
    let durable = bash_command("t-1", "printf x", "\x1b[32m中\x1b[0mx");
    let (live, reattached) = reattach(&durable, &bash_prompt("t-2"));
    assert_eq!(row_texts(&live), ["$ printf x", "中x$"]);
    assert_eq!(row_texts(&reattached), row_texts(&live));
    assert_eq!(reattached.export_cursor(), live.export_cursor());
    let (live, reattached) = (live.snapshot().unwrap(), reattached.snapshot().unwrap());
    assert_eq!(reattached.row_style_pairs(1), live.row_style_pairs(1));
}

#[test]
fn a_reattached_prompt_after_output_that_filled_its_last_row_starts_on_the_next_row() {
    let durable = bash_command("t-1", "printf y", &"y".repeat(80));
    let (live, reattached) = reattach(&durable, &bash_prompt("t-2"));
    assert_eq!(row_texts(&live), ["$ printf y", &"y".repeat(80), "$"]);
    assert_eq!(row_texts(&reattached), row_texts(&live));
    assert_eq!(reattached.export_cursor(), live.export_cursor());
}

#[test]
fn a_reattached_prompt_after_output_without_a_newline_survives_a_width_change() {
    let durable = zsh_precmd_command("t-1", "$ ", "printf x", "x");
    let mut host = mirror(80, 24);
    host.feed(format!("{durable}{}", zsh_precmd_prompt("t-2", "$ ")).as_bytes());
    host.resize(60, 24);
    let (_, reattached) = live_and_reattached(&mut host, &durable, "\r\x1b[J$ ", 60);
    let rows = row_texts(&reattached);
    assert_eq!(rows[rows.len() - 3..], ["$ printf x", "x%", "$"]);
    assert_eq!(reattached.export_cursor().0, rows.len() - 1);
    assert_eq!(reattached.line_editor_state(), LineEditorState::Owned);
}

#[test]
fn output_that_ended_with_a_newline_still_replays_below_the_settled_rows() {
    let durable = zsh_precmd_command("t-1", "$ ", "echo one", "one\r\n");
    let (live, reattached) = reattach(&durable, &zsh_precmd_prompt("t-2", "$ "));
    assert_eq!(row_texts(&reattached), row_texts(&live));
    assert_eq!(reattached.export_cursor(), live.export_cursor());
}
