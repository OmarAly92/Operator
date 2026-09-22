import { describe, expect, it } from "vitest";
import { cellAtByte, cellAtOffset, cellCount, cellSlice, offsetAtByte, rowClusters, rowCoordinates } from "./clusters";

const HAN = "漢";
const ROCKET = "\u{1f680}";
const FAMILY = "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}";

describe("rowClusters", () => {
	it("gives every code point one cell when the row has no spans", () => {
		expect(rowClusters("ab", [])).toEqual([
			{ text: "a", start: 0, end: 1 },
			{ text: "b", start: 1, end: 2 },
		]);
	});
	it("follows the exported spans for wide, joined and multi-scalar clusters", () => {
		expect(rowClusters(`a${HAN}b`, [1, 4, 2])).toEqual([
			{ text: "a", start: 0, end: 1 },
			{ text: HAN, start: 1, end: 3 },
			{ text: "b", start: 3, end: 4 },
		]);
		expect(rowClusters("éx", [0, 3, 1])).toEqual([
			{ text: "é", start: 0, end: 1 },
			{ text: "x", start: 1, end: 2 },
		]);
		expect(rowClusters(`${FAMILY}!`, [0, 18, 2])).toEqual([
			{ text: FAMILY, start: 0, end: 2 },
			{ text: "!", start: 2, end: 3 },
		]);
	});
	it("gives a rocket the two cells the core gave it", () => {
		expect(cellCount(`${ROCKET}ab`, [0, 4, 2])).toBe(4);
	});
});

describe("cellSlice", () => {
	it("cuts ascii by column", () => {
		expect(cellSlice("hello world", [], 6, 11)).toBe("world");
	});
	it("keeps a wide character whose first cell is inside the cut", () => {
		expect(cellSlice(`a${HAN}b`, [1, 4, 2], 1, 3)).toBe(HAN);
		expect(cellSlice(`a${HAN}b`, [1, 4, 2], 2, 4)).toBe("b");
	});
	it("keeps combining marks with their base", () => {
		expect(cellSlice("éx", [0, 3, 1], 0, 1)).toBe("é");
	});
	it("clamps past the end", () => {
		expect(cellSlice("abc", [], 1, 99)).toBe("bc");
		expect(cellCount(`a${HAN}b`, [1, 4, 2])).toBe(4);
	});
});

describe("rowCoordinates", () => {
	it("maps cell, byte and utf-16 offset for ascii, wide and astral clusters", () => {
		expect(rowCoordinates("a漢b", [1, 4, 2])).toEqual([
			{ cell: 0, byte: 0, offset: 0 },
			{ cell: 1, byte: 1, offset: 1 },
			{ cell: 3, byte: 4, offset: 2 },
			{ cell: 4, byte: 5, offset: 3 },
		]);
		expect(cellAtOffset("a漢b", [1, 4, 2], 2)).toBe(3);
		expect(cellAtOffset("a漢b", [1, 4, 2], 3)).toBe(4);
		expect(cellAtByte("a漢b", [1, 4, 2], 4)).toBe(3);
		expect(offsetAtByte("a漢b", [1, 4, 2], 5)).toBe(3);
		expect(cellAtOffset("x🚀y", [1, 5, 2], 3)).toBe(3);
	});
});
