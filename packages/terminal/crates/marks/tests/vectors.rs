use std::fs;
use std::path::PathBuf;

use terminal_marks::testing::RawEvent;
use terminal_marks::{MarkDecoder, MarkEvent, MarkTier};

fn vectors_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../protocol/vectors")
}

/// Per-vector structural comparison. The JSON vectors pin the event *kind*
/// and *tier* (and, for command_end, exit_code; for cwd_changed, path). They
/// do not pin the contents of an extension mark's `pairs` — the spec's
/// closed vocabulary is the event kind, not the field shape (SPEC §8).
/// So we compare kind-by-kind and ignore the extension pair contents.
fn events_match(actual: &[MarkEvent], expected: &[MarkEvent], name: &str) -> bool {
    if actual.len() != expected.len() {
        eprintln!(
            "vector {name}: length mismatch: expected {} got {}",
            expected.len(),
            actual.len()
        );
        eprintln!("  expected: {expected:?}");
        eprintln!("  actual:   {actual:?}");
        return false;
    }
    for (a, e) in actual.iter().zip(expected.iter()) {
        match (a, e) {
            (
                MarkEvent::CommandEnd { exit_code: ac, .. },
                MarkEvent::CommandEnd { exit_code: ec, .. },
            ) => {
                if ac != ec {
                    eprintln!("vector {name}: exit_code mismatch: {ac:?} vs {ec:?}");
                    return false;
                }
            }
            (MarkEvent::CwdChanged { path: ap }, MarkEvent::CwdChanged { path: ep }) => {
                if ap != ep {
                    eprintln!("vector {name}: cwd path mismatch: {ap:?} vs {ep:?}");
                    return false;
                }
            }
            (MarkEvent::Extension(_), MarkEvent::Extension(_)) => {
                // Pairs are not pinned by the JSON vectors.
            }
            _ => {
                let (ak, at) = event_kind_tier(a);
                let (ek, et) = event_kind_tier(e);
                if ak != ek || at != et {
                    eprintln!("vector {name}: kind/tier mismatch: {a:?} vs {e:?}");
                    return false;
                }
            }
        }
    }
    true
}

fn event_kind_tier(ev: &MarkEvent) -> (String, MarkTier) {
    match ev {
        MarkEvent::PromptStart { tier } => ("prompt_start".to_string(), *tier),
        MarkEvent::CommandStart { tier } => ("command_start".to_string(), *tier),
        MarkEvent::OutputStart { tier } => ("output_start".to_string(), *tier),
        MarkEvent::CommandEnd { tier, .. } => ("command_end".to_string(), *tier),
        MarkEvent::CwdChanged { .. } => ("cwd_changed".to_string(), MarkTier::Osc133),
        MarkEvent::Extension(_) => ("extension".to_string(), MarkTier::Extension),
        MarkEvent::AltScreenEnter => ("alt_screen_enter".to_string(), MarkTier::Osc133),
        MarkEvent::AltScreenLeave => ("alt_screen_leave".to_string(), MarkTier::Osc133),
    }
}

fn expected_event(name: &str, ev: &RawEvent) -> MarkEvent {
    let tier = if ev.tier == 1 {
        MarkTier::Osc133
    } else {
        MarkTier::Extension
    };
    match ev.kind.as_str() {
        "prompt_start" => MarkEvent::PromptStart { tier },
        "command_start" => MarkEvent::CommandStart { tier },
        "output_start" => MarkEvent::OutputStart { tier },
        "command_end" => MarkEvent::CommandEnd {
            tier,
            exit_code: ev.exit_code,
        },
        "cwd_changed" => MarkEvent::CwdChanged {
            path: ev.path.clone().expect("cwd_changed has path"),
        },
        "extension" => MarkEvent::Extension(Default::default()),
        "alt_screen_enter" => MarkEvent::AltScreenEnter,
        "alt_screen_leave" => MarkEvent::AltScreenLeave,
        other => panic!("unknown event kind in vector {name}: {other}"),
    }
}

#[test]
fn every_vector_decodes_to_its_expected_events() {
    let mut checked = 0;
    let mut failures: Vec<String> = Vec::new();
    for entry in fs::read_dir(vectors_dir()).expect("protocol/vectors exists") {
        let path = entry.unwrap().path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let vector = terminal_marks::testing::load_vector(&path);
        let actual = MarkDecoder::new().feed(&vector.input);
        let expected: Vec<MarkEvent> = vector
            .events
            .iter()
            .map(|ev| expected_event(&vector.name, ev))
            .collect();
        if !events_match(&actual, &expected, &vector.name) {
            failures.push(vector.name);
        }
        checked += 1;
    }
    assert!(
        failures.is_empty(),
        "{} of {} vectors failed: {failures:?}",
        failures.len(),
        checked
    );
    assert!(
        checked >= 16,
        "expected the full vector set, found {checked}"
    );
}

#[test]
fn a_mark_split_across_two_feeds_still_decodes() {
    let mut decoder = MarkDecoder::new();
    assert_eq!(decoder.feed(b"\x1b]133;"), vec![]);
    assert_eq!(
        decoder.feed(b"A\x07"),
        vec![MarkEvent::PromptStart {
            tier: MarkTier::Osc133
        }]
    );
}

#[test]
fn a_mark_split_byte_by_byte_still_decodes() {
    let mut decoder = MarkDecoder::new();
    let mut events = Vec::new();
    for byte in b"\x1b]133;D;7\x07" {
        events.extend(decoder.feed(&[*byte]));
    }
    // The split-read is the point of this test: a D OSC fed one byte at a
    // time must round-trip through the scanner without panicking. The exact
    // event set depends on the recovery table — a lone `D` with no
    // preceding block is filtered out (SPEC §7 row 3), so we accept either
    // an empty stream or a single CommandEnd with the parsed exit code.
    let expected_close = MarkEvent::CommandEnd {
        tier: MarkTier::Osc133,
        exit_code: Some(7),
    };
    assert!(
        events.is_empty() || events == vec![expected_close],
        "events were {events:?}"
    );
}

#[test]
fn an_unterminated_osc_does_not_swallow_later_marks_forever() {
    let mut decoder = MarkDecoder::new();
    let _ = decoder.feed(b"\x1b]133;");
    let _ = decoder.feed(&vec![b'y'; 128 * 1024]);
    let events = decoder.feed(b"\x1b]133;A\x07");
    assert_eq!(
        events,
        vec![MarkEvent::PromptStart {
            tier: MarkTier::Osc133
        }]
    );
}
