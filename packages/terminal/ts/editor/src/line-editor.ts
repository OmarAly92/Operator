import type { FontConfig, TerminalCore, TerminalTheme } from "@operator/terminal-core";
import { EditorBuffer } from "./buffer.js";
import { tokenize, type TokenKind } from "./highlight.js";
import { mapKey, type EditorCommand } from "./keymap.js";
import { editorStyles } from "./styles.js";

export type EditorHost = {
	send(text: string): void;
	sendRaw(data: string): void;
};

export class LineEditor {
	private readonly buffer = new EditorBuffer();
	private core: TerminalCore | null = null;
	private host: EditorHost | null = null;
	private root: HTMLElement | null = null;
	private unsubscribe: (() => void) | null = null;

	mount(container: HTMLElement, core: TerminalCore, host: EditorHost): void {
		this.dispose();
		ensurePackageStyleTag();
		this.core = core;
		this.host = host;
		const root = document.createElement("div");
		root.className = "terminal-editor";
		root.tabIndex = 0;
		root.setAttribute("role", "textbox");
		root.setAttribute("aria-multiline", "true");
		root.addEventListener("keydown", this.onKeyDown);
		container.append(root);
		this.root = root;
		this.unsubscribe = core.onChange(() => this.render());
		this.render();
	}

	setTheme(theme: TerminalTheme): void {
		const style = this.root?.style;
		if (!style) return;
		style.setProperty("--terminal-foreground", theme.foreground);
		style.setProperty("--terminal-background", theme.background);
		style.setProperty("--terminal-cursor", theme.cursor);
		style.setProperty("--terminal-selection", theme.selection);
		for (const [index, color] of theme.ansi.entries()) {
			style.setProperty(`--terminal-ansi-${index}`, color);
		}
	}

	setFont(font: FontConfig): void {
		const style = this.root?.style;
		if (!style) return;
		style.setProperty("--terminal-font-family", font.family);
		style.setProperty("--terminal-font-size", `${font.sizePx}px`);
		style.setProperty("--terminal-line-height", `${font.lineHeight}px`);
		style.setProperty("--terminal-font-weight", String(font.weight));
		style.setProperty("--terminal-letter-spacing", `${font.letterSpacingPx}px`);
		style.setProperty("--terminal-ligatures", font.ligatures ? "normal" : "none");
	}

	setText(text: string): void {
		this.buffer.setText(text);
		this.render();
	}

	focus(): void {
		this.root?.focus();
	}

	dispose(): void {
		this.unsubscribe?.();
		this.unsubscribe = null;
		if (this.root) {
			this.root.removeEventListener("keydown", this.onKeyDown);
			this.root.remove();
		}
		this.root = null;
		this.core = null;
		this.host = null;
	}

	handleKey(event: KeyboardEvent): void {
		const command = mapKey(event);
		if (command) this.apply(command);
	}

	private readonly onKeyDown = (event: KeyboardEvent): void => {
		const command = mapKey(event);
		if (!command) return;
		event.preventDefault();
		this.apply(command);
	};

	private apply(command: EditorCommand): void {
		const host = this.host;
		if (!host) return;
		if (command.kind === "passthrough") {
			host.sendRaw(command.data);
			return;
		}
		if (this.core?.lineEditorState() !== "owned") {
			host.sendRaw(passthroughFor(command));
			return;
		}
		switch (command.kind) {
			case "insert":
				this.buffer.insert(command.text);
				break;
			case "newline":
				this.buffer.insert("\n");
				break;
			case "submit":
				host.send(this.buffer.text);
				this.buffer.clear();
				break;
			case "delete-backward":
				this.buffer.deleteBackward();
				break;
			case "delete-forward":
				this.buffer.deleteForward();
				break;
			case "delete-word-backward":
				this.buffer.deleteWordBackward();
				break;
			case "move":
				this.buffer.moveBy(command.delta);
				break;
			case "move-word":
				this.buffer.moveWord(command.direction);
				break;
			case "move-line":
				this.buffer.moveLine(command.direction);
				break;
			case "home":
				this.buffer.moveHome();
				break;
			case "end":
				this.buffer.moveEnd();
				break;
			case "history":
			case "accept-suggestion":
			case "reverse-search":
				break;
		}
		this.render();
	}

	private render(): void {
		const root = this.root;
		if (!root) return;
		const state = this.core?.lineEditorState() ?? "unknown";
		root.dataset.ownership = state;
		root.setAttribute("aria-readonly", String(state !== "owned"));
		const cursor = this.buffer.cursor;
		const lines = this.buffer.lines();
		const tokens = tokenize(this.buffer.text);
		let offset = 0;
		const nodes = lines.map((text) => {
			const row = document.createElement("div");
			row.className = "terminal-editor-line";
			const lineStart = offset;
			const lineEnd = lineStart + text.length;
			let position = lineStart;
			for (const token of tokens) {
				const start = Math.max(token.start, lineStart);
				const end = Math.min(token.end, lineEnd);
				if (start >= end) continue;
				appendRange(row, this.buffer.text, position, start, null, cursor);
				appendRange(row, this.buffer.text, start, end, token.kind, cursor);
				position = end;
			}
			appendRange(row, this.buffer.text, position, lineEnd, null, cursor);
			if (cursor === lineEnd) row.append(createCaret());
			else if (!row.hasChildNodes()) row.append(document.createTextNode("\u00a0"));
			offset = lineEnd + 1;
			return row;
		});
		root.replaceChildren(...nodes);
	}
}

function appendRange(
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

function createCaret(character = "\u00a0"): HTMLElement {
	const caret = document.createElement("span");
	caret.className = "terminal-editor-caret";
	caret.textContent = character;
	return caret;
}

function passthroughFor(command: EditorCommand): string {
	switch (command.kind) {
		case "insert":
			return command.text;
		case "submit":
			return "\r";
		case "newline":
			return "\n";
		case "delete-backward":
			return "\x7f";
		case "delete-forward":
			return "\x1b[3~";
		case "move":
			return command.delta < 0 ? "\x1b[D" : "\x1b[C";
		case "move-word":
			return command.direction < 0 ? "\x1bb" : "\x1bf";
		case "move-line":
		case "history":
			return command.direction < 0 ? "\x1b[A" : "\x1b[B";
		case "home":
			return "\x01";
		case "end":
			return "\x05";
		case "delete-word-backward":
			return "\x17";
		case "accept-suggestion":
			return "\t";
		case "reverse-search":
			return "\x12";
		case "passthrough":
			return command.data;
	}
}

function ensurePackageStyleTag(): void {
	if (document.getElementById("operator-terminal-editor-styles")) return;
	const tag = document.createElement("style");
	tag.id = "operator-terminal-editor-styles";
	tag.textContent = editorStyles;
	document.head.append(tag);
}
