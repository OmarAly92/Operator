import type { SecretPattern } from "@operator/terminal-core";
import { cellAtOffset } from "./clusters.js";
import { logicalLineAt, type LinkRange, type LogicalLineView } from "./logical-lines.js";
import type { TextRows } from "./selection-text.js";

// warp/crates/warp_terminal/src/model/grid/grid_handler.rs:1134 (the placeholder char)
export const REDACTION_MASK = "*";

export type SecretRange = Readonly<{ start: number; end: number }>;
export type RedactionMatch = Readonly<{ key: string; range: LinkRange }>;

export function compileSecretPatterns(patterns: readonly SecretPattern[]): RegExp[] {
	const out: RegExp[] = [];
	for (const pattern of patterns) {
		const flags = pattern.flags ?? "";
		try {
			out.push(new RegExp(pattern.source, flags.includes("g") ? flags : `${flags}g`));
		} catch {
			continue;
		}
	}
	return out;
}

export function secretRanges(text: string, regexes: readonly RegExp[]): SecretRange[] {
	const hits: SecretRange[] = [];
	for (const regex of regexes) {
		regex.lastIndex = 0;
		for (const match of text.matchAll(regex)) {
			const whole = match.index ?? 0;
			let start = whole;
			let end = whole + match[0].length;
			const first = match[1];
			if (first !== undefined && match[0].startsWith(first)) start += first.length;
			const last = match[match.length - 1];
			if (match.length > 2 && last !== undefined && last !== "" && match[0].endsWith(last)) end -= last.length;
			if (end > start) hits.push({ start, end });
		}
	}
	hits.sort((a, b) => a.start - b.start);
	const merged: SecretRange[] = [];
	for (const hit of hits) {
		const previous = merged[merged.length - 1];
		if (previous && hit.start <= previous.end) {
			merged[merged.length - 1] = { start: previous.start, end: Math.max(previous.end, hit.end) };
			continue;
		}
		merged.push(hit);
	}
	return merged;
}

export function redactionMatches(line: LogicalLineView, regexes: readonly RegExp[]): RedactionMatch[] {
	return secretRanges(line.text, regexes).map((range) => ({
		key: `${line.blockId}:${line.firstRow}:${range.start}:${range.end}`,
		range: line.rangeOf(range.start, range.end),
	}));
}

export function maskedTextRows(rows: TextRows, regexes: readonly RegExp[], revealed: ReadonlySet<string>): TextRows {
	if (regexes.length === 0) return rows;
	const cache = new Map<string, string>();
	const maskedRow = (blockId: string, row: number): string => {
		const key = `${blockId}:${row}`;
		const hit = cache.get(key);
		if (hit !== undefined) return hit;
		const text = rows.rowText(blockId, row);
		const line = logicalLineAt(rows, blockId, row);
		if (!line) {
			cache.set(key, text);
			return text;
		}
		const offset = line.rowOffsets[row - line.firstRow] ?? 0;
		let out = text;
		for (const range of secretRanges(line.text, regexes)) {
			if (revealed.has(`${line.blockId}:${line.firstRow}:${range.start}:${range.end}`)) continue;
			const from = Math.max(range.start - offset, 0);
			const to = Math.min(range.end - offset, text.length);
			if (to <= from) continue;
			out = out.slice(0, from) + REDACTION_MASK.repeat(to - from) + out.slice(to);
		}
		cache.set(key, out);
		return out;
	};
	return { ...rows, rowText: maskedRow };
}

export function maskedCellRange(text: string, spans: ArrayLike<number>, from: number, to: number): { startCell: number; endCell: number } {
	return { startCell: cellAtOffset(text, spans, from), endCell: cellAtOffset(text, spans, to) };
}
