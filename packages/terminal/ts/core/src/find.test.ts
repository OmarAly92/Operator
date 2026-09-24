import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, decodeBlocks, initTerminalCore } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

const encoder = new TextEncoder();

function feedBlocks(core: ReturnType<typeof createTerminalCore>, count: number, from: number = 0): void {
	for (let index = from; index < from + count; index += 1) {
		core.feed(encoder.encode(`\x1b]133;A\x07\x1b]133;C\x07line ${index} of text\x1b]133;D;0\x07\r\n`));
	}
}

function makeCore(): ReturnType<typeof createTerminalCore> {
	return createTerminalCore({ columns: 40, scrollback: 1000, rows: 1 });
}

describe("TerminalCore.findOpen / findUpdate / findResults", () => {
	it("finds a literal across a synthetic 5-block scrollback", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		const blocks = decodeBlocks(core.snapshot());
		expect(blocks.length).toBe(5);
		const session = core.findOpen("line 2", false);
		expect(core.findUpdate(session).complete).toBe(true);
		const matches = core.findResults(session);
		expect(matches).toHaveLength(1);
		expect(blocks.map((block) => block.id)).toContain(matches[0]!.blockId);
		expect(matches[0]!.row).toBe(2);
		expect(matches[0]!.endRow).toBe(2);
		expect(matches[0]!.startByte).toBe(0);
		expect(matches[0]!.endByte).toBe(6);
		core.findCancel(session);
		core.dispose();
	});

	it("returns no matches when the literal is absent", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		const session = core.findOpen("absent-needle", false);
		expect(core.findUpdate(session).complete).toBe(true);
		expect(core.findResults(session)).toEqual([]);
		core.findCancel(session);
		core.dispose();
	});

	it("surfaces an unparseable regex as a rejected open, leaving the core alive", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		expect(() => core.findOpen("(unclosed", true)).toThrow();
		core.feed(encoder.encode("after-error"));
		expect(new TextDecoder().decode(core.snapshot().content)).toContain("after-error");
		core.dispose();
	});

	it("finds every occurrence when updated with a tiny budget", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		const session = core.findOpen("line", false);
		let guard = 0;
		while (!core.findUpdate(session, 8).complete && guard < 1000) {
			guard += 1;
		}
		expect(guard).toBeGreaterThan(0);
		expect(core.findResults(session)).toHaveLength(5);
		core.findCancel(session);
		core.dispose();
	});

	it("matches a valid regex across blocks", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		const session = core.findOpen("line \\d of", true);
		core.findUpdate(session);
		expect(core.findResults(session)).toHaveLength(5);
		core.findCancel(session);
		core.dispose();
	});

	it("ignores case for a query without capitals", () => {
		const core = makeCore();
		core.feed(encoder.encode("Error one\r\nerror two\r\n"));
		const lower = core.findOpen("error", false);
		core.findUpdate(lower);
		expect(core.findResults(lower)).toHaveLength(2);
		const upper = core.findOpen("Error", false);
		core.findUpdate(upper);
		expect(core.findResults(upper)).toHaveLength(1);
		core.dispose();
	});

	it("searches a session without block marks, screen rows included", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 1000, rows: 5 });
		for (let index = 0; index < 20; index += 1) core.feed(encoder.encode(`hello ${index}\r\n`));
		const session = core.findOpen("hello", false);
		core.findUpdate(session);
		expect(core.findResults(session)).toHaveLength(20);
		core.dispose();
	});
});

describe("TerminalCore.findUpdate on a growing buffer", () => {
	it("picks up output that arrives after the scan completed", () => {
		const core = makeCore();
		feedBlocks(core, 3);
		const session = core.findOpen("UNIQUE_NEEDLE", false);
		expect(core.findUpdate(session).complete).toBe(true);
		expect(core.findResults(session)).toEqual([]);
		core.feed(encoder.encode("\x1b]133;A\x07\x1b]133;C\x07UNIQUE_NEEDLE appears here\x1b]133;D;0\x07\r\n"));
		const update = core.findUpdate(session);
		expect(update.added).toBe(1);
		expect(update.complete).toBe(true);
		expect(core.findResults(session)).toHaveLength(1);
		core.findCancel(session);
		core.dispose();
	});

	it("scans only the new history when output arrives", () => {
		const core = makeCore();
		feedBlocks(core, 50);
		const session = core.findOpen("line", false);
		core.findUpdate(session);
		const scanned = core.findHistoryBytesScanned(session);
		expect(scanned).toBeGreaterThan(0);
		const quiet = core.findUpdate(session);
		expect(quiet).toEqual({ added: 0, removed: 0, complete: true });
		expect(core.findHistoryBytesScanned(session)).toBe(scanned);
		feedBlocks(core, 1, 50);
		core.findUpdate(session);
		const grown = core.findHistoryBytesScanned(session) - scanned;
		expect(grown).toBeGreaterThan(0);
		expect(grown).toBeLessThan(scanned / 10);
		expect(core.findResults(session)).toHaveLength(51);
		core.dispose();
	});
});

describe("TerminalCore.findCancel", () => {
	it("forgets the session, so a later update is an error", () => {
		const core = makeCore();
		feedBlocks(core, 3);
		const session = core.findOpen("line", false);
		core.findUpdate(session);
		core.findCancel(session);
		expect(() => core.findUpdate(session)).toThrow();
		expect(() => core.findCancel(session)).not.toThrow();
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
