use vt_core::TerminalCore;

fn core() -> TerminalCore {
    let mut core = TerminalCore::new(80, 100).unwrap();
    core.resize(80, 24);
    core
}

#[test]
fn a_fresh_core_does_not_bracket_a_paste() {
    assert!(!core().bracketed_paste());
}

#[test]
fn bracketed_paste_follows_2004() {
    let mut core = core();
    core.feed(b"\x1b[?2004h");
    assert!(core.bracketed_paste());
    core.feed(b"\x1b[?2004l");
    assert!(!core.bracketed_paste());
}

#[test]
fn leaving_the_alt_screen_does_not_clear_the_mode() {
    let mut core = core();
    core.feed(b"\x1b[?2004h\x1b[?1049h");
    assert!(core.bracketed_paste());
    core.feed(b"\x1b[?1049l");
    assert!(core.bracketed_paste());
}
