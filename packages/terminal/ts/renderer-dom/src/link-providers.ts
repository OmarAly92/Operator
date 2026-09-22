import type { PathCandidate, ResolvedPath } from "@operator/terminal-core";
import { LINK_MAX_LINE_LENGTH } from "./link-parsing.js";
import type { LinkRange, LogicalLineView } from "./logical-lines.js";
import { pathCandidatesAt, type PathSpan } from "./path-candidates.js";

export type LinkKind = "hyperlink" | "url" | "path";
export type DetectedLink = Readonly<{ kind: LinkKind; text: string; uri?: string; path?: string; line?: number; column?: number; range: LinkRange }>;
export type LinkProvider = (line: LogicalLineView, offset: number) => Promise<readonly DetectedLink[]>;

// xterm.js/addons/addon-web-links/src/WebLinksAddon.ts:21 (strictUrlRegex)
const STRICT_URL = /(https?|HTTPS?):[/]{2}[^\s"'!*(){}|\\^<>`]*[^\s"':,.!?{}|\\^~\[\]`()<>]/g;
const PATH_CACHE_LINES = 256;

export const hyperlinkProvider: LinkProvider = async (line) => {
	const out: DetectedLink[] = [];
	let index = 0;
	while (index < line.linkRuns.length) {
		const first = line.linkRuns[index]!;
		let end = first.endOffset;
		let next = index + 1;
		while (next < line.linkRuns.length && line.linkRuns[next]!.linkId === first.linkId && line.linkRuns[next]!.startOffset === end) {
			end = line.linkRuns[next]!.endOffset;
			next += 1;
		}
		const uri = line.linkUri(first.linkId);
		if (uri !== null) out.push({ kind: "hyperlink", text: line.text.slice(first.startOffset, end), uri, range: line.rangeOf(first.startOffset, end) });
		index = next;
	}
	return out;
};

export const urlProvider: LinkProvider = async (line) => {
	const out: DetectedLink[] = [];
	for (const match of line.text.matchAll(STRICT_URL)) {
		const start = match.index ?? 0;
		out.push({ kind: "url", text: match[0], uri: match[0], range: line.rangeOf(start, start + match[0].length) });
	}
	return out;
};

type FoundPath = PathSpan & Readonly<{ resolved: string }>;

function pathLink(line: LogicalLineView, found: FoundPath): DetectedLink {
	return {
		kind: "path",
		text: line.text.slice(found.start, found.end),
		path: found.resolved,
		...(found.line === undefined ? {} : { line: found.line }),
		...(found.column === undefined ? {} : { column: found.column }),
		range: line.rangeOf(found.start, found.end),
	};
}

export function createPathProvider(
	resolveFirstPath: (candidates: readonly PathCandidate[], cwd: string) => Promise<ResolvedPath | null>,
	cwdOf: (blockId: string) => string,
): LinkProvider {
	const found = new Map<string, FoundPath[]>();
	const remember = (key: string, path: FoundPath) => {
		const paths = found.get(key) ?? [];
		found.delete(key);
		found.set(key, [...paths, path]);
		if (found.size > PATH_CACHE_LINES) found.delete(found.keys().next().value as string);
	};
	return async (line, offset) => {
		const text = line.text;
		if (text.length === 0 || text.length > LINK_MAX_LINE_LENGTH) return [];
		const taken: [number, number][] = [
			...line.linkRuns.map((run) => [run.startOffset, run.endOffset] as [number, number]),
			...[...text.matchAll(STRICT_URL)].map((match) => [match.index ?? 0, (match.index ?? 0) + match[0].length] as [number, number]),
		];
		if (taken.some(([start, end]) => offset >= start && offset < end)) return [];
		const cwd = cwdOf(line.blockId);
		const key = `${cwd}\u0000${text}`;
		const known = found.get(key)?.find((path) => offset >= path.start && offset < path.end);
		if (known) return [pathLink(line, known)];
		const spans = pathCandidatesAt(text, offset).filter((span) => !taken.some(([start, end]) => span.start < end && start < span.end));
		if (spans.length === 0) return [];
		const result = await resolveFirstPath(spans.map((span) => ({ path: span.path, allowDirectory: span.allowDirectory })), cwd);
		const span = result ? spans[result.index] : undefined;
		if (!result || !span) return [];
		const path = { ...span, resolved: result.path };
		remember(key, path);
		return [pathLink(line, path)];
	};
}

export const DEFAULT_LINK_PROVIDERS: readonly LinkProvider[] = [hyperlinkProvider, urlProvider];
