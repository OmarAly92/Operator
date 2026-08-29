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

describe("exit code decoding", () => {
	function recordWith(packed: number, exitWord: number): Uint32Array {
		const words = new Uint32Array(BLOCK_RECORD_WORDS);
		words[3] = 1;
		words[4] = packed;
		words[5] = exitWord;
		words[6] = 0xffffffff;
		words[7] = 0xffffffff;
		return words;
	}

	const FINISHED_OSC133 = 1;
	const HAS_EXIT = 1 << 16;

	it("reads an absent exit code as null", () => {
		const blocks = decodeBlocks({
			blocks: recordWith(FINISHED_OSC133, 0),
			blockText: new Uint8Array(),
		});
		expect(blocks[0].exitCode).toBeNull();
	});

	it("round-trips a negative exit code without colliding with absent", () => {
		const blocks = decodeBlocks({
			blocks: recordWith(FINISHED_OSC133 | HAS_EXIT, 0xffffffff),
			blockText: new Uint8Array(),
		});
		expect(blocks[0].exitCode).toBe(-1);
	});

	it("round-trips the largest exit code without overflow", () => {
		const blocks = decodeBlocks({
			blocks: recordWith(FINISHED_OSC133 | HAS_EXIT, 0x7fffffff),
			blockText: new Uint8Array(),
		});
		expect(blocks[0].exitCode).toBe(2147483647);
	});
});
