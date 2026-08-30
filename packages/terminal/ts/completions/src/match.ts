export type MatchResult =
	| Readonly<{ kind: "exact"; caseSensitive: boolean }>
	| Readonly<{ kind: "prefix"; caseSensitive: boolean }>
	| Readonly<{ kind: "fuzzy"; score: number; indices: readonly number[] }>;

export const BONUS_FIRST_CHAR = 24;
export const BONUS_WORD_START = 16;
export const BONUS_CONSECUTIVE = 8;
export const PENALTY_GAP = 3;
export const MAX_GAP_PENALTY = 12;

const WORD_SEPARATORS = new Set(["/", "-", "_", ".", " ", ":", "@"]);

export function matchQuery(text: string, query: string): MatchResult | null {
	if (query.length === 0) return { kind: "prefix", caseSensitive: true };

	const caseSensitive = /[A-Z]/.test(query);
	const haystack = caseSensitive ? text : text.toLowerCase();
	const needle = caseSensitive ? query : query.toLowerCase();

	if (haystack === needle) return { kind: "exact", caseSensitive: text === query };
	if (haystack.startsWith(needle)) {
		return { kind: "prefix", caseSensitive: text.startsWith(query) };
	}

	const indices = subsequenceIndices(haystack, needle);
	if (indices === null) return null;
	return { kind: "fuzzy", score: scoreIndices(text, indices), indices };
}

function subsequenceIndices(haystack: string, needle: string): number[] | null {
	const indices: number[] = [];
	let position = 0;
	for (const ch of needle) {
		const found = haystack.indexOf(ch, position);
		if (found === -1) return null;
		indices.push(found);
		position = found + 1;
	}
	return indices;
}

function scoreIndices(text: string, indices: readonly number[]): number {
	let score = 0;
	let previous = -1;
	for (const index of indices) {
		if (index === 0) score += BONUS_FIRST_CHAR;
		else if (isWordStart(text, index)) score += BONUS_WORD_START;
		if (previous >= 0) {
			if (index === previous + 1) score += BONUS_CONSECUTIVE;
			else score -= Math.min(MAX_GAP_PENALTY, (index - previous - 1) * PENALTY_GAP);
		}
		previous = index;
	}
	return score;
}

function isWordStart(text: string, index: number): boolean {
	const previous = text[index - 1];
	if (previous === undefined) return true;
	if (WORD_SEPARATORS.has(previous)) return true;
	const current = text[index]!;
	return previous === previous.toLowerCase() && current === current.toUpperCase()
		&& current !== current.toLowerCase();
}
