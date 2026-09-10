const WIDE_RANGES: readonly (readonly [number, number])[] = [
	[0x1100, 0x115f],
	[0x2e80, 0x303e],
	[0x3041, 0x33ff],
	[0x3400, 0x4dbf],
	[0x4e00, 0x9fff],
	[0xa000, 0xa4cf],
	[0xac00, 0xd7a3],
	[0xf900, 0xfaff],
	[0xfe30, 0xfe4f],
	[0xff00, 0xff60],
	[0xffe0, 0xffe6],
	[0x1f300, 0x1f64f],
	[0x1f900, 0x1f9ff],
	[0x20000, 0x2fffd],
	[0x30000, 0x3fffd],
];

const ZERO_RANGES: readonly (readonly [number, number])[] = [
	[0x0300, 0x036f],
	[0x1ab0, 0x1aff],
	[0x1dc0, 0x1dff],
	[0x200b, 0x200f],
	[0x20d0, 0x20ff],
	[0xfe00, 0xfe0f],
	[0xfe20, 0xfe2f],
	[0xe0100, 0xe01ef],
];

function inRanges(codePoint: number, ranges: readonly (readonly [number, number])[]): boolean {
	for (const [start, end] of ranges) {
		if (codePoint < start) return false;
		if (codePoint <= end) return true;
	}
	return false;
}

export function cellWidthOf(codePoint: number): 0 | 1 | 2 {
	if (codePoint === 0) return 0;
	if (inRanges(codePoint, ZERO_RANGES)) return 0;
	if (inRanges(codePoint, WIDE_RANGES)) return 2;
	return 1;
}

export function cellCount(text: string): number {
	let cells = 0;
	for (const character of text) cells += cellWidthOf(character.codePointAt(0) ?? 0);
	return cells;
}

export function cellSlice(text: string, fromCell: number, toCell: number): string {
	let cell = 0;
	let out = "";
	for (const character of text) {
		const width = cellWidthOf(character.codePointAt(0) ?? 0);
		const inside = width === 0 ? out !== "" || (cell >= fromCell && cell < toCell) : cell >= fromCell && cell < toCell;
		if (inside) out += character;
		cell += width;
		if (cell >= toCell && width > 0) break;
	}
	return out;
}
