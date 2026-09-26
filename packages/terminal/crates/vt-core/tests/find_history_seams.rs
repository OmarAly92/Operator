mod common;

use vt_core::{FindQuery, FindSession, Limits, TerminalCore};

const READY: &str = "\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07";

fn hits(core: &TerminalCore, session: &FindSession) -> Vec<(u64, usize)> {
    core.find_results(session)
        .iter()
        .map(|hit| (hit.row, hit.start))
        .collect()
}

fn fresh_hits(core: &TerminalCore, needle: &str) -> Vec<(u64, usize)> {
    let mut session = FindSession::new(FindQuery::literal(needle));
    core.find_update(&mut session, usize::MAX);
    hits(core, &session)
}

#[test]
fn a_history_chunk_prepended_after_a_front_trim_is_searched() {
    let mut mirror = TerminalCore::with_limits(40, Limits::rows_only(10)).unwrap();
    mirror.set_reflow_on_resize(false);
    mirror.resize(40, 5);
    mirror.set_cold_ring_bytes(1 << 20);
    let mut pane = TerminalCore::with_limits(40, Limits::rows_only(10)).unwrap();
    pane.resize(40, 5);
    let older: String = (0..10).map(|i| format!("needle {i:02}\r\n")).collect();
    let lines: String = (0..10).map(|i| format!("hay {i:02}\r\n")).collect();
    let newer: String = (10..20).map(|i| format!("row {i:02}\r\n")).collect();
    mirror.feed(format!("{older}{newer}").as_bytes());
    pane.feed(format!("{lines}{newer}").as_bytes());
    let mut session = FindSession::new(FindQuery::literal("needle"));
    assert!(pane.find_update(&mut session, usize::MAX).complete);
    let more: String = (20..23).map(|i| format!("row {i:02}\r\n")).collect();
    mirror.feed(more.as_bytes());
    pane.feed(more.as_bytes());
    let chunk = mirror
        .older_chunk(pane.first_stable_row(), 2, 1 << 20)
        .expect("the mirror has older rows");
    pane.feed(&chunk.bytes);
    common::check(&pane);
    pane.find_update(&mut session, usize::MAX);
    let fresh = fresh_hits(&pane, "needle");
    assert_eq!(fresh.len(), 2);
    assert_eq!(hits(&pane, &session), fresh);
}

#[test]
fn a_find_session_stays_exact_after_more_prompt_resizes_than_the_cut_list_holds() {
    let mut core = TerminalCore::new(40, 1_000_000).unwrap();
    core.resize(40, 10);
    let mut session = FindSession::new(FindQuery::literal("needle"));
    for i in 0..1_500 {
        core.feed(
            format!(
                "\x1b]133;A\x07$ {READY}x\r\n\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07needle {i}\r\nhay\r\n\x1b]133;D;0\x07\x1b]133;A\x07$ {READY}"
            )
            .as_bytes(),
        );
        core.resize(40, 12);
        core.resize(40, 10);
        if i % 97 == 0 {
            core.find_update(&mut session, usize::MAX);
        }
    }
    common::check(&core);
    assert!(core.find_update(&mut session, usize::MAX).complete);
    assert_eq!(hits(&core, &session), fresh_hits(&core, "needle"));
    assert_eq!(fresh_hits(&core, "needle").len(), 1_500);
}
