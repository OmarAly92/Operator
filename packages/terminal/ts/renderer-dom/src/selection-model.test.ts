import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "./dom-block-renderer";
import { ROW_END, resolveRange, type SelectionPoint } from "./selection-model";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");
beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

const order = (id: string) => Number(id);
const rows: Record<string, string[]> = { "0": ["first row here", "second row"], "1": ["third block row"] };
const rowText = (id: string, row: number) => rows[id]?.[row] ?? "";
const at = (blockId: string, row: number, column: number, side: "left" | "right" = "left"): SelectionPoint => ({ blockId, row, column, side });

describe("resolveRange", () => {
	it("orders head and tail whichever way the drag went", () => {
		const range = resolveRange({ head: at("1", 0, 3), tail: at("0", 0, 2), kind: "simple" }, order, rowText)!;
		expect(range.start).toEqual({ blockId: "0", row: 0, cell: 2 });
		expect(range.end).toEqual({ blockId: "1", row: 0, cell: 3 });
	});
	it("puts a right-side point after its cell, Warp's range_simple correction", () => {
		const range = resolveRange({ head: at("0", 0, 2, "right"), tail: at("0", 0, 5, "right"), kind: "simple" }, order, rowText)!;
		expect(range.start.cell).toBe(3);
		expect(range.end.cell).toBe(6);
	});
	it("is empty when both ends meet", () => {
		expect(resolveRange({ head: at("0", 0, 2, "right"), tail: at("0", 0, 3, "left"), kind: "simple" }, order, rowText)).toBeNull();
	});
	it("expands a word selection to word edges on both ends", () => {
		const range = resolveRange({ head: at("0", 0, 1), tail: at("0", 1, 8), kind: "word" }, order, rowText)!;
		expect(range.start).toEqual({ blockId: "0", row: 0, cell: 0 });
		expect(range.end).toEqual({ blockId: "0", row: 1, cell: 10 });
	});
	it("expands a line selection to the whole rows", () => {
		const range = resolveRange({ head: at("0", 1, 4), tail: at("0", 0, 4), kind: "line" }, order, rowText)!;
		expect(range.start).toEqual({ blockId: "0", row: 0, cell: 0 });
		expect(range.end).toEqual({ blockId: "0", row: 1, cell: ROW_END });
	});
});

describe("stable-row selection", () => {
	it("a selection survives a trim above it", async () => {
		const core = createTerminalCore({ columns: 40, limits: { rows: 6, bytes: 0xffff_ffff }, rows: 2 });
		const encoder = new TextEncoder();
		for (const line of ["1", "2", "needle", "4"]) core.feed(encoder.encode(`${line}\r\n`));
		const host = document.createElement("div");
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		const blockId = host.querySelector<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionBegin({ blockId, row: 2, column: 0, side: "left" }, "line");
		expect(renderer.selectedText()).toBe("needle");
		for (const line of ["5", "6", "7"]) core.feed(encoder.encode(`${line}\r\n`));
		expect(core.snapshot().firstStableRow).toBe(1);
		expect(renderer.selectedText()).toBe("needle");
		await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
		expect(host.querySelector('[data-terminal-row="2"]')?.textContent).toBe("needle");
		expect(host.querySelector('[data-terminal-row="0"]')).toBeNull();
		renderer.dispose();
	});
});
