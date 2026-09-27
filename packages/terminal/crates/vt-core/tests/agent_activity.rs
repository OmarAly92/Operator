use vt_core::activity::input_patterns::detects_high_confidence_input_pattern;
use vt_core::activity::{AgentActivity, ACTIVITY_IDLE_AFTER_MS, ACTIVITY_POLLING_AFTER_MS};
use vt_core::TerminalCore;

fn core() -> TerminalCore {
    let mut core = TerminalCore::new(80, 1_000).expect("core");
    core.resize(80, 24);
    core
}

#[test]
fn the_vscode_patterns_match_what_they_matched_in_typescript() {
    for line in [
        "Overwrite existing file? (y/n) ",
        "Continue? [Y/n] ",
        "Proceed (yes/no) ",
        "Ok to proceed? (y) ",
        "package name: (demo) ",
        "(END)",
        "[sudo] password for dev:",
        "Press any key to continue",
        "? Pick a color ❯ ",
        "[~] $ ",
    ] {
        assert!(
            detects_high_confidence_input_pattern(line),
            "{line:?} should match"
        );
    }
    for line in [
        "❯ ",
        "❯\u{a0}",
        "$ ",
        "➜  repo git:(main) ",
        "Last Command: ",
        "✻ Baked for 11s · done 6:13 PM",
        "  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents",
    ] {
        assert!(
            !detects_high_confidence_input_pattern(line),
            "{line:?} should not match"
        );
    }
}

#[test]
fn the_cursor_line_is_padded_in_cells_to_the_cursor() {
    let mut core = core();
    core.feed("继续吗 [y/n]".as_bytes());
    assert_eq!(core.cursor_line_text(), "继续吗 [y/n]");
    core.feed(b"\x1b[2C");
    assert_eq!(core.cursor_line_text(), "继续吗 [y/n]  ");
}

#[test]
fn the_cursor_line_of_the_alternate_screen_is_read_while_it_is_active() {
    let mut core = core();
    core.feed(b"primary\r\n\x1b[?1049hContinue? [Y/n] ");
    assert_eq!(core.cursor_line_text(), "Continue? [Y/n] ");
    assert!(core.cursor_line_prompts());
}

#[test]
fn activity_follows_the_quiet_time() {
    let mut core = core();
    core.feed(b"working on it");
    assert_eq!(core.agent_activity(Some(0)), AgentActivity::Active);
    assert_eq!(
        core.agent_activity(Some(ACTIVITY_POLLING_AFTER_MS - 1)),
        AgentActivity::Active
    );
    assert_eq!(
        core.agent_activity(Some(ACTIVITY_POLLING_AFTER_MS)),
        AgentActivity::PollingForIdle
    );
    assert_eq!(
        core.agent_activity(Some(ACTIVITY_IDLE_AFTER_MS - 1)),
        AgentActivity::PollingForIdle
    );
    assert_eq!(
        core.agent_activity(Some(ACTIVITY_IDLE_AFTER_MS)),
        AgentActivity::Idle
    );
    assert_eq!(core.agent_activity(None), AgentActivity::Idle);
}

#[test]
fn a_question_needs_a_prompt_on_the_cursor_line_not_just_silence() {
    let mut core = core();
    core.feed(b"compiling crate 12 of 40");
    assert_eq!(core.agent_activity(Some(40_000)), AgentActivity::Idle);
    core.feed(b"\r\nOverwrite greet.py? (y/n) ");
    assert_eq!(core.agent_activity(Some(100)), AgentActivity::Active);
    assert_eq!(
        core.agent_activity(Some(ACTIVITY_POLLING_AFTER_MS)),
        AgentActivity::Prompting
    );
    assert_eq!(core.agent_activity(Some(60_000)), AgentActivity::Prompting);
}

#[test]
fn a_prompt_the_shell_line_editor_owns_is_not_a_question() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;input-ready=1\x07[~] $ ");
    assert!(!core.cursor_line_prompts());
    assert_eq!(
        core.agent_activity(Some(ACTIVITY_POLLING_AFTER_MS)),
        AgentActivity::PollingForIdle
    );
    core.feed(b"\x1b]7000;v=1;input-released=1\x07\r\nOverwrite greet.py? (y/n) ");
    assert!(core.cursor_line_prompts());
}

#[test]
fn the_wire_values_are_stable() {
    assert_eq!(AgentActivity::Active.wire(), 0);
    assert_eq!(AgentActivity::PollingForIdle.wire(), 1);
    assert_eq!(AgentActivity::Idle.wire(), 2);
    assert_eq!(AgentActivity::Prompting.wire(), 3);
}

fn fixture(name: &str) -> (Vec<u8>, Vec<(usize, usize, usize)>) {
    let dir = format!(
        "{}/../../bench/agent-session/fixtures/{name}",
        env!("CARGO_MANIFEST_DIR")
    );
    let recording = std::fs::read(format!("{dir}/recording")).expect("recording");
    let sizes: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(format!("{dir}/size.json")).expect("size.json"),
    )
    .expect("json");
    let sizes = sizes
        .as_array()
        .expect("array")
        .iter()
        .map(|size| {
            (
                size["offset"].as_u64().expect("offset") as usize,
                size["cols"].as_u64().expect("cols") as usize,
                size["rows"].as_u64().expect("rows") as usize,
            )
        })
        .collect();
    (recording, sizes)
}

#[test]
fn no_frame_of_the_claude_code_recordings_prompts() {
    const ESU: &[u8] = b"\x1b[?2026l";
    for name in [
        "claude-spinner-10s",
        "claude-markdown-reply",
        "claude-long-50k",
    ] {
        let (recording, sizes) = fixture(name);
        let mut core = TerminalCore::new(sizes[0].1, 200_000).expect("core");
        core.resize(sizes[0].1, sizes[0].2);
        let mut ends: Vec<usize> = recording
            .windows(ESU.len())
            .enumerate()
            .filter(|(_, window)| *window == ESU)
            .map(|(at, _)| at + ESU.len())
            .collect();
        ends.push(recording.len());
        let mut fed = 0;
        let mut next = 1;
        let mut prompts = 0;
        for end in ends {
            while next < sizes.len() && sizes[next].0 <= end {
                core.feed(&recording[fed..sizes[next].0]);
                fed = sizes[next].0;
                core.resize(sizes[next].1, sizes[next].2);
                next += 1;
            }
            core.feed(&recording[fed..end]);
            fed = end;
            if core.cursor_line_prompts() {
                prompts += 1;
            }
        }
        assert_eq!(prompts, 0, "{name}");
    }
}

#[test]
fn a_title_that_only_blinks_is_not_live_output() {
    let mut core = core();
    core.feed(b"working\r\n");
    let live = core.live_output_bytes();
    core.feed(b"\x1b]0;[ ! ] Action Required | Create approved.txt\x07");
    core.feed(b"\x1b]0;[ . ] Action Required | Create approved.txt\x1b\\");
    core.feed(b"\x1b]2;one\x07\x1b]0;two\x07");
    assert_eq!(core.live_output_bytes(), live);
    core.feed(b"\x1b]0;busy\x07x");
    assert_eq!(core.live_output_bytes(), live + 1);
}
