import type { AltScreenView } from "@operator/terminal-core";
import { buildRowNode } from "./row-builder.js";

const SURFACE_ATTR = "data-terminal-alt-surface";
const CURSOR_ATTR = "data-terminal-cursor";
const CLASS_SURFACE = "terminal-alt-surface";
const CLASS_CURSOR = "terminal-alt-cursor";

export type CellMetrics = Readonly<{ cellWidth: number; cellHeight: number }>;

export function renderAltSurface(
	view: AltScreenView,
	into: HTMLElement,
	decoder: TextDecoder,
	metrics: CellMetrics,
): void {
	if (!into.hasAttribute(SURFACE_ATTR)) {
		into.dataset.terminalAltSurface = "";
		into.classList.add(CLASS_SURFACE);
	}
	const source = {
		content: view.content,
		rows: view.rowRanges,
		runRanges: view.runRanges,
		stylePairs: view.stylePairs,
	};
	const existingRows = Array.from(into.querySelectorAll<HTMLElement>("[data-terminal-row]"));
	if (existingRows.length === view.rows) {
		for (let i = 0; i < view.rows; i += 1) {
			const fresh = buildRowNode(source, i, i, decoder);
			existingRows[i]!.replaceChildren(...Array.from(fresh.childNodes));
		}
	} else {
		const fragment = document.createDocumentFragment();
		for (let i = 0; i < view.rows; i += 1) {
			fragment.append(buildRowNode(source, i, i, decoder));
		}
		const existingCursor = into.querySelector<HTMLElement>(`[${CURSOR_ATTR}]`);
		into.replaceChildren(fragment);
		if (existingCursor) {
			into.append(existingCursor);
		}
	}
	applyCursor(into, view, metrics);
}

function applyCursor(into: HTMLElement, view: AltScreenView, metrics: CellMetrics): void {
	const existing = into.querySelector<HTMLElement>(`[${CURSOR_ATTR}]`);
	if (!view.cursorVisible) {
		existing?.remove();
		return;
	}
	if (existing) {
		positionCursor(existing, view, metrics);
		return;
	}
	const cursor = document.createElement("div");
	cursor.dataset.terminalCursor = "";
	cursor.classList.add(CLASS_CURSOR);
	positionCursor(cursor, view, metrics);
	into.append(cursor);
}

function positionCursor(cursor: HTMLElement, view: AltScreenView, metrics: CellMetrics): void {
	cursor.dataset.row = String(view.cursorRow);
	cursor.dataset.column = String(view.cursorColumn);
	const x = view.cursorColumn * metrics.cellWidth;
	const y = view.cursorRow * metrics.cellHeight;
	cursor.style.width = `${metrics.cellWidth}px`;
	cursor.style.height = `${metrics.cellHeight}px`;
	cursor.style.transform = `translate(${x}px, ${y}px)`;
}
