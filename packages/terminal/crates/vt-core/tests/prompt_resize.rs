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

#[test]
fn growing_the_window_pulls_the_newest_rows_back_onto_the_screen() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..30).map(|i| format!("line {i}\r\n")).collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    let before = texts(&core);
    let history = core.history_rows();
    assert_eq!(screen_cursor(&core), (9, 2));
    core.resize(40, 16);
    common::check(&core);
    assert_eq!(texts(&core), before);
    assert_eq!(core.history_rows(), history - 6);
    assert_eq!(screen_cursor(&core), (15, 2));
}

#[test]
fn a_narrower_window_keeps_the_prompt_the_same_distance_from_the_bottom() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..30).map(|i| format!("line {i}\r\n")).collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    core.resize(20, 10);
    common::check(&core);
    assert_eq!(screen_cursor(&core), (9, 2));
    assert_eq!(texts(&core).last().unwrap(), "$");
}

#[test]
fn a_shorter_window_pushes_the_rows_above_the_prompt_into_scrollback() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..30).map(|i| format!("line {i}\r\n")).collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    let before = texts(&core);
    let history = core.history_rows();
    core.resize(40, 6);
    common::check(&core);
    assert_eq!(texts(&core), before);
    assert_eq!(core.history_rows(), history + 4);
    assert_eq!(screen_cursor(&core), (5, 2));
}

#[test]
fn pull_back_stops_at_a_row_that_cannot_be_restored_exactly() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let long = "abc de ".repeat(12);
    run(&mut core, "echo", &format!("{long}\r\n"));
    prompt(&mut core, "$ ");
    core.resize(30, 12);
    common::check(&core);
    assert_eq!(screen_cursor(&core), (1, 2));
    assert!(logical_lines(&core).contains(&long.trim_end().to_string()));
}

#[test]
fn rows_pulled_back_commit_again_byte_for_byte() {
    for graphemes in [false, true] {
        let mut core = core(30, 8);
        core.set_grapheme_clusters(graphemes);
        prompt(&mut core, "$ ");
        let mut output = String::new();
        for i in 0..20 {
            output.push_str(&format!(
                "\x1b[3{}m{i} red\x1b[0m \x1b]8;;https://example.com/{i}\x1b\\link\x1b]8;;\x1b\\ \u{4e2d}e\u{301}\x1b[48;2;1;2;3m bg \x1b[0m\r\n",
                i % 8
            ));
        }
        run(&mut core, "paint", &output);
        prompt(&mut core, "$ ");
        core.resize(30, 20);
        common::check(&core);
        assert!(screen_cursor(&core).0 > 7, "rows were pulled back");
        let before = core.snapshot().unwrap();
        core.feed(b"\r\n\x1b]7000;v=1;input-released=1\x07");
        core.feed("\r\n".repeat(30).as_bytes());
        common::check(&core);
        let after = core.snapshot().unwrap();
        for row in 0..before.row_count() - 1 {
            assert_eq!(after.row_text(row), before.row_text(row), "row {row}");
            assert_eq!(
                after.row_style_pairs(row),
                before.row_style_pairs(row),
                "row {row}"
            );
            assert_eq!(
                after.row_cell_spans(row),
                before.row_cell_spans(row),
                "row {row}"
            );
            assert_eq!(after.row_wrapped(row), before.row_wrapped(row), "row {row}");
        }
    }
}

#[test]
fn blocks_keep_their_text_and_the_open_prompt_block_starts_on_the_prompt() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..14).map(|i| format!("out {i}\r\n")).collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    let text_of = |core: &TerminalCore, first: u32, count: u32| -> Vec<String> {
        let snapshot = core.snapshot().unwrap();
        (first..first + count)
            .map(|row| snapshot.row_text(row as usize).trim_end().to_string())
            .collect()
    };
    let before = core.snapshot().unwrap();
    let finished: Vec<(u32, u32)> = before
        .blocks
        .iter()
        .map(|b| (b.first_row, b.row_count))
        .collect();
    let finished_text: Vec<Vec<String>> = finished
        .iter()
        .map(|&(first, count)| text_of(&core, first, count))
        .collect();
    core.resize(40, 16);
    common::check(&core);
    let after = core.snapshot().unwrap();
    for (index, &(first, count)) in finished.iter().enumerate() {
        let block = &after.blocks[index];
        assert_eq!(
            text_of(&core, block.first_row, block.row_count),
            finished_text[index]
        );
        assert_eq!((block.first_row, block.row_count), (first, count));
    }
    let open = after.blocks.last().unwrap();
    assert_eq!(after.row_text(open.first_row as usize).trim_end(), "$");
}

#[test]
fn the_older_output_floor_and_first_stable_row_survive_a_prompt_resize() {
    let mut core = TerminalCore::with_limits(40, vt_core::Limits::rows_only(20)).unwrap();
    core.resize(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..60).map(|i| format!("line {i}\r\n")).collect();
    run(&mut core, "seq", &output);
    core.feed(b"\x1b]7000;v=1;older=3\x07");
    prompt(&mut core, "$ ");
    let first = core.first_stable_row();
    let older = core.older_state();
    core.resize(40, 16);
    common::check(&core);
    assert_eq!(core.first_stable_row(), first);
    assert_eq!(core.older_state(), older);
    core.resize(25, 8);
    common::check(&core);
    assert!(core.first_stable_row() >= first);
}

#[test]
fn an_older_output_chunk_still_lands_after_a_prompt_resize_pulled_every_row_back() {
    let mut mirror = TerminalCore::with_limits(
        40,
        vt_core::Limits {
            rows: 50,
            bytes: usize::MAX,
        },
    )
    .unwrap();
    mirror.set_reflow_on_resize(false);
    mirror.resize(40, 3);
    mirror.set_cold_ring_bytes(1 << 20);
    let numbered: String = (0..200).map(|i| format!("row {i:05}\r\n")).collect();
    mirror.feed(numbered.as_bytes());
    let origin = mirror.first_stable_row();
    let mut pane = TerminalCore::new(40, 10_000).unwrap();
    pane.resize(40, 6);
    pane.feed(format!("\x1b]7000;v=1;origin={origin}\x1b\\").as_bytes());
    prompt(&mut pane, "$ ");
    run(&mut pane, "echo", "one\r\ntwo\r\nthree\r\n");
    prompt(&mut pane, "$ ");
    pane.resize(40, 12);
    common::check(&pane);
    assert_eq!(pane.history_rows(), 0);
    let chunk = mirror
        .older_chunk(origin, 8, 1 << 20)
        .expect("the mirror has older rows");
    pane.feed(&chunk.bytes);
    common::check(&pane);
    assert_eq!(pane.first_stable_row(), origin - 8);
    let rows = texts(&pane);
    let expected: Vec<String> = (origin - 8..origin)
        .map(|row| format!("row {row:05}"))
        .collect();
    assert_eq!(rows[..8].to_vec(), expected);
    assert_eq!(rows.iter().filter(|row| row.as_str() == "three").count(), 1);
}

fn older_rows_after_the_chunk_scrolls_away(
    pull: bool,
) -> Vec<(String, Vec<(u32, vt_core::CellStyle)>)> {
    let mut mirror = TerminalCore::with_limits(
        40,
        vt_core::Limits {
            rows: 50,
            bytes: usize::MAX,
        },
    )
    .unwrap();
    mirror.set_reflow_on_resize(false);
    mirror.resize(40, 3);
    mirror.set_cold_ring_bytes(1 << 20);
    let numbered: String = (0..200)
        .map(|i| format!("\x1b[32mrow {i:05}\x1b[0m\r\n"))
        .collect();
    mirror.feed(numbered.as_bytes());
    let origin = mirror.first_stable_row();
    let mut pane = TerminalCore::new(40, 10_000).unwrap();
    pane.resize(40, 6);
    pane.feed(format!("\x1b]7000;v=1;origin={origin}\x1b\\").as_bytes());
    prompt(&mut pane, "$ ");
    run(&mut pane, "echo", "one\r\ntwo\r\nthree\r\n");
    prompt(&mut pane, "$ ");
    if pull {
        pane.resize(40, 12);
    }
    let chunk = mirror
        .older_chunk(origin, 4, 1 << 20)
        .expect("the mirror has older rows");
    pane.feed(&chunk.bytes);
    pane.feed(b"\x1b]7000;v=1;input-released=1\x07\x1b[H\x1b[31mQ\x1b[0m");
    for _ in 0..14 {
        pane.feed(b"\r\nx");
    }
    common::check(&pane);
    let snapshot = pane.snapshot().unwrap();
    (0..snapshot.row_count())
        .filter(|&row| snapshot.row_text(row).starts_with("row "))
        .map(|row| {
            (
                snapshot.row_text(row).to_string(),
                snapshot.row_style_pairs(row).to_vec(),
            )
        })
        .collect()
}

#[test]
fn an_older_output_chunk_keeps_its_styles_after_a_prompt_resize_pulled_every_row_back() {
    let unpulled = older_rows_after_the_chunk_scrolls_away(false);
    assert_eq!(unpulled.len(), 4);
    assert!(unpulled.iter().all(|(_, runs)| runs.len() == 1));
    assert_eq!(older_rows_after_the_chunk_scrolls_away(true), unpulled);
}
