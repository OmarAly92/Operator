/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE-VSCODE-MIT beside this file.
 *--------------------------------------------------------------------------------------------*/

use regex_automata::meta::Regex;
use std::sync::OnceLock;

const HIGH_CONFIDENCE_INPUT_PATTERNS: [&str; 9] = [
    r#"\s*(?:\[[^\]]\][^\[]*)+(?:\(default is\s+"[^"]+"\):)?\s+$"#,
    r"(?i)(?:\(|\[)\s*(?:y(?:es)?\s*/\s*n(?:o)?|n(?:o)?\s*/\s*y(?:es)?)\s*(?:\]|\))\s+$",
    r"(?i)[?:]\s*(?:\(|\[)?\s*y(?:es)?\s*/\s*n(?:o)?\s*(?:\]|\))?\s+$",
    r"(?i)\(y\) +$",
    r":\s+\([^)]*\) +$",
    r"\(END\)$",
    r"(?i)password(?: for [^:]+)?:\s*$",
    r"(?i)press a(?:ny)? key",
    r"^(?:\s|\x1b\[[0-9;]*m)*\?.*[›❯▸▶]\s*$",
];

fn patterns() -> &'static [Regex] {
    static PATTERNS: OnceLock<Vec<Regex>> = OnceLock::new();
    PATTERNS.get_or_init(|| {
        HIGH_CONFIDENCE_INPUT_PATTERNS
            .iter()
            .map(|pattern| Regex::new(pattern).expect("input pattern compiles"))
            .collect()
    })
}

pub fn detects_high_confidence_input_pattern(cursor_line: &str) -> bool {
    patterns()
        .iter()
        .any(|pattern| pattern.is_match(cursor_line))
}
