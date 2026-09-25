import { afterEach, describe, expect, it, vi } from "vitest";
import {
	MAX_TERMINAL_MARK_PATTERN,
	MAX_TERMINAL_MARKS,
	TERMINAL_MARK_COLOURS,
	newTerminalMark,
	readStoredTerminalMarks,
	sanitizeTerminalMarks,
	terminalMarkColourCss,
	terminalMarkPatternValid,
	terminalMarkRules,
	terminalMarksStorageKey,
	writeStoredTerminalMarks,
	type TerminalMark,
} from "./terminal-marks";

const mark = (overrides: Partial<TerminalMark> = {}): TerminalMark => ({ id: "a", pattern: "error", regex: false, colour: "red", ...overrides });

describe("terminal marks", () => {
	afterEach(() => {
		vi.unstubAllGlobals();
		window.localStorage.clear();
	});

	it("offers five colours from the terminal palette and none of them is the selection's blue", () => {
		expect(TERMINAL_MARK_COLOURS.map((colour) => colour.id)).toEqual(["yellow", "red", "green", "cyan", "magenta"]);
		expect(TERMINAL_MARK_COLOURS.map((colour) => colour.ansi)).not.toContain(4);
	});

	it("tints a colour from the terminal's own ANSI variable at the selection's strength", () => {
		expect(terminalMarkColourCss("red")).toBe("color-mix(in srgb, var(--terminal-ansi-1) 40%, transparent)");
		expect(terminalMarkColourCss("cyan")).toBe("color-mix(in srgb, var(--terminal-ansi-6) 40%, transparent)");
	});

	it("turns stored marks into renderer rules and skips empty and broken patterns", () => {
		expect(terminalMarkRules([
			mark(),
			mark({ id: "b", pattern: "" }),
			mark({ id: "c", pattern: "(oops", regex: true }),
			mark({ id: "d", pattern: "FAIL|panic", regex: true, colour: "yellow" }),
		])).toEqual([
			{ pattern: "error", regex: false, colour: terminalMarkColourCss("red") },
			{ pattern: "FAIL|panic", regex: true, colour: terminalMarkColourCss("yellow") },
		]);
	});

	it("accepts any literal and only a regex that compiles", () => {
		expect(terminalMarkPatternValid("(oops", false)).toBe(true);
		expect(terminalMarkPatternValid("(oops", true)).toBe(false);
		expect(terminalMarkPatternValid("err(or)?", true)).toBe(true);
	});

	it("reads back what it wrote", () => {
		const marks = [mark(), mark({ id: "b", pattern: "warn", regex: true, colour: "green" })];
		writeStoredTerminalMarks(marks);
		expect(window.localStorage.getItem(terminalMarksStorageKey)).toBe(JSON.stringify(marks));
		expect(readStoredTerminalMarks()).toEqual(marks);
	});

	it("reads nothing from missing, broken or foreign storage", () => {
		expect(readStoredTerminalMarks()).toEqual([]);
		window.localStorage.setItem(terminalMarksStorageKey, "{not json");
		expect(readStoredTerminalMarks()).toEqual([]);
		window.localStorage.setItem(terminalMarksStorageKey, JSON.stringify({ pattern: "x" }));
		expect(readStoredTerminalMarks()).toEqual([]);
	});

	it("falls back to no marks when storage throws", () => {
		vi.stubGlobal("localStorage", {
			getItem: () => {
				throw new Error("denied");
			},
			setItem: () => {
				throw new Error("denied");
			},
		});
		expect(readStoredTerminalMarks()).toEqual([]);
		expect(() => writeStoredTerminalMarks([mark()])).not.toThrow();
	});

	it("drops malformed entries, duplicate ids, unknown colours and anything past the cap", () => {
		const many = Array.from({ length: MAX_TERMINAL_MARKS + 3 }, (_, index) => mark({ id: `m${index}` }));
		expect(sanitizeTerminalMarks([
			null,
			"error",
			{ id: "x", pattern: "a", regex: "yes", colour: "red" },
			{ id: "y", pattern: "a", regex: false, colour: "blue" },
			{ id: "", pattern: "a", regex: false, colour: "red" },
			mark({ id: "z" }),
			mark({ id: "z", pattern: "again" }),
		])).toEqual([mark({ id: "z" })]);
		expect(sanitizeTerminalMarks(many)).toHaveLength(MAX_TERMINAL_MARKS);
		expect(sanitizeTerminalMarks([mark({ pattern: "x".repeat(MAX_TERMINAL_MARK_PATTERN + 50) })])[0]!.pattern).toHaveLength(MAX_TERMINAL_MARK_PATTERN);
	});

	it("starts a new mark empty, literal, with a fresh id and the first colour not yet used", () => {
		const first = newTerminalMark([]);
		expect(first).toMatchObject({ pattern: "", regex: false, colour: "yellow" });
		const second = newTerminalMark([first]);
		expect(second.colour).toBe("red");
		expect(second.id).not.toBe(first.id);
	});
});
