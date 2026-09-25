import { describe, expect, it } from "vitest";
import { compareHighlights, EMPTY_ROW_PAINT, HIGHLIGHT_PRIORITY, rowPaint, SELECTION_COLOUR, type Highlight } from "./highlights";
import type { RowBox } from "./selection-geometry";
import { ROW_END, type BlockOrder } from "./selection-model";

const CELL = 10;
const order: BlockOrder = (blockId) => (blockId === "b" ? 0 : -1);
const box = (row: number): RowBox => ({ blockId: "b", row, firstRow: 100, rowCount: 10, left: 0, top: row * 20, bottom: row * 20 + 20, width: 400 });
const range = (startRow: number, startCell: number, endRow: number, endCell: number) => ({
	start: { blockId: "b", row: startRow, cell: startCell },
	end: { blockId: "b", row: endRow, cell: endCell },
});
const mark = (startCell: number, endCell: number, colour = "red", rank = 0, row = 101): Highlight => ({ kind: "mark", range: range(row, startCell, row, endCell), colour, rank });
const selection = (startCell: number, endCell: number, row = 101): Highlight => ({ kind: "selection", range: range(row, startCell, row, endCell), colour: SELECTION_COLOUR, rank: 0 });
const find = (row = 101): Highlight => ({ kind: "find", range: range(row, 0, row, ROW_END), colour: SELECTION_COLOUR, rank: 0 });
const current = (row = 101): Highlight => ({ kind: "find-current", range: range(row, 0, row, ROW_END), colour: SELECTION_COLOUR, rank: 0 });

describe("highlight priority", () => {
	it("orders selection over the current find hit over other find hits over user marks", () => {
		expect(HIGHLIGHT_PRIORITY.selection).toBeGreaterThan(HIGHLIGHT_PRIORITY["find-current"]);
		expect(HIGHLIGHT_PRIORITY["find-current"]).toBeGreaterThan(HIGHLIGHT_PRIORITY.find);
		expect(HIGHLIGHT_PRIORITY.find).toBeGreaterThan(HIGHLIGHT_PRIORITY.mark);
	});

	it("puts an earlier mark rule above a later one", () => {
		expect(compareHighlights(mark(0, 1, "red", 0), mark(0, 1, "blue", 1))).toBeLessThan(0);
		expect(compareHighlights(mark(0, 1, "blue", 1), selection(0, 1))).toBeGreaterThan(0);
	});
});

describe("rowPaint", () => {
	it("paints nothing on a row no highlight touches", () => {
		expect(rowPaint([mark(0, 3)], box(105), order, CELL)).toBe(EMPTY_ROW_PAINT);
	});

	it("lists fill layers top first: selection above a mark it overlaps", () => {
		const paint = rowPaint([mark(2, 8), selection(4, 6)], box(101), order, CELL);
		expect(paint.layers.map((layer) => layer.colour)).toEqual([SELECTION_COLOUR, "red"]);
		expect(paint.layers[0]!.span).toEqual({ left: 40, right: 60 });
		expect(paint.layers[1]!.span).toEqual({ left: 20, right: 80 });
	});

	it("keeps a find hit on the row's own colour when no mark shares the row", () => {
		const paint = rowPaint([find(), selection(1, 3)], box(101), order, CELL);
		expect(paint.findMatch).toBe(true);
		expect(paint.findFill).toBe(true);
		expect(paint.layers.map((layer) => layer.colour)).toEqual([SELECTION_COLOUR]);
	});

	it("lifts a find hit into a layer above the marks when a mark shares the row", () => {
		const paint = rowPaint([mark(2, 5), find(), selection(0, 1)], box(101), order, CELL);
		expect(paint.findMatch).toBe(true);
		expect(paint.findFill).toBe(false);
		expect(paint.layers.map((layer) => layer.colour)).toEqual([SELECTION_COLOUR, SELECTION_COLOUR, "red"]);
		expect(paint.layers[1]!.span).toEqual({ left: 0, right: 400 });
	});

	it("marks the current hit as an outline, not a second fill", () => {
		const paint = rowPaint([find(), current()], box(101), order, CELL);
		expect(paint.findCurrent).toBe(true);
		expect(paint.findFill).toBe(true);
		expect(paint.layers).toEqual([]);
	});

	it("paints a find hit even on a row with no width yet", () => {
		const paint = rowPaint([find()], { ...box(101), width: 0 }, order, CELL);
		expect(paint.findMatch).toBe(true);
	});

	it("fills a mark that wraps across rows to the edge of every row but its last", () => {
		const wrapped: Highlight = { kind: "mark", range: range(101, 30, 103, 4), colour: "red", rank: 0 };
		expect(rowPaint([wrapped], box(101), order, CELL).layers[0]!.span).toEqual({ left: 300, right: 400 });
		expect(rowPaint([wrapped], box(102), order, CELL).layers[0]!.span).toEqual({ left: 0, right: 400 });
		expect(rowPaint([wrapped], box(103), order, CELL).layers[0]!.span).toEqual({ left: 0, right: 40 });
	});

	it("drops an empty range", () => {
		expect(rowPaint([mark(4, 4)], box(101), order, CELL)).toBe(EMPTY_ROW_PAINT);
	});
});
