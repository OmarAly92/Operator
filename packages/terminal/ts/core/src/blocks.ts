import type { BlockSource, BlockState, BlockView, TerminalSnapshot } from "./types.js";

export const BLOCK_RECORD_WORDS = 14;

const STATES: readonly BlockState[] = ["running", "finished", "abandoned"];
const SOURCES: readonly BlockSource[] = ["osc133", "extension", "synthetic"];

const textDecoder = new TextDecoder();

export function decodeBlocks(
	snapshot: Pick<TerminalSnapshot, "blocks" | "blockText">,
): BlockView[] {
	const { blocks, blockText } = snapshot;
	if (blocks.length % BLOCK_RECORD_WORDS !== 0) {
		throw new Error(
			`blocks length ${blocks.length} is not a multiple of ${BLOCK_RECORD_WORDS}`,
		);
	}
	const count = blocks.length / BLOCK_RECORD_WORDS;
	const views: BlockView[] = [];
	for (let i = 0; i < count; i += 1) {
		const base = i * BLOCK_RECORD_WORDS;
		const idLow = blocks[base];
		const idHigh = blocks[base + 1];
		const packed = blocks[base + 4];
		const stateByte = packed & 0xff;
		const sourceByte = (packed >> 8) & 0xff;
		const state = STATES[stateByte];
		const source = SOURCES[sourceByte];
		if (state === undefined) {
			throw new Error(`block state byte ${stateByte} is out of range`);
		}
		if (source === undefined) {
			throw new Error(`block source byte ${sourceByte} is out of range`);
		}
		const hasExit = ((packed >> 16) & 1) === 1;
		// `| 0` reinterprets the u32 word as the i32 it was encoded from.
		const exitCode = hasExit ? blocks[base + 5] | 0 : null;
		const durationLow = blocks[base + 6];
		const durationHigh = blocks[base + 7];
		const durationMs =
			durationLow === 0xffffffff && durationHigh === 0xffffffff
				? null
				: durationHigh * 2 ** 32 + durationLow;
		views.push({
			// The Rust id is a u64; a JS number cannot hold one, so it stays a string.
			id: `${idHigh}:${idLow}`,
			firstRow: blocks[base + 2],
			rowCount: blocks[base + 3],
			state,
			source,
			exitCode,
			durationMs,
			command: decodeSpan(blockText, blocks[base + 8], blocks[base + 9]),
			cwd: decodeSpan(blockText, blocks[base + 10], blocks[base + 11]),
			gitBranch: decodeSpan(blockText, blocks[base + 12], blocks[base + 13]),
		});
	}
	return views;
}

function decodeSpan(text: Uint8Array, start: number, end: number): string {
	if (start === 0 && end === 0) {
		return "";
	}
	return textDecoder.decode(text.subarray(start, end));
}
