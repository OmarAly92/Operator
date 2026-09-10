import { describe, expect, it } from "vitest";
import { ROW_END, resolveRange, type SelectionPoint } from "./selection-model";

const order = (id: string) => Number(id);
const rows: Record<string, string[]> = { "0": ["first row here", "second row"], "1": ["third block row"] };
const rowText = (id: string, row: number) => rows[id]?.[row] ?? "";
const at = (blockId: string, row: number, column: number, side: "left" | "right" = "left"): SelectionPoint => ({ blockId, row, column, side });

describe("resolveRange", () => {
	it("orders head and tail whichever way the drag went", () => {
		const range = resolveRange({ head: at("1", 0, 3), tail: at("0", 0, 2), kind: "simple" }, order, rowText)!;
		expect(range.start).toEqual({ blockId: "0", row: 0, cell: 2 });
		expect(range.end).toEqual({ blockId: "1", row: 0, cell: 3 });
	});
	it("puts a right-side point after its cell, Warp's range_simple correction", () => {
		const range = resolveRange({ head: at("0", 0, 2, "right"), tail: at("0", 0, 5, "right"), kind: "simple" }, order, rowText)!;
		expect(range.start.cell).toBe(3);
		expect(range.end.cell).toBe(6);
	});
	it("is empty when both ends meet", () => {
		expect(resolveRange({ head: at("0", 0, 2, "right"), tail: at("0", 0, 3, "left"), kind: "simple" }, order, rowText)).toBeNull();
	});
	it("expands a word selection to word edges on both ends", () => {
		const range = resolveRange({ head: at("0", 0, 1), tail: at("0", 1, 8), kind: "word" }, order, rowText)!;
		expect(range.start).toEqual({ blockId: "0", row: 0, cell: 0 });
		expect(range.end).toEqual({ blockId: "0", row: 1, cell: 10 });
	});
	it("expands a line selection to the whole rows", () => {
		const range = resolveRange({ head: at("0", 1, 4), tail: at("0", 0, 4), kind: "line" }, order, rowText)!;
		expect(range.start).toEqual({ blockId: "0", row: 0, cell: 0 });
		expect(range.end).toEqual({ blockId: "0", row: 1, cell: ROW_END });
	});
});
