import { afterEach, describe, expect, it, vi } from "vitest";
import { logicalLineAt } from "./logical-lines";
import { compileMarks, markHighlights, MarkCache, MARK_CACHE_LINES, markSpans, visibleLogicalLines, type RowId } from "./marks";
import type { TextRows } from "./selection-text";

const RED = "rgb(255 0 0 / 0.4)";
const BLUE = "rgb(0 0 255 / 0.4)";

function textRows(rows: readonly string[], wrapped: readonly number[] = [], firstRow = 100): TextRows {
	return {
		blockIds: ["b"],
		firstRow: () => firstRow,
		rowCount: () => rows.length,
		rowText: (_id, row) => rows[row - firstRow] ?? "",
		rowSpans: () => [],
		rowWrapped: (_id, row) => wrapped.includes(row),
	};
}

function rendered(rows: readonly number[]): RowId[] {
	return rows.map((row) => ({ blockId: "b", row }));
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("compileMarks", () => {
	it("reads a literal pattern as plain text in any case", () => {
		const [mark] = compileMarks([{ pattern: "a.b", regex: false, colour: RED }]);
		expect(markSpans("A.B axb a.b", [mark!])).toEqual([
			{ start: 0, end: 3, rank: 0 },
			{ start: 8, end: 11, rank: 0 },
		]);
	});

	it("reads a regex pattern as written, case included", () => {
		const marks = compileMarks([{ pattern: "err(or)?", regex: true, colour: RED }]);
		expect(markSpans("err ERROR error", marks)).toEqual([
			{ start: 0, end: 3, rank: 0 },
			{ start: 10, end: 15, rank: 0 },
		]);
	});

	it("drops an invalid regex and keeps the rules around it", () => {
		const marks = compileMarks([
			{ pattern: "(unclosed", regex: true, colour: RED },
			{ pattern: "ok", regex: false, colour: BLUE },
		]);
		expect(marks.map((mark) => mark.colour)).toEqual([BLUE]);
	});

	it("drops an empty pattern and an empty colour", () => {
		expect(compileMarks([
			{ pattern: "", regex: false, colour: RED },
			{ pattern: "x", regex: false, colour: "" },
		])).toEqual([]);
	});

	it("drops a colour the browser does not accept", () => {
		vi.stubGlobal("CSS", { supports: (_property: string, value: string) => value !== "not-a-colour" });
		const marks = compileMarks([
			{ pattern: "x", regex: false, colour: "not-a-colour" },
			{ pattern: "y", regex: false, colour: RED },
		]);
		expect(marks.map((mark) => mark.colour)).toEqual([RED]);
	});
});

describe("markSpans", () => {
	it("yields nothing for a pattern that only matches empty text", () => {
		for (const pattern of ["^", "$", "\\b", "x*", "(?=a)"]) {
			expect(markSpans("aaa bbb", compileMarks([{ pattern, regex: true, colour: RED }]))).toEqual([]);
		}
	});

	it("keeps the non-empty matches of a pattern that can also match empty text", () => {
		expect(markSpans("axxb", compileMarks([{ pattern: "x*", regex: true, colour: RED }]))).toEqual([{ start: 1, end: 3, rank: 0 }]);
	});

	it("merges touching matches of one rule into one span", () => {
		expect(markSpans("abcd", compileMarks([{ pattern: ".", regex: true, colour: RED }]))).toEqual([{ start: 0, end: 4, rank: 0 }]);
	});

	it("ranks each rule by its place in the list", () => {
		const marks = compileMarks([
			{ pattern: "fail", regex: false, colour: RED },
			{ pattern: "failed", regex: false, colour: BLUE },
		]);
		expect(markSpans("it failed", marks)).toEqual([
			{ start: 3, end: 7, rank: 0 },
			{ start: 3, end: 9, rank: 1 },
		]);
	});

	it("gives the same answer when run twice on a global regex", () => {
		const marks = compileMarks([{ pattern: "a", regex: false, colour: RED }]);
		expect(markSpans("a a", marks)).toEqual(markSpans("a a", marks));
	});
});

describe("visibleLogicalLines", () => {
	it("joins a soft-wrapped line once, whichever of its rows are painted", () => {
		const rows = textRows(["the err", "or here", "next"], [100]);
		const lines = visibleLogicalLines(rows, rendered([100, 101, 102]));
		expect(lines.map((line) => [line.firstRow, line.text])).toEqual([
			[100, "the error here"],
			[102, "next"],
		]);
	});
});

describe("markHighlights", () => {
	it("places a match that crosses a soft wrap on both rows, in stable rows", () => {
		const rows = textRows(["the err", "or here"], [100]);
		const marks = compileMarks([{ pattern: "error", regex: false, colour: RED }]);
		const [highlight] = markHighlights(visibleLogicalLines(rows, rendered([100, 101])), marks, new MarkCache());
		expect(highlight).toEqual({
			kind: "mark",
			range: { start: { blockId: "b", row: 100, cell: 4 }, end: { blockId: "b", row: 101, cell: 2 } },
			colour: RED,
			rank: 0,
		});
	});

	it("follows the text when the same line moves to other stable rows", () => {
		const marks = compileMarks([{ pattern: "error", regex: false, colour: RED }]);
		const cache = new MarkCache();
		const before = markHighlights(visibleLogicalLines(textRows(["an error"], [], 100), rendered([100])), marks, cache);
		const after = markHighlights(visibleLogicalLines(textRows(["an error"], [], 40), rendered([40])), marks, cache);
		expect(before[0]!.range.start).toEqual({ blockId: "b", row: 100, cell: 3 });
		expect(after[0]!.range.start).toEqual({ blockId: "b", row: 40, cell: 3 });
	});

	it("returns nothing and touches no text when there are no rules", () => {
		const rowText = vi.fn(() => "error");
		const rows = { ...textRows(["error"]), rowText };
		expect(markHighlights(visibleLogicalLines(rows, []), [], new MarkCache())).toEqual([]);
		expect(rowText).not.toHaveBeenCalled();
	});
});

describe("MarkCache", () => {
	it("reuses a line's highlights while its text and wrap are unchanged", () => {
		const marks = compileMarks([{ pattern: "a", regex: false, colour: RED }]);
		const cache = new MarkCache();
		const line = logicalLineAt(textRows(["a b a"]), "b", 100)!;
		const first = cache.highlights(line, marks);
		expect(cache.highlights(logicalLineAt(textRows(["a b a"]), "b", 100)!, marks)).toBe(first);
		expect(cache.highlights(logicalLineAt(textRows(["a b aa"]), "b", 100)!, marks)).not.toBe(first);
	});

	it("recomputes when the same text wraps differently", () => {
		const marks = compileMarks([{ pattern: "error", regex: false, colour: RED }]);
		const cache = new MarkCache();
		const wide = cache.highlights(logicalLineAt(textRows(["an error"]), "b", 100)!, marks);
		const narrow = cache.highlights(logicalLineAt(textRows(["an er", "ror"], [100]), "b", 100)!, marks);
		expect(wide[0]!.range.end).toEqual({ blockId: "b", row: 100, cell: 8 });
		expect(narrow[0]!.range.end).toEqual({ blockId: "b", row: 101, cell: 3 });
	});

	it("never holds more than its line budget", () => {
		const marks = compileMarks([{ pattern: "a", regex: false, colour: RED }]);
		const cache = new MarkCache();
		for (let index = 0; index < MARK_CACHE_LINES * 2 + 3; index += 1) cache.highlights(logicalLineAt(textRows(["a"], [], index), "b", index)!, marks);
		expect(cache.size()).toBeLessThanOrEqual(MARK_CACHE_LINES);
	});
});
