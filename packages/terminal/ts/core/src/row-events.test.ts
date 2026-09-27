import { describe, expect, it } from "vitest";
import { remapStableRow } from "./row-events";
import type { RowEvent } from "./types";

const event: RowEvent = { trimmed: 0, remap: [[10, 10], [11, 10], [12, 11]], remapEnd: [13, 12] };

describe("remapStableRow", () => {
	it("moves a rewrapped row to the row that now holds its start", () => {
		expect(remapStableRow(11, event)).toBe(10);
		expect(remapStableRow(12, event)).toBe(11);
	});
	it("shifts a row after the rewrapped ones by the change in their count", () => {
		expect(remapStableRow(13, event)).toBe(12);
		expect(remapStableRow(20, event)).toBe(19);
	});
	it("leaves a row before the rewrapped ones alone", () => {
		expect(remapStableRow(4, event)).toBe(4);
	});
	it("leaves every row alone for a trim", () => {
		expect(remapStableRow(20, { trimmed: 3, remap: null, remapEnd: null })).toBe(20);
	});
	it("shifts every row from the end when no completed row was rewrapped", () => {
		expect(remapStableRow(2, { trimmed: 0, remap: null, remapEnd: [0, 3] })).toBe(5);
	});
});
