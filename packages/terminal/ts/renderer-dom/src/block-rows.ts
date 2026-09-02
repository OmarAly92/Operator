import type { BlockView } from "@operator/terminal-core";

type RowSpans = Readonly<{ rows: Uint32Array; content: Uint8Array }>;

const SPACE = 0x20;

function rowIsBlank(snapshot: RowSpans, row: number): boolean {
	const start = snapshot.rows[row * 2] ?? 0;
	const end = snapshot.rows[row * 2 + 1] ?? 0;
	for (let i = start; i < end; i += 1) {
		if (snapshot.content[i] !== SPACE) return false;
	}
	return true;
}

// An agent that repaints in place leaves the rows it erased behind: the block
// keeps its full height while only the first few rows still have text. That
// dead height is what pushes a short transcript off the bottom of the pane and
// fills the rest with blank rows, so a block ends at its last row with content.
// Warp does the same -- a block's output stops at its last non-empty line.
//
// The scan walks back from the end and stops at the first row with content, so
// it costs one comparison for a block that does not end in blanks.
export function trimTrailingBlankRows(snapshot: RowSpans, block: BlockView): BlockView {
	let rowCount = block.rowCount;
	while (rowCount > 1 && rowIsBlank(snapshot, block.firstRow + rowCount - 1)) {
		rowCount -= 1;
	}
	if (rowCount === block.rowCount) return block;
	return { ...block, rowCount };
}
