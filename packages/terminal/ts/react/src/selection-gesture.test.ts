import { describe, expect, it } from "vitest";
import { autoScrollRows, exceedsDragThreshold, isCopyChord, kindForClickCount } from "./selection-gesture";

describe("exceedsDragThreshold", () => {
	it("ignores jitter under half a pixel, Warp's MIN_DELTA_FOR_TEXT_SELECTION", () => {
		expect(exceedsDragThreshold({ x: 10, y: 10 }, 10.4, 10.4)).toBe(false);
		expect(exceedsDragThreshold({ x: 10, y: 10 }, 10.6, 10)).toBe(true);
		expect(exceedsDragThreshold({ x: 10, y: 10 }, 10, 9.4)).toBe(true);
	});
});

describe("kindForClickCount", () => {
	it("maps clicks to Warp's SelectionType::from_click_count", () => {
		expect(kindForClickCount(1)).toBe("simple");
		expect(kindForClickCount(2)).toBe("word");
		expect(kindForClickCount(3)).toBe("line");
		expect(kindForClickCount(4)).toBe("line");
	});
});

describe("autoScrollRows", () => {
	it("is zero inside the list", () => {
		expect(autoScrollRows(50, 0, 100)).toBe(0);
	});
	it("scrolls up past the top and down past the bottom margin with Warp's curve", () => {
		expect(autoScrollRows(-100, 0, 400)).toBeCloseTo(-10, 5);
		expect(autoScrollRows(500, 0, 400)).toBeCloseTo(Math.pow(110, 1.5) / 100, 5);
	});
});

describe("isCopyChord", () => {
	it("is cmd-c on mac and ctrl-shift-c elsewhere", () => {
		expect(isCopyChord({ key: "c", metaKey: true, ctrlKey: false, shiftKey: false, altKey: false }, true)).toBe(true);
		expect(isCopyChord({ key: "c", metaKey: false, ctrlKey: true, shiftKey: false, altKey: false }, true)).toBe(false);
		expect(isCopyChord({ key: "C", metaKey: false, ctrlKey: true, shiftKey: true, altKey: false }, false)).toBe(true);
		expect(isCopyChord({ key: "c", metaKey: false, ctrlKey: true, shiftKey: false, altKey: false }, false)).toBe(false);
	});
});
