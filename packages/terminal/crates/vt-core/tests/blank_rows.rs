use vt_core::TerminalCore;

fn rows(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    (0..snapshot.row_count())
        .map(|i| snapshot.row_text(i).trim_end().to_string())
        .collect()
}

#[test]
fn a_blank_row_scrolled_off_the_screen_stays_in_the_transcript() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 4);
    core.feed(b"one\r\n\r\ntwo\r\n\r\nthree\r\n\r\nfour\r\n\r\nfive\r\n\r\nsix\r\n");
    assert_eq!(
        rows(&core),
        vec!["one", "", "two", "", "three", "", "four", "", "five", "", "six"]
    );
}

#[test]
fn a_blank_row_survives_in_every_screen_mode() {
    for agent_tui in [false, true] {
        let mut core = TerminalCore::new(20, 1000).unwrap();
        core.set_agent_tui_mode(agent_tui);
        core.resize(20, 3);
        core.feed(b"a\r\n\r\nb\r\n\r\nc\r\n");
        assert_eq!(
            rows(&core),
            vec!["a", "", "b", "", "c"],
            "agent_tui={agent_tui}"
        );
    }
}

#[test]
fn blank_rows_keep_their_place_relative_to_blocks() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 3);
    core.feed(
        b"\x1b]133;A\x07\x1b]133;B\x07cmd\r\n\x1b]133;C\x07out\r\n\r\ntail\r\n\x1b]133;D;0\x07",
    );
    let snapshot = core.snapshot().unwrap();
    assert_eq!(rows(&core), vec!["cmd", "out", "", "tail"]);
    let block = snapshot.blocks.first().expect("one block");
    assert_eq!((block.first_row, block.row_count), (0, 4));
}
