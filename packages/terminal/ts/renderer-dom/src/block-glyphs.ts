export const BLOCK_GLYPH_FIRST = 0x2580;
export const BLOCK_GLYPH_LAST = 0x259f;

export type GlyphRect = Readonly<{ x: number; y: number; width: number; height: number }>;

export type BlockGlyph = Readonly<{ rects: readonly GlyphRect[]; opacity: number }>;

const GLYPHS: ReadonlyMap<number, BlockGlyph> = new Map([
	[
		0x2580,
		{ rects: [{ x: 0, y: 0, width: 100, height: 50 }], opacity: 1 },
	],
	[
		0x2581,
		{ rects: [{ x: 0, y: 87.5, width: 100, height: 12.5 }], opacity: 1 },
	],
	[
		0x2582,
		{ rects: [{ x: 0, y: 75, width: 100, height: 25 }], opacity: 1 },
	],
	[
		0x2583,
		{ rects: [{ x: 0, y: 62.5, width: 100, height: 37.5 }], opacity: 1 },
	],
	[
		0x2584,
		{ rects: [{ x: 0, y: 50, width: 100, height: 50 }], opacity: 1 },
	],
	[
		0x2585,
		{ rects: [{ x: 0, y: 37.5, width: 100, height: 62.5 }], opacity: 1 },
	],
	[
		0x2586,
		{ rects: [{ x: 0, y: 25, width: 100, height: 75 }], opacity: 1 },
	],
	[
		0x2587,
		{ rects: [{ x: 0, y: 12.5, width: 100, height: 87.5 }], opacity: 1 },
	],
	[
		0x2588,
		{ rects: [{ x: 0, y: 0, width: 100, height: 100 }], opacity: 1 },
	],
	[
		0x2589,
		{ rects: [{ x: 0, y: 0, width: 87.5, height: 100 }], opacity: 1 },
	],
	[
		0x258a,
		{ rects: [{ x: 0, y: 0, width: 75, height: 100 }], opacity: 1 },
	],
	[
		0x258b,
		{ rects: [{ x: 0, y: 0, width: 62.5, height: 100 }], opacity: 1 },
	],
	[
		0x258c,
		{ rects: [{ x: 0, y: 0, width: 50, height: 100 }], opacity: 1 },
	],
	[
		0x258d,
		{ rects: [{ x: 0, y: 0, width: 37.5, height: 100 }], opacity: 1 },
	],
	[
		0x258e,
		{ rects: [{ x: 0, y: 0, width: 25, height: 100 }], opacity: 1 },
	],
	[
		0x258f,
		{ rects: [{ x: 0, y: 0, width: 12.5, height: 100 }], opacity: 1 },
	],
	[
		0x2590,
		{ rects: [{ x: 50, y: 0, width: 50, height: 100 }], opacity: 1 },
	],
	[
		0x2591,
		{ rects: [{ x: 0, y: 0, width: 100, height: 100 }], opacity: 0.25 },
	],
	[
		0x2592,
		{ rects: [{ x: 0, y: 0, width: 100, height: 100 }], opacity: 0.5 },
	],
	[
		0x2593,
		{ rects: [{ x: 0, y: 0, width: 100, height: 100 }], opacity: 0.75 },
	],
	[
		0x2594,
		{ rects: [{ x: 0, y: 0, width: 100, height: 12.5 }], opacity: 1 },
	],
	[
		0x2595,
		{ rects: [{ x: 87.5, y: 0, width: 12.5, height: 100 }], opacity: 1 },
	],
	[
		0x2596,
		{ rects: [{ x: 0, y: 50, width: 50, height: 50 }], opacity: 1 },
	],
	[
		0x2597,
		{ rects: [{ x: 50, y: 50, width: 50, height: 50 }], opacity: 1 },
	],
	[
		0x2598,
		{ rects: [{ x: 0, y: 0, width: 50, height: 50 }], opacity: 1 },
	],
	[
		0x2599,
		{ rects: [{ x: 0, y: 0, width: 50, height: 100 }, { x: 50, y: 50, width: 50, height: 50 }], opacity: 1 },
	],
	[
		0x259a,
		{ rects: [{ x: 0, y: 0, width: 50, height: 50 }, { x: 50, y: 50, width: 50, height: 50 }], opacity: 1 },
	],
	[
		0x259b,
		{ rects: [{ x: 0, y: 0, width: 100, height: 50 }, { x: 0, y: 50, width: 50, height: 50 }], opacity: 1 },
	],
	[
		0x259c,
		{ rects: [{ x: 0, y: 0, width: 100, height: 50 }, { x: 50, y: 50, width: 50, height: 50 }], opacity: 1 },
	],
	[
		0x259d,
		{ rects: [{ x: 50, y: 0, width: 50, height: 50 }], opacity: 1 },
	],
	[
		0x259e,
		{ rects: [{ x: 50, y: 0, width: 50, height: 50 }, { x: 0, y: 50, width: 50, height: 50 }], opacity: 1 },
	],
	[
		0x259f,
		{ rects: [{ x: 50, y: 0, width: 50, height: 100 }, { x: 0, y: 50, width: 50, height: 50 }], opacity: 1 },
	],
]);

export function isBlockGlyph(codePoint: number): boolean {
	return GLYPHS.has(codePoint);
}

export function blockGlyph(codePoint: number): BlockGlyph | null {
	return GLYPHS.get(codePoint) ?? null;
}

export function isFullBlock(glyph: BlockGlyph): boolean {
	if (glyph.rects.length !== 1) return false;
	const rect = glyph.rects[0]!;
	return rect.x === 0 && rect.y === 0 && rect.width === 100 && rect.height === 100;
}
