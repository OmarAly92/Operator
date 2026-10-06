use regex_automata::dfa::{dense, StartKind};
use regex_automata::MatchKind;
use std::path::PathBuf;

include!("src/activity/input_pattern_sources.rs");
include!("src/activity/compact_sources.rs");

fn automaton(pattern: &str, big_endian: bool) -> Vec<u8> {
    let dfa = dense::Builder::new()
        .configure(
            dense::Config::new()
                .match_kind(MatchKind::All)
                .start_kind(StartKind::Unanchored)
                .minimize(true),
        )
        .build(pattern)
        .expect("pattern compiles to a DFA")
        .to_sparse()
        .expect("pattern DFA is sparse");
    if big_endian {
        dfa.to_bytes_big_endian()
    } else {
        dfa.to_bytes_little_endian()
    }
}

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=src/activity/input_pattern_sources.rs");
    println!("cargo:rerun-if-changed=src/activity/compact_sources.rs");
    let big_endian = std::env::var("CARGO_CFG_TARGET_ENDIAN").as_deref() == Ok("big");
    let out_dir = PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let mut out = Vec::new();
    for pattern in HIGH_CONFIDENCE_INPUT_PATTERNS {
        out.extend(automaton(pattern, big_endian));
    }
    std::fs::write(out_dir.join("input_patterns.dfa"), out)
        .expect("write the input pattern automata");
    std::fs::write(
        out_dir.join("spinner_line.dfa"),
        automaton(SPINNER_LINE, big_endian),
    )
    .expect("write the spinner line automaton");
}
