import { describe, expect, it } from "vitest";
import { anchorOf, followAnchor, followPoint, pointOf } from "./selection-anchor";
import type { TextRows } from "./selection-text";
import { ALT_BLOCK_ID } from "./selection-view";

function rowsOf(lines: readonly string[], wrapped: ReadonlySet<number> = new Set(), indents: ReadonlyMap<number, number> = new Map(), firstRow = 0): TextRows {
	return {
		blockIds: ["b"],
		firstRow: () => firstRow,
		rowCount: () => lines.length,
		rowText: (_id, row) => lines[row - firstRow] ?? "",
		rowSpans: () => [],
		rowWrapped: (_id, row) => wrapped.has(row),
		rowIndent: (_id, row) => indents.get(row) ?? 0,
	};
}

describe("line anchors", () => {
	it("measures a point from the first row of its logical line", () => {
		const rows = rowsOf(["alpha beta ", "gamma delta"], new Set([0]));
		expect(anchorOf({ blockId: "b", row: 1, column: 3, side: "left" }, rows)).toEqual({ blockId: "b", lineRow: 0, cells: 14, side: "left" });
	});
	it("finds the same cell after the line is cut differently", () => {
		const before = rowsOf(["alpha beta gamma delta"]);
		const anchor = anchorOf({ blockId: "b", row: 0, column: 11, side: "left" }, before)!;
		const after = rowsOf(["alpha beta ", "gamma delta"], new Set([0]));
		expect(pointOf(anchor, after)).toEqual({ blockId: "b", row: 1, column: 0, side: "left" });
	});
	it("leaves out a continuation row's hanging indent", () => {
		const rows = rowsOf(["- aaaa bbbb ", "cc dd ee"], new Set([0]), new Map([[1, 2]]));
		const anchor = anchorOf({ blockId: "b", row: 1, column: 5, side: "left" }, rows)!;
		expect(anchor.cells).toBe(15);
		expect(pointOf(anchor, rows)).toEqual({ blockId: "b", row: 1, column: 5, side: "left" });
	});
	it("keeps a point past a wrapped row's text on that row", () => {
		const rows = rowsOf(["abc", "def"], new Set([0]));
		expect(anchorOf({ blockId: "b", row: 0, column: 9, side: "right" }, rows)!.cells).toBe(2);
	});
	it("has no anchor for the alternate screen or a row outside its block", () => {
		expect(anchorOf({ blockId: ALT_BLOCK_ID, row: 0, column: 0, side: "left" }, rowsOf(["x"]))).toBeNull();
		expect(anchorOf({ blockId: "b", row: 7, column: 0, side: "left" }, rowsOf(["x"]))).toBeNull();
	});
	it("moves a line start and a point with a row event, but never an alternate-screen point", () => {
		const event = { trimmed: 0, remap: [[0, 0], [1, 0]] as const, remapEnd: [2, 1] as const };
		expect(followAnchor({ blockId: "b", lineRow: 4, cells: 0, side: "left" }, event).lineRow).toBe(3);
		expect(followPoint({ blockId: "b", row: 1, column: 2, side: "left" }, event).row).toBe(0);
		expect(followPoint({ blockId: ALT_BLOCK_ID, row: 1, column: 2, side: "left" }, event).row).toBe(1);
	});
});
