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
fn resizing_a_shell_reflows_the_frame_into_scrollback() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.feed(b"\x1b[Hframe one\x1b[K");
    core.resize(100, 30);
    core.resize(80, 24);
    assert_eq!(core.snapshot().unwrap().row_count(), 3);
}

#[test]
fn leaving_agent_tui_mode_restores_clear_and_resize_reflow() {
    let mut core = TerminalCore::new(80, 1000).unwrap();
    core.resize(80, 24);
    core.set_agent_tui_mode(true);
    core.feed(b"\x1b[Hagent frame\x1b[K\x1b[2J");
    assert_eq!(core.snapshot().unwrap().row_text(0), "");
    core.feed(b"\x1b[Hshell frame\x1b[K");
    core.set_agent_tui_mode(false);
    core.resize(100, 30);
    core.resize(80, 24);
    assert_eq!(core.snapshot().unwrap().row_count(), 3);
    core.feed(b"\x1b[2J");
    let snapshot = core.snapshot().unwrap();
    assert!((0..snapshot.row_count()).any(|row| snapshot.row_text(row) == "shell frame"));
}
