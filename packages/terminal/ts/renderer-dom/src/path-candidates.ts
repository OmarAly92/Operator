import { detectLinkSuffixes, getLinkSuffix, LINK_MAX_RESOLVED_LENGTH, type LinkSuffix } from "./link-parsing.js";

export const PATH_BREAK_GLYPHS = "─·⏵❯←↓◐◑…✢✳✶✻✽⎿⏺●⚠█▀▐▛▜▝•○◦▪▸▹►└├│";
export const MAX_SPAN_WORDS = 4;
export const MAX_PATH_CANDIDATES = 20;

export type PathSpan = Readonly<{ path: string; allowDirectory: boolean; start: number; end: number; line?: number; column?: number }>;

const BREAKS = new Set([..."\"'`()[]{}<>|;,=", ...PATH_BREAK_GLYPHS]);
const TRAILING = new Set([...".,:;!?"]);
const GITHUB_LINE = /#L(\d+)(?:C(\d+))?$/;
const DIFF_PREFIX = /^[ab]\//;
const SCHEME = /^[a-z][a-z0-9+.-]*:\/\//iu;

type Suffix = Readonly<{ pathEnd: number; rangeEnd: number; line?: number; column?: number }>;

function isSpace(character: string): boolean {
	return /\s/u.test(character);
}

function lastComponent(text: string, start: number, end: number): string {
	let index = end;
	while (index > start && text[index - 1] !== "/" && !isSpace(text[index - 1]!)) index -= 1;
	return text.slice(index, end);
}

function trimTrailing(text: string, start: number, end: number): number {
	while (end > start && TRAILING.has(text[end - 1]!)) {
		const tail = lastComponent(text, start, end);
		if (tail.length <= 2 && /^\.+$/u.test(tail)) break;
		end -= 1;
	}
	return end;
}

function readSuffix(text: string, start: number, end: number, following: ReadonlyMap<number, LinkSuffix>): Suffix {
	const span = text.slice(start, end);
	const inner = getLinkSuffix(span);
	if (inner && inner.suffix.index > 0) return { pathEnd: start + inner.suffix.index, rangeEnd: end, line: inner.row, column: inner.col };
	const github = GITHUB_LINE.exec(span);
	if (github && github.index > 0) {
		return { pathEnd: start + github.index, rangeEnd: end, line: Number(github[1]), column: github[2] === undefined ? undefined : Number(github[2]) };
	}
	const outer = following.get(end);
	if (outer) return { pathEnd: end, rangeEnd: end + outer.suffix.text.length, line: outer.row, column: outer.col };
	return { pathEnd: end, rangeEnd: end };
}

function pathLike(path: string): boolean {
	return path.includes("/") || path.includes("\\") || path.startsWith("~") || path.startsWith(".");
}

function spanOf(path: string, start: number, suffix: Suffix): PathSpan {
	return {
		path,
		allowDirectory: suffix.line === undefined && pathLike(path),
		start,
		end: suffix.rangeEnd,
		...(suffix.line === undefined ? {} : { line: suffix.line }),
		...(suffix.column === undefined ? {} : { column: suffix.column }),
	};
}

export function pathCandidatesAt(text: string, offset: number): PathSpan[] {
	if (offset < 0 || offset >= text.length || BREAKS.has(text[offset]!)) return [];
	let segmentStart = offset;
	while (segmentStart > 0 && !BREAKS.has(text[segmentStart - 1]!)) segmentStart -= 1;
	let segmentEnd = offset;
	while (segmentEnd < text.length && !BREAKS.has(text[segmentEnd]!)) segmentEnd += 1;
	const words: [number, number][] = [];
	for (let index = segmentStart; index < segmentEnd; ) {
		if (isSpace(text[index]!)) {
			index += 1;
			continue;
		}
		const wordStart = index;
		while (index < segmentEnd && !isSpace(text[index]!)) index += 1;
		words.push([wordStart, index]);
	}
	const first = words.findIndex(([, end]) => end > offset);
	let last = -1;
	for (let index = 0; index < words.length && words[index]![0] <= offset; index += 1) last = index;
	if (first < 0 || last < 0) return [];
	const spans: [number, number][] = [];
	for (let from = Math.max(0, first - MAX_SPAN_WORDS + 1); from <= last; from += 1) {
		for (let to = Math.max(from, first); to < Math.min(words.length, from + MAX_SPAN_WORDS); to += 1) {
			spans.push([words[from]![0], words[to]![1]]);
		}
	}
	spans.sort((a, b) => b[1] - b[0] - (a[1] - a[0]) || a[0] - b[0]);
	const following = new Map(detectLinkSuffixes(text).map((suffix) => [suffix.suffix.index, suffix] as const));
	const seen = new Set<string>();
	const out: PathSpan[] = [];
	const offer = (span: PathSpan) => {
		if (span.path.length === 0 || seen.has(span.path) || offset < span.start || offset >= span.end) return;
		seen.add(span.path);
		out.push(span);
	};
	for (const [start, end] of spans) {
		if (end - start > LINK_MAX_RESOLVED_LENGTH) continue;
		const trimmed = trimTrailing(text, start, end);
		if (trimmed <= start) continue;
		const suffix = readSuffix(text, start, trimmed, following);
		const path = text.slice(start, suffix.pathEnd);
		if (SCHEME.test(path)) continue;
		offer(spanOf(path, start, suffix));
		if (DIFF_PREFIX.test(path)) offer(spanOf(path.slice(2), start + 2, suffix));
	}
	return out.slice(0, MAX_PATH_CANDIDATES);
}
