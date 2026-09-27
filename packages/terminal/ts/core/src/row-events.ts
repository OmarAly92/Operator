import type { WasmTerminalCore } from "../wasm/vt_core.js";
import type { RowEvent } from "./types.js";
import { getMemory, u32View } from "./wasm-runtime.js";

export function takeRowEvent(inner: WasmTerminalCore): RowEvent | null {
	const trimmed = inner.row_events_trimmed();
	const remapLen = inner.remap_len();
	if (trimmed === 0 && remapLen === 0) return null;
	const words = u32View(getMemory(), inner.remap_ptr(), remapLen);
	const pairs: Array<readonly [number, number]> = [];
	for (let index = 0; index + 1 < words.length; index += 2) pairs.push([words[index]!, words[index + 1]!]);
	inner.clear_row_events();
	const remapEnd = pairs.pop() ?? null;
	return { trimmed, remap: pairs.length > 0 ? pairs : null, remapEnd };
}

export function remapStableRow(row: number, event: RowEvent): number {
	const remap = event.remap ?? [];
	let low = 0;
	let high = remap.length - 1;
	while (low <= high) {
		const mid = (low + high) >> 1;
		const [from, to] = remap[mid]!;
		if (from === row) return to;
		if (from < row) low = mid + 1;
		else high = mid - 1;
	}
	const end = event.remapEnd;
	return end && row >= end[0] ? row - end[0] + end[1] : row;
}
