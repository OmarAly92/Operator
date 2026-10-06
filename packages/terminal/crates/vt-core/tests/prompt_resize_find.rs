mod common;

use vt_core::{FindQuery, FindSession, LineEditorState, TerminalCore};

const READY: &str = "\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07";

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

#[test]
fn find_hits_point_at_their_text_after_rows_are_pulled_back() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..30)
        .map(|i| {
            if i % 3 == 0 {
                format!("needle {i}\r\n")
            } else {
                format!("hay {i}\r\n")
            }
        })
        .collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    let mut session = FindSession::new(FindQuery::literal("needle"));
    core.find_update(&mut session, usize::MAX);
    let before = core.find_results(&session).len();
    core.resize(40, 18);
    core.find_update(&mut session, usize::MAX);
    let hits = core.find_results(&session);
    assert_eq!(hits.len(), before);
    let snapshot = core.snapshot().unwrap();
    for hit in hits {
        let flat = core.flat_row(hit.row).expect("hit row still exists");
        assert!(snapshot.row_text(flat).contains("needle"), "row {flat}");
    }
}

#[test]
fn find_hits_stay_on_their_text_when_pulled_rows_are_rewritten_before_the_next_update() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..30)
        .map(|i| {
            if i % 3 == 0 {
                format!("needle {i}\r\n")
            } else {
                format!("hay {i}\r\n")
            }
        })
        .collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    let mut session = FindSession::new(FindQuery::literal("needle"));
    core.find_update(&mut session, usize::MAX);
    core.resize(40, 18);
    core.feed(b"\x1b]7000;v=1;input-released=1\x07\x1b[1;1H");
    for _ in 0..8 {
        core.feed(b"zzzzzzzzzzzzz\x1b[K\r\n");
    }
    core.feed(b"\x1b[18;1H");
    for _ in 0..20 {
        core.feed(b"\r\nmore");
    }
    core.find_update(&mut session, usize::MAX);
    common::check(&core);
    let hits = core.find_results(&session);
    assert_eq!(hits.len(), count(&core, "needle"));
    let snapshot = core.snapshot().unwrap();
    for hit in hits {
        let flat = core.flat_row(hit.row).expect("hit row still exists");
        assert!(
            snapshot.row_text(flat).contains("needle"),
            "row {flat} {:?}",
            snapshot.row_text(flat)
        );
    }
}

#[test]
fn a_prompt_resize_keeps_a_finished_find_session_without_rescanning() {
    let mut core = core(80, 24);
    prompt(&mut core, "$ ");
    let output: String = (0..300).map(|i| format!("needle line {i}\r\n")).collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    let mut session = FindSession::new(FindQuery::literal("needle"));
    assert!(core.find_update(&mut session, usize::MAX).complete);
    let hits = core.find_results(&session).len();
    for (cols, rows) in [
        (79, 24),
        (78, 24),
        (77, 24),
        (80, 24),
        (80, 24),
        (81, 23),
        (80, 22),
    ] {
        let scanned = session.history_bytes_scanned();
        core.resize(cols, rows);
        let update = core.find_update(&mut session, 4096);
        assert!(update.complete, "{cols}x{rows}");
        assert!(
            session.history_bytes_scanned() - scanned < 80,
            "{cols}x{rows}"
        );
        if rows == 24 {
            assert_eq!(update.removed, 0, "{cols}x{rows}");
        }
        assert_eq!(core.find_results(&session).len(), hits, "{cols}x{rows}");
        assert_eq!(hits, count(&core, "needle"), "{cols}x{rows}");
    }
}

#[test]
fn a_taller_prompt_resize_keeps_the_find_hits_below_the_pulled_rows() {
    let mut core = core(80, 24);
    run(&mut core, "seq", &"needle\r\nhay\r\n".repeat(450));
    prompt(&mut core, "$ ");
    let mut session = FindSession::new(FindQuery::literal("needle"));
    assert!(core.find_update(&mut session, usize::MAX).complete);
    let (full, history) = (session.history_bytes_scanned(), core.history_rows());
    core.resize(80, 30);
    let update = core.find_update(&mut session, 256);
    assert!(core.history_rows() < history && update.complete && update.removed < 20);
    assert!(session.history_bytes_scanned() - full < 256);
    let (hits, rows) = (core.find_results(&session), texts(&core));
    assert_eq!(hits.len(), count(&core, "needle"));
    for hit in hits {
        assert!(rows[core.flat_row(hit.row).unwrap()].contains("needle"));
    }
}

fn long_needle_line(tag: usize) -> String {
    format!("{:0>4}{}needle{}", tag, "x".repeat(81), "y".repeat(9))
}

#[test]
fn find_hits_after_a_cut_that_a_rewrap_moved_mid_row_are_rescanned() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..20)
        .map(|i| format!("{}\r\n", long_needle_line(i)))
        .collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    let mut session = FindSession::new(FindQuery::literal("needle"));
    assert!(core.find_update(&mut session, usize::MAX).complete);
    core.resize(40, 11);
    run(&mut core, "true", &"zz\r\n".repeat(30));
    core.resize(60, 11);
    common::check(&core);
    assert!(core.find_update(&mut session, usize::MAX).complete);
    let mut fresh = FindSession::new(FindQuery::literal("needle"));
    core.find_update(&mut fresh, usize::MAX);
    assert_eq!(core.find_results(&session), core.find_results(&fresh));
    assert_eq!(core.find_results(&session).len(), 20);
}
