import { CELL_SPAN_WORDS, type SecretPattern } from "@operator/terminal-core";
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

function utf16OffsetToByte(text: string, offset: number): number {
	let bytes = 0;
	for (const character of text.slice(0, offset)) {
		const codePoint = character.codePointAt(0) ?? 0;
		if (codePoint < 0x80) bytes += 1;
		else if (codePoint < 0x800) bytes += 2;
		else if (codePoint < 0x10000) bytes += 3;
		else bytes += 4;
	}
	return bytes;
}

type MaskEdit = Readonly<{ fromByte: number; toByte: number; deltaByte: number }>;

function maskedRowSpans(spans: ArrayLike<number>, edits: readonly MaskEdit[]): number[] {
	if (edits.length === 0) return Array.from(spans);
	const out: number[] = [];
	const count = Math.floor(spans.length / CELL_SPAN_WORDS);
	for (let index = 0; index < count; index += 1) {
		const start = spans[index * CELL_SPAN_WORDS]!;
		const end = spans[index * CELL_SPAN_WORDS + 1]!;
		const width = spans[index * CELL_SPAN_WORDS + 2]!;
		let dropped = false;
		let shift = 0;
		for (const edit of edits) {
			if (start >= edit.fromByte && start < edit.toByte) {
				dropped = true;
				break;
			}
			if (start >= edit.toByte) shift += edit.deltaByte;
		}
		if (dropped) continue;
		out.push(start + shift, end + shift, width);
	}
	return out;
}

export function maskedTextRows(rows: TextRows, regexes: readonly RegExp[], revealed: ReadonlySet<string>): TextRows {
	if (regexes.length === 0) return rows;
	const cache = new Map<string, { text: string; spans: number[] }>();
	const maskedRow = (blockId: string, row: number): { text: string; spans: number[] } => {
		const key = `${blockId}:${row}`;
		const hit = cache.get(key);
		if (hit !== undefined) return hit;
		const text = rows.rowText(blockId, row);
		const spans = rows.rowSpans(blockId, row);
		const line = logicalLineAt(rows, blockId, row);
		if (!line) {
			const result = { text, spans: Array.from(spans) };
			cache.set(key, result);
			return result;
		}
		const offset = line.rowOffsets[row - line.firstRow] ?? 0;
		const edits: MaskEdit[] = [];
		let out = text;
		for (const range of secretRanges(line.text, regexes)) {
			if (revealed.has(`${line.blockId}:${line.firstRow}:${range.start}:${range.end}`)) continue;
			const from = Math.max(range.start - offset, 0);
			const to = Math.min(range.end - offset, text.length);
			if (to <= from) continue;
			const fromByte = utf16OffsetToByte(text, from);
			const toByte = utf16OffsetToByte(text, to);
			out = out.slice(0, from) + REDACTION_MASK.repeat(to - from) + out.slice(to);
			edits.push({ fromByte, toByte, deltaByte: to - from - (toByte - fromByte) });
		}
		const result = { text: out, spans: maskedRowSpans(spans, edits) };
		cache.set(key, result);
		return result;
	};
	return {
		...rows,
		rowText: (blockId, row) => maskedRow(blockId, row).text,
		rowSpans: (blockId, row) => maskedRow(blockId, row).spans,
	};
}

export function maskedCellRange(text: string, spans: ArrayLike<number>, from: number, to: number): { startCell: number; endCell: number } {
	return { startCell: cellAtOffset(text, spans, from), endCell: cellAtOffset(text, spans, to) };
}
