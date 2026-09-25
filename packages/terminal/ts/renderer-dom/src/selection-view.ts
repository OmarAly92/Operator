import { CELL_SPAN_WORDS, decodeBlocks, STYLE_RUN_WORDS, STYLE_WORD_LINK, type BlockId, type BlockView, type TerminalSnapshot } from "@operator/terminal-core";
import { applyFilter, type BlockFilter } from "./block-filter.js";
import { trimTrailingBlankRows } from "./block-rows.js";
import type { RowBox } from "./selection-geometry.js";
import { resolveRange, type BlockOrder, type SelectionRange, type SelectionState } from "./selection-model.js";
import { type TextRows } from "./selection-text.js";

export const ALT_BLOCK_ID = "alt";

export type SelectionView = Readonly<{ range: SelectionRange; order: BlockOrder; rows: TextRows }>;
export type RenderedRow = Readonly<{ box: RowBox; element: HTMLElement }>;

export function resolveSelectionView(selection: SelectionState, rows: TextRows): SelectionView | null {
	const index = new Map(rows.blockIds.map((id, position) => [id, position] as const));
	const order: BlockOrder = (blockId) => index.get(blockId) ?? -1;
	if (order(selection.head.blockId) < 0 || order(selection.tail.blockId) < 0) return null;
	const range = resolveRange(selection, order, rows.rowText, rows.rowSpans);
	return range ? { range, order, rows } : null;
}

function spanSlice(spanRanges: Uint32Array, cellSpans: Uint32Array, row: number): Uint32Array {
	const start = spanRanges[row * 2] ?? 0;
	const end = spanRanges[row * 2 + 1] ?? start;
	return cellSpans.subarray(start * CELL_SPAN_WORDS, end * CELL_SPAN_WORDS);
}

function linkRuns(runRanges: Uint32Array, stylePairs: Uint32Array, row: number): number[] {
	const start = runRanges[row * 2] ?? 0;
	const end = runRanges[row * 2 + 1] ?? start;
	const out: number[] = [];
	let cursor = 0;
	for (let pair = start; pair < end; pair += 1) {
		const base = pair * STYLE_RUN_WORDS;
		const runEnd = stylePairs[base] ?? cursor;
		const link = stylePairs[base + STYLE_WORD_LINK] ?? 0;
		if (link !== 0) out.push(cursor, runEnd, link);
		cursor = runEnd;
	}
	return out;
}

export function snapshotTextRows(
	snapshot: TerminalSnapshot,
	filter: BlockFilter | null,
	decoder: TextDecoder,
	linkUri?: (id: number) => string | null,
): TextRows {
	const rowString = (content: Uint8Array, rows: Uint32Array, row: number): string => {
		const start = rows[row * 2] ?? 0;
		const end = rows[row * 2 + 1] ?? start;
		if (end <= start) return "";
		return decoder.decode(content.subarray(start, end));
	};
	const alt = snapshot.altScreen;
	if (alt) {
		return {
			blockIds: [ALT_BLOCK_ID],
			firstRow: () => 0,
			rowCount: () => alt.rows,
			rowText: (_id, row) => rowString(alt.content, alt.rowRanges, row),
			rowSpans: (_id, row) => spanSlice(alt.spanRanges, alt.cellSpans, row),
			rowWrapped: () => false,
			rowLinkRuns: (_id, row) => linkRuns(alt.runRanges, alt.stylePairs, row),
			linkUri: (id) => linkUri?.(id) ?? null,
		};
	}
	const blocks = applyFilter(decodeBlocks(snapshot), filter).map((block) => trimTrailingBlankRows(snapshot, block));
	const byId = new Map(blocks.map((block) => [block.id, block] as const));
	const base = snapshot.firstStableRow;
	return {
		blockIds: blocks.map((block) => block.id),
		firstRow: (id) => base + (byId.get(id)?.firstRow ?? 0),
		rowCount: (id) => byId.get(id)?.rowCount ?? 0,
		rowText: (id, row) => {
			const block = byId.get(id);
			if (!block) return "";
			const flat = row - base;
			if (flat < block.firstRow || flat >= block.firstRow + block.rowCount) return "";
			return rowString(snapshot.content, snapshot.rows, flat);
		},
		rowSpans: (id, row) => {
			const block = byId.get(id);
			if (!block) return [];
			const flat = row - base;
			if (flat < block.firstRow || flat >= block.firstRow + block.rowCount) return [];
			return spanSlice(snapshot.spanRanges, snapshot.cellSpans, flat);
		},
		rowWrapped: (id, row) => {
			const block = byId.get(id);
			if (!block) return false;
			const flat = row - base;
			if (flat < block.firstRow || flat + 1 >= block.firstRow + block.rowCount) return false;
			return snapshot.rowWrapped[flat] === 1;
		},
		rowLinkRuns: (id, row) => {
			const block = byId.get(id);
			if (!block) return [];
			const flat = row - base;
			if (flat < block.firstRow || flat >= block.firstRow + block.rowCount) return [];
			return linkRuns(snapshot.runRanges, snapshot.stylePairs, flat);
		},
		linkUri: (id) => linkUri?.(id) ?? null,
	};
}

export type RowRef = Readonly<{ element: HTMLElement; blockId: string; row: number; firstRow: number; rowCount: number }>;

export function renderedRowRefs(
	altRoot: HTMLElement | null,
	filteredBlocks: readonly BlockView[],
	blockElements: ReadonlyMap<BlockId, HTMLElement>,
	firstStableRow: number,
): RowRef[] {
	const out: RowRef[] = [];
	const alt = altRoot && !altRoot.hidden ? altRoot : null;
	if (alt) {
		const rows = alt.querySelectorAll<HTMLElement>("[data-terminal-row]");
		for (const element of rows) out.push({ element, blockId: ALT_BLOCK_ID, row: Number(element.dataset.terminalRow), firstRow: 0, rowCount: rows.length });
		return out;
	}
	const byId = new Map(filteredBlocks.map((block) => [block.id, block] as const));
	for (const [id, section] of blockElements) {
		const block = byId.get(id);
		const firstRow = firstStableRow + (block?.firstRow ?? 0);
		const rowCount = block?.rowCount ?? 0;
		for (const element of section.querySelectorAll<HTMLElement>("[data-terminal-row]")) {
			out.push({ element, blockId: id, row: Number(element.dataset.terminalRow), firstRow, rowCount });
		}
	}
	return out;
}

export function measureRow(ref: RowRef): RenderedRow {
	const rect = ref.element.getBoundingClientRect();
	return {
		element: ref.element,
		box: { blockId: ref.blockId, row: ref.row, firstRow: ref.firstRow, rowCount: ref.rowCount, left: rect.left, top: rect.top, bottom: rect.bottom, width: rect.width },
	};
}

export function renderedRows(
	altRoot: HTMLElement | null,
	filteredBlocks: readonly BlockView[],
	blockElements: ReadonlyMap<BlockId, HTMLElement>,
	firstStableRow: number,
): RenderedRow[] {
	return renderedRowRefs(altRoot, filteredBlocks, blockElements, firstStableRow).map(measureRow);
}
