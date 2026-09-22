import { describe, expect, it } from "vitest";
import { ROW_END } from "./selection-model";
import { selectedText, type TextRows } from "./selection-text";

const blocks: Record<string, string[]> = {
	a: ["alpha beta   ", "", "gamma 漢字 delta"],
	b: ["> hi                 "],
};
const rows: TextRows = {
	blockIds: ["a", "b"],
	firstRow: () => 0,
	rowCount: (id) => blocks[id]!.length,
	rowText: (id, row) => blocks[id]![row] ?? "",
	rowSpans: (id, row) => (id === "a" && row === 2 ? [6, 9, 2, 9, 12, 2] : []),
};

describe("selectedText", () => {
	it("cuts the first and last rows by cell and joins rows with newlines", () => {
		expect(selectedText({ start: { blockId: "a", row: 0, cell: 6 }, end: { blockId: "a", row: 2, cell: 5 } }, rows)).toBe("beta\n\ngamma");
	});
	it("keeps a blank row inside as an empty line and trims trailing spaces", () => {
		expect(selectedText({ start: { blockId: "a", row: 0, cell: 0 }, end: { blockId: "a", row: 1, cell: ROW_END } }, rows)).toBe("alpha beta\n");
	});
	it("puts one newline between blocks", () => {
		expect(selectedText({ start: { blockId: "a", row: 2, cell: 0 }, end: { blockId: "b", row: 0, cell: 4 } }, rows)).toBe("gamma 漢字 delta\n> hi");
	});
	it("excludes a last row the range ends at the start of", () => {
		expect(selectedText({ start: { blockId: "a", row: 0, cell: 0 }, end: { blockId: "a", row: 1, cell: 0 } }, rows)).toBe("alpha beta");
	});
	it("starts at the block's first retained row when the range begins above it", () => {
		const trimmed: TextRows = { blockIds: ["a"], firstRow: () => 1, rowCount: () => 2, rowText: (_id, row) => blocks.a![row] ?? "", rowSpans: () => [] };
		expect(selectedText({ start: { blockId: "a", row: 0, cell: 3 }, end: { blockId: "a", row: 2, cell: 5 } }, trimmed)).toBe("\ngamma");
	});
	it("cuts a wide character by cell", () => {
		expect(selectedText({ start: { blockId: "a", row: 2, cell: 6 }, end: { blockId: "a", row: 2, cell: 8 } }, rows)).toBe("漢");
	});
	it("cuts by cells, not code points, across a wide cluster", () => {
		expect(selectedText({ start: { blockId: "a", row: 2, cell: 6 }, end: { blockId: "a", row: 2, cell: 8 } }, rows)).toBe("漢");
	});
	it("walks whole rows from the block's first stable row", () => {
		const shifted: TextRows = { blockIds: ["a"], firstRow: () => 100, rowCount: () => 3, rowText: (_id, row) => blocks.a![row - 100] ?? "", rowSpans: () => [] };
		expect(selectedText({ start: { blockId: "a", row: 100, cell: 6 }, end: { blockId: "a", row: 102, cell: 5 } }, shifted)).toBe("beta\n\ngamma");
	});
});
