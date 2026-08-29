use std::fs;
use std::path::PathBuf;

use terminal_marks::testing::{RawEvent, RawTier};
use terminal_marks::{MarkDecoder, MarkEvent, MarkTier};

fn vectors_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../protocol/vectors")
}

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
            (MarkEvent::Extension(actual), MarkEvent::Extension(expected)) => {
                if !expected.pairs.is_empty() && actual != expected {
                    eprintln!(
                        "vector {name}: extension pairs mismatch: {actual:?} vs {expected:?}"
                    );
                    return false;
                }
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
        MarkEvent::InputReady => ("input_ready".to_string(), MarkTier::Extension),
        MarkEvent::InputReleased => ("input_released".to_string(), MarkTier::Extension),
        MarkEvent::AltScreenEnter => ("alt_screen_enter".to_string(), MarkTier::Osc133),
        MarkEvent::AltScreenLeave => ("alt_screen_leave".to_string(), MarkTier::Osc133),
    }
}

fn expected_event(name: &str, ev: &RawEvent) -> MarkEvent {
    match ev.kind.as_str() {
        "prompt_start" => MarkEvent::PromptStart {
            tier: expected_tier(name, ev),
        },
        "command_start" => MarkEvent::CommandStart {
            tier: expected_tier(name, ev),
        },
        "output_start" => MarkEvent::OutputStart {
            tier: expected_tier(name, ev),
        },
        "command_end" => MarkEvent::CommandEnd {
            tier: expected_tier(name, ev),
            exit_code: ev.exit_code,
        },
        "cwd_changed" => MarkEvent::CwdChanged {
            path: ev.path.clone().expect("cwd_changed has path"),
        },
        "extension" => MarkEvent::Extension(terminal_marks::ExtensionFields {
            pairs: ev.pairs.clone().unwrap_or_default(),
        }),
        "input_ready" => MarkEvent::InputReady,
        "input_released" => MarkEvent::InputReleased,
        "alt_screen_enter" => MarkEvent::AltScreenEnter,
        "alt_screen_leave" => MarkEvent::AltScreenLeave,
        other => panic!("unknown event kind in vector {name}: {other}"),
    }
}

fn expected_tier(name: &str, ev: &RawEvent) -> MarkTier {
    ev.tier
        .as_ref()
        .and_then(RawTier::mark_tier)
        .unwrap_or_else(|| {
            panic!(
                "unsupported or missing tier in vector {name}: {:?}",
                ev.tier
            )
        })
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
fn unsupported_vector_tiers_are_rejected() {
    assert_eq!(RawTier::Number(3).mark_tier(), None);
    assert_eq!(RawTier::Name("extension".to_string()).mark_tier(), None);
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
    // time must round-trip through the scanner and produce exactly the close
    // event, with its exit code intact. Accepting "either an empty stream or
    // the event" would let a decoder that silently stopped emitting
    // CommandEnd pass this test.
    assert_eq!(
        events,
        vec![MarkEvent::CommandEnd {
            tier: MarkTier::Osc133,
            exit_code: Some(7),
        }]
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
