import { STYLE_RUN_WORDS } from "@operator/terminal-core";
import { blockGlyph, type BlockGlyph, isFullBlock } from "./block-glyphs.js";
import {
	styleCodeIsBold,
	styleCodeIsDim,
	styleCodeToBackgroundCss,
	styleCodeToCssVar,
} from "./style-code.js";

export const CLASS_ROW = "terminal-row";
export const CLASS_RUN = "terminal-run";

export type RowSource = Readonly<{
	content: Uint8Array;
	rows: Uint32Array;
	rowIndents?: Uint16Array;
	runRanges: Uint32Array;
	stylePairs: Uint32Array;
}>;

export function buildRowNode(
	source: RowSource,
	snapshotRowIndex: number,
	label: number,
	decoder: TextDecoder,
	cellWidth = 0,
): HTMLElement {
	const { content, rows, runRanges, stylePairs } = source;
	const indent = source.rowIndents?.[snapshotRowIndex] ?? 0;
	const rowsBase = snapshotRowIndex * 2;
	const rowContentStart = rows[rowsBase] ?? 0;
	const rowContentEnd = rows[rowsBase + 1] ?? rowContentStart;
	const rowLength = rowContentEnd - rowContentStart;
	const pairStart = runRanges[rowsBase] ?? 0;
	const pairEnd = runRanges[rowsBase + 1] ?? pairStart;
	const rowNode = document.createElement("div");
	rowNode.dataset.terminalRow = String(label);
	rowNode.className = CLASS_ROW;
	if (indent > 0 && cellWidth > 0) {
		rowNode.style.paddingLeft = `${indent * cellWidth}px`;
	}
	let rowCursor = 0;
	for (let pairIndex = pairStart; pairIndex < pairEnd; pairIndex += 1) {
		const elementIndex = pairIndex * STYLE_RUN_WORDS;
		const pairRunEnd = stylePairs[elementIndex] ?? rowCursor;
		const styleCode = stylePairs[elementIndex + 1] ?? 255;
		const backgroundCode = stylePairs[elementIndex + 2] ?? 254;
		const slice = content.subarray(rowContentStart + rowCursor, rowContentStart + pairRunEnd);
		const run = document.createElement("span");
		run.dataset.terminalRun = String(pairIndex);
		run.className = CLASS_RUN;
		const foreground = styleCodeToCssVar(styleCode);
		run.style.color = foreground;
		const background = styleCodeToBackgroundCss(backgroundCode);
		if (background !== null) {
			run.style.backgroundColor = background;
		}
		if (styleCodeIsBold(styleCode)) {
			run.style.fontWeight = "700";
		}
		if (styleCodeIsDim(styleCode)) {
			run.style.opacity = "0.55";
		}
		appendRunText(run, decoder.decode(slice), foreground);
		rowNode.append(run);
		rowCursor = pairRunEnd;
	}
	if (rowCursor < rowLength) {
		const tail = content.subarray(rowContentStart + rowCursor, rowContentStart + rowLength);
		appendRunText(rowNode, decoder.decode(tail), "var(--terminal-foreground)");
	}
	return rowNode;
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
