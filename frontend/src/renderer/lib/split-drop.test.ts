import { describe, expect, it } from "vitest";
import { resolveDrop, sameResolution, type PaneGeometry } from "./split-drop";

const pane: PaneGeometry = {
	paneId: "p1",
	pane: { left: 0, top: 0, width: 1000, height: 800 },
	strip: { left: 0, top: 0, width: 1000, height: 40 },
	tabs: [
		{ left: 0, top: 0, width: 100, height: 40 },
		{ left: 100, top: 0, width: 100, height: 40 },
	],
};
const outsider = { paneId: null, index: null, soleTab: false };

describe("resolveDrop", () => {
	it.each([
		["left", 100, 400, { left: 0, top: 0, width: 500, height: 800 }],
		["right", 900, 400, { left: 500, top: 0, width: 500, height: 800 }],
		["top", 500, 120, { left: 0, top: 0, width: 1000, height: 400 }],
		["bottom", 500, 780, { left: 0, top: 400, width: 1000, height: 400 }],
	] as const)("offers the %s half", (edge, x, y, box) => {
		expect(resolveDrop({ x, y }, [pane], outsider)).toEqual({ kind: "split", paneId: "p1", edge, box });
	});

	it("picks the nearer edge along the pane's diagonals", () => {
		expect(resolveDrop({ x: 150, y: 300 }, [pane], outsider)).toMatchObject({ edge: "left" });
		expect(resolveDrop({ x: 250, y: 60 }, [pane], outsider)).toMatchObject({ edge: "top" });
	});

	it("moves into the pane from its centre region", () => {
		expect(resolveDrop({ x: 500, y: 400 }, [pane], outsider)).toEqual({
			kind: "move",
			paneId: "p1",
			index: 2,
			box: pane.pane,
		});
	});

	it("computes the strip insertion index from tab midpoints", () => {
		expect(resolveDrop({ x: 40, y: 20 }, [pane], outsider)).toMatchObject({ kind: "move", index: 0 });
		expect(resolveDrop({ x: 160, y: 20 }, [pane], outsider)).toMatchObject({ kind: "move", index: 2 });
		expect(resolveDrop({ x: 120, y: 20 }, [pane], outsider)).toMatchObject({ kind: "move", index: 1 });
	});

	it("returns null for no-op drops of a tab on its own position or pane centre", () => {
		const own = { paneId: "p1", index: 0, soleTab: false };
		expect(resolveDrop({ x: 40, y: 20 }, [pane], own)).toBeNull();
		expect(resolveDrop({ x: 120, y: 20 }, [pane], own)).toBeNull();
		expect(resolveDrop({ x: 500, y: 400 }, [pane], own)).toBeNull();
		expect(resolveDrop({ x: 160, y: 20 }, [pane], own)).toMatchObject({ kind: "move", index: 2 });
	});

	it("never splits a pane by its own only tab", () => {
		expect(resolveDrop({ x: 900, y: 400 }, [pane], { paneId: "p1", index: 0, soleTab: true })).toBeNull();
	});

	it("refuses halves below the minimum pane size", () => {
		const narrow = { ...pane, pane: { left: 0, top: 0, width: 600, height: 380 } };
		expect(resolveDrop({ x: 590, y: 190 }, [narrow], outsider)).toBeNull();
		expect(resolveDrop({ x: 300, y: 370 }, [narrow], outsider)).toBeNull();
		const wide = { ...pane, pane: { left: 0, top: 0, width: 640, height: 400 } };
		expect(resolveDrop({ x: 630, y: 200 }, [wide], outsider)).toMatchObject({ edge: "right" });
		expect(resolveDrop({ x: 320, y: 390 }, [wide], outsider)).toMatchObject({ edge: "bottom" });
	});

	it("returns null outside every pane and resolves the pane under the pointer", () => {
		const second: PaneGeometry = { ...pane, paneId: "p2", pane: { left: 1000, top: 0, width: 1000, height: 800 }, strip: { left: 1000, top: 0, width: 1000, height: 40 }, tabs: [] };
		expect(resolveDrop({ x: 2500, y: 10 }, [pane, second], outsider)).toBeNull();
		expect(resolveDrop({ x: 1900, y: 400 }, [pane, second], outsider)).toMatchObject({ paneId: "p2", edge: "right" });
	});

	it("compares resolutions structurally", () => {
		const a = resolveDrop({ x: 900, y: 400 }, [pane], outsider);
		const b = resolveDrop({ x: 910, y: 410 }, [pane], outsider);
		expect(sameResolution(a, b)).toBe(true);
		expect(sameResolution(a, resolveDrop({ x: 100, y: 400 }, [pane], outsider))).toBe(false);
		expect(sameResolution(null, null)).toBe(true);
	});
});
