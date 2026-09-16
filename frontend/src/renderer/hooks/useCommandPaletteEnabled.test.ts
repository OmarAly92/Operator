import { describe, expect, it } from "vitest";
import { isCommandPaletteEnabled } from "./useCommandPaletteEnabled";

describe("isCommandPaletteEnabled", () => {
	it("enables search in identified desktop builds and development", () => {
		expect(isCommandPaletteEnabled("0.10.3", true)).toBe(true);
		expect(isCommandPaletteEnabled(undefined, true)).toBe(true);
		expect(isCommandPaletteEnabled("0.10.3", false)).toBe(true);
		expect(isCommandPaletteEnabled(undefined, false)).toBe(false);
	});
});
