import { cellSlice } from "./cell-width.js";
import { ROW_END, type SelectionRange } from "./selection-model.js";

export type TextRows = Readonly<{
	rowText(blockId: string, row: number): string;
	rowCount(blockId: string): number;
	blockIds: readonly string[];
}>;

function cut(text: string, from: number, to: number): string {
	const sliced = to === ROW_END && from === 0 ? text : cellSlice(text, from, to === ROW_END ? Number.MAX_SAFE_INTEGER : to);
	return sliced.replace(/ +$/u, "");
}

export function selectedText(range: SelectionRange, rows: TextRows): string {
	const first = rows.blockIds.indexOf(range.start.blockId);
	const last = rows.blockIds.indexOf(range.end.blockId);
	if (first < 0 || last < 0 || last < first) return "";
	const lines: string[] = [];
	for (let index = first; index <= last; index += 1) {
		const blockId = rows.blockIds[index]!;
		const fromRow = index === first ? range.start.row : 0;
		let toRow = index === last ? range.end.row : rows.rowCount(blockId) - 1;
		if (index === last && range.end.cell === 0 && toRow > fromRow) toRow -= 1;
		for (let row = fromRow; row <= toRow; row += 1) {
			const from = index === first && row === range.start.row ? range.start.cell : 0;
			const to = index === last && row === range.end.row ? range.end.cell : ROW_END;
			lines.push(cut(rows.rowText(blockId, row), from, to));
		}
	}
	return lines.join("\n");
}
