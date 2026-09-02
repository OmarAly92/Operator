import { describe, expect, it } from "vitest";
import { fillRect } from "./selection-fill";

const root = { left: 10, top: 100 };
const row = { top: 140, left: 26, right: 626, height: 17 };

describe("fillRect", () => {
	it("covers the empty space from the last glyph to the end of the row", () => {
		expect(fillRect(row, 200, root)).toEqual({ top: 40, left: 190, width: 426, height: 17 });
	});

	it("fills a row the selection painted nothing on, such as a blank line", () => {
		expect(fillRect(row, row.left, root)).toEqual({ top: 40, left: 16, width: 600, height: 17 });
	});

	it("adds nothing to a row whose text already reaches the end", () => {
		expect(fillRect(row, 626, root)).toBeNull();
	});

	// Sub-pixel text metrics leave slivers that read as artefacts rather than
	// as part of the selection.
	it("ignores a sliver narrower than half a pixel", () => {
		expect(fillRect(row, 625.7, root)).toBeNull();
	});

	it("never starts left of the row, whatever the range reports", () => {
		expect(fillRect(row, 0, root)?.left).toBe(16);
	});
});
