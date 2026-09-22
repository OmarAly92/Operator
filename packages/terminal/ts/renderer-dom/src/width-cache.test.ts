import { describe, expect, it, vi } from "vitest";
import { REPEAT, WidthCache } from "./width-cache";
import { buildRowNode, type RowSource } from "./row-builder";
import { DEFAULT_FEATURES } from "./features";

describe("WidthCache", () => {
	it("measures each distinct text once per variant and forgets on clear", () => {
		const measure = vi.fn((text: string) => (text === "漢" ? 17 : 8));
		const cache = new WidthCache(measure);
		expect(cache.get("漢", false, false)).toBe(17);
		expect(cache.get("漢", false, false)).toBe(17);
		expect(cache.get("漢", true, false)).toBe(17);
		expect(measure).toHaveBeenCalledTimes(2);
		cache.clear();
		cache.get("漢", false, false);
		expect(measure).toHaveBeenCalledTimes(3);
		expect(REPEAT).toBe(32);
	});
});

describe("letter-spacing correction in a row", () => {
	function rowOf(text: string, spans: number[], widthCache: boolean, measured: number): HTMLElement {
		const content = new TextEncoder().encode(text);
		const source: RowSource = {
			content,
			rows: Uint32Array.from([0, content.byteLength]),
			runRanges: Uint32Array.from([0, 1]),
			stylePairs: Uint32Array.from([content.byteLength, 255, 254, 0, 255]),
			spanRanges: Uint32Array.from([0, spans.length / 3]),
			cellSpans: Uint32Array.from(spans),
		};
		const cache = new WidthCache(() => measured);
		return buildRowNode(source, 0, 0, new TextDecoder(), 8, { ...DEFAULT_FEATURES, widthCache }, cache);
	}
	it("pads a glyph narrower than its cells and pulls in one that is wider", () => {
		const wide = rowOf("a漢b", [1, 4, 2], true, 17);
		const corrected = wide.querySelector<HTMLElement>("[data-terminal-width]")!;
		expect(corrected.textContent).toBe("漢");
		expect(corrected.style.letterSpacing).toBe("-1px");
		expect(wide.textContent).toBe("a漢b");
		const narrow = rowOf("a漢b", [1, 4, 2], true, 15);
		expect(narrow.querySelector<HTMLElement>("[data-terminal-width]")!.style.letterSpacing).toBe("1px");
	});
	it("leaves ascii and exact glyphs alone, and everything alone with the flag off", () => {
		expect(rowOf("abc", [], true, 8).querySelector("[data-terminal-width]")).toBeNull();
		expect(rowOf("a漢b", [1, 4, 2], true, 16).querySelector("[data-terminal-width]")).toBeNull();
		expect(rowOf("a漢b", [1, 4, 2], false, 17).querySelector("[data-terminal-width]")).toBeNull();
	});
});
