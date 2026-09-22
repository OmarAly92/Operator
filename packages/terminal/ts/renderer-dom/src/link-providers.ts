import type { LinkRange, LogicalLineView } from "./logical-lines.js";

export type LinkKind = "hyperlink" | "url" | "path";
export type DetectedLink = Readonly<{ kind: LinkKind; text: string; uri?: string; path?: string; line?: number; column?: number; range: LinkRange }>;
export type LinkProvider = (line: LogicalLineView) => Promise<readonly DetectedLink[]>;

// xterm.js/addons/addon-web-links/src/WebLinksAddon.ts:21 (strictUrlRegex)
const STRICT_URL = /(https?|HTTPS?):[/]{2}[^\s"'!*(){}|\\^<>`]*[^\s"':,.!?{}|\\^~\[\]`()<>]/g;

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

export const DEFAULT_LINK_PROVIDERS: readonly LinkProvider[] = [hyperlinkProvider, urlProvider];
