import { afterEach, describe, expect, it } from "vitest";
import {
	TERMINAL_BACKGROUNDS,
	applyTerminalBackground,
	defaultTerminalBackground,
	readStoredTerminalBackground,
	terminalBackgroundColor,
	terminalBackgroundStorageKey,
} from "./terminal-background";

afterEach(() => {
	window.localStorage.clear();
	document.documentElement.style.removeProperty("--terminal-background");
});

describe("readStoredTerminalBackground", () => {
	it("falls back to black when nothing is stored", () => {
		expect(readStoredTerminalBackground()).toBe("black");
		expect(defaultTerminalBackground).toBe("black");
	});

	it("falls back to black when the stored value is not a known id", () => {
		window.localStorage.setItem(terminalBackgroundStorageKey, "chartreuse");
		expect(readStoredTerminalBackground()).toBe("black");
	});

	it("returns a stored id", () => {
		window.localStorage.setItem(terminalBackgroundStorageKey, "charcoal");
		expect(readStoredTerminalBackground()).toBe("charcoal");
	});
});

describe("terminalBackgroundColor", () => {
	it("resolves every id to its hex", () => {
		expect(terminalBackgroundColor("black")).toBe("#000000");
		expect(terminalBackgroundColor("charcoal")).toBe("#1d2022");
	});

	it("lists black first, then charcoal", () => {
		expect(TERMINAL_BACKGROUNDS[0]?.id).toBe("black");
		expect(TERMINAL_BACKGROUNDS[1]?.id).toBe("charcoal");
	});

	it("keeps every colour a distinct six-digit hex", () => {
		const colors = TERMINAL_BACKGROUNDS.map((option) => option.color);
		expect(new Set(colors).size).toBe(colors.length);
		for (const color of colors) expect(color).toMatch(/^#[0-9a-f]{6}$/);
	});
});

describe("applyTerminalBackground", () => {
	it("writes the resolved colour to the document root", () => {
		applyTerminalBackground("charcoal");
		expect(document.documentElement.style.getPropertyValue("--terminal-background")).toBe("#1d2022");
	});
});
