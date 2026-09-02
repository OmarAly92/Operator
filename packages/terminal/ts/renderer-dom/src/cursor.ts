export const CLASS_CURSOR = "terminal-cursor";
export const CURSOR_ATTR = "data-terminal-cursor-cell";

const LINE_EDITOR_OWNED = 1;

export type CursorSnapshot = Readonly<{
	cursorRow: number;
	cursorColumn: number;
	cursorVisible: boolean;
	lineEditorState: number;
	altScreen: unknown;
}>;

export type CursorPlacement = Readonly<{ row: number; column: number }>;

// Where the block list should draw the terminal's own cursor, or null when it
// must not draw one at all.
//
// The line editor draws its own caret while it owns the line, so drawing this
// one too leaves two carets in the pane. Everything else -- a child process
// holding the line, a shell with no integration -- has no other caret, and
// without this the pane shows none at all.
export function primaryCursorPlacement(snapshot: CursorSnapshot): CursorPlacement | null {
	if (snapshot.altScreen) return null;
	if (!snapshot.cursorVisible) return null;
	if (snapshot.lineEditorState === LINE_EDITOR_OWNED) return null;
	return { row: snapshot.cursorRow, column: snapshot.cursorColumn };
}

export function createCursorElement(column: number, cellWidth: number): HTMLElement {
	const cursor = document.createElement("span");
	cursor.className = CLASS_CURSOR;
	cursor.setAttribute(CURSOR_ATTR, "");
	cursor.dataset.column = String(column);
	cursor.style.width = `${cellWidth}px`;
	cursor.style.transform = `translateX(${column * cellWidth}px)`;
	return cursor;
}
