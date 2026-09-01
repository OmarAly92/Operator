import type { BenchmarkRenderer } from "./harness";
import { FIND_STEP_BUDGET, type TerminalCore } from "@operator/terminal-core";

export const FIND_SCENARIO_NAME = "find-500k";
export const FIND_LINE_COUNT = 500000;
export const FIND_LINE_BYTES = 37;
export const FIND_QUERY = "row 250000";
export const FIND_CHUNK_SIZE = 65536;

export function buildFindScrollbackBytes(): Uint8Array {
	const encoder = new TextEncoder();
	const buffer = new Uint8Array(FIND_LINE_BYTES * FIND_LINE_COUNT);
	let offset = 0;
	for (let index = 0; index < FIND_LINE_COUNT; index += 1) {
		const line = `\x1b]133;A\x07\x1b]133;C\x07row ${index.toString()}\x1b]133;D;0\x07\n`;
		const bytes = encoder.encode(line);
		buffer.set(bytes, offset);
		offset += bytes.byteLength;
	}
	return buffer;
}

export function* chunkBytes(bytes: Uint8Array, size: number = FIND_CHUNK_SIZE): Generator<Uint8Array> {
	for (let offset = 0; offset < bytes.byteLength; offset += size) {
		yield bytes.subarray(offset, Math.min(offset + size, bytes.byteLength));
	}
}

function domCoreOf(renderer: BenchmarkRenderer): TerminalCore {
	const core = renderer.getCoreForBench?.() as TerminalCore | undefined;
	if (!core) throw new Error("find bench requires a DOM renderer with a core");
	return core;
}

export async function populateScrollback(renderer: BenchmarkRenderer, bytes: Uint8Array): Promise<void> {
	const core = domCoreOf(renderer);
	for (const chunk of chunkBytes(bytes)) {
		core.feed(chunk);
	}
	await renderer.waitForPaint();
}

export function measureFindFirstResult(renderer: BenchmarkRenderer, budget: number = FIND_STEP_BUDGET): number {
	const core = domCoreOf(renderer);
	const session = core.findOpen(FIND_QUERY, false);
	const startedAt = performance.now();
	let guard = 0;
	while (guard < 1_000_000) {
		core.findStep(session, budget);
		const results = core.findResults();
		if (results.length > 0) {
			core.findCancel(session);
			return performance.now() - startedAt;
		}
		if (core.findIsComplete(session)) {
			break;
		}
		guard += 1;
	}
	core.findCancel(session);
	throw new Error("find-500k: no match in 1,000,000 steps");
}
