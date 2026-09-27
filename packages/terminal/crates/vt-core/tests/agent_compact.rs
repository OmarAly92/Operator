use vt_core::activity::compact::{
    cap_lines, compact_lines, is_spinner_line, COMPACT_REDRAW_LOOKBACK,
};
use vt_core::TerminalCore;

fn strings(lines: &[&str]) -> Vec<String> {
    lines.iter().map(|line| line.to_string()).collect()
}

#[test]
fn spinner_lines_are_recognised_and_finished_lines_are_not() {
    for line in [
        "✽ Flambéing… (13s · still thinking with high effort)",
        "· Thinking…",
        "  ⠋ Installing dependencies...",
        "◐ Loading…",
    ] {
        assert!(is_spinner_line(line), "{line:?}");
    }
    for line in [
        "✻ Baked for 11s · done 6:13 PM",
        "- Installing dependencies...",
        "* item one…",
        "Thinking…",
        "✻",
        "· Linking... done in 3.2s",
        "⠿ Container db  Started... healthy",
    ] {
        assert!(!is_spinner_line(line), "{line:?}");
    }
}

#[test]
fn compact_lines_matches_the_typescript_cases() {
    assert_eq!(
        compact_lines(&["", "a   ", "", "", "b", "", ""]),
        strings(&["a", "", "b"])
    );
    assert_eq!(
        compact_lines(&["✽ Working… (3s)", "result", "✻ Worked for 3s"]),
        strings(&["result", "✻ Worked for 3s"])
    );
    assert_eq!(
        compact_lines(&["banner", "banner", "body"]),
        strings(&["banner", "body"])
    );
    let frame = ["╭───╮", "│ > │", "╰───╯"];
    let separated: Vec<&str> = frame
        .iter()
        .copied()
        .chain(["between"])
        .chain(frame)
        .chain(["after"])
        .collect();
    assert_eq!(compact_lines(&separated), strings(&separated));
    assert_eq!(
        compact_lines(&["a", "b", "x", "a", "b"]),
        strings(&["a", "b", "x", "a", "b"])
    );
    let filler: Vec<String> = (0..COMPACT_REDRAW_LOOKBACK)
        .map(|index| format!("filler {index}"))
        .collect();
    let mut far: Vec<String> = strings(&["one", "two", "three"]);
    far.extend(filler);
    far.extend(strings(&["one", "two", "three"]));
    assert_eq!(compact_lines(&far), far);
    let steps = [
        "test a", "setup", "run", "teardown", "test b", "setup", "run", "teardown",
    ];
    assert_eq!(compact_lines(&steps), strings(&steps));
    let redrawn: Vec<&str> = frame
        .iter()
        .copied()
        .chain(frame)
        .chain(frame)
        .chain(["after"])
        .collect();
    assert_eq!(
        compact_lines(&redrawn),
        strings(&["╭───╮", "│ > │", "╰───╯", "after"])
    );
    assert_eq!(
        compact_lines(&["a", "", "b", "x", "a", "", "b"]),
        strings(&["a", "", "b", "x", "a", "", "b"])
    );
}

#[test]
fn cap_lines_keeps_the_head_and_the_tail_around_one_marker() {
    let lines: Vec<String> = (0..10).map(|index| format!("line {index}")).collect();
    assert_eq!(
        cap_lines(&lines, 5),
        strings(&[
            "line 0",
            "line 1",
            "… 6 lines omitted …",
            "line 8",
            "line 9"
        ])
    );
    assert_eq!(cap_lines(&lines, 10), lines);
    assert!(cap_lines(&lines, 0).is_empty());
    assert_eq!(cap_lines(&lines, 1), strings(&["… 10 lines omitted …"]));
    assert_eq!(
        cap_lines(&lines, 2),
        strings(&["line 0", "… 9 lines omitted …"])
    );
}

#[test]
fn the_tail_is_the_newest_logical_lines_compacted_and_capped() {
    let mut core = TerminalCore::new(20, 1_000).expect("core");
    core.resize(20, 10);
    core.feed(b"first line\r\n");
    core.feed(b"a line long enough to wrap twice here\r\n");
    core.feed("✽ Working… (3s)\r\n".as_bytes());
    core.feed(b"last line\r\n");
    assert_eq!(
        core.tail_output(100, true, 10),
        "first line\na line long enough to wrap twice here\nlast line"
    );
    assert_eq!(
        core.tail_output(100, true, 2),
        "first line\n… 2 lines omitted …"
    );
    assert_eq!(core.tail_output(1, false, 10), "");
}
