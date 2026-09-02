import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, decodeBlocks, initTerminalCore, type TerminalCore } from "@operator/terminal-core";
import { trimTrailingBlankRows } from "./block-rows";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");

beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

function agentCore(): TerminalCore {
	const core = createTerminalCore({ columns: 80, scrollback: 2000 });
	core.setAgentTuiMode(true);
	core.resize(80, 40);
	return core;
}

const w = (core: TerminalCore, s: string) => core.feed(new TextEncoder().encode(s));

describe("trimTrailingBlankRows", () => {
	it("drops the rows an in-place redraw erased", () => {
		const core = agentCore();
		w(core, "\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1; cmd=claude\x07\x1b]133;C\x07");
		w(core, "\x1b[2J\x1b[H" + Array.from({ length: 30 }, (_u, i) => `line-${i + 1}`).join("\r\n") + "\r\n");
		w(core, "\x1b[H" + "short-1\r\nshort-2\r\nshort-3\r\n" + "\x1b[J");
		const snapshot = core.snapshot();
		const block = decodeBlocks(snapshot)[0]!;
		expect(block.rowCount).toBe(31);
		expect(trimTrailingBlankRows(snapshot, block).rowCount).toBe(3);
	});

	it("leaves a block whose last row has text alone", () => {
		const core = agentCore();
		w(core, "\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1; cmd=ls\x07\x1b]133;C\x07");
		w(core, "one\r\ntwo\r\nthree");
		const snapshot = core.snapshot();
		const block = decodeBlocks(snapshot)[0]!;
		expect(trimTrailingBlankRows(snapshot, block).rowCount).toBe(block.rowCount);
	});

	it("keeps a blank row that has text below it", () => {
		const core = agentCore();
		w(core, "\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1; cmd=ls\x07\x1b]133;C\x07");
		w(core, "one\r\n\r\nthree");
		const snapshot = core.snapshot();
		const block = decodeBlocks(snapshot)[0]!;
		expect(trimTrailingBlankRows(snapshot, block).rowCount).toBe(3);
	});

	it("never trims a block away entirely", () => {
		const core = agentCore();
		w(core, "\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1; cmd=clear\x07\x1b]133;C\x07");
		w(core, "\r\n\r\n\r\n");
		const snapshot = core.snapshot();
		const block = decodeBlocks(snapshot)[0]!;
		expect(trimTrailingBlankRows(snapshot, block).rowCount).toBe(1);
	});

	it("treats a row of spaces as blank", () => {
		const core = agentCore();
		w(core, "\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1; cmd=ls\x07\x1b]133;C\x07");
		w(core, "one\r\n      \r\n   ");
		const snapshot = core.snapshot();
		const block = decodeBlocks(snapshot)[0]!;
		expect(trimTrailingBlankRows(snapshot, block).rowCount).toBe(1);
	});
});
