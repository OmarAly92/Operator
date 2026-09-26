import type { TokenKind } from "./highlight.js";
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
