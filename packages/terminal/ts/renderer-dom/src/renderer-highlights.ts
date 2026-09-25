import { HighlightPainter } from "./highlight-painter.js";
import { SELECTION_COLOUR, type Highlight } from "./highlights.js";
import { compileMarks, markHighlights, MarkCache, visibleLogicalLines, type CompiledMark, type MarkRule } from "./marks.js";
import { RendererSelection } from "./renderer-selection.js";
import { ROW_END, type BlockOrder } from "./selection-model.js";
import type { TextRows } from "./selection-text.js";
import { ALT_BLOCK_ID, type RowRef } from "./selection-view.js";

export type { MarkRule } from "./marks.js";

export type FindHighlights = Readonly<{ rows: ReadonlySet<number>; current: Readonly<{ row: number; endRow: number }> | null }>;

export type RendererHighlightsDeps = Readonly<{
	hasCore: () => boolean;
	painting: () => boolean;
	textRows: () => TextRows;
	rowRefs: () => RowRef[];
	cellWidth: () => number;
}>;

export class RendererHighlights {
	readonly selection: RendererSelection;
	private find: FindHighlights | null = null;
	private marks: CompiledMark[] = [];
	private readonly markCache = new MarkCache();
	private readonly painter = new HighlightPainter();

	constructor(private readonly deps: RendererHighlightsDeps) {
		this.selection = new RendererSelection({ hasCore: deps.hasCore, textRows: deps.textRows, repaint: () => this.paint() });
	}

	setFind(find: FindHighlights | null): void {
		this.find = find;
		this.paint();
	}

	setMarks(rules: readonly MarkRule[]): void {
		this.marks = compileMarks(rules);
		this.markCache.clear();
		this.paint();
	}

	paint(): void {
		if (!this.deps.painting()) return;
		const selection = this.selection.view();
		const active = selection !== null || this.find !== null || this.marks.length > 0;
		if (!active && this.painter.idle()) return;
		const rows = this.deps.rowRefs();
		const textRows = selection?.rows ?? (this.deps.hasCore() ? this.deps.textRows() : null);
		const highlights: Highlight[] = [];
		if (selection) highlights.push({ kind: "selection", range: selection.range, colour: SELECTION_COLOUR, rank: 0 });
		this.collectFind(rows, highlights);
		if (textRows && this.marks.length > 0) highlights.push(...markHighlights(visibleLogicalLines(textRows, rows), this.marks, this.markCache));
		this.painter.paint(rows, highlights, selection?.order ?? blockOrder(textRows), this.deps.cellWidth());
	}

	reset(): void {
		this.selection.reset();
		this.find = null;
		this.marks = [];
		this.markCache.clear();
		this.painter.reset();
	}

	private collectFind(rows: readonly RowRef[], out: Highlight[]): void {
		const find = this.find;
		if (!find) return;
		for (const box of rows) {
			if (box.blockId === ALT_BLOCK_ID) continue;
			const range = { start: { blockId: box.blockId, row: box.row, cell: 0 }, end: { blockId: box.blockId, row: box.row, cell: ROW_END } };
			if (find.rows.has(box.row)) out.push({ kind: "find", range, colour: SELECTION_COLOUR, rank: 0 });
			if (find.current && box.row >= find.current.row && box.row <= find.current.endRow) out.push({ kind: "find-current", range, colour: SELECTION_COLOUR, rank: 0 });
		}
	}
}

function blockOrder(rows: TextRows | null): BlockOrder {
	const index = new Map((rows?.blockIds ?? []).map((id, position) => [id, position] as const));
	return (blockId) => index.get(blockId) ?? -1;
}
