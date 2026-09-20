import { describe, expect, it } from "vitest";
import { CLASS_CURSOR, createCursorElement, placeCursor, primaryCursorPlacement } from "./cursor";

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

describe("placeCursor", () => {
	it("moves the cursor into a new row and leaves it alone when it is already there", async () => {
		const first = document.createElement("div");
		const second = document.createElement("div");
		const cursor = createCursorElement(0, 8);
		const records: MutationRecord[] = [];
		const observer = new MutationObserver((batch) => records.push(...batch));
		observer.observe(first, { childList: true });
		observer.observe(second, { childList: true });
		placeCursor(first, cursor, 2, 8);
		expect(cursor.parentElement).toBe(first);
		placeCursor(first, cursor, 3, 8);
		expect(cursor.style.transform).toBe("translateX(24px)");
		placeCursor(second, cursor, 1, 8);
		expect(cursor.parentElement).toBe(second);
		await Promise.resolve();
		records.push(...observer.takeRecords());
		observer.disconnect();
		const moves = records.flatMap((record) => [...record.addedNodes]).filter((node) => node === cursor);
		expect(moves).toHaveLength(2);
	});
});
