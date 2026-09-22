import { ATTR_ITALIC, CELL_SPAN_WORDS, STYLE_DEFAULT_UNDERLINE, STYLE_RUN_WORDS } from "@operator/terminal-core";
import { applyAttributes, underlinedText } from "./attributes.js";
import { blockGlyph, type BlockGlyph, isFullBlock } from "./block-glyphs.js";
import { rowClusters } from "./clusters.js";
import { DEFAULT_FEATURES, type RendererFeatures } from "./features.js";
import {
	styleCodeIsBold,
	styleCodeIsDim,
	styleCodeToBackgroundCss,
	styleCodeToCssVar,
} from "./style-code.js";
import type { WidthCache } from "./width-cache.js";

export const CLASS_ROW = "terminal-row";
export const CLASS_RUN = "terminal-run";

export type RowSource = Readonly<{
	content: Uint8Array;
	rows: Uint32Array;
	rowIndents?: Uint16Array;
	runRanges: Uint32Array;
	stylePairs: Uint32Array;
	spanRanges?: Uint32Array;
	cellSpans?: Uint32Array;
}>;

export function buildRowNode(
	source: RowSource,
	snapshotRowIndex: number,
	label: number,
	decoder: TextDecoder,
	cellWidth = 0,
	features: RendererFeatures = DEFAULT_FEATURES,
	widths: WidthCache | null = null,
): HTMLElement {
	const { content, rows, runRanges, stylePairs } = source;
	const indent = source.rowIndents?.[snapshotRowIndex] ?? 0;
	const rowsBase = snapshotRowIndex * 2;
	const rowContentStart = rows[rowsBase] ?? 0;
	const rowContentEnd = rows[rowsBase + 1] ?? rowContentStart;
	const rowLength = rowContentEnd - rowContentStart;
	const pairStart = runRanges[rowsBase] ?? 0;
	const pairEnd = runRanges[rowsBase + 1] ?? pairStart;
	const spanStart = source.spanRanges?.[rowsBase] ?? 0;
	const spanEnd = source.spanRanges?.[rowsBase + 1] ?? spanStart;
	const rowSpans = source.cellSpans?.subarray(spanStart * CELL_SPAN_WORDS, spanEnd * CELL_SPAN_WORDS) ?? new Uint32Array(0);
	const rowNode = document.createElement("div");
	rowNode.dataset.terminalRow = String(label);
	rowNode.className = CLASS_ROW;
	if (indent > 0 && cellWidth > 0) {
		rowNode.style.paddingLeft = `${indent * cellWidth}px`;
	}
	let rowCursor = 0;
	let pendingIndex = -1;
	let pendingStart = 0;
	let pendingEnd = 0;
	let pendingStyleCode = 255;
	let pendingBackgroundCode = 254;
	let pendingAttrs = 0;
	let pendingUnderline = STYLE_DEFAULT_UNDERLINE;
	const flushPending = (): void => {
		if (pendingIndex < 0) {
			return;
		}
		const slice = content.subarray(rowContentStart + pendingStart, rowContentStart + pendingEnd);
		const run = document.createElement("span");
		run.dataset.terminalRun = String(pendingIndex);
		run.className = CLASS_RUN;
		const foreground = styleCodeToCssVar(pendingStyleCode);
		run.style.color = foreground;
		const background = styleCodeToBackgroundCss(pendingBackgroundCode);
		if (background !== null) {
			run.style.backgroundColor = background;
		}
		if (styleCodeIsBold(pendingStyleCode)) {
			run.style.fontWeight = "700";
		}
		if (styleCodeIsDim(pendingStyleCode)) {
			run.style.opacity = "0.55";
		}
		const text = decoder.decode(slice);
		const underlined = features.attributes === "warp" && applyAttributes(run, pendingAttrs, pendingUnderline);
		if (features.widthCache && widths && cellWidth > 0 && hasNonAscii(text)) {
			const bold = styleCodeIsBold(pendingStyleCode);
			const italic = features.attributes === "warp" && (pendingAttrs & ATTR_ITALIC) !== 0;
			const runSpans = spansForRun(rowSpans, pendingStart, pendingEnd);
			appendMeasuredText(run, text, runSpans, cellWidth, bold, italic, widths, foreground, underlined);
		} else {
			appendRunText(run, underlined ? underlinedText(text) : text, foreground);
		}
		rowNode.append(run);
	};
	for (let pairIndex = pairStart; pairIndex < pairEnd; pairIndex += 1) {
		const elementIndex = pairIndex * STYLE_RUN_WORDS;
		const pairRunEnd = stylePairs[elementIndex] ?? rowCursor;
		const styleCode = stylePairs[elementIndex + 1] ?? 255;
		const backgroundCode = stylePairs[elementIndex + 2] ?? 254;
		const attrs = stylePairs[elementIndex + 3] ?? 0;
		const underlineCode = stylePairs[elementIndex + 4] ?? STYLE_DEFAULT_UNDERLINE;
		const attrsMatch = features.attributes !== "warp" || (attrs === pendingAttrs && underlineCode === pendingUnderline);
		if (pendingIndex >= 0 && styleCode === pendingStyleCode && backgroundCode === pendingBackgroundCode && attrsMatch) {
			pendingEnd = pairRunEnd;
		} else {
			flushPending();
			pendingIndex = pairIndex;
			pendingStart = rowCursor;
			pendingEnd = pairRunEnd;
			pendingStyleCode = styleCode;
			pendingBackgroundCode = backgroundCode;
			pendingAttrs = attrs;
			pendingUnderline = underlineCode;
		}
		rowCursor = pairRunEnd;
	}
	flushPending();
	if (rowCursor < rowLength) {
		const tail = content.subarray(rowContentStart + rowCursor, rowContentStart + rowLength);
		appendRunText(rowNode, decoder.decode(tail), "var(--terminal-foreground)");
	}
	return rowNode;
}

function hasNonAscii(text: string): boolean {
	for (let index = 0; index < text.length; index += 1) {
		if (text.charCodeAt(index) >= 0x80) return true;
	}
	return false;
}

function spansForRun(rowSpans: ArrayLike<number>, runStart: number, runEnd: number): number[] {
	const out: number[] = [];
	const spanCount = Math.floor(rowSpans.length / CELL_SPAN_WORDS);
	for (let index = 0; index < spanCount; index += 1) {
		const start = rowSpans[index * CELL_SPAN_WORDS]!;
		if (start < runStart || start >= runEnd) continue;
		const end = rowSpans[index * CELL_SPAN_WORDS + 1]!;
		const width = rowSpans[index * CELL_SPAN_WORDS + 2]!;
		out.push(start - runStart, end - runStart, width);
	}
	return out;
}

function appendMeasuredText(
	run: HTMLElement,
	text: string,
	spans: ArrayLike<number>,
	cellWidth: number,
	bold: boolean,
	italic: boolean,
	widths: WidthCache,
	foreground: string,
	underlined: boolean,
): void {
	let plain = "";
	const flushPlain = (): void => {
		if (plain === "") return;
		appendRunText(run, underlined ? underlinedText(plain) : plain, foreground);
		plain = "";
	};
	for (const cluster of rowClusters(text, spans)) {
		const ascii = cluster.text.codePointAt(0)! < 0x80 && cluster.text.length === 1;
		const spacing = ascii ? 0 : Math.round((cluster.end - cluster.start) * cellWidth - widths.get(cluster.text, bold, italic));
		if (spacing === 0) {
			plain += cluster.text;
			continue;
		}
		flushPlain();
		const node = document.createElement("span");
		node.dataset.terminalWidth = "";
		node.textContent = underlined ? underlinedText(cluster.text) : cluster.text;
		node.style.letterSpacing = `${spacing}px`;
		run.append(node);
	}
	flushPlain();
}

export const CLASS_GLYPH = "terminal-block-glyph";

const BLOCK_GLYPH_PATTERN = /[\u2580-\u259f]/;

function appendRunText(run: HTMLElement, text: string, foreground: string): void {
	if (!BLOCK_GLYPH_PATTERN.test(text)) {
		run.append(text);
		return;
	}
	let plain = "";
	for (const character of text) {
		const glyph = blockGlyph(character.codePointAt(0) ?? 0);
		if (glyph === null) {
			plain += character;
			continue;
		}
		if (plain !== "") {
			run.append(document.createTextNode(plain));
			plain = "";
		}
		run.append(glyphNode(character, glyph, foreground));
	}
	if (plain !== "") {
		run.append(document.createTextNode(plain));
	}
}

function glyphNode(character: string, glyph: BlockGlyph, foreground: string): HTMLElement {
	const node = document.createElement("span");
	node.className = CLASS_GLYPH;
	node.textContent = character;
	if (glyph.opacity !== 1) {
		node.style.opacity = String(glyph.opacity);
	}
	if (isFullBlock(glyph)) {
		node.style.background = foreground;
		return node;
	}
	for (const rect of glyph.rects) {
		const fill = document.createElement("i");
		fill.style.left = `${rect.x}%`;
		fill.style.top = `${rect.y}%`;
		fill.style.width = `${rect.width}%`;
		fill.style.height = `${rect.height}%`;
		fill.style.background = foreground;
		node.append(fill);
	}
	return node;
}
