mod common;

use proptest::prelude::*;
use vt_core::TerminalCore;

#[derive(Debug, Clone)]
enum Op {
    Print(String),
    Newline,
    Sgr(u8),
    Cup(u8, u8),
    Ed(u8),
    El(u8),
    Il(u8),
    Dl(u8),
    Resize(u8, u8),
    PromptStart,
    CommandStart,
    OutputStart,
    CommandEnd(u8),
    Boundary,
    TakeDelta,
}

fn op() -> impl Strategy<Value = Op> {
    prop_oneof![
        4 => "[ -~]{0,40}".prop_map(Op::Print),
        3 => Just(Op::Newline),
        1 => (0u8..=107).prop_map(Op::Sgr),
        1 => ((1u8..=30), (1u8..=100)).prop_map(|(r, c)| Op::Cup(r, c)),
        1 => (0u8..=2).prop_map(Op::Ed),
        1 => (0u8..=2).prop_map(Op::El),
        1 => (1u8..=5).prop_map(Op::Il),
        1 => (1u8..=5).prop_map(Op::Dl),
        1 => ((4u8..=60), (2u8..=20)).prop_map(|(c, r)| Op::Resize(c, r)),
        1 => Just(Op::PromptStart),
        1 => Just(Op::CommandStart),
        1 => Just(Op::OutputStart),
        1 => (0u8..=2).prop_map(Op::CommandEnd),
        1 => Just(Op::Boundary),
        1 => Just(Op::TakeDelta),
    ]
}

fn apply(core: &mut TerminalCore, op: &Op) {
    match op {
        Op::Print(text) => core.feed(text.as_bytes()),
        Op::Newline => core.feed(b"\r\n"),
        Op::Sgr(n) => core.feed(format!("\x1b[{n}m").as_bytes()),
        Op::Cup(r, c) => core.feed(format!("\x1b[{r};{c}H").as_bytes()),
        Op::Ed(n) => core.feed(format!("\x1b[{n}J").as_bytes()),
        Op::El(n) => core.feed(format!("\x1b[{n}K").as_bytes()),
        Op::Il(n) => core.feed(format!("\x1b[{n}L").as_bytes()),
        Op::Dl(n) => core.feed(format!("\x1b[{n}M").as_bytes()),
        Op::Resize(c, r) => core.resize(usize::from(*c), usize::from(*r)),
        Op::PromptStart => core.feed(b"\x1b]133;A\x07"),
        Op::CommandStart => core.feed(b"\x1b]133;B\x07"),
        Op::OutputStart => core.feed(b"\x1b]133;C\x07"),
        Op::CommandEnd(n) => core.feed(format!("\x1b]133;D;{n}\x07").as_bytes()),
        Op::Boundary => core.feed(b"\x1b]7000;v=1;boundary=0\x07"),
        Op::TakeDelta => {
            core.take_delta();
        }
    }
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 256, ..ProptestConfig::default() })]

    #[test]
    fn every_operation_leaves_the_model_consistent(
        agent_tui in any::<bool>(),
        ops in prop::collection::vec(op(), 1..80),
    ) {
        let mut core = TerminalCore::new(40, 32).unwrap();
        core.resize(40, 8);
        core.set_agent_tui_mode(agent_tui);
        common::check(&core);
        for op in &ops {
            apply(&mut core, op);
            common::check(&core);
        }
    }
}

#[test]
fn a_boundary_closed_empty_block_survives_a_shrinking_resize() {
    let mut core = TerminalCore::new(40, 32).unwrap();
    core.resize(40, 8);
    core.set_agent_tui_mode(false);
    core.resize(4, 16);
    core.feed(b"\x1b[16;1H");
    core.feed(b"\x1b]133;A\x07");
    core.feed(b"\x1b]7000;v=1;boundary=0\x07");
    core.resize(4, 2);
    common::check(&core);
}

#[cfg(feature = "trace")]
#[test]
fn trace_records_every_dispatched_action_with_its_stream_offset() {
    use vt_core::trace::TraceAction;
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.feed(b"ab\x1b[31m\r\n");
    core.feed(b"\x1b]133;A\x07c");
    let entries = core.trace();
    let summary: Vec<(u64, String)> = entries
        .iter()
        .map(|entry| {
            let action = match &entry.action {
                TraceAction::Print(c) => format!("print {c}"),
                TraceAction::Execute(b) => format!("execute {b:#04x}"),
                TraceAction::Csi { action, params, .. } => format!("csi {action} {params:?}"),
                TraceAction::Esc { byte, .. } => format!("esc {byte:#04x}"),
                TraceAction::Osc(params) => format!("osc {}", params.len()),
            };
            (entry.offset, action)
        })
        .collect();
    assert_eq!(
        summary,
        vec![
            (0, "print a".to_string()),
            (1, "print b".to_string()),
            (6, "csi m [[31]]".to_string()),
            (7, "execute 0x0d".to_string()),
            (8, "execute 0x0a".to_string()),
            (16, "osc 2".to_string()),
            (17, "print c".to_string()),
        ]
    );
    core.clear_trace();
    assert!(core.trace().is_empty());
}

#[test]
fn a_fresh_core_is_consistent() {
    let core = TerminalCore::new(80, 100).unwrap();
    common::check(&core);
}

#[test]
fn a_trimmed_core_is_consistent() {
    let mut core = TerminalCore::new(20, 4).unwrap();
    core.resize(20, 2);
    for index in 0..50 {
        core.feed(format!("row {index}\r\n").as_bytes());
        common::check(&core);
    }
}

#[test]
fn a_rewrapped_core_is_consistent() {
    let mut core = TerminalCore::new(40, 100).unwrap();
    core.resize(40, 3);
    core.feed(b"- a bullet line that is long enough to need wrapping when narrow\r\nplain\r\n");
    for cols in [12usize, 8, 30, 60] {
        core.resize(cols, 3);
        common::check(&core);
    }
}

#[test]
fn a_block_opened_on_the_screen_survives_a_rewrap_and_a_trim() {
    let ops = vec![
        Op::Print("a0a  0AAaAA AaA".into()),
        Op::Cup(6, 1),
        Op::Print("0".into()),
        Op::Resize(4, 2),
        Op::Cup(1, 4),
        Op::Print("A a0a AAa0aAA aaaa a".into()),
        Op::Boundary,
        Op::Print("AA ".into()),
        Op::Print("A0Aaa".into()),
        Op::PromptStart,
        Op::Print("A A a 0".into()),
        Op::Print("AA a0a aaa Aa AaAA 0AA 00".into()),
        Op::Print(" 0aAAa A0A AaAA0AAAa0Aa a 0aaa".into()),
        Op::Resize(7, 2),
    ];
    let mut core = TerminalCore::new(40, 32).unwrap();
    core.resize(40, 8);
    for op in &ops {
        apply(&mut core, op);
        common::check(&core);
    }
}

#[test]
fn a_trim_past_a_block_that_starts_above_the_cut_does_not_underflow() {
    let ops = vec![
        Op::Cup(3, 1),
        Op::PromptStart,
        Op::CommandEnd(0),
        Op::Boundary,
        Op::PromptStart,
        Op::Cup(8, 27),
        Op::Print("a a0A".into()),
        Op::Newline,
        Op::Newline,
        Op::Print("A".into()),
        Op::Resize(15, 20),
        Op::PromptStart,
        Op::Cup(20, 1),
        Op::Print("AA0 A aaa0Aaa0 !".into()),
        Op::Boundary,
    ];
    let mut core = TerminalCore::new(40, 32).unwrap();
    core.resize(40, 8);
    for op in &ops {
        apply(&mut core, op);
        common::check(&core);
    }
}
