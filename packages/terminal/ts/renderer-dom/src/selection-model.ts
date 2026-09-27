import { wordCellRange } from "./words.js";

export type SelectionKind = "simple" | "word" | "line" | "rectangle";
export type SelectionSide = "left" | "right";
export type SelectionPoint = Readonly<{ blockId: string; row: number; column: number; side: SelectionSide }>;
export type SelectionState = Readonly<{ head: SelectionPoint; tail: SelectionPoint; kind: SelectionKind }>;
export type Boundary = Readonly<{ blockId: string; row: number; cell: number }>;
export type SelectionRange = Readonly<{ start: Boundary; end: Boundary; rectangle?: boolean }>;
export type RowText = (blockId: string, row: number) => string;
export type RowSpans = (blockId: string, row: number) => ArrayLike<number>;
export type RowIndent = (blockId: string, row: number) => number;
export type BlockOrder = (blockId: string) => number;

export const ROW_END = Number.POSITIVE_INFINITY;

export function compareBoundary(a: Boundary, b: Boundary, order: BlockOrder): number {
	const blocks = order(a.blockId) - order(b.blockId);
	if (blocks !== 0) return blocks;
	if (a.row !== b.row) return a.row - b.row;
	return a.cell - b.cell;
}

function boundaryOf(point: SelectionPoint): Boundary {
	return { blockId: point.blockId, row: point.row, cell: point.column + (point.side === "right" ? 1 : 0) };
}

function expand(point: SelectionPoint, kind: SelectionKind, rowText: RowText, rowSpans: RowSpans, rowIndent: RowIndent): [Boundary, Boundary] {
	if (kind === "line") {
		return [
			{ blockId: point.blockId, row: point.row, cell: 0 },
			{ blockId: point.blockId, row: point.row, cell: ROW_END },
		];
	}
	if (kind === "word") {
		const indent = rowIndent(point.blockId, point.row);
		const word = wordCellRange(rowText(point.blockId, point.row), rowSpans(point.blockId, point.row), Math.max(point.column - indent, 0));
		return [
			{ blockId: point.blockId, row: point.row, cell: word.start + indent },
			{ blockId: point.blockId, row: point.row, cell: word.end + indent },
		];
	}
	const boundary = boundaryOf(point);
	return [boundary, boundary];
}

function rectangleRange(state: SelectionState, order: BlockOrder): SelectionRange | null {
	const head = boundaryOf(state.head);
	const tail = boundaryOf(state.tail);
	const left = Math.min(head.cell, tail.cell);
	const right = Math.max(head.cell, tail.cell);
	if (right <= left) return null;
	const headFirst = compareBoundary({ ...head, cell: 0 }, { ...tail, cell: 0 }, order) <= 0;
	const top = headFirst ? head : tail;
	const bottom = headFirst ? tail : head;
	return { start: { ...top, cell: left }, end: { ...bottom, cell: right }, rectangle: true };
}

export function resolveRange(state: SelectionState, order: BlockOrder, rowText: RowText, rowSpans: RowSpans = () => [], rowIndent: RowIndent = () => 0): SelectionRange | null {
	if (state.kind === "rectangle") return rectangleRange(state, order);
	const [headStart, headEnd] = expand(state.head, state.kind, rowText, rowSpans, rowIndent);
	const [tailStart, tailEnd] = expand(state.tail, state.kind, rowText, rowSpans, rowIndent);
	const start = compareBoundary(headStart, tailStart, order) <= 0 ? headStart : tailStart;
	const end = compareBoundary(headEnd, tailEnd, order) >= 0 ? headEnd : tailEnd;
	if (compareBoundary(start, end, order) >= 0) return null;
	return { start, end };
}
