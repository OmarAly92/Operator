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
const decoder = new TextDecoder();

function rowOf(core: TerminalCore, text: string): number {
	const snapshot = core.snapshot();
	for (let row = 0; row * 2 < snapshot.rows.length; row += 1) {
		if (decoder.decode(snapshot.content.subarray(snapshot.rows[row * 2]!, snapshot.rows[row * 2 + 1]!)) === text) return snapshot.firstStableRow + row;
	}
	throw new Error(`no row reads ${JSON.stringify(text)}`);
}

describe("a rewrapped bullet continuation", () => {
	it("copies and double-clicks the word painted under the pointer", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100, rows: 2 });
		core.feed(encoder.encode("- aaaa bbbb cc dd ee\r\nx\r\ny\r\n"));
		core.resize(12, 2);
		const host = document.createElement("div");
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		const blockId = host.querySelector<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		const row = rowOf(core, "cc dd ee");
		expect(core.snapshot().rowIndents[row - core.snapshot().firstStableRow]).toBe(2);
		renderer.selectionBegin({ blockId, row, column: 5, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId, row, column: 6, side: "right" });
		expect(renderer.selectedText()).toBe("dd");
		renderer.selectionBegin({ blockId, row, column: 5, side: "left" }, "word");
		expect(renderer.selectedText()).toBe("dd");
		renderer.dispose();
	});
});
