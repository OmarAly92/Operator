use vt_core::{LineEditorState, TerminalCore};

fn core() -> TerminalCore {
    let mut core = TerminalCore::new(80, 100).expect("core");
    core.resize(80, 24);
    core
}

fn alt_row(core: &TerminalCore, row: usize) -> String {
    core.alt_grid()
        .expect("alt grid is active")
        .row_text(row)
        .trim_end()
        .to_string()
}

#[test]
fn bytes_go_to_the_alt_grid_only_while_it_is_active() {
    let mut c = core();
    c.feed(b"normal\n");
    assert!(c.alt_grid().is_none());
    c.feed(b"\x1b[?1049h");
    c.feed(b"inside");
    assert_eq!(alt_row(&c, 0), "inside");
    c.feed(b"\x1b[?1049l");
    assert!(c.alt_grid().is_none());
}

#[test]
fn the_normal_buffer_is_untouched_by_what_the_alt_screen_printed() {
    let mut c = core();
    c.feed(b"before\n");
    c.feed(b"\x1b[?1049hinside\x1b[?1049l");
    c.feed(b"after\n");
    let snapshot = c.snapshot().expect("snapshot");
    let text: Vec<&str> = (0..snapshot.row_count()).map(|i| snapshot.row_text(i)).collect();
    assert!(text.contains(&"before"));
    assert!(text.contains(&"after"));
    assert!(!text.iter().any(|row| row.contains("inside")));
}

#[test]
fn entering_the_alt_screen_starts_from_a_blank_grid() {
    let mut c = core();
    c.feed(b"\x1b[?1049hfirst\x1b[?1049l");
    c.feed(b"\x1b[?1049h");
    assert_eq!(alt_row(&c, 0), "");
}

#[test]
fn a_repeated_enter_while_already_inside_does_not_blank_the_screen() {
    let mut c = core();
    c.feed(b"\x1b[?1049hkeep me");
    c.feed(b"\x1b[?1049h");
    assert_eq!(alt_row(&c, 0), "keep me");
}

#[test]
fn cursor_addressing_inside_the_alt_screen_lands_where_it_says() {
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[3;5Hx");
    assert_eq!(c.alt_grid().expect("alt").cell(2, 4).ch, 'x');
}

#[test]
fn carriage_return_is_no_longer_a_no_op_inside_the_alt_screen() {
    let mut c = core();
    c.feed(b"\x1b[?1049habcd\rXY");
    assert_eq!(alt_row(&c, 0), "XYcd");
}

#[test]
fn carriage_return_is_still_a_no_op_in_the_normal_buffer() {
    let mut c = core();
    c.feed(b"abcd\rXY\n");
    let snapshot = c.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "abcdXY");
}

#[test]
fn erase_in_display_clears_the_screen_the_way_a_tui_expects() {
    let mut c = core();
    c.feed(b"\x1b[?1049hjunk\x1b[H\x1b[2Jclean");
    assert_eq!(alt_row(&c, 0), "clean");
}

#[test]
fn a_scroll_region_and_a_line_feed_scroll_only_the_region() {
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[2;3r\x1b[2;1Htop\x1b[3;1Hbottom\x1b[3;1H\n");
    assert_eq!(alt_row(&c, 1), "bottom");
}

#[test]
fn sgr_inside_the_alt_screen_colours_the_cells_it_precedes() {
    use vt_core::StyleCode;
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[31mR\x1b[0mD");
    let alt = c.alt_grid().expect("alt");
    assert_eq!(alt.cell(0, 0).style, StyleCode::ansi(1));
    assert_eq!(alt.cell(0, 1).style, StyleCode::DEFAULT);
}

#[test]
fn the_cursor_can_be_hidden_and_shown() {
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[?25l");
    assert!(!c.alt_grid().expect("alt").cursor_visible());
    c.feed(b"\x1b[?25h");
    assert!(c.alt_grid().expect("alt").cursor_visible());
}

#[test]
fn blocks_recorded_before_entering_survive_the_alt_screen_byte_for_byte() {
    let mut c = core();
    c.feed(b"\x1b]133;A\x07\x1b]7000;v=1;cmd=ls\x07out\n\x1b]133;D;0\x07");
    let before = c.snapshot().expect("snapshot");
    let blocks_before: Vec<_> = before
        .blocks
        .iter()
        .map(|b| (b.id, b.first_row, b.row_count, b.exit_code))
        .collect();

    c.feed(b"\x1b[?1049h");
    c.feed(b"\x1b]133;A\x07\x1b]133;D;1\x07garbage");
    c.feed(b"\x1b[?1049l");

    let after = c.snapshot().expect("snapshot");
    let blocks_after: Vec<_> = after
        .blocks
        .iter()
        .map(|b| (b.id, b.first_row, b.row_count, b.exit_code))
        .collect();
    assert_eq!(blocks_before, blocks_after);
}

#[test]
fn ownership_stays_released_inside_the_alt_screen() {
    let mut c = core();
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    c.feed(b"\x1b[?1049h");
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Released);
}

#[test]
fn application_cursor_keys_is_tracked_and_survives_leaving_the_alt_screen() {
    let mut c = core();
    assert!(!c.application_cursor_keys());
    c.feed(b"\x1b[?1049h\x1b[?1h");
    assert!(c.application_cursor_keys());
    c.feed(b"\x1b[?1049l");
    assert!(c.application_cursor_keys());
    c.feed(b"\x1b[?1l");
    assert!(!c.application_cursor_keys());
}

#[test]
fn the_recorded_agent_cli_first_frame_parses_the_way_the_spec_says() {
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[22;0;0t\x1b[?1h\x1b=\x1b[H\x1b[2J");
    assert!(c.alt_grid().is_some());
    assert!(c.application_cursor_keys());
    assert_eq!(c.alt_grid().expect("alt").cursor(), (0, 0));
    assert_eq!(alt_row(&c, 0), "");
}

#[test]
fn a_sequence_split_across_two_feeds_still_switches() {
    let mut c = core();
    c.feed(b"\x1b[?10");
    c.feed(b"49h");
    c.feed(b"split");
    assert_eq!(alt_row(&c, 0), "split");
}

#[test]
fn the_snapshot_carries_the_alt_grid_only_while_it_is_active() {
    let mut c = core();
    assert!(c.snapshot().expect("snapshot").alt.is_none());
    c.feed(b"\x1b[?1049h\x1b[2;3Hhi");
    let snapshot = c.snapshot().expect("snapshot");
    let alt = snapshot.alt.as_ref().expect("alt snapshot");
    assert_eq!(alt.rows, 24);
    assert_eq!(alt.cols, 80);
    assert_eq!(alt.cursor_row, 1);
    assert_eq!(alt.cursor_col, 4);
    let (start, end) = alt.row_ranges[1];
    let text = std::str::from_utf8(&alt.content[start as usize..end as usize]).expect("utf-8");
    assert_eq!(text.trim_end(), "  hi");
}

#[test]
fn every_alt_row_ends_its_style_runs_at_the_row_length() {
    let mut c = core();
    c.feed(b"\x1b[?1049h\x1b[31mred\x1b[0m tail");
    let snapshot = c.snapshot().expect("snapshot");
    let alt = snapshot.alt.as_ref().expect("alt snapshot");
    for row in 0..alt.rows {
        let (row_start, row_end) = alt.row_ranges[row];
        let (pair_start, pair_end) = alt.run_ranges[row];
        assert!(pair_end > pair_start, "row {row} has no style runs");
        let last = alt.style_pairs[pair_end as usize - 1].0;
        assert_eq!(last, row_end - row_start, "row {row} runs stop short");
    }
}

#[test]
fn the_alt_snapshot_never_grows_past_one_screen() {
    let mut c = core();
    c.resize(10, 3);
    c.feed(b"\x1b[?1049h");
    for i in 0..50 {
        c.feed(format!("line {i}\r\n").as_bytes());
    }
    let snapshot = c.snapshot().expect("snapshot");
    assert_eq!(snapshot.alt.as_ref().expect("alt").row_ranges.len(), 3);
}
