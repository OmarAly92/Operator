import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore, type TerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "./dom-block-renderer";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");
beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

const encoder = new TextEncoder();
const frames = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));

function mount(core: TerminalCore): { host: HTMLElement; renderer: DomBlockRenderer } {
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	return { host, renderer };
}

describe("extending a selection in a trimmed session", () => {
	it("extends from the first retained row when the caret's row was trimmed", () => {
		const lines = ["1", "2", "needle", "4", "5", "6", "7", "8"];
		const core = createTerminalCore({ columns: 40, limits: { rows: 6, bytes: 0xffff_ffff }, rows: 2 });
		for (const line of lines.slice(0, 4)) core.feed(encoder.encode(`${line}\r\n`));
		const { host, renderer } = mount(core);
		const blockId = host.querySelector<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionClear({ blockId, row: 0, column: 0, side: "left" });
		for (const line of lines.slice(4)) core.feed(encoder.encode(`${line}\r\n`));
		const first = core.snapshot().firstStableRow;
		expect(first).toBeGreaterThan(0);
		renderer.selectionUpdate({ blockId, row: 6, column: 0, side: "right" }, true);
		expect(renderer.selectedText()).toBe(lines.slice(first, 7).join("\n"));
		renderer.dispose();
	});

	it("places a fresh caret when the caret's block was trimmed away", async () => {
		const core = createTerminalCore({ columns: 40, limits: { rows: 8, bytes: 0xffff_ffff }, rows: 2 });
		const block = (text: string) => `\x1b]133;A\x07\x1b]133;C\x07${text}\r\n\x1b]133;D;0\x07`;
		core.feed(encoder.encode(block("first")));
		const { host, renderer } = mount(core);
		const firstId = host.querySelector<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionBegin({ blockId: firstId, row: 0, column: 0, side: "left" }, "line");
		expect(renderer.selectedText()).toBe("first");
		for (let index = 0; index < 12; index += 1) core.feed(encoder.encode(block(`later ${index}`)));
		await frames();
		expect(core.snapshot().firstStableRow).toBeGreaterThan(0);
		expect(renderer.hasSelection()).toBe(false);
		const lastElement = [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")].find((element) => element.textContent === "later 11")!;
		const lastId = lastElement.closest<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		expect(lastId).not.toBe(firstId);
		const lastRow = Number(lastElement.dataset.terminalRow);
		renderer.selectionUpdate({ blockId: lastId, row: lastRow, column: 0, side: "left" }, true);
		expect(renderer.hasSelection()).toBe(false);
		renderer.selectionUpdate({ blockId: lastId, row: lastRow, column: 4, side: "right" }, true);
		expect(renderer.selectedText()).toBe("later");
		renderer.dispose();
	});
});
