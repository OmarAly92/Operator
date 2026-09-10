import { describe, expect, it } from "vitest";
import { fillGradient, runFill } from "./selection-fill";

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
