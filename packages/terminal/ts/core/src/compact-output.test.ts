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

	it("drops a redrawn frame of three or more lines seen within the lookback", () => {
		const frame = ["╭───╮", "│ > │", "╰───╯"];
		expect(compactLines([...frame, "between", ...frame, "after"])).toEqual([...frame, "between", "after"]);
	});

	it("keeps a repeat of only two lines and a repeat beyond the lookback", () => {
		expect(compactLines(["a", "b", "x", "a", "b"])).toEqual(["a", "b", "x", "a", "b"]);
		const block = ["one", "two", "three"];
		const filler = Array.from({ length: COMPACT_REDRAW_LOOKBACK }, (_, index) => `filler ${index}`);
		expect(compactLines([...block, ...filler, ...block])).toEqual([...block, ...filler, ...block]);
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

	it("rejects a cap below three lines or not an integer", () => {
		expect(() => capLines(["a"], 2)).toThrow(RangeError);
		expect(() => capLines(["a"], 3.5)).toThrow(RangeError);
	});
});
