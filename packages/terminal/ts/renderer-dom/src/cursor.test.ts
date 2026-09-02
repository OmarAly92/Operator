import { describe, expect, it } from "vitest";
import { CLASS_CURSOR, createCursorElement, primaryCursorPlacement } from "./cursor";

const snapshot = (over: Partial<Parameters<typeof primaryCursorPlacement>[0]> = {}) => ({
	cursorRow: 4,
	cursorColumn: 7,
	cursorVisible: true,
	lineEditorState: 2,
	altScreen: null,
	...over,
});

describe("primaryCursorPlacement", () => {
	it("places the cursor where the core says it is", () => {
		expect(primaryCursorPlacement(snapshot())).toEqual({ row: 4, column: 7 });
	});

	it("draws nothing while the line editor owns the line", () => {
		expect(primaryCursorPlacement(snapshot({ lineEditorState: 1 }))).toBeNull();
	});

	it("draws nothing for a hidden cursor", () => {
		expect(primaryCursorPlacement(snapshot({ cursorVisible: false }))).toBeNull();
	});

	it("leaves the alt screen to the alt surface", () => {
		expect(primaryCursorPlacement(snapshot({ altScreen: {} }))).toBeNull();
	});

	it("draws for a shell with no integration at all", () => {
		expect(primaryCursorPlacement(snapshot({ lineEditorState: 0 }))).toEqual({ row: 4, column: 7 });
	});
});

describe("createCursorElement", () => {
	it("sits over the cell the cursor is on", () => {
		const node = createCursorElement(3, 8);
		expect(node.className).toBe(CLASS_CURSOR);
		expect(node.style.width).toBe("8px");
		expect(node.style.transform).toBe("translateX(24px)");
	});
});
