// Warp's BlockPadding, in grid cells rather than pixels
// (app/src/settings/mod.rs, TerminalSpacing::normal), plus the terminal view's
// own horizontal inset (app/src/terminal/view.rs, PADDING_LEFT = 16).
//
// These are the numbers the stylesheet uses. The virtualiser has to reserve the
// same space when it estimates a block's height, or its estimate drifts from
// what it actually renders and the scroll position walks away from the content.
export const BLOCK_PADDING_TOP_LINES = 1.1;
export const BLOCK_PADDING_BOTTOM_LINES = 1;
export const BLOCK_COMMAND_GAP_LINES = 0.5;
export const BLOCK_PADDING_X_PX = 16;

export function blockPaddingY(rowHeight: number): number {
	return (BLOCK_PADDING_TOP_LINES + BLOCK_PADDING_BOTTOM_LINES) * rowHeight;
}
