/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE-VSCODE-MIT beside this file.
 *--------------------------------------------------------------------------------------------*/

const HIGH_CONFIDENCE_INPUT_PATTERNS: readonly RegExp[] = [
	/\s*(?:\[[^\]]\][^\[]*)+(?:\(default is\s+"[^"]+"\):)?\s+$/,
	/(?:\(|\[)\s*(?:y(?:es)?\s*\/\s*n(?:o)?|n(?:o)?\s*\/\s*y(?:es)?)\s*(?:\]|\))\s+$/i,
	/[?:]\s*(?:\(|\[)?\s*y(?:es)?\s*\/\s*n(?:o)?\s*(?:\]|\))?\s+$/i,
	/\(y\) +$/i,
	/:\s+\([^)]*\) +$/,
	/\(END\)$/,
	/password(?: for [^:]+)?:\s*$/i,
	/press a(?:ny)? key/i,
	/^(?:\s|\x1b\[[0-9;]*m)*\?.*[›❯▸▶]\s*$/,
];

export function detectsHighConfidenceInputPattern(cursorLine: string): boolean {
	return HIGH_CONFIDENCE_INPUT_PATTERNS.some((pattern) => pattern.test(cursorLine));
}
