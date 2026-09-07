import { describe, expect, it } from "vitest";
import { blockGlyph, isBlockGlyph, isFullBlock } from "./block-glyphs.js";
import { buildRowNode, CLASS_GLYPH, type RowSource } from "./row-builder.js";

const DEFAULT_FOREGROUND = 255;
const DEFAULT_BACKGROUND = 254;

function rowOf(text: string, styleCode = DEFAULT_FOREGROUND): HTMLElement {
	const content = new TextEncoder().encode(text);
	const source: RowSource = {
		content,
		rows: Uint32Array.from([0, content.byteLength]),
		runRanges: Uint32Array.from([0, 1]),
		stylePairs: Uint32Array.from([content.byteLength, styleCode, DEFAULT_BACKGROUND]),
	};
	return buildRowNode(source, 0, 0, new TextDecoder("utf-8", { fatal: true }));
}

function glyphs(row: HTMLElement): HTMLElement[] {
	return [...row.querySelectorAll<HTMLElement>(`.${CLASS_GLYPH}`)];
}

describe("block glyph table", () => {
	it("covers the whole block-elements range", () => {
		for (let cp = 0x2580; cp <= 0x259f; cp += 1) {
			expect(isBlockGlyph(cp), `U+${cp.toString(16)}`).toBe(true);
		}
	});

	it("claims nothing outside that range", () => {
		expect(isBlockGlyph(0x257f)).toBe(false);
		expect(isBlockGlyph(0x25a0)).toBe(false);
		expect(isBlockGlyph("a".codePointAt(0)!)).toBe(false);
	});

	it("keeps every rect inside the cell", () => {
		for (let cp = 0x2580; cp <= 0x259f; cp += 1) {
			for (const rect of blockGlyph(cp)!.rects) {
				expect(rect.x + rect.width).toBeLessThanOrEqual(100);
				expect(rect.y + rect.height).toBeLessThanOrEqual(100);
				expect(rect.width).toBeGreaterThan(0);
				expect(rect.height).toBeGreaterThan(0);
			}
		}
	});

	it("shades the three shade characters instead of giving them a shape", () => {
		for (const [cp, opacity] of [
			[0x2591, 0.25],
			[0x2592, 0.5],
			[0x2593, 0.75],
		] as const) {
			const glyph = blockGlyph(cp)!;
			expect(isFullBlock(glyph)).toBe(true);
			expect(glyph.opacity).toBe(opacity);
		}
	});
});

describe("block glyph rendering", () => {
	it("draws the full block as a solid cell with no child rects", () => {
		const glyph = glyphs(rowOf("█"))[0]!;
		expect(glyph.style.background).toBe("var(--terminal-foreground)");
		expect(glyph.querySelectorAll("i").length).toBe(0);
	});

	it("draws a quadrant glyph as two positioned rects", () => {
		const fills = [...glyphs(rowOf("▛"))[0]!.querySelectorAll<HTMLElement>("i")];
		expect(fills.length).toBe(2);
		expect([fills[0]!.style.left, fills[0]!.style.top, fills[0]!.style.width, fills[0]!.style.height]).toEqual(
			["0%", "0%", "100%", "50%"],
		);
		expect([fills[1]!.style.left, fills[1]!.style.top, fills[1]!.style.width, fills[1]!.style.height]).toEqual(
			["0%", "50%", "50%", "50%"],
		);
	});

	it("fills the rects with the run's own foreground", () => {
		const fill = glyphs(rowOf("▐", 1))[0]!.querySelector<HTMLElement>("i")!;
		expect(fill.style.background).toBe("var(--terminal-ansi-1)");
	});

	it("keeps the character in the DOM so selection and copy still see it", () => {
		const row = rowOf(" ▐▛███▛█");
		expect(row.textContent).toBe(" ▐▛███▛█");
	});

	it("leaves ordinary text as plain text nodes", () => {
		const row = rowOf("plain text");
		expect(glyphs(row).length).toBe(0);
		expect(row.textContent).toBe("plain text");
	});

	it("splits a mixed run into text and glyphs without losing order", () => {
		const row = rowOf("a█b▀c");
		expect(glyphs(row).length).toBe(2);
		expect(row.textContent).toBe("a█b▀c");
	});
});
