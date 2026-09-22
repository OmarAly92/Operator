import { type AltScreenView, STYLE_RUN_WORDS } from "@operator/terminal-core";
import { DEFAULT_FEATURES, type RendererFeatures } from "./features.js";
import { buildRowNode, type RowSource } from "./row-builder.js";

const SURFACE_ATTR = "data-terminal-alt-surface";
const CURSOR_ATTR = "data-terminal-cursor";
const CLASS_SURFACE = "terminal-alt-surface";
const CLASS_CURSOR = "terminal-alt-cursor";

type RowFingerprint = Readonly<{
	content: Uint8Array;
	stylePairs: Uint32Array;
	attributes: RendererFeatures["attributes"];
}>;

const rowFingerprints = new WeakMap<HTMLElement, readonly RowFingerprint[]>();

export type CellMetrics = Readonly<{ cellWidth: number; cellHeight: number }>;

export function renderAltSurface(
	view: AltScreenView,
	into: HTMLElement,
	decoder: TextDecoder,
	metrics: CellMetrics,
	features: RendererFeatures = DEFAULT_FEATURES,
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
		rowFingerprints.set(
			into,
			repaintChangedRows(source, existingRows, rowFingerprints.get(into), decoder, features),
		);
	} else {
		replaceRows(source, into, view.rows, decoder, features);
	}
	applyCursor(into, view, metrics);
}

function repaintChangedRows(
	source: RowSource,
	rows: readonly HTMLElement[],
	previousFingerprints: readonly RowFingerprint[] | undefined,
	decoder: TextDecoder,
	features: RendererFeatures,
): readonly RowFingerprint[] {
	return rows.map((row, index) => {
		const previous = previousFingerprints?.[index];
		if (previous && rowMatches(source, index, previous, features)) return previous;
		const fresh = buildRowNode(source, index, index, decoder, 0, features);
		row.replaceChildren(...Array.from(fresh.childNodes));
		return fingerprintRow(source, index, features);
	});
}

function replaceRows(
	source: RowSource,
	into: HTMLElement,
	rowCount: number,
	decoder: TextDecoder,
	features: RendererFeatures,
): void {
	const fragment = document.createDocumentFragment();
	const fingerprints = new Array<RowFingerprint>(rowCount);
	for (let row = 0; row < rowCount; row += 1) {
		fragment.append(buildRowNode(source, row, row, decoder, 0, features));
		fingerprints[row] = fingerprintRow(source, row, features);
	}
	const cursor = into.querySelector<HTMLElement>(`[${CURSOR_ATTR}]`);
	into.replaceChildren(fragment);
	if (cursor) into.append(cursor);
	rowFingerprints.set(into, fingerprints);
}

function fingerprintRow(source: RowSource, row: number, features: RendererFeatures): RowFingerprint {
	const rangeIndex = row * 2;
	const contentStart = source.rows[rangeIndex] ?? 0;
	const contentEnd = source.rows[rangeIndex + 1] ?? contentStart;
	const pairStart = source.runRanges[rangeIndex] ?? 0;
	const pairEnd = source.runRanges[rangeIndex + 1] ?? pairStart;
	return {
		content: source.content.slice(contentStart, contentEnd),
		stylePairs: source.stylePairs.slice(pairStart * STYLE_RUN_WORDS, pairEnd * STYLE_RUN_WORDS),
		attributes: features.attributes,
	};
}

function rowMatches(source: RowSource, row: number, fingerprint: RowFingerprint, features: RendererFeatures): boolean {
	if (fingerprint.attributes !== features.attributes) return false;
	const rangeIndex = row * 2;
	const contentStart = source.rows[rangeIndex] ?? 0;
	const contentEnd = source.rows[rangeIndex + 1] ?? contentStart;
	if (!rangeMatches(source.content, contentStart, contentEnd, fingerprint.content)) return false;
	const runStart = source.runRanges[rangeIndex] ?? 0;
	const runEnd = source.runRanges[rangeIndex + 1] ?? runStart;
	return rangeMatches(
		source.stylePairs,
		runStart * STYLE_RUN_WORDS,
		runEnd * STYLE_RUN_WORDS,
		fingerprint.stylePairs,
	);
}

function rangeMatches(
	current: Uint8Array | Uint32Array,
	start: number,
	end: number,
	previous: Uint8Array | Uint32Array,
): boolean {
	if (end - start !== previous.length) return false;
	for (let index = 0; index < previous.length; index += 1) {
		if (current[start + index] !== previous[index]) return false;
	}
	return true;
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
