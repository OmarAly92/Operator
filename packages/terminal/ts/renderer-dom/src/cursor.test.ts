import { describe, expect, it } from "vitest";
import {
	CLASS_CURSOR,
	CLASS_CURSOR_HOLLOW,
	CLASS_CURSOR_INVERTED,
	createCursorElement,
	cursorPaintFor,
	placeCursor,
	PLAIN_CURSOR_PAINT,
	primaryCursorPlacement,
} from "./cursor";
import { DEFAULT_FEATURES } from "./features";
import type { RowSource } from "./row-builder";
import { warpDarkTheme } from "./theme-warp";

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

describe("placeCursor with a paint", () => {
	it("stays a plain box by default", () => {
		const row = document.createElement("div");
		const cursor = createCursorElement(0, 8);
		placeCursor(row, cursor, 3, 8);
		expect(cursor.className).toBe(CLASS_CURSOR);
		expect(cursor.textContent).toBe("");
		expect(cursor.style.width).toBe("8px");
	});
	it("inverts with the cell's text and spans the cluster's cells", () => {
		const row = document.createElement("div");
		const cursor = createCursorElement(0, 8);
		placeCursor(row, cursor, 3, 8, { inverted: true, hollow: false, text: "漢", cells: 2 });
		expect(cursor.classList.contains(CLASS_CURSOR_INVERTED)).toBe(true);
		expect(cursor.textContent).toBe("漢");
		expect(cursor.style.width).toBe("16px");
		placeCursor(row, cursor, 3, 8);
		expect(cursor.classList.contains(CLASS_CURSOR_INVERTED)).toBe(false);
		expect(cursor.textContent).toBe("");
	});
	it("hollows when asked", () => {
		const cursor = createCursorElement(0, 8);
		placeCursor(document.createElement("div"), cursor, 0, 8, { inverted: false, hollow: true, text: "", cells: 1 });
		expect(cursor.classList.contains(CLASS_CURSOR_HOLLOW)).toBe(true);
	});
});

describe("cursorPaintFor", () => {
	const encoder = new TextEncoder();
	const decoder = new TextDecoder();
	const RGB_CURSOR_BAND = 0x0200_0000 | (25 << 16) | (170 << 8) | 216;
	function source(text: string, background: number, spans: number[] = []): RowSource {
		const content = encoder.encode(text);
		return {
			content,
			rows: Uint32Array.from([0, content.byteLength]),
			runRanges: Uint32Array.from([0, 1]),
			stylePairs: Uint32Array.from([content.byteLength, 255, background, 0, 255]),
			spanRanges: Uint32Array.from([0, spans.length / 3]),
			cellSpans: Uint32Array.from(spans),
		};
	}
	const base = { row: 0, theme: warpDarkTheme, focused: true, decoder };

	it("is plain with every flag off, whatever the band", () => {
		expect(cursorPaintFor({ ...base, source: source("ab", RGB_CURSOR_BAND), column: 1, features: DEFAULT_FEATURES })).toEqual(PLAIN_CURSOR_PAINT);
	});
	it("inverts over a band that matches the cursor colour and carries the cell's cluster", () => {
		const features = { ...DEFAULT_FEATURES, cursorContrast: true };
		expect(cursorPaintFor({ ...base, source: source("a漢b", RGB_CURSOR_BAND, [1, 4, 2]), column: 1, features })).toEqual({ inverted: true, hollow: false, text: "漢", cells: 2 });
		expect(cursorPaintFor({ ...base, source: source("ab", 254), column: 1, features })).toEqual({ ...PLAIN_CURSOR_PAINT, text: "b" });
		expect(cursorPaintFor({ ...base, source: source("ab", RGB_CURSOR_BAND), column: 7, features })).toEqual({ inverted: true, hollow: false, text: "", cells: 1 });
	});
	it("hollows when unfocused only with its flag", () => {
		const features = { ...DEFAULT_FEATURES, cursorHollowUnfocused: true };
		expect(cursorPaintFor({ ...base, source: source("ab", 254), column: 0, features, focused: false }).hollow).toBe(true);
		expect(cursorPaintFor({ ...base, source: source("ab", 254), column: 0, features, focused: true }).hollow).toBe(false);
		expect(cursorPaintFor({ ...base, source: source("ab", 254), column: 0, features: DEFAULT_FEATURES, focused: false }).hollow).toBe(false);
	});
});
