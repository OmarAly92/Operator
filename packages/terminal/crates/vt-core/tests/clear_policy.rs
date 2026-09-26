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

fn rows(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    (0..snapshot.row_count())
        .map(|i| snapshot.row_text(i).trim_end().to_string())
        .filter(|row| !row.is_empty())
        .collect()
}

const ECHO_BLOCK: &[u8] = b"\x1b]133;A\x07\x1b]133;B\x07echo one; echo two\r\n\x1b]7000;v=1;cmd=echo%20one\x1b\\\x1b]133;C\x07one\r\ntwo\r\n\x1b]133;D;0\x07";
const CLEAR_BLOCK: &[u8] = b"\x1b]133;A\x07\x1b]133;B\x07clear\r\n\x1b]7000;v=1;cmd=clear\x1b\\\x1b]133;C\x07\x1b[3J\x1b[H\x1b[2J\x1b]133;D;0\x07";

#[test]
fn erasing_saved_lines_never_blanks_the_rows_of_a_finished_block() {
    let mut core = TerminalCore::new(40, 1000).unwrap();
    core.resize(40, 10);
    core.feed(ECHO_BLOCK);
    core.feed(CLEAR_BLOCK);
    assert_eq!(rows(&core), ["echo one; echo two", "one", "two", "clear"]);
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn erasing_saved_lines_without_blocks_still_blanks_the_screen() {
    let mut core = TerminalCore::new(40, 1000).unwrap();
    core.resize(40, 10);
    core.feed(b"UNDERLINED\r\n$ clear\r\n\x1b[3J\x1b[H\x1b[2J$ ");
    assert_eq!(rows(&core), ["$"]);
}
