import type { BlockId, FindMatch } from "./types.js";

export function budgetNow(): number {
	return typeof performance !== "undefined" ? performance.now() : Date.now();
}

export function validateEvenLength(name: string, length: number): void {
	if (length % 2 !== 0) {
		throw new Error(`${name} length ${length} is not even`);
	}
}

export function validateMultipleOf(name: string, length: number, words: number): void {
	if (length % words !== 0) {
		throw new Error(`${name} length ${length} is not a multiple of ${words}`);
	}
}

export function parseBlockId(id: BlockId): [number, number] {
	const separator = id.indexOf(":");
	if (separator < 0) {
		throw new Error(`block id ${id} is not in hi:lo form`);
	}
	const hi = Number.parseInt(id.slice(0, separator), 10);
	const lo = Number.parseInt(id.slice(separator + 1), 10);
	if (!Number.isFinite(hi) || !Number.isFinite(lo)) {
		throw new Error(`block id ${id} is not numeric`);
	}
	return [lo, hi];
}

export function decodeFindMatches(view: Uint32Array, words: number): FindMatch[] {
	const matches: FindMatch[] = [];
	for (let base = 0; base + words <= view.length; base += words) {
		matches.push({
			blockId: `${view[base + 1]!}:${view[base]!}`,
			row: view[base + 2]!,
			endRow: view[base + 3]!,
			startByte: view[base + 4]!,
			endByte: view[base + 5]!,
		});
	}
	return matches;
}
