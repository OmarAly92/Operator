import { describe, expect, it } from "vitest";
import { capLines, COMPACT_REDRAW_LOOKBACK, compactLines, isSpinnerLine } from "./index";

describe("isSpinnerLine", () => {
	it.each([
		"✽ Flambéing… (13s · still thinking with high effort)",
		"· Thinking…",
		"  ⠋ Installing dependencies...",
		"◐ Loading…",
	])("recognises %j", (line) => {
		expect(isSpinnerLine(line)).toBe(true);
	});

	it.each([
		"✻ Baked for 11s · done 6:13 PM",
		"- Installing dependencies...",
		"* item one…",
		"Thinking…",
		"✻",
		"· Linking... done in 3.2s",
		"⠿ Container db  Started... healthy",
	])("leaves %j", (line) => {
		expect(isSpinnerLine(line)).toBe(false);
	});
});

describe("compactLines", () => {
	it("trims trailing spaces, collapses blank runs and drops leading and trailing blanks", () => {
		expect(compactLines(["", "a   ", "", "", "b", "", ""])).toEqual(["a", "", "b"]);
	});

	it("drops spinner status lines", () => {
		expect(compactLines(["✽ Working… (3s)", "result", "✻ Worked for 3s"])).toEqual(["result", "✻ Worked for 3s"]);
	});

	it("collapses a line repeated back to back", () => {
		expect(compactLines(["banner", "banner", "body"])).toEqual(["banner", "body"]);
	});

	it("keeps a frame repeated after a distinct line", () => {
		const frame = ["╭───╮", "│ > │", "╰───╯"];
		expect(compactLines([...frame, "between", ...frame, "after"])).toEqual([...frame, "between", ...frame, "after"]);
	});

	it("keeps a repeat of only two lines and a repeat beyond the lookback", () => {
		expect(compactLines(["a", "b", "x", "a", "b"])).toEqual(["a", "b", "x", "a", "b"]);
		const block = ["one", "two", "three"];
		const filler = Array.from({ length: COMPACT_REDRAW_LOOKBACK }, (_, index) => `filler ${index}`);
		expect(compactLines([...block, ...filler, ...block])).toEqual([...block, ...filler, ...block]);
	});

	it("keeps a later run of the same steps separated by a distinct line", () => {
		const lines = ["test a", "setup", "run", "teardown", "test b", "setup", "run", "teardown"];
		expect(compactLines(lines)).toEqual(lines);
	});

	it("drops a frame redrawn back to back, however many times", () => {
		const frame = ["╭───╮", "│ > │", "╰───╯"];
		expect(compactLines([...frame, ...frame, ...frame, "after"])).toEqual([...frame, "after"]);
	});

	it("does not count blank lines toward a redrawn frame", () => {
		expect(compactLines(["a", "", "b", "x", "a", "", "b"])).toEqual(["a", "", "b", "x", "a", "", "b"]);
	});
});

describe("capLines", () => {
	it("keeps the head and the tail around one marker line", () => {
		const lines = Array.from({ length: 10 }, (_, index) => `line ${index}`);
		expect(capLines(lines, 5)).toEqual(["line 0", "line 1", "… 6 lines omitted …", "line 8", "line 9"]);
		expect(capLines(lines, 10)).toEqual(lines);
	});

	it("reads zero or less as nothing, Infinity as no cap and a fraction as its floor", () => {
		const lines = Array.from({ length: 10 }, (_, index) => `line ${index}`);
		expect(capLines(lines, 0)).toEqual([]);
		expect(capLines(lines, -4)).toEqual([]);
		expect(capLines(lines, Number.POSITIVE_INFINITY)).toEqual(lines);
		expect(capLines(lines, 5.9)).toEqual(capLines(lines, 5));
		expect(capLines(lines, 1)).toEqual(["… 10 lines omitted …"]);
		expect(capLines(lines, 2)).toEqual(["line 0", "… 9 lines omitted …"]);
		expect(() => capLines(lines, Number.NaN)).toThrow(RangeError);
	});
});
