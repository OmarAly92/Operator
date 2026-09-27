use proptest::prelude::*;
use regex_automata::meta::Regex;
use std::sync::OnceLock;
use vt_core::activity::compact::{is_spinner_line, SPINNER_LINE};

fn regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(SPINNER_LINE).expect("pattern compiles"))
}

const ALPHABET: &[char] = &[
    ' ', '\t', '\u{a0}', '\u{2003}', '\u{3000}', '\u{85}', '\u{feff}', '\n', '⠀', '⠋', '⣿', '·',
    '✢', '✳', '✶', '✻', '✽', '◐', '◑', '◓', '◔', '*', '-', '…', '.', '(', ')', 'a', 'T', 's', '1',
    '3', ':', '继', 'é',
];

const PIECES: &[&str] = &[
    "✽ ",
    "· ",
    "  ⠋ ",
    "Thinking",
    "…",
    "...",
    " (13s · still thinking)",
    " (3s)",
    "(",
    ")",
    " done",
    "  ",
];

fn line() -> impl Strategy<Value = String> {
    prop::collection::vec(
        prop_oneof![
            prop::sample::select(ALPHABET).prop_map(String::from),
            prop::sample::select(PIECES).prop_map(String::from),
        ],
        0..16,
    )
    .prop_map(|parts| parts.concat())
}

#[test]
fn the_automaton_agrees_with_the_regex_on_the_ported_examples() {
    let regex = regex();
    for line in [
        "✽ Flambéing… (13s · still thinking with high effort)",
        "· Thinking…",
        "  ⠋ Installing dependencies...",
        "◐ Loading…",
        "✻ Baked for 11s · done 6:13 PM",
        "- Installing dependencies...",
        "* item one…",
        "Thinking…",
        "✻",
        "· Linking... done in 3.2s",
        "⠿ Container db  Started... healthy",
        "✽ Working… (3s)",
        "✽\u{a0}Working…\u{3000}(3s)",
        "\u{2003}✽ Working…",
        "✽ Working… (a (b) c)",
        "✽ Working…\n",
        "",
    ] {
        assert_eq!(is_spinner_line(line), regex.is_match(line), "{line:?}");
    }
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 4096, ..ProptestConfig::default() })]

    #[test]
    fn the_automaton_agrees_with_the_regex(line in line()) {
        prop_assert_eq!(is_spinner_line(&line), regex().is_match(&line));
    }
}
