import { describe, expect, it } from "vitest";
import { cellCount, cellSlice, cellWidthOf } from "./cell-width";

describe("cellWidthOf", () => {
	it("gives ascii one cell", () => {
		expect(cellWidthOf("a".codePointAt(0)!)).toBe(1);
	});
	it("gives CJK and fullwidth two cells", () => {
		expect(cellWidthOf("漢".codePointAt(0)!)).toBe(2);
		expect(cellWidthOf("Ａ".codePointAt(0)!)).toBe(2);
	});
	it("gives combining marks and joiners no cell", () => {
		expect(cellWidthOf(0x0301)).toBe(0);
		expect(cellWidthOf(0x200d)).toBe(0);
	});
	it("gives emoji presentation two cells", () => {
		expect(cellWidthOf("😀".codePointAt(0)!)).toBe(2);
	});
});

describe("cellSlice", () => {
	it("cuts ascii by column", () => {
		expect(cellSlice("hello world", 6, 11)).toBe("world");
	});
	it("keeps a wide character whose first cell is inside the cut", () => {
		expect(cellSlice("a漢b", 1, 3)).toBe("漢");
		expect(cellSlice("a漢b", 2, 4)).toBe("b");
	});
	it("keeps combining marks with their base", () => {
		expect(cellSlice("éx", 0, 1)).toBe("é");
	});
	it("clamps past the end", () => {
		expect(cellSlice("abc", 1, 99)).toBe("bc");
		expect(cellCount("a漢b")).toBe(4);
	});
});
