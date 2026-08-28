export type MatchScore = { tier: number; offset: number; spread?: number };
export type FuzzyPolicy = { maxEdits: number; transpositionsOnly: boolean };
export type MatchOptions = { fuzzy?: FuzzyPolicy | null; subsequence?: boolean };
export type TextFieldsOptions = { typoTolerant?: boolean; subsequence?: boolean };
export type MatchRange = { start: number; length: number };

export const TIER_EXACT = 0;
export const TIER_WHOLE_WORD = 1;
export const TIER_PREFIX = 2;
export const TIER_WORD_START = 3;
export const TIER_SUBSTRING = 4;
export const TIER_SUBSEQUENCE = 5;
export const TIER_FUZZY = 6;

function isWordBoundaryChar(ch: string | undefined): boolean {
	return ch === undefined || !/[a-z0-9]/.test(ch);
}

function scoreSubstringMatch(query: string, text: string): MatchScore | null {
	let best: MatchScore | null = null;
	let pos = 0;
	while (pos <= text.length - query.length) {
		const found = text.indexOf(query, pos);
		if (found === -1) break;
		const startsAtBoundary = found === 0 || isWordBoundaryChar(text[found - 1]);
		const endsAtBoundary = isWordBoundaryChar(text[found + query.length]);
		const tier = startsAtBoundary && endsAtBoundary
			? TIER_WHOLE_WORD
			: found === 0
				? TIER_PREFIX
				: startsAtBoundary
					? TIER_WORD_START
					: TIER_SUBSTRING;
		if (best === null || tier < best.tier || (tier === best.tier && found < best.offset)) {
			best = { tier, offset: found };
		}
		pos = found + 1;
	}
	return best;
}

function scoreSubsequenceMatch(query: string, text: string): MatchScore | null {
	let queryIndex = 0;
	let firstIndex = -1;
	let lastIndex = -1;
	for (let textIndex = 0; textIndex < text.length && queryIndex < query.length; textIndex += 1) {
		if (text[textIndex] !== query[queryIndex]) continue;
		if (firstIndex === -1) firstIndex = textIndex;
		lastIndex = textIndex;
		queryIndex += 1;
	}
	if (queryIndex !== query.length || firstIndex === -1) return null;
	return { tier: TIER_SUBSEQUENCE, offset: firstIndex, spread: lastIndex - firstIndex + 1 };
}

function boundedEditDistance(query: string, word: string, budget: number): number | null {
	if (Math.abs(query.length - word.length) > budget) return null;
	let twoRowsBack: number[] = [];
	let previousRow = Array.from({ length: word.length + 1 }, (_, index) => index);
	for (let queryIndex = 1; queryIndex <= query.length; queryIndex += 1) {
		const currentRow = [queryIndex];
		let rowBest = queryIndex;
		for (let wordIndex = 1; wordIndex <= word.length; wordIndex += 1) {
			const substitutionCost = query[queryIndex - 1] === word[wordIndex - 1] ? 0 : 1;
			let cost = Math.min(
				currentRow[wordIndex - 1]! + 1,
				previousRow[wordIndex]! + 1,
				previousRow[wordIndex - 1]! + substitutionCost,
			);
			const isTransposition = queryIndex > 1 && wordIndex > 1 && query[queryIndex - 1] === word[wordIndex - 2] && query[queryIndex - 2] === word[wordIndex - 1];
			if (isTransposition) cost = Math.min(cost, twoRowsBack[wordIndex - 2]! + 1);
			currentRow.push(cost);
			rowBest = Math.min(rowBest, cost);
		}
		if (rowBest > budget) return null;
		twoRowsBack = previousRow;
		previousRow = currentRow;
	}
	const distance = previousRow[word.length]!;
	return distance <= budget ? distance : null;
}

function isAdjacentTransposition(query: string, word: string): boolean {
	if (query.length !== word.length) return false;
	let index = 0;
	while (index < query.length && query[index] === word[index]) index += 1;
	if (index >= query.length - 1) return false;
	return query[index] === word[index + 1] && query[index + 1] === word[index] && query.slice(index + 2) === word.slice(index + 2);
}

export function fuzzyPolicyForToken(token: string): FuzzyPolicy | null {
	if (token.length <= 3) return null;
	if (token.length === 4) return { maxEdits: 1, transpositionsOnly: true };
	if (token.length <= 7) return { maxEdits: 1, transpositionsOnly: false };
	return { maxEdits: 2, transpositionsOnly: false };
}

function scoreFuzzyMatch(query: string, text: string, policy: FuzzyPolicy): MatchScore | null {
	if (policy.maxEdits <= 0 || query.length <= policy.maxEdits) return null;
	let best: MatchScore | null = null;
	const wordPattern = /[a-z0-9]+/g;
	let word = wordPattern.exec(text);
	while (word !== null) {
		const candidates = new Set([word[0], word[0].slice(0, query.length), word[0].slice(0, query.length + policy.maxEdits)]);
		for (const candidate of candidates) {
			const distance = policy.transpositionsOnly
				? (isAdjacentTransposition(query, candidate) ? 1 : null)
				: boundedEditDistance(query, candidate, policy.maxEdits);
			if (distance === null) continue;
			const score = { tier: TIER_FUZZY, offset: word.index, spread: distance };
			if (best === null || compareMatchScores(score, best) < 0) best = score;
		}
		word = wordPattern.exec(text);
	}
	return best;
}

export function scoreMatch(query: string, text: string, options: MatchOptions = {}): MatchScore | null {
	if (!query) return { tier: TIER_EXACT, offset: 0 };
	const q = query.toLowerCase();
	const t = text.toLowerCase();
	if (t === q) return { tier: TIER_EXACT, offset: 0 };
	const substring = scoreSubstringMatch(q, t);
	const exact = substring ?? (options.subsequence === false ? null : scoreSubsequenceMatch(q, t));
	if (exact) return exact;
	return options.fuzzy ? scoreFuzzyMatch(q, t, options.fuzzy) : null;
}

function mergeAdjacentRanges(indices: readonly number[]): MatchRange[] {
	const ranges: MatchRange[] = [];
	for (const index of indices) {
		const last = ranges.at(-1);
		if (last && last.start + last.length === index) last.length += 1;
		else ranges.push({ start: index, length: 1 });
	}
	return ranges;
}

function wordRangeAt(text: string, offset: number): MatchRange {
	let end = offset;
	while (end < text.length && /[a-z0-9]/.test(text[end]!)) end += 1;
	return { start: offset, length: Math.max(end - offset, 1) };
}

export function matchRanges(query: string, text: string, score: MatchScore): MatchRange[] {
	if (!query) return [];
	const q = query.toLowerCase();
	const t = text.toLowerCase();
	if (score.tier === TIER_EXACT) return [{ start: 0, length: text.length }];
	if (score.tier === TIER_FUZZY) return [wordRangeAt(t, score.offset)];
	if (score.tier === TIER_SUBSEQUENCE) {
		const indices: number[] = [];
		let queryIndex = 0;
		for (let textIndex = 0; textIndex < t.length && queryIndex < q.length; textIndex += 1) {
			if (t[textIndex] !== q[queryIndex]) continue;
			indices.push(textIndex);
			queryIndex += 1;
		}
		return mergeAdjacentRanges(indices);
	}
	return [{ start: score.offset, length: q.length }];
}

export function compareMatchScores(a: MatchScore, b: MatchScore): number {
	if (a.tier !== b.tier) return a.tier - b.tier;
	if (a.offset !== b.offset) return a.offset - b.offset;
	return (a.spread ?? 0) - (b.spread ?? 0);
}

export function tokenizeQuery(query: string): string[] {
	return query.trim().toLowerCase().split(/\s+/).filter((token) => token.length > 0);
}

export function scoreTextFields(query: string, fields: readonly string[], options: TextFieldsOptions = {}): MatchScore | null {
	const tokens = tokenizeQuery(query);
	if (tokens.length === 0) return { tier: TIER_EXACT, offset: 0, spread: 0 };
	const aggregate: MatchScore = { tier: TIER_EXACT, offset: 0, spread: 0 };
	for (const token of tokens) {
		const fuzzy = options.typoTolerant ? fuzzyPolicyForToken(token) : null;
		let best: MatchScore | null = null;
		for (const field of fields) {
			const score = scoreMatch(token, field, { fuzzy, subsequence: options.subsequence });
			if (score && (best === null || compareMatchScores(score, best) < 0)) best = score;
		}
		if (best === null) return null;
		aggregate.tier += best.tier;
		aggregate.offset += best.offset;
		aggregate.spread = (aggregate.spread ?? 0) + (best.spread ?? token.length);
	}
	return aggregate;
}
