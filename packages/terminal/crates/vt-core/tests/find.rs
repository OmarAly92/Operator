use vt_core::{FindQuery, TerminalCore};

fn core_with_blocks(count: usize) -> TerminalCore {
    let mut core = TerminalCore::new(40, 10_000).unwrap();
    core.resize(40, 1);
    for index in 0..count {
        core.feed(
            format!("\x1b]133;A\x07\x1b]133;C\x07line {index} of text\x1b]133;D;0\x07\r\n")
                .as_bytes(),
        );
    }
    core
}

#[test]
fn a_literal_query_finds_every_occurrence() {
    let core = core_with_blocks(20);
    let mut cursor = core.find(FindQuery::literal("line 7"));
    while !cursor.is_complete() {
        cursor.step(4);
    }
    assert_eq!(cursor.results().len(), 1);
}

#[test]
fn stepping_respects_the_budget_and_resumes_where_it_stopped() {
    let core = core_with_blocks(100);
    let mut cursor = core.find(FindQuery::literal("line"));
    cursor.step(10);
    assert!(!cursor.is_complete());
    let after_first = cursor.results().len();
    assert!(after_first > 0 && after_first < 100);

    while !cursor.is_complete() {
        cursor.step(10);
    }
    assert_eq!(cursor.results().len(), 100);
}

#[test]
fn a_cancelled_cursor_stops_producing_results() {
    let core = core_with_blocks(50);
    let mut cursor = core.find(FindQuery::literal("line"));
    cursor.step(5);
    let at_cancel = cursor.results().len();
    cursor.cancel();
    cursor.step(50);
    assert_eq!(cursor.results().len(), at_cancel);
    assert!(cursor.is_complete());
}

#[test]
fn an_invalid_regex_is_an_error_not_a_panic() {
    assert!(FindQuery::regex("(unclosed").is_err());
}

#[test]
fn a_valid_regex_matches_across_blocks() {
    let core = core_with_blocks(5);
    let mut cursor = core.find(FindQuery::regex(r"line \d of").unwrap());
    while !cursor.is_complete() {
        cursor.step(2);
    }
    assert_eq!(cursor.results().len(), 5);
}
