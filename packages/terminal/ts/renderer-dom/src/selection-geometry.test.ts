import { describe, expect, it } from "vitest";
import { pointAtFromRows, rowFillSpan, type RowBox } from "./selection-geometry";
import { ROW_END } from "./selection-model";

const cw = 8;
const ch = 16;
const box = (blockId: string, row: number, top: number, rowCount = 4): RowBox => ({ blockId, row, rowCount, left: 100, top, bottom: top + ch, width: 400 });
const rows = [box("a", 0, 0), box("a", 1, 16), box("b", 0, 60), box("b", 1, 76)];
const order = (id: string) => (id === "a" ? 0 : 1);

describe("pointAtFromRows", () => {
	it("floors the column and picks the side from the half cell", () => {
		expect(pointAtFromRows(rows, 100 + 8 * 3 + 2, 20, cw, ch)).toEqual({ blockId: "a", row: 1, column: 3, side: "left" });
		expect(pointAtFromRows(rows, 100 + 8 * 3 + 6, 20, cw, ch)).toEqual({ blockId: "a", row: 1, column: 3, side: "right" });
	});
	it("clamps left of the row to column zero", () => {
		expect(pointAtFromRows(rows, 10, 4, cw, ch)!.column).toBe(0);
	});
	it("extrapolates over a spacer from the nearest rendered row", () => {
		expect(pointAtFromRows(rows, 100, 45, cw, ch)).toEqual({ blockId: "a", row: 2, column: 0, side: "left" });
	});
	it("clamps the extrapolated row to the block", () => {
		expect(pointAtFromRows(rows, 100, 1000, cw, ch)!.row).toBe(3);
	});
	it("gives nothing with no rows", () => {
		expect(pointAtFromRows([], 1, 1, cw, ch)).toBeNull();
	});
});

describe("rowFillSpan", () => {
	const range = { start: { blockId: "a", row: 0, cell: 3 }, end: { blockId: "b", row: 1, cell: 5 } };
	it("runs the first row from its cell to the edge", () => {
		expect(rowFillSpan(range, rows[0]!, order, cw)).toEqual({ left: 24, right: 400 });
	});
	it("fills a middle row whole", () => {
		expect(rowFillSpan(range, rows[1]!, order, cw)).toEqual({ left: 0, right: 400 });
		expect(rowFillSpan(range, rows[2]!, order, cw)).toEqual({ left: 0, right: 400 });
	});
	it("runs the last row from the edge to its cell", () => {
		expect(rowFillSpan(range, rows[3]!, order, cw)).toEqual({ left: 0, right: 40 });
	});
	it("leaves rows outside the range alone", () => {
		expect(rowFillSpan({ start: { blockId: "a", row: 1, cell: 0 }, end: { blockId: "a", row: 1, cell: 2 } }, rows[0]!, order, cw)).toBeNull();
	});
	it("keeps a single row between its own cells", () => {
		expect(rowFillSpan({ start: { blockId: "a", row: 1, cell: 1 }, end: { blockId: "a", row: 1, cell: 3 } }, rows[1]!, order, cw)).toEqual({ left: 8, right: 24 });
	});
	it("paints nothing on a last row the range ends at the start of", () => {
		expect(rowFillSpan({ start: { blockId: "a", row: 0, cell: 0 }, end: { blockId: "a", row: 1, cell: 0 } }, rows[1]!, order, cw)).toBeNull();
	});
	it("runs a line selection to the edge", () => {
		expect(rowFillSpan({ start: { blockId: "a", row: 1, cell: 0 }, end: { blockId: "a", row: 1, cell: ROW_END } }, rows[1]!, order, cw)).toEqual({ left: 0, right: 400 });
	});
});
