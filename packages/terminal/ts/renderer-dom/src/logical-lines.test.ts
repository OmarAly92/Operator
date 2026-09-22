import { describe, expect, it } from "vitest";
import { logicalLineAt, rangeContains } from "./logical-lines";
import type { TextRows } from "./selection-text";

const rows: TextRows = {
	blockIds: ["b"],
	firstRow: () => 10,
	rowCount: () => 4,
	rowText: (_id, row) => ["one ", "two", "three", "four"][row - 10] ?? "",
	rowSpans: () => [],
	rowWrapped: (_id, row) => row === 10,
	rowLinkRuns: (_id, row) => (row === 10 ? [0, 3, 7] : row === 11 ? [0, 3, 7] : []),
	linkUri: (id) => (id === 7 ? "https://seven" : null),
};

describe("logicalLineAt", () => {
	it("maps a cell back to its line offset across the wrap, wide cells included, and nothing past the text", () => {
		const line = logicalLineAt(rows, "b", 10)!;
		expect(line.offsetAt(10, 2)).toBe(2);
		expect(line.offsetAt(11, 1)).toBe(5);
		expect(line.offsetAt(11, 3)).toBeNull();
		expect(line.offsetAt(12, 0)).toBeNull();
		const wide = logicalLineAt({ ...rows, rowText: () => "漢a", rowSpans: () => [0, 3, 2], rowWrapped: () => false }, "b", 10)!;
		expect([0, 1, 2, 3].map((cell) => wide.offsetAt(10, cell))).toEqual([0, 0, 1, null]);
	});
	it("joins the wrapped pair and leaves the others alone", () => {
		const line = logicalLineAt(rows, "b", 11)!;
		expect(line).toMatchObject({ blockId: "b", firstRow: 10, rowCount: 2, text: "one two", rowOffsets: [0, 4] });
		expect(logicalLineAt(rows, "b", 12)).toMatchObject({ firstRow: 12, rowCount: 1, text: "three" });
		expect(logicalLineAt(rows, "b", 9)).toBeNull();
		expect(logicalLineAt(rows, "x", 10)).toBeNull();
	});
	it("maps string offsets to cells across the wrap and lifts link runs into line offsets", () => {
		const line = logicalLineAt(rows, "b", 10)!;
		expect(line.rangeOf(2, 6)).toEqual({ blockId: "b", startRow: 10, startCell: 2, endRow: 11, endCell: 2 });
		expect(line.rangeOf(0, 4)).toEqual({ blockId: "b", startRow: 10, startCell: 0, endRow: 10, endCell: 4 });
		expect(line.linkRuns).toEqual([
			{ startOffset: 0, endOffset: 3, linkId: 7 },
			{ startOffset: 4, endOffset: 7, linkId: 7 },
		]);
		expect(line.linkUri(7)).toBe("https://seven");
	});
});

describe("rangeContains", () => {
	const range = { blockId: "b", startRow: 10, startCell: 2, endRow: 11, endCell: 2 };
	it("is inclusive of the start cell, exclusive of the end cell, and whole rows in between", () => {
		expect(rangeContains(range, 10, 1)).toBe(false);
		expect(rangeContains(range, 10, 2)).toBe(true);
		expect(rangeContains(range, 10, 70)).toBe(true);
		expect(rangeContains(range, 11, 1)).toBe(true);
		expect(rangeContains(range, 11, 2)).toBe(false);
		expect(rangeContains(range, 12, 0)).toBe(false);
	});
});
