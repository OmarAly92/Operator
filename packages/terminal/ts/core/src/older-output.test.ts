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

	it("lands every row of a full 2,048-row chunk with its text", () => {
		const core = createTerminalCore({ columns: 88, rows: 3, limits: { rows: 1000, bytes: 1 << 24 } });
		let live = "";
		for (let index = 0; index < 6000; index += 1) live += `${index + 1}\r\n`;
		core.feed(encoder.encode(live));
		const front = core.snapshot().firstStableRow;
		const first = front - 2048;
		let chunk = `\x1b]7000;v=1;history=${first},2048;cols=4\x1b\\`;
		for (let index = 0; index < 2048; index += 1) chunk += `${first + index + 1}\r\n`;
		core.feed(encoder.encode(chunk));
		expect(core.snapshot().firstStableRow).toBe(first);
		const expected = Array.from({ length: 2048 }, (_, index) => `${first + index + 1}`);
		expect(rowTexts(core).slice(0, 2048)).toEqual(expected);
		core.dispose();
	});

	it("forgets the floor at a process boundary so the pane stops offering older rows", () => {
		const core = createTerminalCore({ columns: 20, rows: 3, limits: { rows: 10, bytes: 1 << 20 } });
		core.feed(encoder.encode("\x1b]7000;v=1;older=3\x1b\\"));
		core.feed(encoder.encode("\x1b[?1049l\x1b[0m\x1b]7000;v=1;boundary=0\x07"));
		expect(core.olderOutput()).toEqual({ floor: null, marks: 2 });
		core.dispose();
	});

	it("reads no floor from a disposed core", () => {
		const core = createTerminalCore({ columns: 20, rows: 3, limits: { rows: 10, bytes: 1 << 20 } });
		core.feed(encoder.encode("\x1b]7000;v=1;older=3\x1b\\"));
		core.dispose();
		expect(core.olderOutput()).toEqual({ floor: null, marks: 0 });
	});
});
