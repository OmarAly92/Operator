use vt_core::TerminalCore;

fn core() -> TerminalCore {
    let mut core = TerminalCore::new(80, 100).unwrap();
    core.resize(80, 24);
    core
}

#[test]
fn a_fresh_core_reports_no_mouse_tracking() {
    let core = core();
    assert!(!core.sgr_mouse());
    assert!(!core.mouse_tracking());
}

#[test]
fn sgr_mouse_follows_1006() {
    let mut core = core();
    core.feed(b"\x1b[?1006h");
    assert!(core.sgr_mouse());
    core.feed(b"\x1b[?1006l");
    assert!(!core.sgr_mouse());
}

#[test]
fn tracking_follows_1000_1002_and_1003() {
    for mode in [b"1000".as_slice(), b"1002".as_slice(), b"1003".as_slice()] {
        let mut core = core();
        let mut on = b"\x1b[?".to_vec();
        on.extend_from_slice(mode);
        let mut off = on.clone();
        on.push(b'h');
        off.push(b'l');
        core.feed(&on);
        assert!(core.mouse_tracking(), "mode {mode:?} did not enable tracking");
        core.feed(&off);
        assert!(!core.mouse_tracking(), "mode {mode:?} did not disable tracking");
    }
}

#[test]
fn the_modes_survive_entering_the_alternate_screen() {
    let mut core = core();
    core.feed(b"\x1b[?1049h\x1b[?1006h\x1b[?1002h");
    assert!(core.sgr_mouse());
    assert!(core.mouse_tracking());
}

#[test]
fn the_real_tmux_attach_prologue_enables_both() {
    let mut core = core();
    core.feed(b"\x1b[?1049h\x1b[22;0;0t\x1b[?1h\x1b=\x1b[H\x1b[2J\x1b[?12l\x1b[?25h");
    core.feed(b"\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l\x1b[?1005l");
    assert!(!core.sgr_mouse(), "tmux resets the modes before enabling them");
    core.feed(b"\x1b[?2004h\x1b[?2031h\x1b[?1006h\x1b[?1000h\x1b[?1002h");
    assert!(core.sgr_mouse());
    assert!(core.mouse_tracking());
}
