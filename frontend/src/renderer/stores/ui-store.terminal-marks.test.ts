import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useUiStore } from "./ui-store";
import { MAX_TERMINAL_MARKS, terminalMarksStorageKey, type TerminalMark } from "../lib/terminal-marks";

const mark = (id: string): TerminalMark => ({ id, pattern: `word ${id}`, regex: false, colour: "red" });

describe("ui-store terminal marks", () => {
	beforeEach(() => {
		useUiStore.setState({ terminalMarks: [] });
	});

	afterEach(() => window.localStorage.clear());

	it("persists the list", () => {
		useUiStore.getState().setTerminalMarks([mark("a")]);
		expect(useUiStore.getState().terminalMarks).toEqual([mark("a")]);
		expect(window.localStorage.getItem(terminalMarksStorageKey)).toBe(JSON.stringify([mark("a")]));
	});

	it("keeps no more than the cap", () => {
		useUiStore.getState().setTerminalMarks(Array.from({ length: MAX_TERMINAL_MARKS + 2 }, (_, index) => mark(`m${index}`)));
		expect(useUiStore.getState().terminalMarks).toHaveLength(MAX_TERMINAL_MARKS);
	});

	it("starts from the marks a previous run saved", async () => {
		window.localStorage.setItem(terminalMarksStorageKey, JSON.stringify([mark("saved")]));
		vi.resetModules();
		const { useUiStore: fresh } = await import("./ui-store");
		expect(fresh.getState().terminalMarks).toEqual([mark("saved")]);
	});
});
