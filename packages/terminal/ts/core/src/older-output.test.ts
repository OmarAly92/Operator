import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore, type TerminalCore } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function rowTexts(core: TerminalCore): string[] {
	const snapshot = core.snapshot();
	const rows: string[] = [];
	for (let index = 0; index < snapshot.rows.length / 2; index += 1) {
		rows.push(decoder.decode(snapshot.content.subarray(snapshot.rows[index * 2]!, snapshot.rows[index * 2 + 1]!)));
	}
	while (rows.length > 0 && rows.at(-1) === "") rows.pop();
	return rows;
}

describe("olderOutput", () => {
	it("reports no floor until a mark arrives", () => {
		const core = createTerminalCore({ columns: 20, rows: 4, limits: { rows: 100, bytes: 1 << 20 } });
		expect(core.olderOutput()).toEqual({ floor: null, marks: 0 });
		core.feed(encoder.encode("\x1b]7000;v=1;older=7\x1b\\"));
		expect(core.olderOutput()).toEqual({ floor: 7, marks: 1 });
		core.feed(encoder.encode("\x1b]7000;v=1;older=7\x1b\\"));
		expect(core.olderOutput()).toEqual({ floor: 7, marks: 2 });
		core.dispose();
	});

	it("prepends a chunk of older rows above a core that has trimmed", () => {
		const core = createTerminalCore({ columns: 20, rows: 3, limits: { rows: 10, bytes: 1 << 20 } });
		for (let index = 0; index < 30; index += 1) core.feed(encoder.encode(`live ${index}\r\n`));
		const front = core.snapshot().firstStableRow;
		expect(front).toBeGreaterThan(2);
		core.feed(
			encoder.encode(
				`\x1b]7000;v=1;history=${front - 2},2;cols=30\x1b\\\x1b[0m\x1b[31mold one\x1b[0m\r\n\x1b[0mold two\x1b[0m\r\n\x1b]7000;v=1;older=0\x1b\\`,
			),
		);
		expect(core.snapshot().firstStableRow).toBe(front - 2);
		expect(rowTexts(core).slice(0, 2)).toEqual(["old one", "old two"]);
		expect(core.olderOutput().floor).toBe(0);
		core.dispose();
	});

	it("reads no floor from a disposed core", () => {
		const core = createTerminalCore({ columns: 20, rows: 3, limits: { rows: 10, bytes: 1 << 20 } });
		core.feed(encoder.encode("\x1b]7000;v=1;older=3\x1b\\"));
		core.dispose();
		expect(core.olderOutput()).toEqual({ floor: null, marks: 0 });
	});
});
