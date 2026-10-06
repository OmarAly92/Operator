import type { FillSpan } from "./selection-fill.js";
import { rowFillSpan, type RowBox } from "./selection-geometry.js";
import type { BlockOrder, SelectionRange } from "./selection-model.js";

export type HighlightKind = "selection" | "find-current" | "find" | "mark";

export type Highlight = Readonly<{ kind: HighlightKind; range: SelectionRange; colour: string; rank: number }>;

export type FillLayer = Readonly<{ span: FillSpan; colour: string }>;

export type RowPaint = Readonly<{ layers: readonly FillLayer[]; findMatch: boolean; findFill: boolean; findCurrent: boolean }>;

export const HIGHLIGHT_PRIORITY: Readonly<Record<HighlightKind, number>> = { selection: 3, "find-current": 2, find: 1, mark: 0 };

export const SELECTION_COLOUR = "var(--terminal-selection)";

export const EMPTY_ROW_PAINT: RowPaint = { layers: [], findMatch: false, findFill: false, findCurrent: false };

export function compareHighlights(a: Highlight, b: Highlight): number {
	return HIGHLIGHT_PRIORITY[b.kind] - HIGHLIGHT_PRIORITY[a.kind] || a.rank - b.rank;
}

export function rowPaint(highlights: readonly Highlight[], box: RowBox, order: BlockOrder, cellWidth: number): RowPaint {
	const hits: { highlight: Highlight; span: FillSpan }[] = [];
	for (const highlight of highlights) {
		if (highlight.kind === "find" || highlight.kind === "find-current") {
			if (highlight.range.start.blockId === box.blockId && highlight.range.start.row === box.row) hits.push({ highlight, span: { left: 0, right: box.width } });
			continue;
		}
		const span = rowFillSpan(highlight.range, box, order, cellWidth);
		if (span) hits.push({ highlight, span });
	}
	if (hits.length === 0) return EMPTY_ROW_PAINT;
	hits.sort((a, b) => compareHighlights(a.highlight, b.highlight));
	const marked = hits.some(({ highlight }) => highlight.kind === "mark");
	const layers: FillLayer[] = [];
	let findMatch = false;
	let findCurrent = false;
	for (const { highlight, span } of hits) {
		if (highlight.kind === "find-current") {
			findCurrent = true;
			continue;
		}
		if (highlight.kind === "find") {
			if (findMatch) continue;
			findMatch = true;
			if (!marked) continue;
		}
		layers.push({ span, colour: highlight.colour });
	}
	return { layers, findMatch, findFill: findMatch && !marked, findCurrent };
}
