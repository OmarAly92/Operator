import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore, type TerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "./index";
import { feed, flushRepaint, font, loadedCore, stubRowLayout, theme } from "./renderer-harness";

const CELL_W = 10;
const CELL_H = 20;
const RED = "rgba(255, 0, 0, 0.4)";
const BLUE = "rgba(0, 0, 255, 0.4)";

beforeAll(async () => {
	await loadedCore();
});

afterEach(() => {
	vi.restoreAllMocks();
	vi.unstubAllGlobals();
});

function mount(core: TerminalCore): { host: HTMLElement; renderer: DomBlockRenderer } {
	const host = document.createElement("div");
	document.body.append(host);
	const renderer = new DomBlockRenderer();
	renderer.measure = () => ({ cellWidth: CELL_W, cellHeight: CELL_H });
	renderer.mount(host, core);
	renderer.setTheme(theme);
	renderer.setFont(font);
	return { host, renderer };
}

function coreWith(text: string, columns = 40, scrollback = 100): TerminalCore {
	const core = createTerminalCore({ columns, scrollback });
	feed(core, text);
	return core;
}

function rowsHolding(host: HTMLElement, text: string): HTMLElement[] {
	return [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")].filter((row) => (row.textContent ?? "").includes(text));
}

function paintedRows(host: HTMLElement): HTMLElement[] {
	return [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")].filter((row) => row.style.backgroundImage !== "");
}

describe("DomBlockRenderer highlights", () => {
	it("paints a user mark over the matching cells of a rendered row", async () => {
		stubRowLayout();
		const { host, renderer } = mount(coreWith("all good\r\nan error here\r\nfine"));
		await flushRepaint();
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		const [row] = rowsHolding(host, "an error here");
		expect(row!.style.backgroundImage).toBe(`linear-gradient(to right, transparent 30px, ${RED} 30px, ${RED} 80px, transparent 80px)`);
		expect(paintedRows(host)).toEqual([row]);
		renderer.dispose();
	});

	it("orders selection over the current find hit over other hits over marks on one row", async () => {
		stubRowLayout();
		const core = coreWith("error one\r\nerror two");
		const { host, renderer } = mount(core);
		await flushRepaint();
		const [first] = rowsHolding(host, "error one");
		const [second] = rowsHolding(host, "error two");
		const firstRow = Number(first!.dataset.terminalRow);
		const secondRow = Number(second!.dataset.terminalRow);
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		renderer.setFindHighlights({ rows: new Set([firstRow, secondRow]), current: { row: secondRow, endRow: secondRow } });
		renderer.selectionBegin({ blockId: first!.closest<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!, row: firstRow, column: 0, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId: first!.closest<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!, row: firstRow, column: 2, side: "right" });
		const layers = first!.style.backgroundImage.split("linear-gradient").filter(Boolean).map((layer) => (layer.includes(RED) ? "mark" : "selection-colour"));
		expect(layers).toEqual(["selection-colour", "selection-colour", "mark"]);
		expect(first!.classList.contains("terminal-find-row-match")).toBe(false);
		expect(first!.hasAttribute("data-terminal-find-row-match")).toBe(true);
		expect(second!.classList.contains("terminal-find-row-active")).toBe(true);
		expect(first!.classList.contains("terminal-find-row-active")).toBe(false);
		renderer.dispose();
	});

	it("keeps a mark on its text after the scrollback trims rows off the front", async () => {
		stubRowLayout();
		const core = createTerminalCore({ columns: 40, scrollback: 8, rows: 4 });
		const { host, renderer } = mount(core);
		for (let index = 0; index < 12; index += 1) feed(core, `line ${index}\r\n`);
		feed(core, "the needle\r\n");
		await flushRepaint();
		renderer.setMarks([{ pattern: "needle", regex: false, colour: RED }]);
		const before = rowsHolding(host, "the needle")[0]!;
		const trimmedBefore = core.snapshot().firstStableRow;
		for (let index = 0; index < 3; index += 1) feed(core, `more ${index}\r\n`);
		await flushRepaint();
		expect(core.snapshot().firstStableRow).toBeGreaterThan(trimmedBefore);
		const after = rowsHolding(host, "the needle")[0]!;
		expect(after.dataset.terminalRow).toBe(before.dataset.terminalRow);
		expect(after.style.backgroundImage).toContain(RED);
		expect(paintedRows(host)).toEqual([after]);
		renderer.dispose();
	});

	it("moves a mark with its text when a narrower width rewraps the line", async () => {
		stubRowLayout();
		const core = coreWith("prefix words then error at the end\r\nnext\r\n", 40);
		const { host, renderer } = mount(core);
		await flushRepaint();
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		expect(paintedRows(host).map((row) => row.textContent)).toEqual(["prefix words then error at the end"]);
		core.resize(12, 24);
		await flushRepaint();
		const painted = paintedRows(host);
		expect(painted).toHaveLength(1);
		expect(painted[0]!.textContent).toContain("error");
		renderer.dispose();
	});

	it("paints a mark that a soft wrap splits on both rows", async () => {
		stubRowLayout();
		const { host, renderer } = mount(coreWith("0123456789abcderror", 16));
		await flushRepaint();
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		expect(paintedRows(host).map((row) => row.textContent)).toEqual(["0123456789abcder", "ror"]);
		renderer.dispose();
	});

	it("never schedules a repaint when highlights change", async () => {
		stubRowLayout();
		const { host, renderer } = mount(coreWith("error here"));
		await flushRepaint();
		const paints = vi.fn();
		renderer.onPaint(paints);
		const frames = vi.spyOn(globalThis, "requestAnimationFrame");
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		renderer.setFindHighlights({ rows: new Set([0]), current: null });
		const row = host.querySelector<HTMLElement>("[data-terminal-row]")!;
		const blockId = row.closest<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionBegin({ blockId, row: 0, column: 0, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId, row: 0, column: 3, side: "right" });
		renderer.setFindHighlights(null);
		renderer.setMarks([]);
		expect(frames).not.toHaveBeenCalled();
		await flushRepaint();
		expect(paints).not.toHaveBeenCalled();
		renderer.dispose();
	});

	it("reads no layout and writes no style on a paint with nothing highlighted", async () => {
		const core = coreWith("plain\r\n");
		const { host, renderer } = mount(core);
		await flushRepaint();
		const rects = vi.spyOn(HTMLElement.prototype, "getBoundingClientRect");
		for (let index = 0; index < 5; index += 1) feed(core, `row ${index}\r\n`);
		await flushRepaint();
		expect(rects.mock.contexts.filter((element) => (element as HTMLElement).hasAttribute("data-terminal-row"))).toEqual([]);
		expect(paintedRows(host)).toEqual([]);
		renderer.dispose();
	});

	it("repaints marks on rows a later paint rebuilds", async () => {
		stubRowLayout();
		const core = coreWith("error 0");
		const { host, renderer } = mount(core);
		await flushRepaint();
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		const before = rowsHolding(host, "error 0")[0]!;
		feed(core, "\x1b[2K\rerror 1");
		await flushRepaint();
		const after = rowsHolding(host, "error 1")[0]!;
		expect(after).not.toBe(before);
		expect(after.style.backgroundImage).toContain(RED);
		renderer.dispose();
	});

	it("does not touch a parked pane's rows until it is shown again", async () => {
		stubRowLayout();
		const { host, renderer } = mount(coreWith("error here"));
		await flushRepaint();
		renderer.setVisible(false);
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		expect(paintedRows(host)).toEqual([]);
		renderer.setVisible(true);
		expect(rowsHolding(host, "error here")[0]!.style.backgroundImage).toContain(RED);
		renderer.dispose();
	});

	it("marks the alternate screen but never paints find hits on it", async () => {
		stubRowLayout();
		const core = coreWith("\x1b[?1049herror on alt");
		const { host, renderer } = mount(core);
		await flushRepaint();
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		renderer.setFindHighlights({ rows: new Set([0]), current: { row: 0, endRow: 0 } });
		const alt = host.querySelector<HTMLElement>(".terminal-alt-surface [data-terminal-row]")!;
		expect(alt.style.backgroundImage).toContain(RED);
		expect(alt.hasAttribute("data-terminal-find-row-match")).toBe(false);
		expect(alt.classList.contains("terminal-find-row-active")).toBe(false);
		renderer.dispose();
	});

	it("keeps the selection when a mark's colour is rejected", async () => {
		stubRowLayout();
		vi.stubGlobal("CSS", { supports: (_property: string, value: string) => value !== "nonsense" });
		const { host, renderer } = mount(coreWith("error here"));
		await flushRepaint();
		const row = host.querySelector<HTMLElement>("[data-terminal-row]")!;
		const blockId = row.closest<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionBegin({ blockId, row: 0, column: 0, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId, row: 0, column: 3, side: "right" });
		renderer.setMarks([{ pattern: "error", regex: false, colour: "nonsense" }, { pattern: "here", regex: false, colour: BLUE }]);
		expect(row.style.backgroundImage).toContain("var(--terminal-selection)");
		expect(row.style.backgroundImage).toContain(BLUE);
		expect(row.style.backgroundImage).not.toContain("nonsense");
		renderer.dispose();
	});

	it("forgets marks and find hits on dispose, and a disposed renderer ignores new ones", async () => {
		stubRowLayout();
		const core = coreWith("error here");
		const { renderer } = mount(core);
		await flushRepaint();
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		renderer.setFindHighlights({ rows: new Set([0]), current: null });
		renderer.dispose();
		expect(() => renderer.setMarks([{ pattern: "here", regex: false, colour: RED }])).not.toThrow();
		expect(() => renderer.setFindHighlights({ rows: new Set([0]), current: null })).not.toThrow();
		const fresh = document.createElement("div");
		renderer.mount(fresh, core);
		await flushRepaint();
		expect(paintedRows(fresh)).toEqual([]);
		expect(fresh.querySelector("[data-terminal-find-row-match]")).toBeNull();
		renderer.dispose();
	});
});
