mod common;

use vt_core::TerminalCore;

const WIDE: &str = "abcd\u{65e5}";

fn primary(setup: impl Fn(&mut TerminalCore), input: &str) -> String {
    let mut core = TerminalCore::new(6, 100).unwrap();
    core.resize(6, 4);
    setup(&mut core);
    core.feed(input.as_bytes());
    core.resize(5, 4);
    common::check(&core);
    let snapshot = core.snapshot().unwrap();
    let row = core.history_rows();
    assert!(
        snapshot.row_cell_spans(row).is_empty(),
        "{:?}",
        snapshot.row_cell_spans(row)
    );
    snapshot.row_text(row).trim_end().to_string()
}

#[test]
fn a_mirror_resize_blanks_a_wide_lead_cut_from_its_continuation() {
    for graphemes in [false, true] {
        let text = primary(
            |core| {
                core.set_reflow_on_resize(false);
                core.set_grapheme_clusters(graphemes);
            },
            WIDE,
        );
        assert_eq!(text, "abcd");
    }
}

#[test]
fn an_agent_tui_resize_blanks_a_wide_lead_cut_from_its_continuation() {
    let text = primary(|core| core.set_agent_tui_mode(true), WIDE);
    assert_eq!(text, "abcd");
}

#[test]
fn a_resize_with_a_scroll_region_blanks_a_wide_lead_cut_from_its_continuation() {
    let text = primary(|_| {}, &format!("\x1b[1;3r\x1b[H{WIDE}"));
    assert_eq!(text, "abcd");
}

#[test]
fn an_alternate_screen_resize_blanks_a_wide_lead_cut_from_its_continuation() {
    let mut core = TerminalCore::new(6, 100).unwrap();
    core.resize(6, 4);
    core.feed(format!("\x1b[?1049h{WIDE}").as_bytes());
    core.resize(5, 4);
    common::check(&core);
    let alt = core.alt_grid().expect("alt grid");
    let row: String = (0..alt.cols()).map(|col| alt.cell(0, col).ch).collect();
    assert_eq!(row.trim_end(), "abcd");
}
