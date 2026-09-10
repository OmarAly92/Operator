import { describe, expect, it } from "vitest";
import { fillGradient, rowFill, runFill } from "./selection-fill";

const row = { left: 26, right: 626 };

describe("rowFill", () => {
	// Warp runs the first row of a selection from where it started to the end of
	// the row, not to the end of its text (grid_renderer.rs
	// calculate_background_bounds).
	it("runs the first row from where the selection started to the row's end", () => {
		expect(rowFill(row, { left: 100, right: 300 }, "first")).toEqual({ left: 74, right: 600 });
	});

	it("fills a row in the middle whole, text or not", () => {
		expect(rowFill(row, null, "middle")).toEqual({ left: 0, right: 600 });
	});

	it("stops the last row where the selection ends", () => {
		expect(rowFill(row, { left: 26, right: 300 }, "last")).toEqual({ left: 0, right: 274 });
	});

	it("keeps a selection inside one row between its own ends", () => {
		expect(rowFill(row, { left: 100, right: 300 }, "only")).toEqual({ left: 74, right: 274 });
	});

	// A drag that stops at the very start of a row includes the row in the range
	// without covering any of it.
	it("paints nothing on an end row the selection did not reach into", () => {
		expect(rowFill(row, null, "last")).toBeNull();
		expect(rowFill(row, null, "first")).toBeNull();
	});

	it("never runs outside the row, whatever the range reports", () => {
		expect(rowFill(row, { left: 0, right: 900 }, "only")).toEqual({ left: 0, right: 600 });
	});

	it("ignores a sliver narrower than half a pixel", () => {
		expect(rowFill(row, { left: 100, right: 100.4 }, "only")).toBeNull();
	});
});

// Warp pushes the selection rect after the cell background rects and blends it
// over them (grid_renderer.rs render_selection -> render_background, wgpu
// ALPHA_BLENDING), with glyphs drawn above both. A run that paints its own
// background gets the same wash, clipped to the part of the row's fill it covers.
describe("runFill", () => {
	it("covers a run inside the fill from edge to edge, in the run's own coordinates", () => {
		expect(runFill({ left: 126, right: 226 }, 26, { left: 0, right: 600 })).toEqual({ left: 0, right: 100 });
	});

	it("clips to the fill when the selection starts or ends inside the run", () => {
		expect(runFill({ left: 126, right: 226 }, 26, { left: 150, right: 600 })).toEqual({ left: 50, right: 100 });
		expect(runFill({ left: 126, right: 226 }, 26, { left: 0, right: 150 })).toEqual({ left: 0, right: 50 });
	});

	it("leaves a run the fill does not reach alone", () => {
		expect(runFill({ left: 400, right: 500 }, 26, { left: 0, right: 300 })).toBeNull();
	});
});

describe("fillGradient", () => {
	it("paints only the span, transparent either side", () => {
		expect(fillGradient({ left: 10, right: 40 }, "red")).toBe(
			"linear-gradient(to right, transparent 10px, red 10px, red 40px, transparent 40px)",
		);
	});
});
