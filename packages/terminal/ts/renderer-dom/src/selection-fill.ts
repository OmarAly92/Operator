export type FillSpan = Readonly<{ left: number; right: number }>;

export type RowFill = Readonly<{ row: HTMLElement; left: number; right: number }>;

type Box = Readonly<{ left: number; right: number }>;

export type RowPosition = "only" | "first" | "middle" | "last";

// Warp paints a selected row as one rectangle the full height of the row, and
// only the ends of the selection stop short: the first row runs from the
// starting column to the end of the row and the last row from the row's start
// to the cursor (grid_renderer.rs calculate_background_bounds). The browser
// instead paints each row's glyph box, which is narrower than the row and
// shorter than the line, so a multi-row selection reads as a ragged staircase
// with gaps between the bands. These spans are what the renderer paints instead.
export function rowFill(row: Box, painted: Box | null, position: RowPosition): FillSpan | null {
	const startsHere = position === "only" || position === "first";
	const endsHere = position === "only" || position === "last";
	// An end of the selection that painted nothing is a row the drag stopped on
	// without covering; only a blank row *inside* the selection is filled whole.
	if (!painted && (startsHere || endsHere)) return null;
	const left = startsHere && painted ? Math.max(painted.left, row.left) : row.left;
	const right = endsHere && painted ? Math.min(painted.right, row.right) : row.right;
	if (right - left <= 0.5) return null;
	return { left: left - row.left, right: right - row.left };
}

function positionOf(index: number, count: number): RowPosition {
	if (count === 1) return "only";
	if (index === 0) return "first";
	return index === count - 1 ? "last" : "middle";
}

function paintedSpan(rects: readonly DOMRect[], top: number, bottom: number): Box | null {
	let left = Number.POSITIVE_INFINITY;
	let right = Number.NEGATIVE_INFINITY;
	const middle = (top + bottom) / 2;
	for (const rect of rects) {
		if (rect.top > middle || rect.bottom < middle) continue;
		left = Math.min(left, rect.left);
		right = Math.max(right, rect.right);
	}
	return right > left ? { left, right } : null;
}

export function selectionRowFills(root: HTMLElement, selection: Selection | null): RowFill[] {
	if (!selection || selection.isCollapsed || selection.rangeCount === 0) return [];
	const range = selection.getRangeAt(0);
	const rows = [...root.querySelectorAll<HTMLElement>("[data-terminal-row]")].filter((row) =>
		range.intersectsNode(row),
	);
	const painted = [...range.getClientRects()];
	const fills: RowFill[] = [];
	for (const [index, row] of rows.entries()) {
		const box = row.getBoundingClientRect();
		const span = rowFill(box, paintedSpan(painted, box.top, box.bottom), positionOf(index, rows.length));
		if (span) fills.push({ row, left: span.left, right: span.right });
	}
	return fills;
}
