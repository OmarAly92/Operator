import { joinLogicalLine } from "@operator/terminal-core";
import { cellAtOffset, offsetAtByte, rowCoordinates } from "./clusters.js";
import type { TextRows } from "./selection-text.js";

export type LinkRange = Readonly<{ blockId: string; startRow: number; startCell: number; endRow: number; endCell: number }>;
export type LinkRun = Readonly<{ startOffset: number; endOffset: number; linkId: number }>;
export type LogicalLineView = Readonly<{
	blockId: string;
	firstRow: number;
	rowCount: number;
	text: string;
	rowOffsets: readonly number[];
	linkRuns: readonly LinkRun[];
	rangeOf(startOffset: number, endOffset: number): LinkRange;
	offsetAt(row: number, cell: number): number | null;
	linkUri(id: number): string | null;
}>;

export function logicalLineAt(rows: TextRows, blockId: string, row: number): LogicalLineView | null {
	if (!rows.blockIds.includes(blockId)) return null;
	const first = rows.firstRow(blockId);
	const count = rows.rowCount(blockId);
	if (count <= 0 || row < first || row >= first + count) return null;
	let start = row;
	while (start > first && rows.rowWrapped(blockId, start - 1)) start -= 1;
	let end = row;
	while (end + 1 < first + count && rows.rowWrapped(blockId, end)) end += 1;
	const texts: string[] = [];
	const spans: ArrayLike<number>[] = [];
	for (let index = start; index <= end; index += 1) {
		texts.push(rows.rowText(blockId, index));
		spans.push(rows.rowSpans(blockId, index));
	}
	const { text, rowOffsets } = joinLogicalLine(texts);
	const linkRuns: LinkRun[] = [];
	for (let index = 0; index < texts.length; index += 1) {
		const runs = rows.rowLinkRuns?.(blockId, start + index) ?? [];
		for (let k = 0; k + 2 < runs.length; k += 3) {
			linkRuns.push({
				startOffset: rowOffsets[index]! + offsetAtByte(texts[index]!, spans[index]!, runs[k]!),
				endOffset: rowOffsets[index]! + offsetAtByte(texts[index]!, spans[index]!, runs[k + 1]!),
				linkId: runs[k + 2]!,
			});
		}
	}
	const rowIndexOf = (offset: number): number => {
		let index = rowOffsets.length - 1;
		while (index > 0 && rowOffsets[index]! > offset) index -= 1;
		return index;
	};
	const rangeOf = (startOffset: number, endOffset: number): LinkRange => {
		const startIndex = rowIndexOf(startOffset);
		const endIndex = endOffset > startOffset ? rowIndexOf(endOffset - 1) : startIndex;
		return {
			blockId,
			startRow: start + startIndex,
			startCell: cellAtOffset(texts[startIndex]!, spans[startIndex]!, startOffset - rowOffsets[startIndex]!),
			endRow: start + endIndex,
			endCell: cellAtOffset(texts[endIndex]!, spans[endIndex]!, endOffset - rowOffsets[endIndex]!),
		};
	};
	const offsetAt = (row: number, cell: number): number | null => {
		const index = row - start;
		if (index < 0 || index >= texts.length) return null;
		const coordinates = rowCoordinates(texts[index]!, spans[index]!);
		for (let k = 0; k + 1 < coordinates.length; k += 1) {
			if (cell >= coordinates[k]!.cell && cell < coordinates[k + 1]!.cell) return rowOffsets[index]! + coordinates[k]!.offset;
		}
		return null;
	};
	return {
		blockId,
		firstRow: start,
		rowCount: end - start + 1,
		text,
		rowOffsets,
		linkRuns,
		rangeOf,
		offsetAt,
		linkUri: (id) => rows.linkUri?.(id) ?? null,
	};
}

export function rangeContains(range: LinkRange, row: number, cell: number): boolean {
	if (row < range.startRow || row > range.endRow) return false;
	if (row === range.startRow && cell < range.startCell) return false;
	if (row === range.endRow && cell >= range.endCell) return false;
	return true;
}

export function rangesOverlap(a: LinkRange, b: LinkRange): boolean {
	if (a.blockId !== b.blockId) return false;
	const aStart = a.startRow * 1e9 + a.startCell;
	const aEnd = a.endRow * 1e9 + a.endCell;
	const bStart = b.startRow * 1e9 + b.startCell;
	const bEnd = b.endRow * 1e9 + b.endCell;
	return aStart < bEnd && bStart < aEnd;
}
