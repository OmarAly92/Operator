import { cellSlice } from "./clusters.js";
import { ROW_END, type SelectionRange } from "./selection-model.js";

export type TextRows = Readonly<{
	rowText(blockId: string, row: number): string;
	rowSpans(blockId: string, row: number): ArrayLike<number>;
	rowWrapped(blockId: string, row: number): boolean;
	rowLinkRuns?(blockId: string, row: number): ArrayLike<number>;
	linkUri?(id: number): string | null;
	firstRow(blockId: string): number;
	rowCount(blockId: string): number;
	blockIds: readonly string[];
}>;

function cut(text: string, spans: ArrayLike<number>, from: number, to: number): string {
	const sliced = to === ROW_END && from === 0 ? text : cellSlice(text, spans, from, to === ROW_END ? Number.MAX_SAFE_INTEGER : to);
	return sliced.replace(/ +$/u, "");
}

export function selectedText(range: SelectionRange, rows: TextRows): string {
	const first = rows.blockIds.indexOf(range.start.blockId);
	const last = rows.blockIds.indexOf(range.end.blockId);
	if (first < 0 || last < 0 || last < first) return "";
	const lines: string[] = [];
	for (let index = first; index <= last; index += 1) {
		const blockId = rows.blockIds[index]!;
		const fromRow = Math.max(index === first ? range.start.row : rows.firstRow(blockId), rows.firstRow(blockId));
		let toRow = index === last ? range.end.row : rows.firstRow(blockId) + rows.rowCount(blockId) - 1;
		if (index === last && range.end.cell === 0 && toRow > fromRow) toRow -= 1;
		let pending = "";
		for (let row = fromRow; row <= toRow; row += 1) {
			const from = index === first && row === range.start.row ? range.start.cell : 0;
			const to = index === last && row === range.end.row ? range.end.cell : ROW_END;
			const text = rows.rowText(blockId, row);
			const spans = rows.rowSpans(blockId, row);
			const joins = row < toRow && rows.rowWrapped(blockId, row);
			if (joins) {
				pending += to === ROW_END && from === 0 ? text : cellSlice(text, spans, from, to === ROW_END ? Number.MAX_SAFE_INTEGER : to);
				continue;
			}
			lines.push(pending + cut(text, spans, from, to));
			pending = "";
		}
		if (pending !== "") lines.push(pending.replace(/ +$/u, ""));
	}
	return lines.join("\n");
}
