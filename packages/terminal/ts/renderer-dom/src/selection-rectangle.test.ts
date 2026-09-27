import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore, type FontConfig } from "@operator/terminal-core";
import { ALT_BLOCK_ID, DomBlockRenderer, warpDarkTheme } from "./index";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");
const font: FontConfig = { family: "ui-monospace, monospace", sizePx: 14, lineHeight: 1.2, weight: 400, letterSpacingPx: 0, ligatures: false };
const CELL_W = 8.4;
const CELL_H = 16.8;
beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

function layoutRows(host: HTMLElement): HTMLElement[] {
	const rows = [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")];
	rows.forEach((row, index) => {
		row.getBoundingClientRect = () => ({ left: 0, right: 600, width: 600, top: index * CELL_H, bottom: (index + 1) * CELL_H, height: CELL_H, x: 0, y: index * CELL_H, toJSON: () => ({}) }) as DOMRect;
	});
	return rows;
}

function mountWith(input: string) {
	const core = createTerminalCore({ columns: 40, scrollback: 100 });
	core.feed(new TextEncoder().encode(input));
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(warpDarkTheme);
	renderer.setFont(font);
	renderer.measure = () => ({ cellWidth: CELL_W, cellHeight: CELL_H });
	return { core, host, renderer };
}

describe("rectangle selection in the renderer", () => {
	it("paints the same cells on every row and copies each row's slice", () => {
		const { host, renderer } = mountWith("alpha beta\r\ngamma delta\r\nepsilon\r\n");
		const rows = layoutRows(host);
		const blockId = host.querySelector<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionBegin({ blockId, row: 0, column: 2, side: "left" }, "rectangle");
		renderer.selectionUpdate({ blockId, row: 2, column: 5, side: "right" });
		expect(renderer.selectedText()).toBe("pha\nmma\nsilo");
		for (const row of rows.slice(0, 3)) {
			expect(row.style.backgroundImage).toContain(`transparent ${2 * CELL_W}px`);
			expect(row.style.backgroundImage).toContain(`${6 * CELL_W}px`);
		}
		renderer.dispose();
	});

	it("works on the alternate screen", () => {
		const { host, renderer } = mountWith("\x1b[?1049halpha beta\r\ngamma delta\r\n");
		renderer.selectionBegin({ blockId: ALT_BLOCK_ID, row: 0, column: 6, side: "left" }, "rectangle");
		renderer.selectionUpdate({ blockId: ALT_BLOCK_ID, row: 1, column: 9, side: "right" });
		expect(renderer.selectedText()).toBe("beta\ndelt");
		expect(host.querySelector(".terminal-alt-surface")).not.toBeNull();
		renderer.dispose();
	});
});
