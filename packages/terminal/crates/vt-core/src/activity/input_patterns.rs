/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE-VSCODE-MIT beside this file.
 *--------------------------------------------------------------------------------------------*/

use regex_automata::dfa::sparse::DFA;
use regex_automata::dfa::Automaton;
use regex_automata::Input;
use std::sync::OnceLock;

include!("input_pattern_sources.rs");

static AUTOMATA: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/input_patterns.dfa"));

fn automata() -> &'static [DFA<&'static [u8]>] {
    static DFAS: OnceLock<Vec<DFA<&'static [u8]>>> = OnceLock::new();
    DFAS.get_or_init(|| {
        let mut rest = AUTOMATA;
        let mut out = Vec::with_capacity(HIGH_CONFIDENCE_INPUT_PATTERNS.len());
        while !rest.is_empty() {
            let (dfa, read) = DFA::from_bytes(rest).expect("input pattern automaton");
            out.push(dfa);
            rest = &rest[read..];
        }
        out
    })
}

pub fn detects_high_confidence_input_pattern(cursor_line: &str) -> bool {
    let input = Input::new(cursor_line).earliest(true);
    automata()
        .iter()
        .any(|dfa| matches!(dfa.try_search_fwd(&input), Ok(Some(_))))
}
