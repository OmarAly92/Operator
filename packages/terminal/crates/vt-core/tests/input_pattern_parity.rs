use proptest::prelude::*;
use regex_automata::meta::Regex;
use std::sync::OnceLock;
use vt_core::activity::input_patterns::{
    detects_high_confidence_input_pattern, HIGH_CONFIDENCE_INPUT_PATTERNS,
};

fn regexes() -> &'static [Regex] {
    static REGEXES: OnceLock<Vec<Regex>> = OnceLock::new();
    REGEXES.get_or_init(|| {
        HIGH_CONFIDENCE_INPUT_PATTERNS
            .iter()
            .map(|pattern| Regex::new(pattern).expect("pattern compiles"))
            .collect()
    })
}

fn regex_matches(regexes: &[Regex], line: &str) -> bool {
    regexes.iter().any(|regex| regex.is_match(line))
}

const ALPHABET: &[char] = &[
    ' ', '\t', '\u{a0}', '\u{2003}', '\u{3000}', '\n', '[', ']', '(', ')', '"', ':', '?', '/', 'y',
    'Y', 'e', 'E', 's', 'S', '\u{17f}', 'n', 'N', 'o', 'O', 'k', 'K', '\u{212a}', 'D', 'd', 'a',
    'A', 'p', 'P', 'r', 'w', 'f', 'i', 'u', 'l', 't', '›', '❯', '▸', '▶', '>', '\x1b', 'm', '0',
    '3', ';', 'x', '继', '·',
];

const PIECES: &[&str] = &[
    "(y/n)",
    "[Y/n]",
    "(yes/no)",
    "[no/yes]",
    "(y)",
    "(END)",
    "password",
    "Password for dev",
    "press any key",
    "Press a key",
    "? ",
    "❯",
    "(default is \"x\"):",
    "[a]",
    "[~]",
    ": (demo)",
    "\x1b[1;32m",
    " ",
    "  ",
    "?",
];

fn line() -> impl Strategy<Value = String> {
    prop::collection::vec(
        prop_oneof![
            prop::sample::select(ALPHABET).prop_map(String::from),
            prop::sample::select(PIECES).prop_map(String::from),
        ],
        0..24,
    )
    .prop_map(|parts| parts.concat())
}

#[test]
fn the_automaton_agrees_with_the_regexes_on_the_ported_examples() {
    let regexes = regexes();
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
        "❯ ",
        "❯\u{a0}",
        "$ ",
        "PRESS ANY \u{212a}EY",
        "pa\u{17f}\u{17f}word:",
        "Continue?\u{a0}[Y/n]\u{3000}",
        "\x1b[1m? Pick ❯ ",
        "",
    ] {
        assert_eq!(
            detects_high_confidence_input_pattern(line),
            regex_matches(regexes, line),
            "{line:?}"
        );
    }
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 4096, ..ProptestConfig::default() })]

    #[test]
    fn the_automaton_agrees_with_the_regexes(line in line()) {
        let regexes = regexes();
        prop_assert_eq!(detects_high_confidence_input_pattern(&line), regex_matches(regexes, &line));
    }
}
