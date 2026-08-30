import { describe, expect, it } from "vitest";
import type { AltScreenView } from "@operator/terminal-core";
import { renderAltSurface } from "./alt-surface.js";

const DEFAULT_STYLE_CODE = 255;
const ROW_ENCODER = new TextEncoder();

function buildAltView(
	_rows: number,
	_columns: number,
	rowTexts: readonly string[],
	overrides: Partial<Pick<AltScreenView, "cursorRow" | "cursorColumn" | "cursorVisible">> = {},
): AltScreenView {
	const rowRanges: number[] = [];
	const runRanges: number[] = [];
	const stylePairs: number[] = [];
	const chunks: Uint8Array[] = [];
	let cursor = 0;
	let pairIndex = 0;
	for (let i = 0; i < rowTexts.length; i += 1) {
		const text = rowTexts[i] ?? "";
		const bytes = ROW_ENCODER.encode(text);
		chunks.push(bytes);
		rowRanges.push(cursor, cursor + bytes.byteLength);
		runRanges.push(pairIndex, pairIndex + 1);
		stylePairs.push(bytes.byteLength, DEFAULT_STYLE_CODE);
		pairIndex += 1;
		cursor += bytes.byteLength;
	}
	const totalLength = chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0);
	const content = new Uint8Array(totalLength);
	let offset = 0;
	for (const chunk of chunks) {
		content.set(chunk, offset);
		offset += chunk.byteLength;
	}
	return {
		rows: rowTexts.length,
		columns: 10,
		content,
		rowRanges: Uint32Array.from(rowRanges),
		runRanges: Uint32Array.from(runRanges),
		stylePairs: Uint32Array.from(stylePairs),
		cursorRow: overrides.cursorRow ?? 0,
		cursorColumn: overrides.cursorColumn ?? 0,
		cursorVisible: overrides.cursorVisible ?? true,
	};
}

const METRICS = { cellWidth: 8, cellHeight: 20 } as const;

function mountAlt(
	rows: number,
	columns: number,
	rowTexts: readonly string[],
	overrides: Partial<Pick<AltScreenView, "cursorRow" | "cursorColumn" | "cursorVisible">> = {},
): HTMLElement {
	const view = buildAltView(rows, columns, rowTexts, overrides);
	const host = document.createElement("div");
	const decoder = new TextDecoder("utf-8", { fatal: true });
	renderAltSurface(view, host, decoder, METRICS);
	return host;
}

function mountAltReusable(
	rows: number,
	columns: number,
	rowTexts: readonly string[],
): { host: HTMLElement; render: (rowTexts: readonly string[]) => void } {
	const decoder = new TextDecoder("utf-8", { fatal: true });
	const host = document.createElement("div");
	renderAltSurface(buildAltView(rows, columns, rowTexts), host, decoder, METRICS);
	return {
		host,
		render: (newRowTexts: readonly string[]): void => {
			renderAltSurface(buildAltView(rows, columns, newRowTexts), host, decoder, METRICS);
		},
	};
}

describe("renderAltSurface", () => {
	it("renders one row element per grid row, blank rows included", () => {
		const host = mountAlt(3, 10, ["ab", "", "cd"]);
		const rows = host.querySelectorAll("[data-terminal-row]");
		expect(rows.length).toBe(3);
		expect(rows[1]!.textContent).toBe("");
	});

	it("draws no block chrome in the alternate screen", () => {
		const host = mountAlt(3, 10, ["ab", "", ""]);
		expect(host.querySelector(".terminal-block-header")).toBeNull();
		expect(host.querySelector("[data-terminal-block-id]")).toBeNull();
	});

	it("places the cursor at the reported cell", () => {
		const host = mountAlt(3, 10, ["abc", "", ""], { cursorRow: 0, cursorColumn: 2 });
		const cursor = host.querySelector("[data-terminal-cursor]") as HTMLElement;
		expect(cursor.dataset.row).toBe("0");
		expect(cursor.dataset.column).toBe("2");
	});

	it("positions the cursor in resolved pixels, not through undefined css variables", () => {
		const host = mountAlt(5, 10, ["abc", "", "", "", ""], { cursorRow: 3, cursorColumn: 7 });
		const cursor = host.querySelector("[data-terminal-cursor]") as HTMLElement;
		expect(cursor.style.transform).toBe("translate(56px, 60px)");
		expect(cursor.style.transform).not.toContain("var(");
	});

	it("sizes the cursor to one cell", () => {
		const host = mountAlt(3, 10, ["abc", "", ""], { cursorRow: 0, cursorColumn: 0 });
		const cursor = host.querySelector("[data-terminal-cursor]") as HTMLElement;
		expect(cursor.style.width).toBe("8px");
		expect(cursor.style.height).toBe("20px");
	});

	it("hides the cursor when the program hid it", () => {
		const host = mountAlt(3, 10, ["abc", "", ""], { cursorVisible: false });
		expect(host.querySelector("[data-terminal-cursor]")).toBeNull();
	});

	it("does not virtualize: the alternate buffer is one screen and all of it is on screen", () => {
		const host = mountAlt(60, 10, new Array(60).fill("x"));
		expect(host.querySelectorAll("[data-terminal-row]").length).toBe(60);
	});

	it("reuses row elements across repaints instead of rebuilding the surface", () => {
		const { host, render } = mountAltReusable(3, 10, ["a", "b", "c"]);
		const first = host.querySelector("[data-terminal-row]");
		render(["a", "b", "d"]);
		expect(host.querySelector("[data-terminal-row]")).toBe(first);
	});
});
