use vt_core::agent::{AgentEvent, AgentState, MAX_PENDING_AGENT_EVENTS};
use vt_core::program::ProgramNotification;
use vt_core::TerminalCore;

const VECTORS: &str = include_str!("../../../protocol/agent-vectors/agent-state.json");

struct Case {
    name: String,
    input: Vec<u8>,
    events: Vec<(String, String)>,
}

fn cases() -> Vec<Case> {
    let doc: serde_json::Value = serde_json::from_str(VECTORS).expect("vector file is JSON");
    doc["cases"]
        .as_array()
        .expect("cases")
        .iter()
        .map(|case| Case {
            name: case["name"].as_str().expect("name").to_string(),
            input: case["input"].as_str().expect("input").as_bytes().to_vec(),
            events: case["events"]
                .as_array()
                .expect("events")
                .iter()
                .map(|event| {
                    (
                        event["state"].as_str().expect("state").to_string(),
                        event["detail"].as_str().expect("detail").to_string(),
                    )
                })
                .collect(),
        })
        .collect()
}

fn core() -> TerminalCore {
    TerminalCore::new(80, 1_000).expect("core")
}

fn pairs(events: Vec<AgentEvent>) -> Vec<(String, String)> {
    events
        .into_iter()
        .map(|event| (event.state.as_str().to_string(), event.detail))
        .collect()
}

fn event(state: AgentState, detail: &str) -> AgentEvent {
    AgentEvent {
        state,
        detail: detail.to_string(),
    }
}

#[test]
fn every_vector_case_yields_its_events() {
    let cases = cases();
    assert!(cases.len() >= 20, "expected the full vector table");
    for case in cases {
        let mut core = core();
        core.feed(&case.input);
        assert_eq!(
            pairs(core.take_agent_events()),
            case.events,
            "{}",
            case.name
        );
    }
}

#[test]
fn every_vector_case_split_byte_by_byte_yields_the_same_events() {
    for case in cases() {
        let mut core = core();
        for byte in &case.input {
            core.feed(std::slice::from_ref(byte));
        }
        assert_eq!(
            pairs(core.take_agent_events()),
            case.events,
            "{}",
            case.name
        );
    }
}

#[test]
fn events_are_taken_once() {
    let mut core = core();
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    assert_eq!(core.take_agent_events().len(), 1);
    assert!(core.take_agent_events().is_empty());
}

#[test]
fn an_agent_event_bumps_the_program_generation_and_a_duplicate_does_not() {
    let mut core = core();
    let start = core.program_generation();
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    assert_eq!(core.program_generation().wrapping_sub(start), 1);
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    assert_eq!(core.program_generation().wrapping_sub(start), 1);
}

#[test]
fn a_notify_beside_an_agent_event_still_notifies_and_neither_leaks_into_the_other() {
    let mut core = core();
    core.feed(b"\x1b]777;notify;Build;done\x07\x1b]777;agent-state;v=1;state=done\x07");
    assert_eq!(
        core.take_notifications(),
        vec![ProgramNotification {
            title: "Build".to_string(),
            body: "done".to_string(),
        }]
    );
    assert_eq!(core.take_agent_events(), vec![event(AgentState::Done, "")]);
}

#[test]
fn an_agent_event_prints_nothing() {
    let mut core = core();
    core.feed(b"a\x1b]777;agent-state;v=1;state=idle;detail=hidden\x07b");
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "ab");
}

#[test]
fn a_flood_keeps_only_the_newest_pending_events() {
    let mut core = core();
    for index in 0..10_000 {
        let state = if index % 2 == 0 { "working" } else { "waiting" };
        core.feed(format!("\x1b]777;agent-state;v=1;state={state};detail={index}\x07").as_bytes());
    }
    let events = core.take_agent_events();
    assert_eq!(events.len(), MAX_PENDING_AGENT_EVENTS);
    assert_eq!(events.last(), Some(&event(AgentState::Waiting, "9999")));
    assert_eq!(events[0], event(AgentState::Working, "9984"));
}

#[test]
fn a_flood_of_identical_events_queues_one() {
    let mut core = core();
    for _ in 0..10_000 {
        core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    }
    assert_eq!(
        core.take_agent_events(),
        vec![event(AgentState::Working, "")]
    );
}

#[test]
fn a_process_boundary_lets_the_same_state_fire_again() {
    let mut core = core();
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    core.feed(b"\x1b]7000;v=1;boundary=0\x07");
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    assert_eq!(
        core.take_agent_events(),
        vec![
            event(AgentState::Working, ""),
            event(AgentState::Working, "")
        ]
    );
}

#[test]
fn an_event_inside_a_sync_block_lands_when_the_block_flushes() {
    let mut core = core();
    core.feed_at(b"\x1b[?2026h\x1b]777;agent-state;v=1;state=working\x07", 0);
    assert!(core.take_agent_events().is_empty());
    core.feed_at(b"\x1b[?2026l", 1);
    assert_eq!(
        core.take_agent_events(),
        vec![event(AgentState::Working, "")]
    );
}

#[test]
fn a_history_chunk_never_raises_an_agent_event() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\\x1b]7000;v=1;ready=1\x1b\\live\r\n");
    core.feed(b"\x1b]7000;v=1;history=998,2\x1b\\");
    core.feed(b"\x1b]777;agent-state;v=1;state=waiting\x07one\r\ntwo\x1b]777;agent-state;v=1;state=done\x07\r\n");
    assert_eq!(core.first_stable_row(), 998);
    assert!(core.take_agent_events().is_empty());
}

#[test]
fn an_older_answer_split_byte_by_byte_never_raises_an_agent_event() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\\x1b]7000;v=1;ready=1\x1b\\live\r\n");
    let answer = b"\x1b]7000;v=1;history=998,2;cols=80\x1b\\\x1b]777;agent-state;v=1;state=working\x07one\r\ntwo\r\n\x1b]7000;v=1;older=998\x1b\\";
    for byte in answer {
        core.feed(std::slice::from_ref(byte));
    }
    assert_eq!(core.first_stable_row(), 998);
    assert!(core.take_agent_events().is_empty());
    core.feed(b"\x1b]777;agent-state;v=1;state=idle\x07");
    assert_eq!(core.take_agent_events(), vec![event(AgentState::Idle, "")]);
}

#[test]
fn an_older_answer_landing_inside_a_live_event_keeps_the_live_event() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\\x1b]7000;v=1;ready=1\x1b\\live\r\n");
    core.feed(b"\x1b]777;agent-sta");
    core.feed(
        b"\x1b]7000;v=1;history=998,2;cols=80\x1b\\one\r\ntwo\r\n\x1b]7000;v=1;older=998\x1b\\",
    );
    core.feed(b"te;v=1;state=waiting\x07");
    assert_eq!(core.first_stable_row(), 998);
    assert_eq!(
        core.take_agent_events(),
        vec![event(AgentState::Waiting, "")]
    );
}

#[test]
fn an_event_in_the_replay_frame_is_ignored_and_live_events_after_ready_fire() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\");
    core.feed(b"frame\x1b]777;agent-state;v=1;state=working\x07\r\n");
    assert!(core.take_agent_events().is_empty());
    core.feed(b"\x1b]7000;v=1;ready=1\x1b\\");
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    assert_eq!(
        core.take_agent_events(),
        vec![event(AgentState::Working, "")]
    );
}

#[test]
fn an_origin_mark_after_rows_exist_silences_events_until_ready() {
    let mut core = core();
    core.feed(b"live\r\n\x1b]7000;v=1;origin=9999\x1b\\");
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    assert!(core.take_agent_events().is_empty());
    core.feed(b"\x1b]7000;v=1;ready=1\x1b\\\x1b]777;agent-state;v=1;state=working\x07");
    assert_eq!(
        core.take_agent_events(),
        vec![event(AgentState::Working, "")]
    );
}

#[test]
fn a_replay_into_a_reused_core_is_neither_live_output_nor_an_event() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\\x1b]7000;v=1;ready=1\x1b\\live\r\n");
    let live = core.live_output_bytes();
    core.feed(
        b"\x1b]7000;v=1;origin=1000\x1b\\frame\x1b]777;agent-state;v=1;state=waiting\x07\r\n",
    );
    core.feed(b"\x1b]7000;v=1;ready=1\x1b\\");
    assert_eq!(core.live_output_bytes(), live);
    assert!(core.take_agent_events().is_empty());
    core.feed(b"xy");
    assert_eq!(core.live_output_bytes(), live + 2);
}

#[test]
fn live_output_counts_live_bytes_only() {
    let mut fresh = core();
    assert_eq!(fresh.live_output_bytes(), 0);
    fresh.feed(b"abc");
    assert_eq!(fresh.live_output_bytes(), 3);

    let mut reopened = core();
    reopened.feed(b"\x1b]7000;v=1;origin=1000\x1b\\frame\r\n");
    assert_eq!(reopened.live_output_bytes(), 0);
    reopened.feed(b"\x1b]7000;v=1;ready=1\x1b\\");
    assert_eq!(reopened.live_output_bytes(), 0);
    reopened.feed(b"\x1b]7000;v=1;history=998,2\x1b\\one\r\ntwo\r\n");
    assert_eq!(reopened.first_stable_row(), 998);
    assert_eq!(reopened.live_output_bytes(), 0);
    reopened.feed(b"\x1b]7000;v=1;older=998\x1b\\");
    assert_eq!(reopened.live_output_bytes(), 0);
    reopened.feed(b"xy");
    assert_eq!(reopened.live_output_bytes(), 2);
}

#[test]
fn a_replay_split_byte_by_byte_into_a_reused_core_is_not_live_output() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\\x1b]7000;v=1;ready=1\x1b\\live\r\n");
    let live = core.live_output_bytes();
    let replay = b"\x1b]7000;v=1;origin=1000\x1b\\frame\r\n\x1b]7000;v=1;ready=1\x1b\\";
    for byte in replay {
        core.feed(std::slice::from_ref(byte));
    }
    assert_eq!(core.live_output_bytes(), live);
    core.feed(b"x\x1b]7000;v=1;origin=1000\x1b\\frame\x1b]7000;v=1;ready=1\x1b\\y");
    assert_eq!(core.live_output_bytes(), live + 2);
}

#[test]
fn the_claude_code_recordings_carry_no_agent_event() {
    for name in [
        "claude-spinner-10s",
        "claude-long-50k",
        "claude-markdown-reply",
    ] {
        let path = format!(
            "{}/../../bench/agent-session/fixtures/{name}/recording",
            env!("CARGO_MANIFEST_DIR")
        );
        let recording = std::fs::read(path).expect("recording");
        let mut core = TerminalCore::new(120, 200_000).expect("core");
        core.set_agent_tui_mode(true);
        core.feed(&recording);
        assert!(core.take_agent_events().is_empty(), "{name}");
        assert_eq!(core.live_output_bytes(), recording.len() as u64, "{name}");
    }
}
