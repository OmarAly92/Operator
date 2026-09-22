import type { PathMatch, PathQuery } from "@operator/terminal-core";
import type { DetectedLink } from "./link-providers.js";
import type { LogicalLineView } from "./logical-lines.js";

export const LINK_NUM_CHARACTER_SCAN = 4096;
export const MAX_LINK_PATH_FRAGMENTS = 32;

const FILE_LINK_SEPARATORS = new Set([
	"\0", "\t", " ", "(", ")", ":", "\\", ",", '"', "'", "[", "]", "{", "}", "<", ">", ";", "|", "`", "=",
	"│", "├", "└", "─", "┬", "┴", "┼", "║", "╠", "╚", "═", "╦", "╩", "╬",
]);
const NON_ASCII_BOUNDARY = /^[\s\p{Ps}\p{Pe}\p{Pi}\p{Pf}\p{Po}]$/u;
const NON_ASCII_SENTENCE_END = /^[\p{Pe}\p{Pf}\p{Po}]$/u;
const LINE_AND_COLUMN = [
	/:(\d+)/,
	/:(\d+)-(?:\d+)/,
	/:(\d+):(\d+)/,
	/\[(\d+), ?(\d+)]/,
	/", line (\d+), column (\d+)/,
	/", line (\d+), in/,
	/\((\d+), ?(\d+)\)/,
	/#L(\d+)/,
	/#L(\d+):(\d+)/,
];
const PREFIXES_TO_REMOVE = ["a/", "b/"];
const SUFFIXES_TO_REMOVE = ["@"];

export type CleanPath = Readonly<{ path: string; line?: number; column?: number }>;
export type PossiblePath = Readonly<{ path: CleanPath; start: number; end: number }>;
export type FileLinkCandidate = Readonly<{ path: string; line?: number; column?: number; allowDirectory: boolean; start: number; end: number }>;
export type PathResolver = (queries: readonly PathQuery[], cwd: string) => Promise<PathMatch | null>;
export type PathLookup = (line: LogicalLineView, offset: number) => Promise<DetectedLink | null>;

export function isFileLinkSeparator(character: string): boolean {
	if (FILE_LINK_SEPARATORS.has(character)) return true;
	if ((character.codePointAt(0) ?? 0) < 0x80) return false;
	return NON_ASCII_BOUNDARY.test(character);
}

function isTrailingSentencePunctuation(character: string): boolean {
	if (character === ".") return true;
	if ((character.codePointAt(0) ?? 0) < 0x80) return false;
	return NON_ASCII_SENTENCE_END.test(character);
}

function positiveInteger(digits: string | undefined): number | undefined {
	if (digits === undefined) return undefined;
	const value = Number(digits);
	return Number.isSafeInteger(value) ? value : undefined;
}

export function cleanPath(path: string): CleanPath {
	let cleaned: CleanPath = { path };
	for (const pattern of LINE_AND_COLUMN) {
		const match = pattern.exec(path);
		if (!match || match.index + match[0].length !== path.length) continue;
		const line = positiveInteger(match[1]);
		const column = positiveInteger(match[2]);
		cleaned = {
			path: path.slice(0, match.index),
			...(line === undefined ? {} : { line }),
			...(line === undefined || column === undefined ? {} : { column }),
		};
	}
	return cleaned;
}

function fragmentsOf(text: string): string[] {
	const out: string[] = [];
	let run = "";
	for (const character of text) {
		if (!isFileLinkSeparator(character)) {
			run += character;
			continue;
		}
		if (run !== "") out.push(run);
		run = "";
		out.push(character);
	}
	if (run !== "") out.push(run);
	return out;
}

function firstCharacter(text: string): string {
	return String.fromCodePoint(text.codePointAt(0) ?? 0);
}

export function possibleFilePaths(text: string, offset: number): PossiblePath[] {
	const prefix = fragmentsOf(text.slice(Math.max(0, offset - LINK_NUM_CHARACTER_SCAN), offset)).slice(-MAX_LINK_PATH_FRAGMENTS);
	const suffix = fragmentsOf(text.slice(offset, offset + LINK_NUM_CHARACTER_SCAN)).slice(0, MAX_LINK_PATH_FRAGMENTS);
	const last = prefix[prefix.length - 1];
	if (last === undefined || isFileLinkSeparator(firstCharacter(last))) prefix.push("");
	const out: PossiblePath[] = [];
	let left = "";
	for (let index = prefix.length - 1; index >= 0; index -= 1) {
		left = prefix[index]! + left;
		let right = "";
		for (const chunk of suffix) {
			right += chunk;
			out.push({ path: cleanPath(`${left}${right}`), start: offset - left.length, end: offset + right.length });
		}
	}
	return out.reverse();
}

function withoutTrailingSentencePunctuation(path: string): { path: string; removed: number } | null {
	let trimmed = path;
	let removed = 0;
	while (trimmed !== "") {
		const character = [...trimmed].pop()!;
		if (!isTrailingSentencePunctuation(character)) break;
		const shorter = trimmed.slice(0, trimmed.length - character.length);
		if (shorter === "") break;
		if (character === ".") {
			const before = [...shorter].pop();
			if (before === "." || before === "/" || before === "\\") break;
		}
		trimmed = shorter;
		removed += character.length;
	}
	return removed > 0 ? { path: trimmed, removed } : null;
}

export function fileLinkCandidates(paths: readonly PossiblePath[]): FileLinkCandidate[] {
	const out: FileLinkCandidate[] = [];
	for (const possible of paths) {
		const { path, line, column } = possible.path;
		const position = {
			...(line === undefined ? {} : { line }),
			...(column === undefined ? {} : { column }),
			allowDirectory: line === undefined,
		};
		const trimmed = withoutTrailingSentencePunctuation(path);
		if (trimmed) out.push({ path: trimmed.path, ...position, start: possible.start, end: possible.end - trimmed.removed });
		out.push({ path, ...position, start: possible.start, end: possible.end });
		for (const prefix of PREFIXES_TO_REMOVE) {
			if (path.startsWith(prefix)) out.push({ path: path.slice(prefix.length), ...position, start: possible.start + prefix.length, end: possible.end });
		}
		for (const suffix of SUFFIXES_TO_REMOVE) {
			if (path.endsWith(suffix)) out.push({ path: path.slice(0, path.length - suffix.length), ...position, start: possible.start, end: possible.end - suffix.length });
		}
	}
	return out;
}

export function fragmentAt(text: string, offset: number): { start: number; end: number } {
	const at = firstCharacter(text.slice(offset));
	if (isFileLinkSeparator(at)) return { start: offset, end: offset + at.length };
	let start = offset;
	while (start > 0) {
		const before = [...text.slice(Math.max(0, start - 2), start)].pop()!;
		if (isFileLinkSeparator(before)) break;
		start -= before.length;
	}
	let end = offset;
	while (end < text.length) {
		const next = firstCharacter(text.slice(end));
		if (isFileLinkSeparator(next)) break;
		end += next.length;
	}
	return { start, end };
}

export function createPathLookup(resolve: PathResolver, cwdOf: (blockId: string) => string): PathLookup {
	return async (line, offset) => {
		if (offset < 0 || offset >= line.text.length) return null;
		const candidates = fileLinkCandidates(possibleFilePaths(line.text, offset));
		if (candidates.length === 0) return null;
		const match = await resolve(
			candidates.map((candidate) => ({ path: candidate.path, allowDirectory: candidate.allowDirectory })),
			cwdOf(line.blockId),
		);
		const candidate = match ? candidates[match.index] : undefined;
		if (!match || !candidate) return null;
		return {
			kind: "path",
			text: line.text.slice(candidate.start, candidate.end),
			path: match.path,
			...(candidate.line === undefined ? {} : { line: candidate.line }),
			...(candidate.column === undefined ? {} : { column: candidate.column }),
			range: line.rangeOf(candidate.start, candidate.end),
		};
	};
}
