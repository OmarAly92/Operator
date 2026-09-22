import { describe, expect, it } from "vitest";
import { contrastRatio, cursorLacksContrast, MIN_CURSOR_CONTRAST, parseHexColour, relativeLuminance, styleCodeToRgb } from "./cursor-contrast";
import { warpDarkTheme } from "./theme-warp";

const RGB = (r: number, g: number, b: number) => 0x0200_0000 | (r << 16) | (g << 8) | b;
const INDEXED = (i: number) => 0x0100_0000 | i;

describe("colour parsing and contrast", () => {
	it("parses #rrggbb and rejects anything else", () => {
		expect(parseHexColour("#19aad8")).toEqual([0x19, 0xaa, 0xd8]);
		expect(parseHexColour("rgb(1 2 3)")).toBeNull();
	});
	it("computes W3C luminance and contrast like vte's Rgb::contrast", () => {
		expect(relativeLuminance([255, 255, 255])).toBeCloseTo(1, 5);
		expect(relativeLuminance([0, 0, 0])).toBeCloseTo(0, 5);
		expect(contrastRatio([255, 255, 255], [0, 0, 0])).toBeCloseTo(21, 5);
		expect(contrastRatio([0, 0, 0], [255, 255, 255])).toBeCloseTo(21, 5);
	});
	it("resolves style codes through the theme", () => {
		expect(styleCodeToRgb(254, warpDarkTheme, "background")).toEqual([0x05, 0x05, 0x05]);
		expect(styleCodeToRgb(255, warpDarkTheme, "foreground")).toEqual([0xff, 0xff, 0xff]);
		expect(styleCodeToRgb(1, warpDarkTheme, "foreground")).toEqual([0xff, 0x82, 0x72]);
		expect(styleCodeToRgb(INDEXED(196), warpDarkTheme, "foreground")).toEqual([255, 0, 0]);
		expect(styleCodeToRgb(INDEXED(236), warpDarkTheme, "background")).toEqual([48, 48, 48]);
		expect(styleCodeToRgb(RGB(25, 170, 216), warpDarkTheme, "background")).toEqual([25, 170, 216]);
	});
	it("flags a background that matches the cursor and accepts the default background", () => {
		expect(MIN_CURSOR_CONTRAST).toBe(1.5);
		expect(cursorLacksContrast(warpDarkTheme, RGB(25, 170, 216))).toBe(true);
		expect(cursorLacksContrast(warpDarkTheme, 254)).toBe(false);
		expect(cursorLacksContrast(warpDarkTheme, INDEXED(236))).toBe(false);
	});
});
