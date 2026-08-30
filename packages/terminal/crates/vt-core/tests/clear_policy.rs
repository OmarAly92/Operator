use vt_core::TerminalCore;

#[test]
fn clear_on_the_primary_screen_pushes_the_viewport_into_scrollback() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 5);
    core.feed(b"keep me\r\n");
    core.feed(b"\x1b[2J\x1b[H");
    let snapshot = core.snapshot().unwrap();
    let found = (0..snapshot.row_count()).any(|i| snapshot.row_text(i).trim_end() == "keep me");
    assert!(found, "clear must scroll history away, not destroy it");
}

#[test]
fn clear_on_the_alternate_screen_destroys_nothing_and_saves_nothing() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.resize(20, 5);
    core.feed(b"before\r\n");
    let before = core.snapshot().unwrap().row_count();
    core.feed(b"\x1b[?1049htui text\x1b[2J\x1b[?1049l");
    assert_eq!(core.snapshot().unwrap().row_count(), before);
}
