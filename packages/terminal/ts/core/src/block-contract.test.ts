import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { BLOCK_RECORD_WORDS, createTerminalCore, decodeBlocks, initTerminalCore } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	await initTerminalCore(
		bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer,
	);
});

describe("block export contract", () => {
	it("exposes one synthetic block covering every row", () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100 });
		core.feed(new TextEncoder().encode("alpha\nbravo"));
		const snapshot = core.snapshot();

		expect(snapshot.blocks.length).toBe(BLOCK_RECORD_WORDS);
		const blocks = decodeBlocks(snapshot);
		expect(blocks).toHaveLength(1);
		expect(blocks[0].firstRow).toBe(0);
		expect(blocks[0].rowCount).toBe(snapshot.rows.length / 2);
		expect(blocks[0].state).toBe("running");
		expect(blocks[0].source).toBe("synthetic");
		expect(blocks[0].exitCode).toBeNull();
		expect(blocks[0].durationMs).toBeNull();
		expect(blocks[0].command).toBe("");
	});

	it("gives every block a stable string id", () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100 });
		core.feed(new TextEncoder().encode("one\n"));
		const first = decodeBlocks(core.snapshot())[0].id;
		core.feed(new TextEncoder().encode("two\n"));
		expect(decodeBlocks(core.snapshot())[0].id).toBe(first);
		expect(typeof first).toBe("string");
	});
});
