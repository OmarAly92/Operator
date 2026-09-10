import { wordCellRange } from "./words.js";

export type SelectionKind = "simple" | "word" | "line";
export type SelectionSide = "left" | "right";
export type SelectionPoint = Readonly<{ blockId: string; row: number; column: number; side: SelectionSide }>;
export type SelectionState = Readonly<{ head: SelectionPoint; tail: SelectionPoint; kind: SelectionKind }>;
export type Boundary = Readonly<{ blockId: string; row: number; cell: number }>;
export type SelectionRange = Readonly<{ start: Boundary; end: Boundary }>;
export type RowText = (blockId: string, row: number) => string;
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

function expand(point: SelectionPoint, kind: SelectionKind, rowText: RowText): [Boundary, Boundary] {
	if (kind === "line") {
		return [
			{ blockId: point.blockId, row: point.row, cell: 0 },
			{ blockId: point.blockId, row: point.row, cell: ROW_END },
		];
	}
	if (kind === "word") {
		const word = wordCellRange(rowText(point.blockId, point.row), point.column);
		return [
			{ blockId: point.blockId, row: point.row, cell: word.start },
			{ blockId: point.blockId, row: point.row, cell: word.end },
		];
	}
	const boundary = boundaryOf(point);
	return [boundary, boundary];
}

export function resolveRange(state: SelectionState, order: BlockOrder, rowText: RowText): SelectionRange | null {
	const [headStart, headEnd] = expand(state.head, state.kind, rowText);
	const [tailStart, tailEnd] = expand(state.tail, state.kind, rowText);
	const start = compareBoundary(headStart, tailStart, order) <= 0 ? headStart : tailStart;
	const end = compareBoundary(headEnd, tailEnd, order) >= 0 ? headEnd : tailEnd;
	if (compareBoundary(start, end, order) >= 0) return null;
	return { start, end };
}
