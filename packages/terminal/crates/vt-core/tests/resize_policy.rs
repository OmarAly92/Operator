use vt_core::TerminalCore;

#[test]
fn resizing_an_agent_tui_appends_no_frame_to_scrollback() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.set_agent_tui_mode(true);
    core.feed(b"\x1b[Hframe one\x1b[K");
    let before = core.snapshot().unwrap().row_count();
    core.resize(100, 30);
    core.resize(80, 24);
    assert_eq!(
        core.snapshot().unwrap().row_count(),
        before,
        "a resize must not push the pre-resize frame into scrollback",
    );
}

#[test]
fn resizing_a_shell_still_keeps_its_scrollback() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 3);
    core.feed(b"one\r\ntwo\r\nthree\r\nfour\r\n");
    let before = core.snapshot().unwrap().row_count();
    core.resize(80, 5);
    assert!(core.snapshot().unwrap().row_count() >= before);
}
