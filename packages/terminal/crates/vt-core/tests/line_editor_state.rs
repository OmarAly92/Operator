use vt_core::{LineEditorState, TerminalCore};

fn core() -> TerminalCore {
    TerminalCore::new(80, 100).expect("valid terminal dimensions")
}

#[test]
fn starts_unknown_because_no_shell_has_spoken_yet() {
    assert_eq!(core().line_editor_state(), LineEditorState::Unknown);
}

#[test]
fn input_ready_takes_ownership_and_input_released_gives_it_back() {
    let mut c = core();
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Owned);
    c.feed(b"\x1b]7000;v=1;input-released=1\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Released);
}

#[test]
fn entering_the_alt_screen_releases_ownership_even_while_owned() {
    let mut c = core();
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    c.feed(b"\x1b[?1049h");
    assert_eq!(c.line_editor_state(), LineEditorState::Released);
}

#[test]
fn input_ready_inside_the_alt_screen_does_not_take_ownership() {
    let mut c = core();
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    c.feed(b"\x1b[?1049h");
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Released);
    c.feed(b"\x1b[?1049l");
    assert_eq!(c.line_editor_state(), LineEditorState::Released);
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Owned);
}

#[test]
fn leaving_the_alt_screen_does_not_invent_ownership() {
    let mut c = core();
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    c.feed(b"\x1b[?1049h");
    c.feed(b"\x1b[?1049l");
    assert_eq!(c.line_editor_state(), LineEditorState::Released);
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Owned);
}

#[test]
fn a_tier_one_only_session_stays_unknown_forever() {
    let mut c = core();
    c.feed(b"\x1b]133;A\x07ls\x1b]133;C\x07out\n\x1b]133;D;0\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Unknown);
}
