use vt_core::{FindMatch, FindQuery, FindSession, Limits, TerminalCore};

const ALL: usize = usize::MAX;

fn core(columns: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::new(columns, 10_000).unwrap();
    core.resize(columns, rows);
    core
}

fn feed_lines(core: &mut TerminalCore, lines: impl IntoIterator<Item = String>) {
    for line in lines {
        core.feed(format!("{line}\r\n").as_bytes());
    }
}

fn feed_block(core: &mut TerminalCore, text: &str) {
    core.feed(format!("\x1b]133;A\x07\x1b]133;C\x07{text}\x1b]133;D;0\x07\r\n").as_bytes());
}

fn search(core: &TerminalCore, query: FindQuery) -> (FindSession, Vec<FindMatch>) {
    let mut session = FindSession::new(query);
    assert!(core.find_update(&mut session, ALL).complete);
    let hits = core.find_results(&session);
    (session, hits)
}

fn refresh(core: &TerminalCore, session: &mut FindSession) -> Vec<FindMatch> {
    assert!(core.find_update(session, ALL).complete);
    core.find_results(session)
}

fn hit_text(core: &TerminalCore, hit: &FindMatch) -> String {
    let snapshot = core.snapshot().unwrap();
    let first = core.flat_row(hit.row).unwrap();
    let last = core.flat_row(hit.end_row).unwrap();
    let mut text = String::new();
    for flat in first..=last {
        let row = snapshot.row_text(flat);
        let from = if flat == first { hit.start } else { 0 };
        let to = if flat == last { hit.end } else { row.len() };
        text.push_str(&row[from..to]);
    }
    text
}

#[test]
fn every_line_of_a_session_without_marks_is_searched() {
    let mut core = core(40, 5);
    feed_lines(&mut core, (0..20).map(|index| format!("hello {index}")));
    let (_, hits) = search(&core, FindQuery::literal("hello"));
    assert_eq!(hits.len(), 20);
    for hit in &hits {
        assert_eq!(hit_text(&core, hit), "hello");
    }
}

#[test]
fn a_block_that_reaches_into_the_screen_is_searched() {
    let mut core = core(40, 5);
    core.feed(b"\x1b]133;A\x07\x1b]133;C\x07");
    feed_lines(&mut core, (0..20).map(|index| format!("hello {index}")));
    let (_, hits) = search(&core, FindQuery::literal("hello"));
    assert_eq!(hits.len(), 20);
    let block = core.snapshot().unwrap().blocks[0].id;
    assert!(hits.iter().all(|hit| hit.block == block));
}

#[test]
fn history_is_not_rescanned_when_output_arrives() {
    let mut core = core(40, 5);
    feed_lines(
        &mut core,
        (0..50).map(|index| format!("line {index} of text")),
    );
    let (mut session, hits) = search(&core, FindQuery::literal("line"));
    assert_eq!(hits.len(), 50);
    let scanned = session.history_bytes_scanned();
    let history_before = core.snapshot().unwrap().history_rows as usize;
    feed_lines(
        &mut core,
        (50..53).map(|index| format!("line {index} of text")),
    );
    let hits = refresh(&core, &mut session);
    assert_eq!(hits.len(), 53);
    let snapshot = core.snapshot().unwrap();
    let history_after = snapshot.history_rows as usize;
    let settled: usize = (history_before..history_after)
        .map(|flat| snapshot.row_text(flat).len())
        .sum();
    assert!(settled > 0);
    assert_eq!(session.history_bytes_scanned() - scanned, settled as u64);
    assert!(scanned > 10 * settled as u64);
}

#[test]
fn the_screen_is_searched_again_only_when_it_changes() {
    let mut core = core(40, 5);
    feed_lines(&mut core, ["one needle".to_string()]);
    let (mut session, _) = search(&core, FindQuery::literal("needle"));
    let scans = session.screen_scans();
    let quiet = core.find_update(&mut session, ALL);
    assert_eq!((quiet.added, quiet.removed), (0, 0));
    assert_eq!(session.screen_scans(), scans);
    core.feed(b"x");
    core.find_update(&mut session, ALL);
    assert_eq!(session.screen_scans(), scans + 1);
}

#[test]
fn a_hit_on_the_live_screen_follows_the_frame() {
    let mut core = core(40, 3);
    core.feed(b"status: idle");
    let (mut session, hits) = search(&core, FindQuery::literal("idle"));
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].row, core.stable_row(core.history_rows()));
    assert_eq!(hit_text(&core, &hits[0]), "idle");
    core.feed(b"\x1b[H\x1b[2Kstatus: busy");
    let update = core.find_update(&mut session, ALL);
    assert_eq!((update.added, update.removed), (0, 1));
    assert!(core.find_results(&session).is_empty());
    assert_eq!(session.history_bytes_scanned(), 0);
}

#[test]
fn a_match_across_the_scrollback_and_screen_boundary_is_one_hit() {
    let mut core = core(10, 2);
    core.feed(b"123456789NEEDLE\r\n");
    assert_eq!(core.history_rows(), 1);
    let (mut session, hits) = search(&core, FindQuery::literal("NEEDLE"));
    assert_eq!(hits.len(), 1);
    assert_eq!(
        (hits[0].row, hits[0].start, hits[0].end_row, hits[0].end),
        (0, 9, 1, 5)
    );
    assert_eq!(hit_text(&core, &hits[0]), "NEEDLE");
    core.feed(b"a\r\nb\r\n");
    let settled = refresh(&core, &mut session);
    assert_eq!(settled, hits);
    assert!(session.history_bytes_scanned() > 0);
}

#[test]
fn a_rewrap_keeps_every_hit_on_its_text() {
    let mut core = core(30, 3);
    feed_lines(
        &mut core,
        (0..40).map(|index| format!("entry {index} carries the needle word")),
    );
    let (mut session, hits) = search(&core, FindQuery::literal("needle"));
    assert_eq!(hits.len(), 40);
    core.resize(12, 3);
    let hits = refresh(&core, &mut session);
    assert_eq!(hits.len(), 40);
    for hit in &hits {
        assert_eq!(hit_text(&core, hit), "needle");
    }
}

#[test]
fn smart_case_ignores_case_only_for_a_query_without_capitals() {
    let mut core = core(40, 5);
    feed_lines(
        &mut core,
        ["Error one", "error two", "ERROR three"].map(String::from),
    );
    assert_eq!(search(&core, FindQuery::literal("error")).1.len(), 3);
    assert_eq!(search(&core, FindQuery::literal("Error")).1.len(), 1);
    assert_eq!(search(&core, FindQuery::regex("err.r").unwrap()).1.len(), 3);
    assert_eq!(search(&core, FindQuery::regex("ERR.R").unwrap()).1.len(), 1);
}

#[test]
fn a_query_without_capitals_folds_unicode_case() {
    let mut core = core(40, 5);
    feed_lines(&mut core, ["ÉCOLE ouverte".to_string()]);
    let (_, hits) = search(&core, FindQuery::literal("école"));
    assert_eq!(hits.len(), 1);
    assert_eq!(hit_text(&core, &hits[0]), "ÉCOLE");
}

#[test]
fn a_regex_reads_metacharacters_and_a_literal_does_not() {
    let mut core = core(40, 5);
    feed_lines(&mut core, ["a.c abc".to_string()]);
    let (_, literal) = search(&core, FindQuery::literal("a.c"));
    assert_eq!(literal.len(), 1);
    assert_eq!(hit_text(&core, &literal[0]), "a.c");
    assert_eq!(search(&core, FindQuery::regex("a.c").unwrap()).1.len(), 2);
}

#[test]
fn an_invalid_regex_is_an_error_not_a_panic() {
    assert!(FindQuery::regex("(unclosed").is_err());
}

#[test]
fn a_zero_width_pattern_finds_nothing_and_completes() {
    let mut core = core(40, 5);
    feed_lines(&mut core, ["abc".to_string(), "def".to_string()]);
    assert!(search(&core, FindQuery::regex("x*").unwrap()).1.is_empty());
    assert!(search(&core, FindQuery::regex("^").unwrap()).1.is_empty());
}

#[test]
fn the_budget_splits_the_first_scan_and_resumes() {
    let mut core = core(40, 2);
    feed_lines(
        &mut core,
        (0..100).map(|index| format!("line {index} of text")),
    );
    let mut session = FindSession::new(FindQuery::literal("line"));
    let first = core.find_update(&mut session, 64);
    assert!(!first.complete);
    let partial = core.find_results(&session).len();
    assert!(partial > 0 && partial < 100);
    let mut rounds = 0;
    while !core.find_update(&mut session, 64).complete {
        rounds += 1;
        assert!(rounds < 1_000);
    }
    assert_eq!(core.find_results(&session).len(), 100);
}

#[test]
fn hits_keep_their_stable_rows_across_a_trim() {
    let mut core = TerminalCore::with_limits(40, Limits::rows_only(6)).unwrap();
    core.resize(40, 2);
    for line in ["1", "2", "needle", "4"] {
        feed_block(&mut core, line);
    }
    let (mut session, hits) = search(&core, FindQuery::literal("needle"));
    assert_eq!(hits[0].row, 2);
    for line in ["5", "6", "7"] {
        feed_block(&mut core, line);
    }
    let hits = refresh(&core, &mut session);
    assert_eq!(core.first_stable_row(), 1);
    assert_eq!(hits[0].row, 2);
    assert_eq!(hit_text(&core, &hits[0]), "needle");
    for line in 8..20 {
        feed_block(&mut core, &line.to_string());
    }
    let update = core.find_update(&mut session, ALL);
    assert!(update.removed >= 1);
    assert!(core.find_results(&session).is_empty());
}

#[test]
fn a_hit_names_the_block_that_holds_it() {
    let mut core = core(40, 1);
    for text in ["alpha", "needle", "gamma"] {
        feed_block(&mut core, text);
    }
    let (_, hits) = search(&core, FindQuery::literal("needle"));
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].block, core.snapshot().unwrap().blocks[1].id);
}
