use std::path::PathBuf;

use vt_core::{TerminalCore, UnknownSequence, UNKNOWN_SEQUENCES_CAP, UNKNOWN_TEXT_BYTES};

fn core() -> TerminalCore {
    let mut core = TerminalCore::new(40, 100).expect("core");
    core.resize(40, 10);
    core
}

fn texts(core: &TerminalCore) -> Vec<(String, u32)> {
    core.unknown_sequences()
        .into_iter()
        .map(|UnknownSequence { text, count }| (text, count))
        .collect()
}

#[test]
fn sequences_the_terminal_handles_are_not_recorded() {
    let mut core = core();
    core.feed(
        b"plain\x1b[1;31;4:3;58;5;9mstyled\x1b[0m\r\n\x1b[2;3H\x1b[K\x1b[2J\x1b[5@\x1b[3P\x1b[4X",
    );
    core.feed(b"\x1b[A\x1b[B\x1b[C\x1b[D\x1b[E\x1b[F\x1b[G\x1b[d\x1b[2L\x1b[M\x1b[S\x1b[T\x1b[2;5r\x1b[r\x1b[s\x1b[u");
    core.feed(b"\x1b[c\x1b[>q\x1b[?2026$p\x1b[14t\x1b[16t\x1b[18t\x1b[22;0t\x1b[23;0t\x1b[22;1t");
    core.feed(
        b"\x1b[?1h\x1b[?25l\x1b[?25h\x1b[?1000;1002;1003;1004;1006;2004h\x1b[?2048h\x1b[?2048l",
    );
    core.feed(b"\x1b[?2026h\x1b[?2026l\x1b[?1049h\x1b[?1049l\x1b7\x1b8\x1bD\x1bE\x1bM\x1bc");
    core.feed(b"\x1b]0;title\x07\x1b]2;title\x1b\\\x1b]1;icon\x07\x1b]8;;https://a.example\x1b\\x\x1b]8;;\x1b\\");
    core.feed(b"\x1b]9;note\x07\x1b]777;notify;t;b\x07\x1b]99;;k\x1b\\\x1b]10;?\x07\x1b]11;?\x07\x1b]22;text\x07");
    core.feed(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]7;file://h/tmp\x07\x1b]7000;v=1;cmd=ls\x07");
    assert_eq!(texts(&core), Vec::<(String, u32)>::new());
}

#[test]
fn an_unhandled_private_sequence_is_recorded_with_how_often_it_came() {
    let mut core = core();
    core.feed(b"\x1b[>1u\x1b[?u\x1b[>1u\x1b[>4;2m");
    assert_eq!(
        texts(&core),
        vec![
            ("CSI ?0u".to_string(), 1),
            ("CSI >1u".to_string(), 2),
            ("CSI >4;2m".to_string(), 1),
        ]
    );
}

#[test]
fn a_private_mode_set_is_recorded_only_when_it_names_an_unknown_mode() {
    let mut core = core();
    core.feed(b"\x1b[?25;1h\x1b[?25;7727h\x1b[?47l");
    assert_eq!(
        texts(&core),
        vec![
            ("CSI ?25;7727h".to_string(), 1),
            ("CSI ?47l".to_string(), 1)
        ]
    );
}

#[test]
fn escape_dcs_and_other_osc_sequences_are_recorded_without_their_payload() {
    let mut core = core();
    core.feed(b"\x1b(0\x1b#8\x1b=\x1bP+q544e\x1b\\\x1b]52;c;U0VDUkVU\x07\x1b]1337;SetMark\x07");
    let got = texts(&core);
    assert_eq!(
        got,
        vec![
            ("ESC (0".to_string(), 1),
            ("ESC #8".to_string(), 1),
            ("ESC =".to_string(), 1),
            ("DCS +0q".to_string(), 1),
            ("OSC 52".to_string(), 1),
            ("OSC 1337".to_string(), 1),
        ]
    );
    assert!(got.iter().all(|(text, _)| !text.contains("U0VD")));
}

#[test]
fn a_sequence_split_byte_by_byte_is_recorded_once() {
    let mut core = core();
    for byte in b"ab\x1b[>1ucd\x1b]52;c;x\x07" {
        core.feed(std::slice::from_ref(byte));
    }
    assert_eq!(
        texts(&core),
        vec![("CSI >1u".to_string(), 1), ("OSC 52".to_string(), 1)]
    );
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "abcd");
}

#[test]
fn the_ring_keeps_the_newest_distinct_sequences_up_to_its_cap() {
    let mut core = core();
    for index in 0..UNKNOWN_SEQUENCES_CAP + 6 {
        core.feed(format!("\x1b[>{index}u").as_bytes());
    }
    let got = texts(&core);
    assert_eq!(got.len(), UNKNOWN_SEQUENCES_CAP);
    assert_eq!(got[0].0, "CSI >6u");
    assert_eq!(
        got.last().map(|entry| entry.0.clone()),
        Some(format!("CSI >{}u", UNKNOWN_SEQUENCES_CAP + 5))
    );
    core.feed(b"\x1b[>6u");
    assert_eq!(texts(&core).last(), Some(&("CSI >6u".to_string(), 2)));
}

#[test]
fn an_oversized_sequence_is_cut_and_marked_as_overflowing() {
    let mut core = core();
    let mut long = b"\x1b[".to_vec();
    for index in 0..40 {
        long.extend_from_slice(format!("{index};").as_bytes());
    }
    long.extend_from_slice(b"99z");
    core.feed(&long);
    let got = texts(&core);
    assert_eq!(got.len(), 1);
    assert!(got[0].0.starts_with("overflow CSI 0;1;2;"), "{}", got[0].0);
    assert_eq!(got[0].0.len(), UNKNOWN_TEXT_BYTES);
}

#[test]
fn clearing_empties_the_ring() {
    let mut core = core();
    core.feed(b"\x1b[>1u");
    core.clear_unknown_sequences();
    assert!(core.unknown_sequences().is_empty());
}

#[test]
fn the_claude_code_recordings_leave_eight_unhandled_sequences() {
    let fixtures =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../bench/agent-session/fixtures");
    let mut seen = Vec::new();
    for name in [
        "claude-spinner-10s",
        "claude-markdown-reply",
        "claude-long-50k",
    ] {
        let bytes = std::fs::read(fixtures.join(name).join("recording")).expect("recording");
        let mut core = TerminalCore::new(120, 200_000).expect("core");
        core.resize(120, 40);
        core.feed(&bytes);
        for entry in core.unknown_sequences() {
            if !seen.contains(&entry.text) {
                seen.push(entry.text);
            }
        }
    }
    seen.sort();
    assert_eq!(
        seen,
        vec![
            "CSI <0u",
            "CSI >4;2m",
            "CSI >4m",
            "CSI >5u",
            "CSI ?0u",
            "CSI ?2031h",
            "CSI ?2031l",
            "ESC (B",
        ]
    );
}
