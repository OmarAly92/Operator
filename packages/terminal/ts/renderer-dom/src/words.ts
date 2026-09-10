import { cellWidthOf } from "./cell-width.js";

const BOUNDARY_CHARS = "`~!@#$%^&*()-=+[{]}\\|;:'\",.<>/?«»";
const ALLOWLIST = "-.~/\\";

export function isWordBoundary(character: string): boolean {
	if (/\s/u.test(character)) return true;
	if (ALLOWLIST.includes(character)) return false;
	return BOUNDARY_CHARS.includes(character);
}

type Cell = Readonly<{ character: string; start: number; end: number }>;

function cells(text: string): Cell[] {
	const out: Cell[] = [];
	let cell = 0;
	for (const character of text) {
		const width = cellWidthOf(character.codePointAt(0) ?? 0);
		if (width === 0 && out.length > 0) continue;
		out.push({ character, start: cell, end: cell + Math.max(width, 1) });
		cell += width;
	}
	return out;
}

export function wordCellRange(text: string, cell: number): { start: number; end: number } {
	const list = cells(text);
	if (list.length === 0) return { start: 0, end: 0 };
	let index = list.findIndex((c) => cell >= c.start && cell < c.end);
	if (index < 0) index = list.length - 1;
	const hit = list[index]!;
	if (isWordBoundary(hit.character)) return { start: hit.start, end: hit.end };
	let first = index;
	while (first > 0 && !isWordBoundary(list[first - 1]!.character)) first -= 1;
	let last = index;
	while (last < list.length - 1 && !isWordBoundary(list[last + 1]!.character)) last += 1;
	return { start: list[first]!.start, end: list[last]!.end };
}
