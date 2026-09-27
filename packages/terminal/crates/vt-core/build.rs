use regex_automata::dfa::{dense, StartKind};
use regex_automata::MatchKind;
use std::path::PathBuf;

include!("src/activity/input_pattern_sources.rs");

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=src/activity/input_pattern_sources.rs");
    let big_endian = std::env::var("CARGO_CFG_TARGET_ENDIAN").as_deref() == Ok("big");
    let mut out = Vec::new();
    for pattern in HIGH_CONFIDENCE_INPUT_PATTERNS {
        let dfa = dense::Builder::new()
            .configure(
                dense::Config::new()
                    .match_kind(MatchKind::All)
                    .start_kind(StartKind::Unanchored)
                    .minimize(true),
            )
            .build(pattern)
            .expect("input pattern compiles to a DFA")
            .to_sparse()
            .expect("input pattern DFA is sparse");
        out.extend(if big_endian {
            dfa.to_bytes_big_endian()
        } else {
            dfa.to_bytes_little_endian()
        });
    }
    let path =
        PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR")).join("input_patterns.dfa");
    std::fs::write(path, out).expect("write the input pattern automata");
}
