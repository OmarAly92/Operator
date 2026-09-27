/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE-VSCODE-MIT beside this file.
 *--------------------------------------------------------------------------------------------*/

pub const HIGH_CONFIDENCE_INPUT_PATTERNS: [&str; 9] = [
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
