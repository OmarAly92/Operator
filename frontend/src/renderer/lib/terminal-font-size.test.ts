import { afterEach, describe, expect, it } from "vitest";
import { TERMINAL_FONT_SIZES, defaultTerminalFontSize, readStoredTerminalFontSize, terminalFontSizeStorageKey } from "./terminal-font-size";

describe("terminal font size", () => {
	afterEach(() => window.localStorage.clear());

	it("defaults to 14 and offers 10 through 20", () => {
		expect(defaultTerminalFontSize).toBe(14);
		expect(TERMINAL_FONT_SIZES[0]).toBe(10);
		expect(TERMINAL_FONT_SIZES.at(-1)).toBe(20);
		expect(readStoredTerminalFontSize()).toBe(14);
	});

	it("reads a stored size and clamps out-of-range or garbage values", () => {
		window.localStorage.setItem(terminalFontSizeStorageKey, "16");
		expect(readStoredTerminalFontSize()).toBe(16);
		window.localStorage.setItem(terminalFontSizeStorageKey, "40");
		expect(readStoredTerminalFontSize()).toBe(20);
		window.localStorage.setItem(terminalFontSizeStorageKey, "3");
		expect(readStoredTerminalFontSize()).toBe(10);
		window.localStorage.setItem(terminalFontSizeStorageKey, "big");
		expect(readStoredTerminalFontSize()).toBe(14);
	});
});
