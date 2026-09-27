import { describe, expect, it } from "vitest";
import { RendererSelection } from "./renderer-selection";
import type { TextRows } from "./selection-text";
import { ALT_BLOCK_ID } from "./selection-view";

function rowsOf(blockId: string, lines: readonly string[], wrapped: ReadonlySet<number> = new Set(), firstRow = 0): TextRows {
	return {
		blockIds: [blockId],
		firstRow: () => firstRow,
		rowCount: () => lines.length,
		rowText: (_id, row) => lines[row - firstRow] ?? "",
		rowSpans: () => [],
		rowWrapped: (_id, row) => wrapped.has(row),
	};
}

function selectionOver(rows: { current: TextRows }): RendererSelection {
	return new RendererSelection({ hasCore: () => true, textRows: () => rows.current, repaint: () => undefined });
}

describe("RendererSelection follows row events", () => {
	it("follows a line that a narrower width cut into more rows", () => {
		const rows = { current: rowsOf("b", ["alpha beta gamma delta"]) };
		const selection = selectionOver(rows);
		selection.begin({ blockId: "b", row: 0, column: 11, side: "left" }, "simple");
		selection.update({ blockId: "b", row: 0, column: 15, side: "right" });
		expect(selection.text()).toBe("gamma");
		rows.current = rowsOf("b", ["alpha beta ", "gamma delta"], new Set([0]));
		selection.followRows({ trimmed: 0, remap: [[0, 0]], remapEnd: [1, 2] });
		expect(selection.text()).toBe("gamma");
	});
	it("moves a point on a row after the rewrapped ones by the end pair", () => {
		const rows = { current: rowsOf("b", ["aaaa bbbb", "tail"]) };
		const selection = selectionOver(rows);
		selection.begin({ blockId: "b", row: 1, column: 0, side: "left" }, "simple");
		selection.update({ blockId: "b", row: 1, column: 3, side: "right" });
		expect(selection.text()).toBe("tail");
		rows.current = rowsOf("b", ["aaaa ", "bbbb", "tail"], new Set([0]));
		selection.followRows({ trimmed: 0, remap: [[0, 0]], remapEnd: [1, 2] });
		expect(selection.text()).toBe("tail");
	});
	it("leaves an alternate-screen selection alone when the primary screen's rows move", () => {
		const rows = { current: rowsOf(ALT_BLOCK_ID, ["alt text here"]) };
		const selection = selectionOver(rows);
		selection.begin({ blockId: ALT_BLOCK_ID, row: 0, column: 0, side: "left" }, "simple");
		selection.update({ blockId: ALT_BLOCK_ID, row: 0, column: 2, side: "right" });
		expect(selection.text()).toBe("alt");
		selection.followRows({ trimmed: 0, remap: [[0, 3], [1, 4]], remapEnd: [2, 5] });
		expect(selection.text()).toBe("alt");
	});
	it("ignores a trim-only event", () => {
		const rows = { current: rowsOf("b", ["one", "two"]) };
		const selection = selectionOver(rows);
		selection.begin({ blockId: "b", row: 1, column: 0, side: "left" }, "line");
		selection.followRows({ trimmed: 1, remap: null, remapEnd: null });
		expect(selection.text()).toBe("two");
	});
});

describe("RendererSelection extends", () => {
	it("extends the current selection from its anchor and keeps its kind", () => {
		const rows = { current: rowsOf("b", ["alpha beta", "gamma delta"]) };
		const selection = selectionOver(rows);
		selection.begin({ blockId: "b", row: 0, column: 1, side: "left" }, "word");
		selection.update({ blockId: "b", row: 1, column: 7, side: "left" }, true);
		expect(selection.text()).toBe("alpha beta\ngamma delta");
	});
	it("selects from the last plain click when there is no selection", () => {
		const rows = { current: rowsOf("b", ["alpha beta", "gamma delta"]) };
		const selection = selectionOver(rows);
		selection.clear({ blockId: "b", row: 0, column: 6, side: "left" });
		selection.update({ blockId: "b", row: 1, column: 4, side: "right" }, true);
		expect(selection.text()).toBe("beta\ngamma");
	});
	it("does nothing on a plain update with no selection", () => {
		const rows = { current: rowsOf("b", ["alpha beta"]) };
		const selection = selectionOver(rows);
		selection.clear({ blockId: "b", row: 0, column: 0, side: "left" });
		selection.update({ blockId: "b", row: 0, column: 4, side: "right" });
		expect(selection.text()).toBeNull();
	});
	it("only places the caret when nothing was clicked before", () => {
		const rows = { current: rowsOf("b", ["alpha beta"]) };
		const selection = selectionOver(rows);
		selection.update({ blockId: "b", row: 0, column: 6, side: "left" }, true);
		expect(selection.text()).toBeNull();
		selection.update({ blockId: "b", row: 0, column: 9, side: "right" }, true);
		expect(selection.text()).toBe("beta");
	});
	it("keeps the caret on its text through a rewrap", () => {
		const rows = { current: rowsOf("b", ["alpha beta gamma delta"]) };
		const selection = selectionOver(rows);
		selection.clear({ blockId: "b", row: 0, column: 11, side: "left" });
		rows.current = rowsOf("b", ["alpha beta ", "gamma delta"], new Set([0]));
		selection.followRows({ trimmed: 0, remap: [[0, 0]], remapEnd: [1, 2] });
		selection.update({ blockId: "b", row: 1, column: 4, side: "right" }, true);
		expect(selection.text()).toBe("gamma");
	});
	it("replaces a caret whose block is gone", () => {
		const rows = { current: rowsOf("old", ["gone"]) };
		const selection = selectionOver(rows);
		selection.clear({ blockId: "old", row: 0, column: 0, side: "left" });
		rows.current = rowsOf("new", ["alpha beta"]);
		selection.update({ blockId: "new", row: 0, column: 6, side: "left" }, true);
		expect(selection.text()).toBeNull();
		selection.update({ blockId: "new", row: 0, column: 9, side: "right" }, true);
		expect(selection.text()).toBe("beta");
	});
});
