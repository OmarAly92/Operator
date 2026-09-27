import { tokenize, type TokenKind } from "./highlight.js";
import { editorStyles } from "./styles.js";

export function appendRange(
	row: HTMLElement,
	text: string,
	start: number,
	end: number,
	kind: TokenKind | null,
	cursor: number,
): void {
	if (start >= end) return;
	const parent = kind ? document.createElement("span") : document.createDocumentFragment();
	if (parent instanceof HTMLElement) {
		parent.className = "terminal-editor-token";
		parent.dataset.tokenKind = kind ?? undefined;
	}
	if (cursor >= start && cursor < end) {
		parent.append(
			document.createTextNode(text.slice(start, cursor)),
			createCaret(text[cursor]),
			document.createTextNode(text.slice(cursor + 1, end)),
		);
	} else {
		parent.append(document.createTextNode(text.slice(start, end)));
	}
	row.append(parent);
}

export function createCaret(character = "\u00a0"): HTMLElement {
	const caret = document.createElement("span");
	caret.className = "terminal-editor-caret";
	caret.textContent = character;
	return caret;
}

export function ensurePackageStyleTag(): void {
	// Refresh the tag rather than skipping it when one is already there. Under
	// HMR the module re-evaluates with new CSS while the tag from the previous
	// version survives, so the new rules never land and the DOM ends up running
	// current markup against a stale stylesheet.
	const existing = document.getElementById("operator-terminal-editor-styles");
	if (existing) {
		if (existing.textContent !== editorStyles) existing.textContent = editorStyles;
		return;
	}
	const tag = document.createElement("style");
	tag.id = "operator-terminal-editor-styles";
	tag.textContent = editorStyles;
	document.head.append(tag);
}

export function renderBufferRows(text: string, lines: readonly string[], cursor: number, ghost: string | null): HTMLElement[] {
	const tokens = tokenize(text);
	let offset = 0;
	const nodes = lines.map((line) => {
		const row = document.createElement("div");
		row.className = "terminal-editor-line";
		const lineStart = offset;
		const lineEnd = lineStart + line.length;
		let position = lineStart;
		for (const token of tokens) {
			const start = Math.max(token.start, lineStart);
			const end = Math.min(token.end, lineEnd);
			if (start >= end) continue;
			appendRange(row, text, position, start, null, cursor);
			appendRange(row, text, start, end, token.kind, cursor);
			position = end;
		}
		appendRange(row, text, position, lineEnd, null, cursor);
		if (cursor === lineEnd) row.append(createCaret());
		else if (!row.hasChildNodes()) row.append(document.createTextNode(" "));
		offset = lineEnd + 1;
		return row;
	});
	if (ghost !== null && cursor === text.length) {
		const span = document.createElement("span");
		span.className = "terminal-editor-ghost";
		span.textContent = ghost;
		nodes[nodes.length - 1]?.append(span);
	}
	return nodes;
}
