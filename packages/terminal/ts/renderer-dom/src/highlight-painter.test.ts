import { describe, expect, it, vi } from "vitest";
import { ATTR_ROW_ACTIVE, ATTR_ROW_MATCH, BUCKET_ROWS, CLASS_ROW_ACTIVE, CLASS_ROW_MATCH, HighlightIndex, HighlightPainter } from "./highlight-painter";
import { SELECTION_COLOUR, type Highlight } from "./highlights";
import { ROW_END, type BlockOrder } from "./selection-model";
import type { RowRef } from "./selection-view";

const order: BlockOrder = () => 0;
const CELL = 10;

function row(index: number, runBackground = ""): RowRef {
	const element = document.createElement("div");
	element.dataset.terminalRow = String(index);
	element.getBoundingClientRect = () => ({ left: 0, right: 400, width: 400, top: index * 20, bottom: index * 20 + 20, height: 20, x: 0, y: index * 20, toJSON: () => ({}) }) as DOMRect;
	const run = document.createElement("span");
	run.dataset.terminalRun = "";
	run.style.backgroundColor = runBackground;
	run.getBoundingClientRect = () => ({ left: 20, right: 120, width: 100, top: 0, bottom: 20, height: 20, x: 20, y: 0, toJSON: () => ({}) }) as DOMRect;
	element.append(run);
	return { element, blockId: "b", row: index, firstRow: 0, rowCount: 200 };
}

const at = (kind: Highlight["kind"], rowIndex: number, startCell: number, endCell: number, colour = SELECTION_COLOUR, rank = 0): Highlight => ({
	kind,
	range: { start: { blockId: "b", row: rowIndex, cell: startCell }, end: { blockId: "b", row: rowIndex, cell: endCell } },
	colour,
	rank,
});

describe("HighlightPainter", () => {
	it("does not measure a row again when its element and highlights are unchanged", () => {
		const rows = [row(0, "rgb(58, 58, 58)"), row(1)];
		const measure = rows.map((ref) => vi.spyOn(ref.element, "getBoundingClientRect"));
		const painter = new HighlightPainter();
		const highlights = [at("mark", 0, 3, 6, "red"), at("mark", 1, 0, 2, "red")];
		painter.paint(rows, highlights, order, CELL);
		const first = measure.map((spy) => spy.mock.calls.length);
		painter.paint(rows, highlights, order, CELL);
		expect(measure.map((spy) => spy.mock.calls.length)).toEqual(first.map((count, index) => (index === 0 ? count + 1 : count)));
		expect(rows[1]!.element.style.backgroundImage).toContain("red");
		const run = rows[0]!.element.querySelector<HTMLElement>("[data-terminal-run]")!;
		expect(run.style.backgroundImage).toContain("red");
	});

	it("measures again when the row's element is replaced or its highlights change", () => {
		const painter = new HighlightPainter();
		const first = row(0);
		painter.paint([first], [at("mark", 0, 0, 2, "red")], order, CELL);
		const replaced = row(0);
		const spy = vi.spyOn(replaced.element, "getBoundingClientRect");
		painter.paint([replaced], [at("mark", 0, 0, 2, "red")], order, CELL);
		expect(spy).toHaveBeenCalled();
		expect(replaced.element.style.backgroundImage).toContain("red");
		const again = vi.spyOn(first.element, "getBoundingClientRect");
		painter.paint([first], [at("mark", 0, 0, 4, "blue")], order, CELL);
		expect(again).toHaveBeenCalled();
		expect(first.element.style.backgroundImage).toContain("blue");
	});

	it("measures again when the pane's geometry changes", () => {
		const painter = new HighlightPainter();
		const ref = row(0);
		painter.paint([ref], [at("mark", 0, 0, 2, "red")], order, CELL);
		ref.element.getBoundingClientRect = () => ({ left: 5, right: 305, width: 300, top: 0, bottom: 20, height: 20, x: 5, y: 0, toJSON: () => ({}) }) as DOMRect;
		const spy = vi.spyOn(ref.element, "getBoundingClientRect");
		painter.paint([ref], [at("find", 0, 0, ROW_END), at("mark", 0, 0, 2, "red")], order, CELL);
		expect(spy).toHaveBeenCalled();
	});

	it("paints a selection exactly the way the selection fill did", () => {
		const rows = [row(0)];
		new HighlightPainter().paint(rows, [at("selection", 0, 2, 5)], order, CELL);
		expect(rows[0]!.element.style.backgroundImage).toBe(
			"linear-gradient(to right, transparent 20px, var(--terminal-selection) 20px, var(--terminal-selection) 50px, transparent 50px)",
		);
	});

	it("stacks layers top first so the selection sits above a mark", () => {
		const rows = [row(0)];
		new HighlightPainter().paint(rows, [at("mark", 0, 0, 8, "red"), at("selection", 0, 2, 5)], order, CELL);
		const image = rows[0]!.element.style.backgroundImage;
		expect(image.indexOf("var(--terminal-selection)")).toBeLessThan(image.indexOf("red"));
	});

	it("gives a find hit the row class and attribute, and the current hit the outline class", () => {
		const rows = [row(0), row(1)];
		new HighlightPainter().paint(rows, [at("find", 0, 0, ROW_END), at("find", 1, 0, ROW_END), at("find-current", 1, 0, ROW_END)], order, CELL);
		expect(rows[0]!.element.classList.contains(CLASS_ROW_MATCH)).toBe(true);
		expect(rows[0]!.element.hasAttribute(ATTR_ROW_MATCH)).toBe(true);
		expect(rows[0]!.element.classList.contains(CLASS_ROW_ACTIVE)).toBe(false);
		expect(rows[1]!.element.classList.contains(CLASS_ROW_ACTIVE)).toBe(true);
		expect(rows[1]!.element.hasAttribute(ATTR_ROW_ACTIVE)).toBe(true);
		expect(rows[0]!.element.style.backgroundImage).toBe("");
	});

	it("paints layers onto a run that has its own background, clipped to the run", () => {
		const rows = [row(0, "rgb(58, 58, 58)")];
		new HighlightPainter().paint(rows, [at("mark", 0, 3, 6, "red")], order, CELL);
		const run = rows[0]!.element.querySelector<HTMLElement>("[data-terminal-run]")!;
		expect(run.style.backgroundImage).toBe("linear-gradient(to right, transparent 10px, red 10px, red 40px, transparent 40px)");
	});

	it("leaves a run without a background alone", () => {
		const rows = [row(0)];
		new HighlightPainter().paint(rows, [at("mark", 0, 3, 6, "red")], order, CELL);
		expect(rows[0]!.element.querySelector<HTMLElement>("[data-terminal-run]")!.style.backgroundImage).toBe("");
	});

	it("clears everything it painted when the highlights go away", () => {
		const rows = [row(0, "rgb(58, 58, 58)"), row(1)];
		const painter = new HighlightPainter();
		painter.paint(rows, [at("mark", 0, 3, 6, "red"), at("find", 1, 0, ROW_END), at("find-current", 1, 0, ROW_END)], order, CELL);
		painter.paint(rows, [], order, CELL);
		expect(rows[0]!.element.style.backgroundImage).toBe("");
		expect(rows[0]!.element.querySelector<HTMLElement>("[data-terminal-run]")!.style.backgroundImage).toBe("");
		expect(rows[1]!.element.className).toBe("");
		expect(rows[1]!.element.hasAttribute(ATTR_ROW_MATCH)).toBe(false);
		expect(rows[1]!.element.hasAttribute(ATTR_ROW_ACTIVE)).toBe(false);
		expect(painter.idle()).toBe(true);
	});

	it("writes nothing to a row whose paint did not change", () => {
		const rows = [row(0), row(1)];
		const painter = new HighlightPainter();
		painter.paint(rows, [at("mark", 0, 0, 4, "red"), at("mark", 1, 0, 4, "red")], order, CELL);
		const writes: Node[] = [];
		const observer = new MutationObserver((records) => records.forEach((record) => writes.push(record.target)));
		for (const { element } of rows) observer.observe(element, { attributes: true });
		painter.paint(rows, [at("mark", 0, 0, 4, "red"), at("mark", 1, 0, 6, "red")], order, CELL);
		const records = observer.takeRecords();
		observer.disconnect();
		expect(records.map((record) => record.target)).toEqual([rows[1]!.element]);
	});

	it("measures one touched row per paint and never an untouched one", () => {
		const rows = Array.from({ length: 50 }, (_, index) => row(index));
		const measured = rows.map((ref) => vi.spyOn(ref.element, "getBoundingClientRect"));
		new HighlightPainter().paint(rows, [at("mark", 7, 0, 4, "red"), at("find", 30, 0, ROW_END)], order, CELL);
		expect(measured.flatMap((spy, index) => (spy.mock.calls.length > 0 ? [index] : []))).toEqual([7]);
		expect(rows[7]!.element.style.backgroundImage).toContain("red");
		expect(rows[30]!.element.classList.contains(CLASS_ROW_MATCH)).toBe(true);
	});
});

describe("HighlightIndex", () => {
	const span = (startRow: number, endRow: number, blockId = "b"): Highlight => ({
		kind: "selection",
		range: { start: { blockId, row: startRow, cell: 0 }, end: { blockId, row: endRow, cell: 3 } },
		colour: SELECTION_COLOUR,
		rank: 0,
	});

	it("finds a short range on each of its rows and nowhere else", () => {
		const index = new HighlightIndex([span(3, 5)], order);
		expect([2, 3, 4, 5, 6].map((index_) => index.at(row(index_)).length)).toEqual([0, 1, 1, 1, 0]);
	});

	it("finds a range longer than a bucket on every row it covers", () => {
		const index = new HighlightIndex([span(1, BUCKET_ROWS + 10)], order);
		expect(index.at(row(0))).toHaveLength(0);
		expect(index.at(row(1))).toHaveLength(1);
		expect(index.at(row(BUCKET_ROWS + 5))).toHaveLength(1);
		expect(index.at(row(BUCKET_ROWS + 11))).toHaveLength(0);
	});

	it("follows block order for a selection that crosses blocks", () => {
		const twoBlocks: BlockOrder = (blockId) => (blockId === "a" ? 0 : blockId === "b" ? 1 : -1);
		const crossing: Highlight = { kind: "selection", range: { start: { blockId: "a", row: 8, cell: 2 }, end: { blockId: "b", row: 11, cell: 1 } }, colour: SELECTION_COLOUR, rank: 0 };
		const index = new HighlightIndex([crossing], twoBlocks);
		expect(index.at({ ...row(10), blockId: "b" })).toHaveLength(1);
		expect(index.at({ ...row(12), blockId: "b" })).toHaveLength(0);
		expect(index.at({ ...row(9), blockId: "a" })).toHaveLength(1);
		expect(index.at({ ...row(7), blockId: "a" })).toHaveLength(0);
	});
});
