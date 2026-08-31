import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, decodeBlocks, initTerminalCore } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

function feedBlocks(core: ReturnType<typeof createTerminalCore>, count: number): void {
	const encoder = new TextEncoder();
	for (let index = 0; index < count; index += 1) {
		core.feed(
			encoder.encode(`\x1b]133;A\x07\x1b]133;C\x07line ${index} of text\x1b]133;D;0\x07\r\n`),
		);
	}
}

function makeCore(): ReturnType<typeof createTerminalCore> {
	return createTerminalCore({ columns: 40, scrollback: 1000, rows: 1 });
}

describe("TerminalCore.findOpen / findStep / findResults", () => {
	it("finds a literal across a synthetic 5-block scrollback", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		const blocks = decodeBlocks(core.snapshot());
		expect(blocks.length).toBe(5);
		const session = core.findOpen("line 2", false);
		let guard = 0;
		while (!core.findIsComplete(session) && guard < 1000) {
			core.findStep(session, 1);
			guard += 1;
		}
		const matches = core.findResults(session);
		expect(matches).toHaveLength(1);
		expect(matches[0]?.blockId).toBeTruthy();
		expect(matches[0]?.row).toBeTypeOf("number");
		expect(matches[0]?.byteRangeStart).toBeTypeOf("number");
		expect(matches[0]?.byteRangeEnd).toBeTypeOf("number");
		expect(matches[0]?.byteRangeEnd).toBeGreaterThan(matches[0]?.byteRangeStart ?? 0);
		core.findCancel(session);
		core.dispose();
	});

	it("returns no matches when the literal is absent", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		const session = core.findOpen("absent-needle", false);
		let guard = 0;
		while (!core.findIsComplete(session) && guard < 1000) {
			core.findStep(session, 1);
			guard += 1;
		}
		expect(core.findResults(session)).toEqual([]);
		core.findCancel(session);
		core.dispose();
	});

	it("surfaces an unparseable regex as a rejected open, leaving the core alive", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		expect(() => core.findOpen("(unclosed", true)).toThrow();
		core.feed(new TextEncoder().encode("after-error"));
		expect(new TextDecoder().decode(core.snapshot().content)).toContain("after-error");
		core.dispose();
	});

	it("finds every occurrence across blocks when stepped with a tiny budget", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		const session = core.findOpen("line", false);
		let guard = 0;
		while (!core.findIsComplete(session) && guard < 10000) {
			core.findStep(session, 1);
			guard += 1;
		}
		const matches = core.findResults(session);
		expect(matches).toHaveLength(5);
		core.findCancel(session);
		core.dispose();
	});

	it("matches a valid regex across blocks", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		const session = core.findOpen("line \\d of", true);
		let guard = 0;
		while (!core.findIsComplete(session) && guard < 1000) {
			core.findStep(session, 2);
			guard += 1;
		}
		expect(core.findResults(session)).toHaveLength(5);
		core.findCancel(session);
		core.dispose();
	});
});

describe("TerminalCore.findCancel", () => {
	it("stops producing results after cancel, even when stepped again", () => {
		const core = makeCore();
		feedBlocks(core, 10);
		const session = core.findOpen("line", false);
		core.findStep(session, 3);
		const atCancel = core.findResults(session).length;
		expect(atCancel).toBeGreaterThan(0);
		core.findCancel(session);
		core.findStep(session, 1000);
		expect(core.findIsComplete(session)).toBe(true);
		expect(core.findResults(session).length).toBe(atCancel);
		core.dispose();
	});

	it("treats findStep on a cancelled session as a no-op", () => {
		const core = makeCore();
		feedBlocks(core, 3);
		const session = core.findOpen("line", false);
		core.findStep(session, 1);
		const before = core.findResults(session).length;
		core.findCancel(session);
		expect(() => core.findStep(session, 1)).not.toThrow();
		expect(core.findResults(session).length).toBe(before);
		core.dispose();
	});

	it("reuses a session id after cancel", () => {
		const core = makeCore();
		feedBlocks(core, 3);
		const first = core.findOpen("line", false);
		core.findCancel(first);
		const second = core.findOpen("line", false);
		expect(second).toBe(first);
		core.findCancel(second);
		core.dispose();
	});

	it("assigns distinct ids to overlapping open sessions", () => {
		const core = makeCore();
		feedBlocks(core, 3);
		const a = core.findOpen("line", false);
		const b = core.findOpen("other", false);
		expect(a).not.toBe(b);
		core.findCancel(a);
		core.findCancel(b);
		core.dispose();
	});
});

describe("TerminalCore.find mutation safety", () => {
	it("does not crash and returns well-formed matches when the core mutates between steps", () => {
		const core = makeCore();
		feedBlocks(core, 50);
		const session = core.findOpen("line", false);
		core.findStep(session, 3);
		const before = core.findResults(session);
		expect(before.length).toBeGreaterThan(0);
		feedBlocks(core, 50);
		expect(() => {
			core.findStep(session, 3);
			core.findStep(session, 3);
		}).not.toThrow();
		const after = core.findResults(session);
		for (const match of after) {
			expect(match.blockId).toBeTruthy();
			expect(match.byteRangeEnd).toBeGreaterThan(match.byteRangeStart);
		}
		core.findCancel(session);
		core.dispose();
	});
});
