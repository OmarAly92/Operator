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

function mounted(core: TerminalCore): { renderer: DomBlockRenderer; blockIds: string[] } {
	const host = document.createElement("div");
	Object.defineProperty(host, "clientHeight", { value: 200, configurable: true });
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	const blockIds = [...host.querySelectorAll<HTMLElement>("[data-terminal-block-id]")].map((element) => element.dataset.terminalBlockId!);
	return { renderer, blockIds };
}

describe("a selection across a width change", () => {
	it("keeps a selection on the same words when a narrower width rewraps its line", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100, rows: 2 });
		core.feed(encoder.encode("alpha beta gamma delta epsilon\r\nx\r\ny\r\n"));
		const { renderer, blockIds } = mounted(core);
		const row = rowOf(core, "alpha beta gamma delta epsilon");
		renderer.selectionBegin({ blockId: blockIds[0]!, row, column: 11, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId: blockIds[0]!, row, column: 21, side: "right" });
		expect(renderer.selectedText()).toBe("gamma delta");
		core.resize(12, 2);
		expect(rowOf(core, "gamma delta ")).toBe(row + 1);
		expect(renderer.selectedText()).toBe("gamma delta");
		core.resize(40, 2);
		expect(renderer.selectedText()).toBe("gamma delta");
		renderer.dispose();
	});

	it("keeps a selection that crosses two blocks", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100, rows: 2 });
		core.feed(encoder.encode("\x1b]133;A\x07\x1b]133;C\x07one two three four five\r\n\x1b]133;D;0\x07\x1b]133;A\x07\x1b]133;C\x07six seven eight nine ten\r\n\x1b]133;D;0\x07\x1b]133;A\x07"));
		const { renderer, blockIds } = mounted(core);
		const first = rowOf(core, "one two three four five");
		const second = rowOf(core, "six seven eight nine ten");
		renderer.selectionBegin({ blockId: blockIds[0]!, row: first, column: 8, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId: blockIds[1]!, row: second, column: 14, side: "right" });
		expect(renderer.selectedText()).toBe("three four five\nsix seven eight");
		core.resize(10, 2);
		expect(renderer.selectedText()).toBe("three four five\nsix seven eight");
		renderer.dispose();
	});

	it("keeps a selection on an agent's live frame when the rows above it rewrap", () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100, rows: 3 });
		core.setAgentTuiMode(true);
		core.feed(encoder.encode("aaaaaaaaaabbbbbbbbbbcccccccccc\r\ntail\r\nx\r\nzeta"));
		const { renderer, blockIds } = mounted(core);
		const row = rowOf(core, "zeta");
		renderer.selectionBegin({ blockId: blockIds[0]!, row, column: 0, side: "left" }, "line");
		expect(renderer.selectedText()).toBe("zeta");
		core.resize(40, 3);
		expect(rowOf(core, "zeta")).toBe(row - 1);
		expect(renderer.selectedText()).toBe("zeta");
		renderer.dispose();
	});

	it("keeps a selection in rows older than the eager rewrap window through the later lazy pass", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 5000, rows: 2 });
		let text = "";
		for (let line = 0; line < 2100; line += 1) text += `line ${String(line).padStart(4, "0")} alpha beta gamma delta\r\n`;
		core.feed(encoder.encode(text));
		const { renderer, blockIds } = mounted(core);
		const row = rowOf(core, "line 0005 alpha beta gamma delta");
		renderer.selectionBegin({ blockId: blockIds[0]!, row, column: 21, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId: blockIds[0]!, row, column: 25, side: "right" });
		expect(renderer.selectedText()).toBe("gamma");
		core.resize(16, 2);
		expect(renderer.selectedText()).toBe("gamma");
		core.setExportWindow(0, 50);
		core.snapshot();
		expect(rowOf(core, "line 0005 alpha ")).toBeGreaterThan(row);
		expect(renderer.selectedText()).toBe("gamma");
		renderer.dispose();
	});
});
