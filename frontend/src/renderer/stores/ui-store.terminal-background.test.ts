import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { useUiStore } from "./ui-store";
import { terminalBackgroundStorageKey } from "../lib/terminal-background";

describe("ui-store terminal background", () => {
	beforeEach(() => {
		useUiStore.setState({ terminalBackground: "charcoal" });
	});

	afterEach(() => {
		window.localStorage.clear();
		document.documentElement.style.removeProperty("--terminal-background");
	});

	it("persists the choice and repaints the surround", () => {
		useUiStore.getState().setTerminalBackground("black");

		expect(useUiStore.getState().terminalBackground).toBe("black");
		expect(window.localStorage.getItem(terminalBackgroundStorageKey)).toBe("black");
		expect(document.documentElement.style.getPropertyValue("--terminal-background")).toBe("#000000");
	});

	it("ignores a re-selection of the current colour", () => {
		useUiStore.getState().setTerminalBackground("charcoal");
		expect(window.localStorage.getItem(terminalBackgroundStorageKey)).toBeNull();
	});
});
