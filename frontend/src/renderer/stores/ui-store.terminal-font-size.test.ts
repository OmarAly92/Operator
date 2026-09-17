import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { useUiStore } from "./ui-store";
import { terminalFontSizeStorageKey } from "../lib/terminal-font-size";

describe("ui-store terminal font size", () => {
	beforeEach(() => {
		useUiStore.setState({ terminalFontSize: 14 });
	});

	afterEach(() => window.localStorage.clear());

	it("persists the choice", () => {
		useUiStore.getState().setTerminalFontSize(16);
		expect(useUiStore.getState().terminalFontSize).toBe(16);
		expect(window.localStorage.getItem(terminalFontSizeStorageKey)).toBe("16");
	});

	it("ignores a re-selection of the current size", () => {
		useUiStore.getState().setTerminalFontSize(14);
		expect(window.localStorage.getItem(terminalFontSizeStorageKey)).toBeNull();
	});
});
