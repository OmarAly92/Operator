import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore, type FontConfig, type TerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer, warpDarkTheme } from "./index";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");
const font: FontConfig = { family: "ui-monospace, monospace", sizePx: 14, lineHeight: 1.2, weight: 400, letterSpacingPx: 0, ligatures: false };
const CELL_W = 8.4;
const CELL_H = 16.8;

beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

function feed(core: TerminalCore, text: string): void {
	core.feed(new TextEncoder().encode(text));
}

function layoutRows(host: HTMLElement): HTMLElement[] {
	const rows = [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")];
	rows.forEach((row, index) => {
		row.getBoundingClientRect = () => ({ left: 0, right: 600, width: 600, top: index * CELL_H, bottom: (index + 1) * CELL_H, height: CELL_H, x: 0, y: index * CELL_H, toJSON: () => ({}) }) as DOMRect;
		for (const run of row.querySelectorAll<HTMLElement>("[data-terminal-run]")) {
			run.getBoundingClientRect = () => ({ left: 0, right: 200, width: 200, top: index * CELL_H, bottom: (index + 1) * CELL_H, height: CELL_H, x: 0, y: index * CELL_H, toJSON: () => ({}) }) as DOMRect;
		}
	});
	return rows;
}

function nextPaint(renderer: DomBlockRenderer): Promise<void> {
	return new Promise((resolve) => {
		const off = renderer.onPaint(() => {
			off();
			resolve();
		});
	});
}

function layoutLive(host: HTMLElement): () => void {
	const original = HTMLElement.prototype.getBoundingClientRect;
	const rect = (index: number, right: number): DOMRect =>
		({ left: 0, right, width: right, top: index * CELL_H, bottom: (index + 1) * CELL_H, height: CELL_H, x: 0, y: index * CELL_H, toJSON: () => ({}) }) as DOMRect;
	HTMLElement.prototype.getBoundingClientRect = function (this: HTMLElement) {
		const rows = [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")];
		const row = this.closest<HTMLElement>("[data-terminal-row]");
		const index = row ? rows.indexOf(row) : -1;
		if (index < 0) return original.call(this);
		return rect(index, row === this ? 600 : 200);
	};
	return () => {
		HTMLElement.prototype.getBoundingClientRect = original;
	};
}

function mountWith(input: string): { core: TerminalCore; host: HTMLElement; renderer: DomBlockRenderer } {
	const core = createTerminalCore({ columns: 40, scrollback: 100 });
	feed(core, input);
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(warpDarkTheme);
	renderer.setFont(font);
	renderer.measure = () => ({ cellWidth: CELL_W, cellHeight: CELL_H });
	return { core, host, renderer };
}

function mountTallWith(input: string): { core: TerminalCore; host: HTMLElement; renderer: DomBlockRenderer } {
	const core = createTerminalCore({ columns: 40, scrollback: 100 });
	feed(core, input);
	const host = document.createElement("div");
	Object.defineProperty(host, "clientHeight", { value: 400, configurable: true });
	const renderer = new DomBlockRenderer();
	renderer.measure = () => ({ cellWidth: CELL_W, cellHeight: CELL_H });
	renderer.mount(host, core);
	renderer.setTheme(warpDarkTheme);
	renderer.setFont(font);
	return { core, host, renderer };
}

describe("the terminal selection", () => {
	it("paints rows from the model: first row to the edge, middle whole, last to its cell", () => {
		const { host, renderer } = mountWith("alpha\r\nbeta\r\ngamma");
		const rows = layoutRows(host);
		renderer.selectionBegin(renderer.pointAt(CELL_W * 2 + 1, CELL_H * 0.5)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(CELL_W * 3 + 1, CELL_H * 2.5)!);
		expect(rows[0]!.style.backgroundImage).toContain(`transparent ${CELL_W * 2}px`);
		expect(rows[0]!.style.backgroundImage).toContain("600px");
		expect(rows[1]!.style.backgroundImage).toContain("transparent 0px");
		expect(rows[2]!.style.backgroundImage).toContain(`${CELL_W * 3}px, transparent`);
		expect(renderer.selectedText()).toBe("pha\nbeta\ngam");
	});

	it("survives a repaint that rebuilds every row", async () => {
		const { core, host, renderer } = mountWith("alpha\r\nbeta\r\ngamma\r\n");
		const restore = layoutLive(host);
		try {
			const before = host.querySelectorAll("[data-terminal-row]")[0]!;
			renderer.selectionBegin(renderer.pointAt(0, CELL_H * 0.5)!, "simple");
			renderer.selectionUpdate(renderer.pointAt(CELL_W * 4, CELL_H * 1.5)!);
			expect(renderer.hasSelection()).toBe(true);
			for (let tick = 0; tick < 20; tick += 1) feed(core, `\x1b[2K\r✻ Baking for ${tick}s`);
			await nextPaint(renderer);
			const rows = [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")];
			expect(rows[0]).not.toBe(before);
			expect(renderer.hasSelection()).toBe(true);
			expect(renderer.selectedText()).toBe("alpha\nbeta");
			expect(rows[0]!.style.backgroundImage).toContain("var(--terminal-selection)");
		} finally {
			restore();
		}
	});

	it("tints a painted run's background instead of hiding under it", () => {
		const band = "\x1b[48;5;237m\x1b[38;5;231m> hi\x1b[0m";
		const { host, renderer } = mountWith(`alpha\r\n${band}\r\ngamma`);
		const rows = layoutRows(host);
		const run = rows[1]!.querySelector<HTMLElement>("[data-terminal-run]")!;
		renderer.selectionBegin(renderer.pointAt(0, CELL_H * 0.5)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(0, CELL_H * 2.5)!);
		expect(run.style.backgroundImage).toContain("var(--terminal-selection)");
		expect(run.style.backgroundImage).toContain("200px");
		renderer.selectionClear();
		expect(run.style.backgroundImage).toBe("");
		expect(rows[1]!.style.backgroundImage).toBe("");
	});

	it("selects a word on a double click and a line on a triple click", () => {
		const { host, renderer } = mountWith("see src/row-builder.ts now");
		layoutRows(host);
		const point = renderer.pointAt(CELL_W * 8, CELL_H * 0.5)!;
		renderer.selectionBegin(point, "word");
		expect(renderer.selectedText()).toBe("src/row-builder.ts");
		renderer.selectionBegin(point, "line");
		expect(renderer.selectedText()).toBe("see src/row-builder.ts now");
	});

	it("drops the selection when its block leaves the snapshot", () => {
		const { core, host, renderer } = mountWith("\x1b]133;A\x07\x1b]133;C\x07one\r\n\x1b]133;D;0\x07");
		layoutRows(host);
		renderer.selectionBegin(renderer.pointAt(0, CELL_H * 0.5)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(CELL_W * 3, CELL_H * 0.5)!);
		expect(renderer.hasSelection()).toBe(true);
		for (let i = 0; i < 400; i += 1) feed(core, `\x1b]133;A\x07\x1b]133;C\x07row ${i}\r\n\x1b]133;D;0\x07`);
		expect(renderer.hasSelection()).toBe(false);
	});

	it("copies to a block's trimmed end, not its untrimmed painted-blank tail", () => {
		const { host, renderer } = mountTallWith(
			"\x1b]133;A\x07\x1b]133;C\x07alpha\r\nbeta\r\ngamma\r\n\x1b[1A\x1b[2K\r\n\x1b]133;D;0\x07\x1b]133;A\x07\x1b]133;C\x07second\r\n\x1b]133;D;0\x07",
		);
		const rows = layoutRows(host);
		expect(rows).toHaveLength(3);
		renderer.selectionBegin(renderer.pointAt(0, CELL_H * 0.5)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(CELL_W * 3, CELL_H * 2.5)!);
		expect(renderer.selectedText()).toBe("alpha\nbeta\nsec");
	});

	it("keeps a cross-block selection copying its trimmed end across repaint ticks", () => {
		const { core, host, renderer } = mountTallWith(
			"\x1b]133;A\x07\x1b]133;C\x07alpha\r\nbeta\r\ngamma\r\n\x1b[1A\x1b[2K\r\n\x1b]133;D;0\x07\x1b]133;A\x07\x1b]133;C\x07\x1b[2K\r✻ Baking for 0s",
		);
		layoutRows(host);
		renderer.selectionBegin(renderer.pointAt(0, CELL_H * 0.5)!, "line");
		renderer.selectionUpdate(renderer.pointAt(0, CELL_H * 2.5)!);
		expect(renderer.hasSelection()).toBe(true);
		for (let tick = 1; tick < 20; tick += 1) feed(core, `\x1b[2K\r✻ Baking for ${tick}s`);
		layoutRows(host);
		expect(renderer.hasSelection()).toBe(true);
		expect(renderer.selectedText()).toBe("alpha\nbeta\n✻ Baking for 19s");
	});

	it("tells listeners when a repaint drops the selection with its block", async () => {
		const { core, host, renderer } = mountWith("\x1b]133;A\x07\x1b]133;C\x07one\r\n\x1b]133;D;0\x07");
		layoutRows(host);
		renderer.selectionBegin(renderer.pointAt(0, CELL_H * 0.5)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(CELL_W * 3, CELL_H * 0.5)!);
		let calls = 0;
		renderer.onSelectionChange(() => { calls += 1; });
		for (let i = 0; i < 400; i += 1) feed(core, `\x1b]133;A\x07\x1b]133;C\x07row ${i}\r\n\x1b]133;D;0\x07`);
		await nextPaint(renderer);
		expect(renderer.hasSelection()).toBe(false);
		expect(calls).toBe(1);
	});

	it("copies only what a block filter leaves visible", async () => {
		const { host, renderer } = mountTallWith(
			"\x1b]133;A\x07\x1b]133;C\x07keep one\r\n\x1b]133;D;1\x07\x1b]133;A\x07\x1b]133;C\x07drop me\r\n\x1b]133;D;0\x07\x1b]133;A\x07\x1b]133;C\x07keep two\r\n\x1b]133;D;1\x07",
		);
		renderer.setFilter({ exitCodeNonZero: true });
		await nextPaint(renderer);
		const rows = layoutRows(host);
		expect(rows.map((row) => row.textContent)).toEqual(["keep one", "keep two"]);
		renderer.selectionBegin(renderer.pointAt(0, CELL_H * 0.5)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(CELL_W * 8, CELL_H * 1.5)!);
		expect(renderer.selectedText()).toBe("keep one\nkeep two");
	});

	it("notifies listeners when the selection changes", () => {
		const { host, renderer } = mountWith("alpha");
		layoutRows(host);
		let calls = 0;
		const off = renderer.onSelectionChange(() => { calls += 1; });
		renderer.selectionBegin(renderer.pointAt(0, 1)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(CELL_W * 3, 1)!);
		renderer.selectionClear();
		off();
		renderer.selectionClear();
		expect(calls).toBe(3);
	});
});
