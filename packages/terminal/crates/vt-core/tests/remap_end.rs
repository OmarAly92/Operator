mod common;

use vt_core::{Limits, TerminalCore};

fn agent_core() -> TerminalCore {
    let mut core = TerminalCore::with_limits(20, Limits::rows_only(100)).unwrap();
    core.resize(20, 3);
    core.set_agent_tui_mode(true);
    core.feed(b"aaaaaaaaaabbbbbbbbbbcccccccccc\r\ntail\r\nx\r\nzeta");
    core.take_delta();
    core.take_remap_end();
    core
}

#[test]
fn a_rewrap_reports_where_the_rows_after_the_rewrapped_ones_went() {
    let mut core = agent_core();
    assert_eq!(core.history_rows(), 2);
    assert_eq!(core.snapshot().unwrap().row_text(4), "zeta");
    core.resize(40, 3);
    let delta = core.take_delta();
    assert_eq!(delta.remap, Some(vec![(0, 0), (1, 0)]));
    assert_eq!(core.take_remap_end(), Some((2, 1)));
    assert_eq!(core.snapshot().unwrap().row_text(3), "zeta");
    common::check(&core);
}

#[test]
fn two_rewraps_before_a_take_compose_into_one_end() {
    let mut core = agent_core();
    core.resize(40, 3);
    core.resize(10, 3);
    core.take_delta();
    assert_eq!(core.take_remap_end(), Some((2, 3)));
    assert_eq!(core.snapshot().unwrap().row_text(5), "zeta");
    common::check(&core);
}

#[test]
fn output_without_a_width_change_has_no_remap_end() {
    let mut core = agent_core();
    core.feed(b"\r\nmore\r\n");
    core.take_delta();
    assert_eq!(core.take_remap_end(), None);
}

#[test]
fn taking_the_end_leaves_nothing_behind() {
    let mut core = agent_core();
    core.resize(40, 3);
    core.take_delta();
    assert!(core.take_remap_end().is_some());
    assert_eq!(core.take_remap_end(), None);
}
