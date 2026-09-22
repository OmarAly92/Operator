import { CELL_SPAN_WORDS, STYLE_RUN_WORDS, type TerminalTheme } from "@operator/terminal-core";
import { rowClusters, type Cluster } from "./clusters.js";
import { cursorLacksContrast } from "./cursor-contrast.js";
import type { RendererFeatures } from "./features.js";
import type { RowSource } from "./row-builder.js";

export const CLASS_CURSOR = "terminal-cursor";
export const CURSOR_ATTR = "data-terminal-cursor-cell";
export const CLASS_CURSOR_INVERTED = "terminal-cursor-inverted";
export const CLASS_CURSOR_HOLLOW = "terminal-cursor-hollow";

const LINE_EDITOR_OWNED = 1;

export type CursorSnapshot = Readonly<{
	cursorRow: number;
	cursorColumn: number;
	cursorVisible: boolean;
	lineEditorState: number;
	altScreen: unknown;
}>;

export type CursorPlacement = Readonly<{ row: number; column: number }>;

// Where the block list should draw the terminal's own cursor, or null when it
// must not draw one at all.
//
// The line editor draws its own caret while it owns the line, so drawing this
// one too leaves two carets in the pane. Everything else -- a child process
// holding the line, a shell with no integration -- has no other caret, and
// without this the pane shows none at all.
export function primaryCursorPlacement(snapshot: CursorSnapshot): CursorPlacement | null {
	if (snapshot.altScreen) return null;
	if (!snapshot.cursorVisible) return null;
	if (snapshot.lineEditorState === LINE_EDITOR_OWNED) return null;
	return { row: snapshot.cursorRow, column: snapshot.cursorColumn };
}

export type CursorPaint = Readonly<{ inverted: boolean; hollow: boolean; text: string; cells: number }>;
export const PLAIN_CURSOR_PAINT: CursorPaint = { inverted: false, hollow: false, text: "", cells: 1 };

export function placeCursor(row: HTMLElement, cursor: HTMLElement, column: number, cellWidth: number, paint: CursorPaint = PLAIN_CURSOR_PAINT): void {
	cursor.dataset.column = String(column);
	cursor.style.width = `${cellWidth * Math.max(1, paint.cells)}px`;
	cursor.style.transform = `translateX(${column * cellWidth}px)`;
	cursor.classList.toggle(CLASS_CURSOR_INVERTED, paint.inverted);
	cursor.classList.toggle(CLASS_CURSOR_HOLLOW, paint.hollow);
	const text = paint.inverted ? paint.text : "";
	if (cursor.textContent !== text) cursor.textContent = text;
	if (cursor.parentElement !== row) row.append(cursor);
}

export function cursorPaintFor(input: {
	source: RowSource;
	row: number;
	column: number;
	theme: TerminalTheme;
	features: RendererFeatures;
	focused: boolean;
	decoder: TextDecoder;
}): CursorPaint {
	const { source, row, column, theme, features, focused, decoder } = input;
	const hollow = features.cursorHollowUnfocused && !focused;
	if (!features.cursorContrast) return hollow ? { ...PLAIN_CURSOR_PAINT, hollow } : PLAIN_CURSOR_PAINT;
	const start = source.rows[row * 2] ?? 0;
	const end = source.rows[row * 2 + 1] ?? start;
	const text = decoder.decode(source.content.subarray(start, end));
	const spanStart = source.spanRanges?.[row * 2] ?? 0;
	const spanEnd = source.spanRanges?.[row * 2 + 1] ?? spanStart;
	const spans = source.cellSpans?.subarray(spanStart * CELL_SPAN_WORDS, spanEnd * CELL_SPAN_WORDS) ?? [];
	let byte = 0;
	let cell: Cluster | null = null;
	for (const cluster of rowClusters(text, spans)) {
		if (cluster.start === column) {
			cell = cluster;
			break;
		}
		if (cluster.start > column) break;
		byte += new TextEncoder().encode(cluster.text).byteLength;
	}
	const pairStart = source.runRanges[row * 2] ?? 0;
	const pairEnd = source.runRanges[row * 2 + 1] ?? pairStart;
	let background = 254;
	for (let pair = pairStart; pair < pairEnd; pair += 1) {
		const runEnd = source.stylePairs[pair * STYLE_RUN_WORDS] ?? 0;
		if (byte < runEnd || (cell === null && pair === pairEnd - 1 && byte === runEnd)) {
			background = source.stylePairs[pair * STYLE_RUN_WORDS + 2] ?? 254;
			break;
		}
	}
	return {
		inverted: cursorLacksContrast(theme, background),
		hollow,
		text: cell?.text ?? "",
		cells: cell ? cell.end - cell.start : 1,
	};
}

export function createCursorElement(column: number, cellWidth: number): HTMLElement {
	const cursor = document.createElement("span");
	cursor.className = CLASS_CURSOR;
	cursor.setAttribute(CURSOR_ATTR, "");
	cursor.dataset.column = String(column);
	cursor.style.width = `${cellWidth}px`;
	cursor.style.transform = `translateX(${column * cellWidth}px)`;
	return cursor;
}
