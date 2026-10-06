use vt_core::program::{
    pointer_shape_css, ProgramNotification, MAX_PENDING_NOTIFICATIONS, MAX_TITLE_BYTES,
    TITLE_STACK_MAX_DEPTH,
};
use vt_core::TerminalCore;

fn core() -> TerminalCore {
    TerminalCore::new(80, 1_000).expect("core")
}

fn note(title: &str, body: &str) -> ProgramNotification {
    ProgramNotification {
        title: title.to_string(),
        body: body.to_string(),
    }
}

#[test]
fn osc_0_and_osc_2_set_the_title_and_the_latest_wins() {
    let mut core = core();
    assert_eq!(core.title(), "");
    core.feed(b"\x1b]0;first\x07");
    assert_eq!(core.title(), "first");
    core.feed(b"\x1b]2;second\x1b\\");
    assert_eq!(core.title(), "second");
}

#[test]
fn a_title_keeps_its_semicolons() {
    let mut core = core();
    core.feed(b"\x1b]2;a;b;c\x07");
    assert_eq!(core.title(), "a;b;c");
}

#[test]
fn an_empty_title_clears_it() {
    let mut core = core();
    core.feed(b"\x1b]2;busy\x07\x1b]2;\x07");
    assert_eq!(core.title(), "");
}

#[test]
fn osc_1_icon_name_leaves_the_title_alone() {
    let mut core = core();
    core.feed(b"\x1b]2;kept\x07\x1b]1;icon\x07");
    assert_eq!(core.title(), "kept");
}

#[test]
fn a_title_drops_control_characters_and_survives_invalid_utf8() {
    let mut core = core();
    core.feed(b"\x1b]2;a\x7fb\xffc\x07");
    assert_eq!(core.title(), "ab\u{fffd}c");
}

#[test]
fn a_title_is_capped_at_the_byte_limit_on_a_character_boundary() {
    let mut core = core();
    let mut sequence = b"\x1b]2;".to_vec();
    sequence.extend("é".repeat(MAX_TITLE_BYTES).as_bytes());
    sequence.push(0x07);
    core.feed(&sequence);
    assert!(core.title().len() <= MAX_TITLE_BYTES);
    assert!(core.title().chars().all(|ch| ch == 'é' || ch == '\u{fffd}'));
}

#[test]
fn a_title_split_across_feeds_lands_once_complete() {
    let mut core = core();
    core.feed(b"\x1b]0;half");
    assert_eq!(core.title(), "");
    core.feed(b" done\x07");
    assert_eq!(core.title(), "half done");
}

#[test]
fn the_program_generation_moves_only_when_something_changed() {
    let mut core = core();
    let start = core.program_generation();
    core.feed(b"\x1b]2;same\x07");
    let once = core.program_generation();
    assert_ne!(once, start);
    core.feed(b"\x1b]2;same\x07");
    assert_eq!(core.program_generation(), once);
    core.feed(b"plain text\r\n");
    assert_eq!(core.program_generation(), once);
}

#[test]
fn xtwinops_22_and_23_push_and_pop_the_title() {
    let mut core = core();
    core.feed(b"\x1b]2;outer\x07\x1b[22;0t\x1b]2;inner\x07");
    assert_eq!(core.title(), "inner");
    core.feed(b"\x1b[23;0t");
    assert_eq!(core.title(), "outer");
    core.feed(b"\x1b[22t\x1b]2;again\x07\x1b[23;2t");
    assert_eq!(core.title(), "outer");
}

#[test]
fn a_pop_on_an_empty_stack_changes_nothing() {
    let mut core = core();
    core.feed(b"\x1b]2;alone\x07\x1b[23;0t");
    assert_eq!(core.title(), "alone");
    assert_eq!(core.title_stack_depth(), 0);
}

#[test]
fn the_icon_only_push_is_ignored() {
    let mut core = core();
    core.feed(b"\x1b]2;title\x07\x1b[22;1t");
    assert_eq!(core.title_stack_depth(), 0);
}

#[test]
fn the_title_stack_stops_growing_at_its_cap_and_drops_the_oldest() {
    let mut core = core();
    core.feed(b"\x1b]2;oldest\x07\x1b[22;0t");
    for index in 0..TITLE_STACK_MAX_DEPTH + 10 {
        core.feed(format!("\x1b]2;t{index}\x07\x1b[22;0t").as_bytes());
    }
    assert_eq!(core.title_stack_depth(), TITLE_STACK_MAX_DEPTH);
    for _ in 0..TITLE_STACK_MAX_DEPTH {
        core.feed(b"\x1b[23;0t");
    }
    assert_eq!(core.title_stack_depth(), 0);
    assert_ne!(core.title(), "oldest");
    assert_eq!(core.title(), "t10");
}

#[test]
fn osc_9_raises_a_notification_with_its_text_as_the_body() {
    let mut core = core();
    core.feed(b"\x1b]9;build done\x07");
    assert_eq!(core.take_notifications(), vec![note("", "build done")]);
    assert!(core.take_notifications().is_empty());
}

#[test]
fn osc_9_keeps_semicolons_in_the_body() {
    let mut core = core();
    core.feed(b"\x1b]9;a;b\x1b\\");
    assert_eq!(core.take_notifications(), vec![note("", "a;b")]);
}

#[test]
fn osc_9_conemu_commands_are_not_notifications() {
    let mut core = core();
    core.feed(b"\x1b]9;4;1;50\x07\x1b]9;1;100\x07\x1b]9;12\x07\x1b]9;9;/tmp\x07");
    assert!(core.take_notifications().is_empty());
    core.feed(b"\x1b]9;13 is a message\x07");
    assert_eq!(core.take_notifications(), vec![note("", "13 is a message")]);
}

#[test]
fn an_empty_osc_9_raises_nothing() {
    let mut core = core();
    core.feed(b"\x1b]9;\x07\x1b]9\x07");
    assert!(core.take_notifications().is_empty());
}

#[test]
fn osc_777_notify_carries_a_title_and_a_body() {
    let mut core = core();
    core.feed(b"\x1b]777;notify;Build;finished;ok\x07");
    assert_eq!(
        core.take_notifications(),
        vec![note("Build", "finished;ok")]
    );
}

#[test]
fn osc_777_without_notify_or_a_title_is_ignored() {
    let mut core = core();
    core.feed(b"\x1b]777;preexec\x07\x1b]777;notify\x07\x1b]777;other;a;b\x07");
    assert!(core.take_notifications().is_empty());
}

#[test]
fn osc_99_single_part_is_a_title() {
    let mut core = core();
    core.feed(b"\x1b]99;;Hello\x1b\\");
    assert_eq!(core.take_notifications(), vec![note("Hello", "")]);
}

#[test]
fn osc_99_collects_title_and_body_across_parts_of_one_id() {
    let mut core = core();
    core.feed(b"\x1b]99;i=1:d=0;Title\x1b\\");
    assert!(core.take_notifications().is_empty());
    core.feed(b"\x1b]99;i=1:d=0:p=body;Body \x1b\\");
    core.feed(b"\x1b]99;i=1:p=body;text\x1b\\");
    assert_eq!(core.take_notifications(), vec![note("Title", "Body text")]);
}

#[test]
fn osc_99_a_new_id_drops_the_unfinished_one() {
    let mut core = core();
    core.feed(b"\x1b]99;i=1:d=0;Lost\x1b\\\x1b]99;i=2;Kept\x1b\\");
    assert_eq!(core.take_notifications(), vec![note("Kept", "")]);
}

#[test]
fn osc_99_encoded_and_unknown_payload_types_are_ignored() {
    let mut core = core();
    core.feed(b"\x1b]99;e=1;SGVsbG8=\x1b\\\x1b]99;p=icon;x\x1b\\\x1b]99;p=?;\x1b\\");
    assert!(core.take_notifications().is_empty());
}

#[test]
fn pending_notifications_are_capped_and_the_oldest_is_dropped() {
    let mut core = core();
    for index in 0..MAX_PENDING_NOTIFICATIONS + 3 {
        core.feed(format!("\x1b]9;n{index}\x07").as_bytes());
    }
    let taken = core.take_notifications();
    assert_eq!(taken.len(), MAX_PENDING_NOTIFICATIONS);
    assert_eq!(taken[0], note("", "n3"));
}

#[test]
fn osc_22_records_a_css_pointer_shape() {
    let mut core = core();
    core.feed(b"\x1b]22;pointer\x07");
    assert_eq!(core.pointer_shape(), "pointer");
    core.feed(b"\x1b]22;xterm\x07");
    assert_eq!(core.pointer_shape(), "text");
}

#[test]
fn osc_22_ignores_an_unknown_shape_and_an_empty_one_resets() {
    let mut core = core();
    core.feed(b"\x1b]22;crosshair\x07\x1b]22;nonsense\x07");
    assert_eq!(core.pointer_shape(), "crosshair");
    core.feed(b"\x1b]22;\x07");
    assert_eq!(core.pointer_shape(), "");
}

#[test]
fn every_css_and_x11_pointer_name_maps_to_a_css_keyword() {
    assert_eq!(pointer_shape_css("left_ptr"), Some("default"));
    assert_eq!(pointer_shape_css("fleur"), Some("all-scroll"));
    assert_eq!(pointer_shape_css("zoom-out"), Some("zoom-out"));
    assert_eq!(pointer_shape_css("Pointer"), None);
}

#[test]
fn a_process_boundary_clears_the_title_stack_and_pointer() {
    let mut core = core();
    core.feed(b"\x1b]2;old\x07\x1b[22;0t\x1b]22;wait\x07");
    core.feed(b"\x1b]7000;v=1;boundary=0\x07");
    assert_eq!(core.title(), "");
    assert_eq!(core.title_stack_depth(), 0);
    assert_eq!(core.pointer_shape(), "");
}

#[test]
fn a_history_chunk_never_changes_the_title_or_raises_a_notification() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\live\r\n");
    core.feed(b"\x1b]2;live title\x07");
    core.feed(b"\x1b]7000;v=1;history=998,2\x1b\\");
    core.feed(b"\x1b]2;old title\x07one\r\n\x1b]9;old\x07\x1b]22;wait\x07two\r\n");
    assert_eq!(core.first_stable_row(), 998);
    assert_eq!(core.title(), "live title");
    assert!(core.take_notifications().is_empty());
    assert_eq!(core.pointer_shape(), "");
}

#[test]
fn a_title_inside_a_sync_block_lands_when_the_block_flushes() {
    let mut core = core();
    core.feed_at(b"\x1b[?2026h\x1b]0;framed\x07", 0);
    assert_eq!(core.title(), "");
    core.feed_at(b"\x1b[?2026l", 1);
    assert_eq!(core.title(), "framed");
}

#[test]
fn the_claude_code_recording_ends_on_its_idle_title() {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../bench/agent-session/fixtures/claude-long-50k/recording"
    );
    let recording = std::fs::read(path).expect("recording");
    let mut core = TerminalCore::new(120, 10_000).expect("core");
    core.resize(120, 40);
    core.set_agent_tui_mode(true);
    let start = core.program_generation();
    core.feed(&recording);
    assert_eq!(core.title(), "\u{2733} Number list 1 to 3000");
    assert_eq!(core.program_generation().wrapping_sub(start), 1_047);
    assert!(core.take_notifications().is_empty());
}
