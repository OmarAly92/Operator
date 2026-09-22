import { rowClusters } from "./clusters.js";

const BOUNDARY_CHARS = "`~!@#$%^&*()-=+[{]}\\|;:'\",.<>/?«»";
const ALLOWLIST = "-.~/\\";

export function isWordBoundary(character: string): boolean {
	if ([...character].length !== 1) return false;
	if (/\s/u.test(character)) return true;
	if (ALLOWLIST.includes(character)) return false;
	return BOUNDARY_CHARS.includes(character);
}

export function wordCellRange(text: string, spans: ArrayLike<number>, cell: number): { start: number; end: number } {
	const list = rowClusters(text, spans);
	if (list.length === 0) return { start: 0, end: 0 };
	let index = list.findIndex((c) => cell >= c.start && cell < c.end);
	if (index < 0) index = list.length - 1;
	const hit = list[index]!;
	if (isWordBoundary(hit.text)) return { start: hit.start, end: hit.end };
	let first = index;
	while (first > 0 && !isWordBoundary(list[first - 1]!.text)) first -= 1;
	let last = index;
	while (last < list.length - 1 && !isWordBoundary(list[last + 1]!.text)) last += 1;
	return { start: list[first]!.start, end: list[last]!.end };
}
