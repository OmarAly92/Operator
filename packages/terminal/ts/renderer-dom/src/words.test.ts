import { describe, expect, it } from "vitest";
import { isWordBoundary, wordCellRange } from "./words";

describe("isWordBoundary", () => {
	it("treats whitespace and Warp's punctuation set as boundaries", () => {
		for (const c of [" ", "\t", "(", ")", "[", "]", "{", "}", "'", '"', ",", ";", ":", "<", ">", "?", "!", "=", "+", "*", "&", "|", "^", "%", "$", "#", "@", "`", "«", "»"]) {
			expect(isWordBoundary(c), c).toBe(true);
		}
	});
	it("keeps Warp's allowlist and underscore inside a word", () => {
		for (const c of ["-", ".", "~", "/", "\\", "_", "a", "9", "漢"]) {
			expect(isWordBoundary(c), c).toBe(false);
		}
	});
});

describe("wordCellRange", () => {
	it("selects a path as one word", () => {
		const text = "see src/row-builder.ts now";
		expect(wordCellRange(text, [], 8)).toEqual({ start: 4, end: 22 });
	});
	it("selects only the boundary character under the pointer", () => {
		expect(wordCellRange("a (b)", [], 2)).toEqual({ start: 2, end: 3 });
	});
	it("clamps a pointer past the text to the last word", () => {
		expect(wordCellRange("ab", [], 10)).toEqual({ start: 0, end: 2 });
	});
	it("steps over a wide cluster as one cell pair", () => {
		expect(wordCellRange(`ab ${"漢"}c d`, [3, 6, 2], 4)).toEqual({ start: 3, end: 6 });
	});
});
