import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, decodeBlocks, initTerminalCore, type TerminalCore } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

const encoder = new TextEncoder();

type Size = { offset: number; cols: number; rows: number };

async function replay(name: string, agentTui: boolean): Promise<TerminalCore> {
	const dir = new URL(`../../../bench/agent-session/fixtures/${name}/`, import.meta.url);
	const recording = new Uint8Array(await readFile(fileURLToPath(new URL("recording", dir))));
	const sizes = JSON.parse(await readFile(fileURLToPath(new URL("size.json", dir)), "utf8")) as Size[];
	const core = createTerminalCore({
		columns: sizes[0]!.cols,
		rows: sizes[0]!.rows,
		limits: { rows: 200_000, bytes: 128 * 1024 * 1024 },
	});
	core.setAgentTuiMode(agentTui);
	let fed = 0;
	for (const size of sizes.slice(1)) {
		core.feed(recording.subarray(fed, size.offset));
		fed = size.offset;
		core.resize(size.cols, size.rows);
	}
	core.feed(recording.subarray(fed));
	return core;
}

function lastBlockId(core: TerminalCore): string {
	return decodeBlocks(core.snapshot()).at(-1)!.id;
}

function count(lines: string[], line: string): number {
	return lines.filter((candidate) => candidate === line).length;
}

describe("readBlockOutput", () => {
	it("returns null for an unknown block and after dispose", () => {
		const core = createTerminalCore({ columns: 20, rows: 5, limits: { rows: 100, bytes: 1 << 20 } });
		core.feed(encoder.encode("hello"));
		expect(core.readBlockOutput("9:9")).toBeNull();
		const id = lastBlockId(core);
		core.dispose();
		expect(core.readBlockOutput(id)).toBeNull();
	});

	it("reads a shell block's rows, joins a soft-wrapped line and drops trailing blank rows", () => {
		const core = createTerminalCore({ columns: 10, rows: 6, limits: { rows: 100, bytes: 1 << 20 } });
		core.feed(encoder.encode("\x1b]133;A\x07$ \x1b]133;B\x07echo\x1b]133;C\x07\r\nabcdefghijklmnopqrstuvwxy\r\nend\r\n\x1b]133;D;0\x07"));
		const block = decodeBlocks(core.snapshot()).find((view) => view.state === "finished")!;
		expect(core.readBlockOutput(block.id)).toBe("$ echo\nabcdefghijklmnopqrstuvwxy\nend");
		core.dispose();
	});

	it("caps the lines with a marker when maxLines is given", () => {
		const core = createTerminalCore({ columns: 20, rows: 30, limits: { rows: 100, bytes: 1 << 20 } });
		for (let index = 0; index < 20; index += 1) core.feed(encoder.encode(`row ${index}\r\n`));
		expect(core.readBlockOutput(lastBlockId(core), { maxLines: 5 })).toBe("row 0\nrow 1\n… 16 lines omitted …\nrow 18\nrow 19");
		core.dispose();
	});

	it("claude-spinner-10s: compact drops the live spinner line and keeps the prompt", async () => {
		const core = await replay("claude-spinner-10s", true);
		const id = lastBlockId(core);
		const raw = core.readBlockOutput(id)!.split("\n");
		const compact = core.readBlockOutput(id, { compact: true })!.split("\n");
		expect(raw.some((line) => line.includes("Flambéing…"))).toBe(true);
		expect(compact.some((line) => line.includes("Flambéing…"))).toBe(false);
		expect(compact.some((line) => line.startsWith("❯ Do all of the following"))).toBe(true);
		expect(raw).toHaveLength(25);
		expect(compact).toHaveLength(24);
		core.dispose();
	});

	it("claude-markdown-reply without agent mode: compact keeps one banner of the three the resizes pushed", async () => {
		const core = await replay("claude-markdown-reply", false);
		const id = lastBlockId(core);
		const raw = core.readBlockOutput(id)!.split("\n");
		const compact = core.readBlockOutput(id, { compact: true })!.split("\n");
		const banner = raw[0]!;
		expect(banner.endsWith("Claude Code v2.1.280")).toBe(true);
		expect(count(raw, banner)).toBe(4);
		expect(count(compact, banner)).toBe(1);
		expect(compact.some((line) => line.startsWith("⏺ I updated greet.py"))).toBe(true);
		expect(raw).toHaveLength(101);
		expect(compact).toHaveLength(88);
		core.dispose();
	});

	it("claude-long-50k: compact keeps all twenty turns of 3,000 numbers", async () => {
		const core = await replay("claude-long-50k", true);
		const id = lastBlockId(core);
		const compact = core.readBlockOutput(id, { compact: true })!.split("\n");
		expect(compact.filter((line) => /^(?:⏺ | {2})\d+$/.test(line))).toHaveLength(60_000);
		expect(compact.filter((line) => line.startsWith("✻ ") && line.includes(" · done "))).toHaveLength(20);
		core.dispose();
	});
});
