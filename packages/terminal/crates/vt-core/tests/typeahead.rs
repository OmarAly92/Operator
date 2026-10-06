use vt_core::{LineEditorState, TerminalCore};

const READY: &[u8] = b"\x1b]7000;v=1;input-ready=1\x07";
const RELEASED: &[u8] = b"\x1b]7000;v=1;input-released=1\x07";
const TYPED: &[u8] = b"\x1b]7000;v=1;typeahead=echo%20caf%c3%a9\x07";

fn core() -> TerminalCore {
    TerminalCore::new(80, 100).expect("valid terminal dimensions")
}

#[test]
fn a_typeahead_after_input_ready_is_taken_once() {
    let mut c = core();
    c.feed(READY);
    c.feed(TYPED);
    assert_eq!(c.take_typeahead().as_deref(), Some("echo café"));
    assert_eq!(c.take_typeahead(), None);
}

#[test]
fn a_typeahead_in_the_same_mark_chunk_as_input_ready_is_kept() {
    let mut c = core();
    c.feed(&[READY, TYPED].concat());
    assert_eq!(c.take_typeahead().as_deref(), Some("echo café"));
}

#[test]
fn a_typeahead_while_a_program_owns_the_tty_is_ignored() {
    let mut c = core();
    c.feed(READY);
    c.feed(RELEASED);
    c.feed(TYPED);
    assert_eq!(c.take_typeahead(), None);
}

#[test]
fn a_typeahead_before_any_shell_mark_is_ignored() {
    let mut c = core();
    c.feed(TYPED);
    assert_eq!(c.line_editor_state(), LineEditorState::Unknown);
    assert_eq!(c.take_typeahead(), None);
}

#[test]
fn input_released_drops_a_typeahead_nobody_took() {
    let mut c = core();
    c.feed(READY);
    c.feed(TYPED);
    c.feed(RELEASED);
    assert_eq!(c.take_typeahead(), None);
}

#[test]
fn the_alternate_screen_drops_and_ignores_typeahead() {
    let mut c = core();
    c.feed(READY);
    c.feed(TYPED);
    c.feed(b"\x1b[?1049h");
    assert_eq!(c.take_typeahead(), None);
    c.feed(READY);
    c.feed(TYPED);
    assert_eq!(c.take_typeahead(), None);
}

#[test]
fn an_empty_typeahead_is_nothing() {
    let mut c = core();
    c.feed(READY);
    c.feed(b"\x1b]7000;v=1;typeahead=\x07");
    assert_eq!(c.take_typeahead(), None);
}

#[test]
fn a_typeahead_mark_changes_no_block_and_no_row() {
    let block = b"\x1b]133;A\x07\x1b]7000;v=1;id=t-1;cmd=sleep%201\x1b\\\x1b]133;C\x07done\r\n\x1b]7000;v=1;id=t-1;exit=0\x1b\\\x1b]133;D;0\x07\x1b]133;A\x07";
    let mut plain = core();
    plain.feed(block);
    plain.feed(READY);
    let mut typed = core();
    typed.feed(block);
    typed.feed(READY);
    typed.feed(TYPED);
    let a = plain.snapshot().expect("snapshot");
    let b = typed.snapshot().expect("snapshot");
    assert_eq!(a.content, b.content);
    assert_eq!(a.rows, b.rows);
    assert_eq!(a.blocks.len(), b.blocks.len());
    assert_eq!(a.block_command(0), "sleep 1");
    assert_eq!(b.block_command(0), "sleep 1");
}

#[test]
fn the_claude_code_recording_never_yields_a_typeahead() {
    let recording = std::fs::read(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../bench/agent-session/fixtures/claude-spinner-10s/recording"),
    )
    .expect("recording");
    let mut c = TerminalCore::new(120, 1000).expect("valid terminal dimensions");
    c.feed(&recording);
    assert_eq!(c.line_editor_state(), LineEditorState::Unknown);
    assert_eq!(c.take_typeahead(), None);
    c.feed(TYPED);
    assert_eq!(c.take_typeahead(), None);
}
