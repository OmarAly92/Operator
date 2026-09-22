import type { RowRange, TerminalSnapshot } from "./types.js";

export type LogicalLine = Readonly<{ firstRow: number; rowCount: number; text: string; rowOffsets: readonly number[] }>;

export function joinLogicalLine(texts: readonly string[]): { text: string; rowOffsets: number[] } {
	const rowOffsets: number[] = [];
	let text = "";
	for (const piece of texts) {
		rowOffsets.push(text.length);
		text += piece;
	}
	return { text, rowOffsets };
}

export function snapshotLogicalLines(snapshot: TerminalSnapshot, range: RowRange, decoder: TextDecoder): LogicalLine[] {
	const rowCount = snapshot.rows.length / 2;
	const wrapped = (row: number): boolean => row >= 0 && row + 1 < rowCount && snapshot.rowWrapped[row] === 1;
	const rowText = (row: number): string => {
		const start = snapshot.rows[row * 2] ?? 0;
		const end = snapshot.rows[row * 2 + 1] ?? start;
		return end > start ? decoder.decode(snapshot.content.subarray(start, end)) : "";
	};
	let first = Math.min(Math.max(range.start, 0), rowCount);
	while (first > 0 && wrapped(first - 1)) first -= 1;
	const stop = Math.min(range.end, rowCount);
	const lines: LogicalLine[] = [];
	let row = first;
	while (row < stop) {
		let last = row;
		while (wrapped(last)) last += 1;
		const texts: string[] = [];
		for (let index = row; index <= last; index += 1) texts.push(rowText(index));
		const { text, rowOffsets } = joinLogicalLine(texts);
		lines.push({ firstRow: row, rowCount: last - row + 1, text, rowOffsets });
		row = last + 1;
	}
	return lines;
}
