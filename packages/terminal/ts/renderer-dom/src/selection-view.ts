import { CELL_SPAN_WORDS, decodeBlocks, type BlockId, type BlockView, type TerminalSnapshot } from "@operator/terminal-core";
import { applyFilter, type BlockFilter } from "./block-filter.js";
import { trimTrailingBlankRows } from "./block-rows.js";
import { fillGradient, runFill } from "./selection-fill.js";
import { rowFillSpan, type RowBox } from "./selection-geometry.js";
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

export function snapshotTextRows(snapshot: TerminalSnapshot, filter: BlockFilter | null, decoder: TextDecoder): TextRows {
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
	};
}

export function renderedRows(
	altRoot: HTMLElement | null,
	filteredBlocks: readonly BlockView[],
	blockElements: ReadonlyMap<BlockId, HTMLElement>,
	firstStableRow: number,
): RenderedRow[] {
	const out: RenderedRow[] = [];
	const push = (blockId: string, firstRow: number, rowCount: number, element: HTMLElement) => {
		const rect = element.getBoundingClientRect();
		out.push({
			element,
			box: { blockId, row: Number(element.dataset.terminalRow), firstRow, rowCount, left: rect.left, top: rect.top, bottom: rect.bottom, width: rect.width },
		});
	};
	const alt = altRoot && !altRoot.hidden ? altRoot : null;
	if (alt) {
		const rows = alt.querySelectorAll<HTMLElement>("[data-terminal-row]");
		for (const row of rows) push(ALT_BLOCK_ID, 0, rows.length, row);
		return out;
	}
	const byId = new Map(filteredBlocks.map((block) => [block.id, block] as const));
	for (const [id, section] of blockElements) {
		const block = byId.get(id);
		for (const row of section.querySelectorAll<HTMLElement>("[data-terminal-row]")) {
			push(id, firstStableRow + (block?.firstRow ?? 0), block?.rowCount ?? 0, row);
		}
	}
	return out;
}

export function selectionFills(view: SelectionView, rows: readonly RenderedRow[], cellWidth: number): Map<HTMLElement, string> {
	const fills = new Map<HTMLElement, string>();
	const colour = "var(--terminal-selection)";
	for (const { box, element } of rows) {
		const span = rowFillSpan(view.range, box, view.order, cellWidth);
		if (!span) continue;
		fills.set(element, fillGradient(span, colour));
		for (const run of element.querySelectorAll<HTMLElement>("[data-terminal-run]")) {
			if (run.style.backgroundColor === "") continue;
			const runSpan = runFill(run.getBoundingClientRect(), box.left, span);
			if (!runSpan) continue;
			fills.set(run, fillGradient(runSpan, colour));
		}
	}
	return fills;
}
