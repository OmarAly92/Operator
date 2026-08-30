import { matchQuery, type MatchResult } from "./match.js";
import { clampPriority } from "./signature.js";
import type { Span } from "./parse.js";

export type CandidateKind = "command" | "subcommand" | "flag" | "argument" | "path";

export type Candidate = Readonly<{
	value: string;
	displayValue?: string;
	description?: string;
	priority?: number;
	kind: CandidateKind;
	isDirectory?: boolean;
}>;

export type Ranked = Readonly<{ candidate: Candidate; match: MatchResult }>;

export type TabAction =
	| Readonly<{ kind: "none" }>
	| Readonly<{ kind: "insert"; text: string; span: Span }>
	| Readonly<{ kind: "insert-and-open"; text: string; span: Span; results: readonly Ranked[] }>
	| Readonly<{ kind: "open"; results: readonly Ranked[] }>;

const display = (candidate: Candidate): string => candidate.displayValue ?? candidate.value;

export function orderByPriority(candidates: readonly Candidate[]): Candidate[] {
	return [...candidates].sort((left, right) => {
		const byPriority = clampPriority(right.priority) - clampPriority(left.priority);
		if (byPriority !== 0) return byPriority;
		return display(left).localeCompare(display(right));
	});
}

export function assemble(matched: readonly Ranked[]): Ranked[] {
	const exact: Ranked[] = [];
	const exactInsensitive: Ranked[] = [];
	const prefix: Ranked[] = [];
	const fuzzy: Ranked[] = [];

	for (const entry of matched) {
		if (entry.match.kind === "exact") (entry.match.caseSensitive ? exact : exactInsensitive).push(entry);
		else if (entry.match.kind === "prefix") prefix.push(entry);
		else fuzzy.push(entry);
	}

	fuzzy.sort((left, right) => {
		const leftScore = left.match.kind === "fuzzy" ? left.match.score : 0;
		const rightScore = right.match.kind === "fuzzy" ? right.match.score : 0;
		return rightScore - leftScore;
	});

	return [...exact, ...exactInsensitive, ...prefix, ...fuzzy];
}

export function rank(candidates: readonly Candidate[], query: string): Ranked[] {
	const ordered = orderByPriority(candidates);
	const matched: Ranked[] = [];
	for (const candidate of ordered) {
		const match = matchQuery(display(candidate), query);
		if (match !== null) matched.push({ candidate, match });
	}
	return assemble(matched);
}

export function tabAction(ranked: readonly Ranked[], query: string, span: Span): TabAction {
	if (ranked.length === 0) return { kind: "none" };

	const prefixMatches = ranked.filter((entry) => entry.match.kind === "prefix");
	if (prefixMatches.length === 1) {
		return { kind: "insert", text: prefixMatches[0]!.candidate.value, span };
	}

	const caseSensitive = ranked.filter(
		(entry) =>
			(entry.match.kind === "prefix" || entry.match.kind === "exact") &&
			entry.match.caseSensitive,
	);
	const common = longestCommonPrefix(caseSensitive.map((entry) => entry.candidate.value));
	if (common !== null && common.length > query.length && common.startsWith(query)) {
		return { kind: "insert-and-open", text: common, span, results: ranked };
	}

	return { kind: "open", results: ranked };
}

function longestCommonPrefix(values: readonly string[]): string | null {
	const first = values[0];
	if (first === undefined) return null;
	let prefix = first;
	for (const value of values.slice(1)) {
		let length = 0;
		while (length < prefix.length && length < value.length && prefix[length] === value[length]) {
			length += 1;
		}
		prefix = prefix.slice(0, length);
		if (prefix.length === 0) return null;
	}
	return prefix;
}
