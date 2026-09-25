mod common;

use vt_core::{LineEditorState, TerminalCore};

const READY: &str = "\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07";
const ZSH_REDRAW: &str = "\r\r\x1b[0m\x1b[27m\x1b[24m\x1b[J";

fn core(cols: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::new(cols, 1000).unwrap();
    core.resize(cols, rows);
    core
}

fn prompt(core: &mut TerminalCore, text: &str) {
    core.feed(format!("\x1b]133;A\x07{text}{READY}").as_bytes());
    assert_eq!(core.line_editor_state(), LineEditorState::Owned);
}

fn run(core: &mut TerminalCore, command: &str, output: &str) {
    core.feed(
        format!(
            "{command}\r\n\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07{output}\x1b]133;D;0\x07"
        )
        .as_bytes(),
    );
}

fn texts(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    (0..snapshot.row_count())
        .map(|row| snapshot.row_text(row).trim_end().to_string())
        .collect()
}

fn count(core: &TerminalCore, text: &str) -> usize {
    texts(core).iter().filter(|row| row.contains(text)).count()
}

fn screen_cursor(core: &TerminalCore) -> (usize, usize) {
    let (row, col, _) = core.export_cursor();
    (row - core.history_rows(), col)
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
        .collect()
}

#[test]
fn a_resize_at_a_visible_prompt_leaves_one_prompt_after_the_shell_redraws() {
    let mut core = core(80, 24);
    prompt(&mut core, "~/p $ ");
    run(&mut core, "echo hi", "hi\r\n");
    prompt(&mut core, "~/p $ ");
    core.resize(40, 24);
    core.feed(format!("{ZSH_REDRAW}~/p $ ").as_bytes());
    common::check(&core);
    assert_eq!(
        texts(&core)
            .iter()
            .filter(|row| row.as_str() == "~/p $")
            .count(),
        1
    );
    assert_eq!(count(&core, "~/p $ echo hi"), 1);
    assert_eq!(count(&core, "hi"), 2);
}

#[test]
fn a_narrower_window_keeps_a_two_line_prompt_where_zsh_redraws_it() {
    let first = "a".repeat(60);
    let mut core = core(80, 24);
    prompt(&mut core, "$ ");
    run(&mut core, "echo hi", "hi\r\n");
    prompt(&mut core, &format!("{first}\r\nline-two $ "));
    core.resize(40, 24);
    core.feed(format!("\r\r\x1bM\x1b[J{first}\r\nline-two $ ").as_bytes());
    common::check(&core);
    assert_eq!(count(&core, "line-two $"), 1);
    assert_eq!(count(&core, &"a".repeat(40)), 1);
    assert_eq!(count(&core, "hi"), 2);
    assert_eq!(screen_cursor(&core).1, 11);
}

#[test]
fn a_wider_window_does_not_let_zsh_erase_the_output_above_a_tall_prompt() {
    let long = format!("/{}/ $ ", "d".repeat(92));
    let mut core = core(40, 24);
    prompt(&mut core, "$ ");
    run(&mut core, "echo keep-me", "keep-me\r\n");
    prompt(&mut core, &long);
    core.resize(100, 24);
    core.feed(format!("\r\r\x1b[A\x1b[A\x1b[0m\x1b[J{long}").as_bytes());
    common::check(&core);
    assert_eq!(count(&core, "keep-me"), 2);
    assert_eq!(count(&core, "/ddd"), 1);
    assert!(logical_lines(&core)
        .iter()
        .any(|line| line == long.trim_end()));
}

#[test]
fn bash_redraws_only_the_last_prompt_line_and_the_first_stays_in_place() {
    let first = format!("first-{}", "b".repeat(54));
    let mut core = core(80, 24);
    prompt(&mut core, &format!("{first}\r\nsecond $ "));
    core.resize(40, 24);
    core.feed(b"\r\x1b[Ksecond $ ");
    common::check(&core);
    assert_eq!(count(&core, "second $"), 1);
    assert_eq!(
        texts(&core)
            .iter()
            .filter(|row| row.starts_with("first-"))
            .count(),
        1
    );
    assert!(texts(&core).contains(&first[..40].to_string()));
}

#[test]
fn fish_repaints_on_the_next_key_from_the_first_row_of_the_kept_prompt() {
    let mut core = core(80, 24);
    prompt(&mut core, "line-one-of-the-prompt\r\nline-two $ ls -la");
    core.resize(40, 24);
    assert_eq!(count(&core, "line-two $ ls -la"), 1);
    core.feed(
        b"\r\x1b[A\r\x1b[K\x1b]133;A;click_events=1\x1b\\line-one-of-the-prompt\r\nline-two $ \x1b]133;B\x1b\\ls -lax\x1b[J",
    );
    common::check(&core);
    assert_eq!(count(&core, "line-one-of-the-prompt"), 1);
    assert_eq!(count(&core, "line-two $ ls -lax"), 1);
}

#[test]
fn a_wide_character_cut_by_a_narrower_prompt_row_is_blanked_whole() {
    let mut core = core(80, 24);
    core.set_grapheme_clusters(true);
    prompt(&mut core, "\u{65e5}\u{672c}\u{8a9e} > ");
    core.resize(5, 24);
    common::check(&core);
    let snapshot = core.snapshot().unwrap();
    let row = snapshot.cursor_row as usize;
    assert_eq!(snapshot.row_text(row).trim_end(), "\u{65e5}\u{672c}");
    assert_eq!(screen_cursor(&core), (0, 4));
}

#[test]
fn the_cursor_keeps_its_place_in_the_prompt() {
    let mut core = core(80, 24);
    prompt(&mut core, "~/p $ ls");
    assert_eq!(screen_cursor(&core), (0, 8));
    core.resize(100, 30);
    assert_eq!(screen_cursor(&core), (0, 8));
    core.resize(5, 30);
    assert_eq!(screen_cursor(&core), (0, 4));
    common::check(&core);
}

#[test]
fn a_resize_while_a_command_runs_still_moves_the_frame_to_scrollback() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    core.feed(b"sleep 5\r\n\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07partial output");
    assert_eq!(core.line_editor_state(), LineEditorState::Released);
    let history = core.history_rows();
    core.resize(30, 10);
    common::check(&core);
    assert_eq!(core.history_rows(), history + 2);
    assert_eq!(screen_cursor(&core), (0, 0));
}

#[test]
fn a_resize_on_the_alternate_screen_leaves_the_primary_frame_alone() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    core.feed(b"\x1b[?1049hfull screen");
    assert_eq!(core.line_editor_state(), LineEditorState::Released);
    let history = core.history_rows();
    core.resize(30, 12);
    common::check(&core);
    assert_eq!(core.history_rows(), history);
    let alt = core.alt_grid().expect("alt grid");
    assert_eq!((alt.cols(), alt.rows()), (30, 12));
}

#[test]
fn agent_tui_mode_keeps_truncating_in_place_at_a_prompt() {
    let mut core = core(40, 10);
    core.set_agent_tui_mode(true);
    prompt(&mut core, "$ ");
    run(&mut core, "echo hi", "hi\r\n");
    prompt(&mut core, "$ ");
    let rows = core.snapshot().unwrap().row_count();
    let history = core.history_rows();
    core.resize(20, 10);
    common::check(&core);
    assert_eq!(core.snapshot().unwrap().row_count(), rows);
    assert_eq!(core.history_rows(), history);
}

#[test]
fn a_prompt_taller_than_the_new_screen_takes_the_old_path() {
    let mut core = core(80, 24);
    prompt(&mut core, "$ ");
    run(&mut core, "echo hi", "hi\r\n");
    prompt(&mut core, "one\r\ntwo\r\nthree $ ");
    let history = core.history_rows();
    core.resize(80, 2);
    common::check(&core);
    assert_eq!(core.history_rows(), history + 5);
    assert_eq!(screen_cursor(&core), (0, 0));
}
