mod common;

use vt_core::{BlockState, TerminalCore};

const BASH_PROMPT: &str = "\x1b]7000;v=1;id=t-2;cwd=%2Ftmp;branch=\x1b\\\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07";
const BASH_REDRAW: &str = "\r\x1b[K";

fn core(cols: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::new(cols, 1000).unwrap();
    core.resize(cols, rows);
    core
}

fn bash_command(id: &str, prompt: &str, command: &str, output: &str) -> String {
    format!(
        "\x1b]7000;v=1;id={id};cwd=%2Ftmp;branch=\x1b\\\x1b]133;A\x07{prompt}\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07{command}\r\n\x1b]7000;v=1;id={id};cmd={}\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07{output}\x1b]7000;v=1;id={id};exit=0\x1b\\\x1b]133;D;0\x07",
        command.replace(' ', "%20")
    )
}

fn rows(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    let mut rows: Vec<String> = (0..snapshot.row_count())
        .map(|row| snapshot.row_text(row).trim_end().to_string())
        .collect();
    while rows.last().is_some_and(|row| row.is_empty()) {
        rows.pop();
    }
    rows
}

#[test]
fn a_prompt_after_output_without_a_newline_starts_on_its_own_row() {
    let mut core = core(40, 10);
    core.feed(bash_command("t-1", "", "printf x", "x").as_bytes());
    core.feed(BASH_PROMPT.as_bytes());
    assert_eq!(core.export_cursor().0, 2);
    assert_eq!(core.export_cursor().1, 0);
    core.feed(BASH_REDRAW.as_bytes());
    assert_eq!(rows(&core), ["printf x", "x"]);
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.blocks[0].state, BlockState::Finished);
    assert_eq!(snapshot.blocks[1].first_row, 2);
    common::check(&core);
}

#[test]
fn the_next_command_after_output_without_a_newline_is_echoed_below_it() {
    let mut core = core(40, 10);
    core.feed(bash_command("t-1", "", "printf x", "x").as_bytes());
    core.feed(format!("{BASH_PROMPT}{BASH_REDRAW}").as_bytes());
    core.feed(
        b"echo next\r\n\x1b]7000;v=1;id=t-2;cmd=echo%20next\x1b\\\x1b]133;C\x07next\r\n\x1b]133;D;0\x07",
    );
    assert_eq!(rows(&core), ["printf x", "x", "echo next", "next"]);
    common::check(&core);
}

#[test]
fn a_visible_prompt_after_output_without_a_newline_is_drawn_on_its_own_row() {
    let mut core = core(40, 10);
    core.feed(bash_command("t-1", "$ ", "printf x", "x").as_bytes());
    core.feed(b"\x1b]133;A\x07$ \x1b]133;B\x07");
    assert_eq!(rows(&core), ["$ printf x", "x", "$"]);
    assert_eq!(core.export_cursor().1, 2);
}

#[test]
fn a_prompt_after_output_that_ended_with_a_newline_stays_where_it_is() {
    let mut core = core(40, 10);
    core.feed(bash_command("t-1", "$ ", "echo x", "x\r\n").as_bytes());
    core.feed(b"\x1b]133;A\x07$ \x1b]133;B\x07");
    assert_eq!(rows(&core), ["$ echo x", "x", "$"]);
}
