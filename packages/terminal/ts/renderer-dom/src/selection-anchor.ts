import { remapStableRow, type RowEvent } from "@operator/terminal-core";
import { cellCount } from "./clusters.js";
import type { SelectionPoint, SelectionSide } from "./selection-model.js";
import type { TextRows } from "./selection-text.js";
import { ALT_BLOCK_ID } from "./selection-view.js";

export type LineAnchor = Readonly<{ blockId: string; lineRow: number; cells: number; side: SelectionSide }>;

function rowCells(rows: TextRows, blockId: string, row: number): number {
	return cellCount(rows.rowText(blockId, row), rows.rowSpans(blockId, row));
}

function inBlock(rows: TextRows, blockId: string, row: number): boolean {
	const first = rows.firstRow(blockId);
	return row >= first && row < first + rows.rowCount(blockId);
}

export function anchorOf(point: SelectionPoint, rows: TextRows): LineAnchor | null {
	if (point.blockId === ALT_BLOCK_ID || !inBlock(rows, point.blockId, point.row)) return null;
	const first = rows.firstRow(point.blockId);
	let lineRow = point.row;
	while (lineRow > first && rows.rowWrapped(point.blockId, lineRow - 1)) lineRow -= 1;
	let cells = Math.max(point.column - (rows.rowIndent?.(point.blockId, point.row) ?? 0), 0);
	if (rows.rowWrapped(point.blockId, point.row)) cells = Math.min(cells, Math.max(rowCells(rows, point.blockId, point.row) - 1, 0));
	for (let row = lineRow; row < point.row; row += 1) cells += rowCells(rows, point.blockId, row);
	return { blockId: point.blockId, lineRow, cells, side: point.side };
}

export function pointOf(anchor: LineAnchor, rows: TextRows): SelectionPoint | null {
	if (!inBlock(rows, anchor.blockId, anchor.lineRow)) return null;
	const last = rows.firstRow(anchor.blockId) + rows.rowCount(anchor.blockId) - 1;
	let row = anchor.lineRow;
	let cells = anchor.cells;
	while (row < last && rows.rowWrapped(anchor.blockId, row)) {
		const width = rowCells(rows, anchor.blockId, row);
		if (cells < width) break;
		cells -= width;
		row += 1;
	}
	return { blockId: anchor.blockId, row, column: cells + (rows.rowIndent?.(anchor.blockId, row) ?? 0), side: anchor.side };
}

export function followAnchor(anchor: LineAnchor, event: RowEvent): LineAnchor {
	return { ...anchor, lineRow: remapStableRow(anchor.lineRow, event) };
}

export function followPoint(point: SelectionPoint, event: RowEvent): SelectionPoint {
	return point.blockId === ALT_BLOCK_ID ? point : { ...point, row: remapStableRow(point.row, event) };
}

export function rowsKeepTheirShape(top: number, bottom: number, event: RowEvent): boolean {
	const base = remapStableRow(top, event);
	for (let row = top + 1; row <= bottom; row += 1) if (remapStableRow(row, event) !== base + (row - top)) return false;
	return true;
}
