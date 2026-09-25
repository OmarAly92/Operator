import { describe, expect, it } from "vitest";
import { terminalAppearance } from "./terminal-appearance";

describe("terminalAppearance", () => {
	const colors = { foreground: "#ffffff", background: "#1d2022" };

	it("reports the cell in device pixels, rounded", () => {
		expect(terminalAppearance({ width: 8.4, height: 16.8 }, colors, 2)).toEqual({
			cellWidth: 17,
			cellHeight: 34,
			foreground: "#ffffff",
			background: "#1d2022",
		});
	});

	it("treats a missing or nonsensical pixel ratio as 1", () => {
		expect(terminalAppearance({ width: 8, height: 17 }, colors, 0)).toMatchObject({ cellWidth: 8, cellHeight: 17 });
		expect(terminalAppearance({ width: 8, height: 17 }, colors, Number.NaN)).toMatchObject({ cellWidth: 8, cellHeight: 17 });
	});
});
