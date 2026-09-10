import type { FillSpan } from "./selection-fill.js";
import { compareBoundary, type BlockOrder, type SelectionPoint, type SelectionRange } from "./selection-model.js";

export type RowBox = Readonly<{
	blockId: string;
	row: number;
	rowCount: number;
	left: number;
	top: number;
	bottom: number;
	width: number;
}>;

function nearestRow(rows: readonly RowBox[], y: number): RowBox | null {
	let best: RowBox | null = null;
	let bestDistance = Number.POSITIVE_INFINITY;
	for (const row of rows) {
		const distance = y < row.top ? row.top - y : y >= row.bottom ? y - row.bottom : 0;
		if (distance < bestDistance) {
			bestDistance = distance;
			best = row;
			if (distance === 0) break;
		}
	}
	return best;
}

export function pointAtFromRows(
	rows: readonly RowBox[],
	x: number,
	y: number,
	cellWidth: number,
	cellHeight: number,
): SelectionPoint | null {
	const anchor = nearestRow(rows, y);
	if (!anchor || cellWidth <= 0 || cellHeight <= 0) return null;
	const rowDelta = Math.floor((y - anchor.top) / cellHeight);
	const row = Math.min(Math.max(anchor.row + rowDelta, 0), Math.max(anchor.rowCount - 1, 0));
	const offset = Math.max(x - anchor.left, 0);
	const column = Math.floor(offset / cellWidth);
	const side = offset - column * cellWidth > cellWidth / 2 ? "right" : "left";
	return { blockId: anchor.blockId, row, column, side };
}

export function rowFillSpan(
	range: SelectionRange,
	box: RowBox,
	order: BlockOrder,
	cellWidth: number,
): FillSpan | null {
	const here = { blockId: box.blockId, row: box.row, cell: 0 };
	const startsHere = range.start.blockId === box.blockId && range.start.row === box.row;
	const endsHere = range.end.blockId === box.blockId && range.end.row === box.row;
	if (!startsHere && compareBoundary(here, range.start, order) < 0) return null;
	if (!endsHere && compareBoundary(here, range.end, order) > 0) return null;
	const left = startsHere ? Math.min(range.start.cell * cellWidth, box.width) : 0;
	const right = endsHere ? Math.min(range.end.cell * cellWidth, box.width) : box.width;
	if (right - left <= 0.5) return null;
	return { left, right };
}
