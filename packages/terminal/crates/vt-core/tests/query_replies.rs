use vt_core::TerminalCore;

#[test]
fn decrqm_2026_is_answered_as_supported_and_reset() {
    let mut core = TerminalCore::new(80, 100).unwrap();
    core.set_answers_queries(true);
    core.feed(b"\x1b[?2026$p");
    assert_eq!(core.take_query_replies(), b"\x1b[?2026;2$y");
    assert!(core.take_query_replies().is_empty());
}

#[test]
fn decrqm_reports_tracked_modes_and_rejects_unknown_ones() {
    let mut core = TerminalCore::new(80, 100).unwrap();
    core.set_answers_queries(true);
    core.feed(b"\x1b[?2004h\x1b[?2004$p\x1b[?1006$p\x1b[?9999$p");
    assert_eq!(
        core.take_query_replies(),
        b"\x1b[?2004;1$y\x1b[?1006;2$y\x1b[?9999;0$y"
    );
}

#[test]
fn a_core_that_does_not_answer_queries_collects_nothing() {
    let mut core = TerminalCore::new(80, 100).unwrap();
    core.feed(b"\x1b[?2026$p");
    assert!(core.take_query_replies().is_empty());
}

#[test]
fn a_query_inside_a_sync_block_is_answered_when_the_block_flushes() {
    let mut core = TerminalCore::new(80, 100).unwrap();
    core.set_answers_queries(true);
    core.feed_at(b"\x1b[?2026h\x1b[?2026$p", 0);
    assert!(core.take_query_replies().is_empty());
    core.feed_at(b"\x1b[?2026l", 1);
    assert_eq!(core.take_query_replies(), b"\x1b[?2026;2$y");
}

#[test]
fn xtversion_is_answered_with_the_host_identity() {
    let mut core = TerminalCore::new(80, 100).unwrap();
    core.set_answers_queries(true);
    core.feed(b"\x1b[>0q");
    assert!(
        core.take_query_replies().is_empty(),
        "no identity, no answer"
    );
    core.set_terminal_identity("Example 1.2");
    core.feed(b"\x1b[>0q");
    assert_eq!(core.take_query_replies(), b"\x1bP>|Example 1.2\x1b\\");
}

#[test]
fn da1_is_answered_as_a_vt220_with_ansi_colour() {
    let mut core = TerminalCore::new(80, 100).unwrap();
    core.set_answers_queries(true);
    core.feed(b"\x1b[c\x1b[0c");
    assert_eq!(core.take_query_replies(), b"\x1b[?62;22c\x1b[?62;22c");
}

#[test]
fn a_claude_code_probe_round_is_answered_in_order() {
    let mut core = TerminalCore::new(80, 100).unwrap();
    core.set_answers_queries(true);
    core.set_terminal_identity("Example");
    core.feed(b"\x1b[>0q\x1b[?u\x1b[c");
    assert_eq!(
        core.take_query_replies(),
        b"\x1bP>|Example\x1b\\\x1b[?62;22c"
    );
}
