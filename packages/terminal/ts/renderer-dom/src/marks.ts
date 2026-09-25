import type { Highlight } from "./highlights.js";
import { logicalLineAt, type LogicalLineView } from "./logical-lines.js";
import type { TextRows } from "./selection-text.js";

export type MarkRule = Readonly<{ pattern: string; regex: boolean; colour: string }>;
export type CompiledMark = Readonly<{ regex: RegExp; colour: string }>;
export type MarkSpan = Readonly<{ start: number; end: number; rank: number }>;

export const MARK_CACHE_LINES = 512;

const LITERAL_SPECIALS = /[.*+?^${}()|[\]\\]/g;

function validColour(colour: string): boolean {
	if (colour.trim() === "") return false;
	const css = (globalThis as { CSS?: { supports?: (property: string, value: string) => boolean } }).CSS;
	return typeof css?.supports !== "function" || css.supports("color", colour);
}

export function compileMarks(rules: readonly MarkRule[]): CompiledMark[] {
	const out: CompiledMark[] = [];
	for (const rule of rules) {
		if (rule.pattern === "" || !validColour(rule.colour)) continue;
		try {
			const regex = rule.regex ? new RegExp(rule.pattern, "g") : new RegExp(rule.pattern.replace(LITERAL_SPECIALS, "\\$&"), "gi");
			out.push({ regex, colour: rule.colour });
		} catch {
			continue;
		}
	}
	return out;
}

export function markSpans(text: string, marks: readonly CompiledMark[]): MarkSpan[] {
	const out: MarkSpan[] = [];
	marks.forEach((mark, rank) => {
		mark.regex.lastIndex = 0;
		let open: { start: number; end: number } | null = null;
		for (const match of text.matchAll(mark.regex)) {
			const start = match.index ?? 0;
			const end = start + match[0].length;
			if (end <= start) continue;
			if (open && start <= open.end) {
				open.end = Math.max(open.end, end);
				continue;
			}
			if (open) out.push({ ...open, rank });
			open = { start, end };
		}
		if (open) out.push({ ...open, rank });
	});
	return out;
}

export type RowId = Readonly<{ blockId: string; row: number }>;

function lineHighlights(line: LogicalLineView, marks: readonly CompiledMark[]): Highlight[] {
	return markSpans(line.text, marks).map((span) => {
		const range = line.rangeOf(span.start, span.end);
		return {
			kind: "mark",
			range: {
				start: { blockId: range.blockId, row: range.startRow, cell: range.startCell },
				end: { blockId: range.blockId, row: range.endRow, cell: range.endCell },
			},
			colour: marks[span.rank]!.colour,
			rank: span.rank,
		};
	});
}

export class MarkCache {
	private readonly lines = new Map<string, { shape: string; highlights: Highlight[] }>();

	highlights(line: LogicalLineView, marks: readonly CompiledMark[]): Highlight[] {
		const key = `${line.blockId}:${line.firstRow}`;
		const shape = `${line.rowOffsets.join(",")}\u0000${line.text}`;
		const hit = this.lines.get(key);
		if (hit && hit.shape === shape) return hit.highlights;
		const highlights = lineHighlights(line, marks);
		if (this.lines.size >= MARK_CACHE_LINES) this.lines.clear();
		this.lines.set(key, { shape, highlights });
		return highlights;
	}

	size(): number {
		return this.lines.size;
	}

	clear(): void {
		this.lines.clear();
	}
}

export function visibleLogicalLines(rows: TextRows, rendered: readonly RowId[]): LogicalLineView[] {
	const covered = new Set<string>();
	const lines: LogicalLineView[] = [];
	for (const { blockId, row } of rendered) {
		if (covered.has(`${blockId}:${row}`)) continue;
		const line = logicalLineAt(rows, blockId, row);
		if (!line) continue;
		for (let row = line.firstRow; row < line.firstRow + line.rowCount; row += 1) covered.add(`${line.blockId}:${row}`);
		lines.push(line);
	}
	return lines;
}

export function markHighlights(lines: readonly LogicalLineView[], marks: readonly CompiledMark[], cache: MarkCache): Highlight[] {
	if (marks.length === 0) return [];
	return lines.flatMap((line) => cache.highlights(line, marks));
}
