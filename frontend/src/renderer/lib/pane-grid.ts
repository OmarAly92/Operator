// The grid of the terminal pane most recently measured in this window. A
// session or shell created from this window will be shown in a pane of the
// same size, so the daemon can spawn its pty at that grid and skip the
// SIGWINCH -- and the agent's full repaint -- that resizing an 80x24 pty on
// first attach otherwise costs. Null until a pane has reported a size.

export type PaneGrid = { cols: number; rows: number };

let lastGrid: PaneGrid | null = null;

export function rememberPaneGrid(cols: number, rows: number): void {
	if (!Number.isInteger(cols) || !Number.isInteger(rows) || cols <= 0 || rows <= 0) return;
	lastGrid = { cols, rows };
}

export function lastPaneGrid(): PaneGrid | null {
	return lastGrid;
}

/** Spread into a create request body; empty when no pane has been measured. */
export function paneGridBody(): Partial<PaneGrid> {
	return lastGrid ? { cols: lastGrid.cols, rows: lastGrid.rows } : {};
}

export function resetPaneGridForTests(): void {
	lastGrid = null;
}
