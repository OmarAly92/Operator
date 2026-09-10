import { describe, expect, it } from "vitest";
import { ROW_END } from "./selection-model";
import { selectedText, type TextRows } from "./selection-text";

const blocks: Record<string, string[]> = {
	a: ["alpha beta   ", "", "gamma 漢字 delta"],
	b: ["> hi                 "],
};
const rows: TextRows = {
	blockIds: ["a", "b"],
	rowCount: (id) => blocks[id]!.length,
	rowText: (id, row) => blocks[id]![row] ?? "",
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
	it("cuts a wide character by cell", () => {
		expect(selectedText({ start: { blockId: "a", row: 2, cell: 6 }, end: { blockId: "a", row: 2, cell: 8 } }, rows)).toBe("漢");
	});
});
