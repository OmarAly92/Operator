mod common;

use vt_core::{BlockState, TerminalCore};

fn zsh_prompt_sp() -> String {
    format!(
        "\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m{}\r \r",
        " ".repeat(119)
    )
}

fn zsh_prompt(id: &str) -> String {
    format!(
        "\x1b]7000;v=1;id={id};cwd=/w;branch=main\x1b\\\x1b]133;A\x07\r\x1b[0m\x1b[27m\x1b[24m\x1b[J\x1b[K\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07\x1b[?2004h\x1b[K"
    )
}

fn zsh_command(id: &str, typed: &str, output: &str) -> String {
    format!(
        "{typed}\x1b[?2004l\r\r\n\x1b]7000;v=1;input-released=1\x07\x1b]7000;v=1;id={id};cmd={}\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07{output}\x1b]7000;v=1;id={id};exit=0\x1b\\\x1b]133;D;0\x07{}",
        typed.replace(' ', "%20"),
        zsh_prompt_sp()
    )
}

const ZSH_CTRL_C: &str = "\x1b[?2004l\x1b[K\r\r\n";
const ZSH_EMPTY_ENTER: &str = "\x1b[K\x1b[?2004l\x1b[K\r\r\n";

fn zsh_session() -> String {
    [
        zsh_prompt_sp(),
        zsh_prompt("t-1"),
        zsh_command("t-1", "printf x", "x"),
        zsh_prompt("t-2"),
        ZSH_CTRL_C.to_string(),
        zsh_prompt_sp(),
        zsh_prompt("t-3"),
        ZSH_EMPTY_ENTER.to_string(),
        zsh_prompt_sp(),
        zsh_prompt("t-4"),
        zsh_command("t-4", "echo two", "two\r\n"),
        zsh_prompt("t-5"),
    ]
    .concat()
}

fn fish_marker() -> String {
    format!(
        "\x1b[?25h\x1b[2m\u{23ce}\x1b[m{}\r\u{23ce} \r\x1b[K",
        " ".repeat(119)
    )
}

fn fish_prompt() -> String {
    "\x1b]7000;v=1;input-ready=1\x07\x1b]7;file://host/w\x07\x1b]0;~/w\x1b\\\x1b[m\x1b]11;?\x1b\\\x1b[6n\x1b[0c\x1b[?1004h\x1b[?2004h\x1b[>4;1m\x1b=\x1b]133;A;click_events=1\x1b\\\x1b]133;B\x1b\\\x1b[K".to_string()
}

fn fish_command(id: &str, next: &str, verb: &str, arg: &str, output: &str) -> String {
    let at = verb.len() + 1;
    format!(
        "{verb} \r\x1b[{at}C\x1b[?1004l\x1b[?2004l\x1b[>4;0m\x1b>{arg}\r\x1b[8C\r{verb} \x1b[36m{arg}\x1b[39m\r\x1b[8C\r\n\x1b[m\x1b]133;C;cmdline_url={verb}%20{arg}\x1b\\\x1b]7000;v=1;id={id};cmd={verb}%20{arg}\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]0;{verb} {arg} ~/w\x1b\\\x1b[m\r{output}\x1b]133;D;0\x1b\\\x1b]7000;v=1;id={id};exit=0\x1b\\\x1b]7000;v=1;id={next};cwd=/w;branch=main\x1b\\{}",
        fish_marker()
    )
}

fn fish_session() -> String {
    [
        "\x1b[?u\x1b[>0q\x1b]11;?\x1b\\\x1b[?1049h\x1bP+q696e646e\x1b\\\x1b[?1049l\x1b[0c\rWelcome to fish, the friendly interactive shell\r\n\x1b]7;file://host/w\x07\x1b]7000;v=1;id=t-1;cwd=/w;branch=main\x1b\\".to_string(),
        fish_prompt(),
        fish_command("t-1", "t-2", "echo", "one", "one\r\n"),
        fish_prompt(),
        fish_command("t-2", "t-3", "printf", "x", "x"),
        fish_prompt(),
        format!("\x1b[?1004l\x1b[?2004l\x1b[>4;0m\x1b>\r\n\x1b[m{}", fish_marker()),
        fish_prompt(),
        fish_command("t-3", "t-4", "echo", "two", "two\r\n"),
        fish_prompt(),
    ]
    .concat()
}

fn bash_prompt(id: &str) -> String {
    format!("\x1b]7000;v=1;id={id};cwd=/w;branch=main\x1b\\\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07")
}

fn bash_command(id: &str, typed: &str, output: &str) -> String {
    format!(
        "{typed}\r\n\x1b]7000;v=1;id={id};cmd={}\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07{output}\x1b]7000;v=1;id={id};exit=0\x1b\\\x1b]133;D;0\x07",
        typed.replace(' ', "%20")
    )
}

fn bash_session() -> String {
    [
        bash_prompt("t-1"),
        bash_command("t-1", "printf x", "x"),
        bash_prompt("t-2"),
        "\r\n".to_string(),
        bash_prompt("t-3"),
        "\r\n".to_string(),
        bash_prompt("t-4"),
        bash_command("t-4", "echo two", "two\r\n"),
        bash_prompt("t-5"),
    ]
    .concat()
}

fn core(cols: usize) -> TerminalCore {
    let mut core = TerminalCore::new(cols, 1000).unwrap();
    core.resize(cols, 40);
    core
}

struct Seen {
    command: String,
    cwd: String,
    state: BlockState,
    rows: Vec<String>,
}

fn blocks(core: &TerminalCore) -> Vec<Seen> {
    let snapshot = core.snapshot().unwrap();
    snapshot
        .blocks
        .iter()
        .enumerate()
        .map(|(index, block)| {
            let first = block.first_row as usize;
            let mut rows: Vec<String> = (first..first + block.row_count as usize)
                .map(|row| snapshot.row_text(row).trim_end().to_string())
                .collect();
            while rows.last().is_some_and(|row| row.is_empty()) {
                rows.pop();
            }
            Seen {
                command: snapshot.block_command(index).to_string(),
                cwd: snapshot.block_cwd(index).to_string(),
                state: block.state,
                rows,
            }
        })
        .collect()
}

fn after_first_command(seen: Vec<Seen>) -> Vec<Seen> {
    let first = seen
        .iter()
        .position(|block| !block.command.is_empty())
        .unwrap();
    seen.into_iter().skip(first).collect()
}

fn commands_and_rows(seen: &[Seen]) -> Vec<(String, Vec<String>)> {
    seen.iter()
        .filter(|block| !block.command.is_empty())
        .map(|block| (block.command.clone(), block.rows.clone()))
        .collect()
}

fn fed(stream: &str) -> TerminalCore {
    let mut core = core(120);
    core.feed(stream.as_bytes());
    common::check(&core);
    core
}

fn expected(pairs: &[(&str, &[&str])]) -> Vec<(String, Vec<String>)> {
    pairs
        .iter()
        .map(|(command, rows)| {
            (
                command.to_string(),
                rows.iter().map(|row| row.to_string()).collect(),
            )
        })
        .collect()
}

#[test]
fn a_zsh_command_block_ends_at_its_output_and_not_at_the_partial_line_mark() {
    let seen = after_first_command(blocks(&fed(&zsh_session())));
    assert_eq!(
        commands_and_rows(&seen),
        expected(&[("printf x", &["x"]), ("echo two", &["two"])])
    );
}

#[test]
fn a_fish_command_block_holds_neither_the_echoed_command_line_nor_the_omitted_newline_mark() {
    let seen = after_first_command(blocks(&fed(&fish_session())));
    assert_eq!(
        commands_and_rows(&seen),
        expected(&[
            ("echo one", &["one"]),
            ("printf x", &["x"]),
            ("echo two", &["two"])
        ])
    );
}

#[test]
fn the_next_bash_prompt_starts_below_output_that_ended_without_a_newline() {
    let stream = [
        bash_prompt("t-1"),
        bash_command("t-1", "printf x", "x"),
        bash_prompt("t-2"),
        bash_command("t-2", "echo two", "two\r\n"),
        bash_prompt("t-3"),
    ]
    .concat();
    let seen = after_first_command(blocks(&fed(&stream)));
    assert_eq!(
        commands_and_rows(&seen),
        expected(&[("printf x", &["x"]), ("echo two", &["two"])])
    );
}

#[test]
fn a_ctrl_c_or_an_empty_enter_at_a_prompt_adds_no_block_and_keeps_the_cwd() {
    for (shell, stream) in [
        ("zsh", zsh_session()),
        ("bash", bash_session()),
        ("fish", fish_session()),
    ] {
        let seen = after_first_command(blocks(&fed(&stream)));
        let commands: Vec<&str> = seen.iter().map(|block| block.command.as_str()).collect();
        let last = *commands.last().unwrap();
        assert!(
            commands[..commands.len() - 1]
                .iter()
                .all(|command| !command.is_empty())
                && last.is_empty(),
            "{shell}: {commands:?}"
        );
        assert!(
            seen.iter()
                .all(|block| block.state != BlockState::Abandoned),
            "{shell}: an abandoned block"
        );
        assert!(
            seen.iter().all(|block| block.cwd == "/w"),
            "{shell}: {:?}",
            seen.iter().map(|block| &block.cwd).collect::<Vec<_>>()
        );
    }
}

#[test]
fn a_prompt_below_rows_the_prompt_did_not_draw_still_abandons_the_old_one() {
    let mut core = core(80);
    core.feed(b"\x1b]133;A\x07$ \x1b]133;B\x07");
    core.feed(b"\r\nbackground job output\r\n\x1b]133;A\x07$ \x1b]133;B\x07");
    common::check(&core);
    let seen = blocks(&core);
    assert_eq!(seen.len(), 2);
    assert_eq!(seen[0].state, BlockState::Abandoned);
    assert!(seen[0]
        .rows
        .iter()
        .any(|row| row == "background job output"));
}
