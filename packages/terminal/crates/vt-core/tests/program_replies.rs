use vt_core::TerminalCore;

fn answering(columns: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::new(columns, 1_000).expect("core");
    core.resize(columns, rows);
    core.set_answers_queries(true);
    core.take_query_replies();
    core
}

#[test]
fn xtwinops_18_reports_the_grid_in_cells() {
    let mut core = answering(100, 30);
    core.feed(b"\x1b[18t");
    assert_eq!(core.take_query_replies(), b"\x1b[8;30;100t");
}

#[test]
fn xtwinops_14_and_16_report_pixels_once_the_cell_size_is_known() {
    let mut core = answering(100, 30);
    core.feed(b"\x1b[14t\x1b[16t");
    assert!(
        core.take_query_replies().is_empty(),
        "no cell size, no pixel answer"
    );
    core.set_cell_pixels(9, 18);
    core.feed(b"\x1b[14t\x1b[16t");
    assert_eq!(
        core.take_query_replies(),
        b"\x1b[4;540;900t\x1b[6;18;9t".as_slice()
    );
}

#[test]
fn a_zero_cell_size_forgets_the_pixels() {
    let mut core = answering(80, 24);
    core.set_cell_pixels(8, 16);
    core.set_cell_pixels(0, 16);
    core.feed(b"\x1b[16t");
    assert!(core.take_query_replies().is_empty());
}

#[test]
fn unknown_xtwinops_are_not_answered() {
    let mut core = answering(80, 24);
    core.set_cell_pixels(8, 16);
    core.feed(b"\x1b[11t\x1b[13t\x1b[19t\x1b[21t\x1b[t");
    assert!(core.take_query_replies().is_empty());
}

#[test]
fn a_core_that_does_not_answer_queries_sends_no_size_report() {
    let mut core = TerminalCore::new(80, 1_000).expect("core");
    core.set_cell_pixels(8, 16);
    core.feed(b"\x1b[18t\x1b[16t\x1b[?2048h\x1b]10;?\x07");
    assert!(core.take_query_replies().is_empty());
}

#[test]
fn mode_2048_reports_at_once_when_enabled_and_on_every_resize() {
    let mut core = answering(80, 24);
    core.set_cell_pixels(8, 16);
    core.feed(b"\x1b[?2048h");
    assert_eq!(core.take_query_replies(), b"\x1b[48;24;80;384;640t");
    core.resize(100, 30);
    assert_eq!(core.take_query_replies(), b"\x1b[48;30;100;480;800t");
    core.set_cell_pixels(10, 20);
    assert_eq!(core.take_query_replies(), b"\x1b[48;30;100;600;1000t");
    core.set_cell_pixels(10, 20);
    assert!(core.take_query_replies().is_empty());
}

#[test]
fn mode_2048_stays_quiet_once_reset_and_without_a_cell_size() {
    let mut core = answering(80, 24);
    core.feed(b"\x1b[?2048h");
    assert!(core.take_query_replies().is_empty());
    core.feed(b"\x1b[?2048l");
    core.set_cell_pixels(8, 16);
    core.resize(90, 20);
    assert!(core.take_query_replies().is_empty());
}

#[test]
fn decrqm_reports_mode_2048() {
    let mut core = answering(80, 24);
    core.feed(b"\x1b[?2048$p");
    assert_eq!(core.take_query_replies(), b"\x1b[?2048;2$y");
    core.feed(b"\x1b[?2048h\x1b[?2048$p");
    assert_eq!(core.take_query_replies(), b"\x1b[?2048;1$y");
}

#[test]
fn osc_10_and_11_queries_answer_from_the_default_colours() {
    let mut core = answering(80, 24);
    core.feed(b"\x1b]10;?\x07\x1b]11;?\x1b\\");
    assert!(core.take_query_replies().is_empty(), "no theme, no answer");
    core.set_default_colors(Some(0xd8dee9), Some(0x0a0b0d));
    core.feed(b"\x1b]10;?\x07");
    assert_eq!(core.take_query_replies(), b"\x1b]10;rgb:d8d8/dede/e9e9\x07");
    core.feed(b"\x1b]11;?\x1b\\");
    assert_eq!(
        core.take_query_replies(),
        b"\x1b]11;rgb:0a0a/0b0b/0d0d\x1b\\"
    );
}

#[test]
fn one_osc_10_can_ask_for_foreground_and_background() {
    let mut core = answering(80, 24);
    core.set_default_colors(Some(0xffffff), Some(0x000000));
    core.feed(b"\x1b]10;?;?\x07");
    assert_eq!(
        core.take_query_replies(),
        b"\x1b]10;rgb:ffff/ffff/ffff\x07\x1b]11;rgb:0000/0000/0000\x07".as_slice()
    );
}

#[test]
fn setting_a_dynamic_colour_is_ignored() {
    let mut core = answering(80, 24);
    core.set_default_colors(Some(0xffffff), Some(0x000000));
    core.feed(b"\x1b]10;#ff0000\x07\x1b]11;rgb:00/00/ff\x07\x1b]10;?\x07");
    assert_eq!(core.take_query_replies(), b"\x1b]10;rgb:ffff/ffff/ffff\x07");
}

#[test]
fn a_cleared_colour_is_no_longer_answered() {
    let mut core = answering(80, 24);
    core.set_default_colors(Some(0xffffff), Some(0x000000));
    core.set_default_colors(None, Some(0x000000));
    core.feed(b"\x1b]10;?\x07\x1b]11;?\x07");
    assert_eq!(core.take_query_replies(), b"\x1b]11;rgb:0000/0000/0000\x07");
}

#[test]
fn the_claude_code_cell_size_probe_is_answered() {
    let mut core = answering(120, 40);
    core.set_cell_pixels(8, 17);
    core.feed(b"\x1b[16t");
    assert_eq!(core.take_query_replies(), b"\x1b[6;17;8t");
}
