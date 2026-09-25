use vt_core::agent::{AgentEvent, AgentState};
use vt_core::program::ProgramNotification;
use vt_wasm::WasmTerminalCore;
use vt_wasm::{flatten_agent_events, flatten_notifications};

#[test]
fn notifications_flatten_to_title_body_pairs_in_order() {
    let flat = flatten_notifications(vec![
        ProgramNotification {
            title: "Build".to_string(),
            body: "done".to_string(),
        },
        ProgramNotification {
            title: String::new(),
            body: "second".to_string(),
        },
    ]);
    assert_eq!(flat, vec!["Build", "done", "", "second"]);
}

#[test]
fn the_wasm_core_exposes_title_pointer_and_notifications() {
    let Ok(mut core) = WasmTerminalCore::new(80, 1_000, 1 << 20) else {
        panic!("core");
    };
    let start = core.program_generation();
    assert!(core
        .feed(
            b"\x1b]0;\xe2\x97\x90 Working\x07\x1b]22;pointer\x07\x1b]9;hi\x07",
            0.0
        )
        .is_ok());
    assert_eq!(core.title(), "\u{25d0} Working");
    assert_eq!(core.pointer_shape(), "pointer");
    assert_eq!(core.take_notifications(), vec!["", "hi"]);
    assert!(core.take_notifications().is_empty());
    assert_eq!(core.program_generation().wrapping_sub(start), 3);
}

#[test]
fn agent_events_flatten_to_state_detail_pairs_in_order() {
    let flat = flatten_agent_events(vec![
        AgentEvent {
            state: AgentState::Waiting,
            detail: "Allow Bash?".to_string(),
        },
        AgentEvent {
            state: AgentState::Done,
            detail: String::new(),
        },
    ]);
    assert_eq!(flat, vec!["waiting", "Allow Bash?", "done", ""]);
}

#[test]
fn the_wasm_core_exposes_agent_events_and_live_output() {
    let Ok(mut core) = WasmTerminalCore::new(80, 1_000, 1 << 20) else {
        panic!("core");
    };
    let start = core.program_generation();
    let bytes = b"ab\x1b]777;agent-state;v=1;state=working;detail=Read\x07";
    assert!(core.feed(bytes, 0.0).is_ok());
    assert_eq!(core.take_agent_events(), vec!["working", "Read"]);
    assert!(core.take_agent_events().is_empty());
    assert_eq!(core.program_generation().wrapping_sub(start), 1);
    assert_eq!(core.live_output_bytes(), bytes.len() as f64);
}

#[test]
fn the_wasm_core_lists_unknown_sequences_with_their_counts() {
    let Ok(mut core) = WasmTerminalCore::new(80, 1_000, 1 << 20) else {
        panic!("core");
    };
    assert!(core.feed(b"\x1b[>1u\x1b[>1u\x1b(0\x1b[31m", 0.0).is_ok());
    assert_eq!(core.unknown_sequences(), vec!["2 CSI >1u", "1 ESC (0"]);
}
