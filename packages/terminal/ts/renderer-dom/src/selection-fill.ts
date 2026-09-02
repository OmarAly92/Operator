export type FillRect = Readonly<{ top: number; left: number; width: number; height: number }>;

type Box = Readonly<{ top: number; left: number; right: number; height: number }>;

// Warp fills a selected row from where the selection starts to the *end of the
// row*, and only the last row of a selection stops at the cursor
// (grid_renderer.rs calculate_background_bounds: the first and middle rows run
// to max_columns). The browser stops every row at its last glyph, so a
// selection reads as a ragged staircase where Warp's is a solid column. These
// are the rectangles that make up the difference: they cover the empty space to
// the right of the text and never the text itself.
export function fillRect(row: Box, selectionRight: number, root: { left: number; top: number }): FillRect | null {
	const from = Math.max(selectionRight, row.left);
	const width = row.right - from;
	if (width <= 0.5) return null;
	return { top: row.top - root.top, left: from - root.left, width, height: row.height };
}

export function selectionFillRects(root: HTMLElement, selection: Selection | null): FillRect[] {
	if (!selection || selection.isCollapsed || selection.rangeCount === 0) return [];
	const range = selection.getRangeAt(0);
	const rows = [...root.querySelectorAll<HTMLElement>("[data-terminal-row]")].filter((row) =>
		range.intersectsNode(row),
	);
	// A selection inside one row ends where the cursor left it, exactly as the
	// browser already draws it.
	if (rows.length < 2) return [];
	const rootBox = root.getBoundingClientRect();
	const painted = [...range.getClientRects()];
	const rects: FillRect[] = [];
	for (const row of rows.slice(0, -1)) {
		const rowBox = row.getBoundingClientRect();
		const middle = rowBox.top + rowBox.height / 2;
		let right = rowBox.left;
		for (const rect of painted) {
			if (rect.top <= middle && rect.bottom >= middle) right = Math.max(right, rect.right);
		}
		const fill = fillRect(
			{ top: rowBox.top, left: rowBox.left, right: rowBox.right, height: rowBox.height },
			right,
			rootBox,
		);
		if (fill) rects.push(fill);
	}
	return rects;
}
