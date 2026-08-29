import {
	decodeBlocks,
	defaultStrings,
	type FontConfig,
	type TerminalCore,
	type TerminalStrings,
	type TerminalTheme,
} from "@operator/terminal-core";
import { EditorBuffer } from "./buffer.js";
import { tokenize, type TokenKind } from "./highlight.js";
import { HistoryModel } from "./history.js";
import { mapKey, type EditorCommand } from "./keymap.js";
import { ReverseSearch } from "./reverse-search.js";
import { editorStyles } from "./styles.js";

export type EditorHost = {
	send(text: string): void;
	sendRaw(data: string): void;
};

export class LineEditor {
	private readonly buffer = new EditorBuffer();
	private history = new HistoryModel();
	private historyPrefix: string | null = null;
	private readonly search = new ReverseSearch();
	private searchOpen = false;
	private strings: TerminalStrings = defaultStrings;
	private core: TerminalCore | null = null;
	private host: EditorHost | null = null;
	private root: HTMLElement | null = null;
	private unsubscribe: (() => void) | null = null;

	mount(container: HTMLElement, core: TerminalCore, host: EditorHost): void {
		this.dispose();
		ensurePackageStyleTag();
		this.core = core;
		this.host = host;
		this.history = new HistoryModel();
		this.historyPrefix = null;
		this.search.cancel();
		this.searchOpen = false;
		const root = document.createElement("div");
		root.className = "terminal-editor";
		root.tabIndex = 0;
		root.setAttribute("role", "textbox");
		root.setAttribute("aria-multiline", "true");
		root.addEventListener("keydown", this.onKeyDown);
		container.append(root);
		this.root = root;
		this.unsubscribe = core.onChange(() => {
			this.ingestHistory();
			this.render();
		});
		this.ingestHistory();
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
		this.historyPrefix = null;
		this.render();
	}

	setStrings(strings: TerminalStrings): void {
		this.strings = strings;
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
		if (this.handleSearchKey(event)) return;
		const command = mapKey(event);
		if (command) this.apply(command);
	}

	private readonly onKeyDown = (event: KeyboardEvent): void => {
		if (this.handleSearchKey(event)) {
			event.preventDefault();
			return;
		}
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
				this.historyPrefix = null;
				break;
			case "newline":
				this.buffer.insert("\n");
				this.historyPrefix = null;
				break;
			case "submit":
				host.send(this.buffer.text);
				this.buffer.clear();
				this.historyPrefix = null;
				break;
			case "delete-backward":
				this.buffer.deleteBackward();
				this.historyPrefix = null;
				break;
			case "delete-forward":
				this.buffer.deleteForward();
				this.historyPrefix = null;
				break;
			case "delete-word-backward":
				this.buffer.deleteWordBackward();
				this.historyPrefix = null;
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
			case "history": {
				this.historyPrefix ??= this.buffer.text;
				const recalled = this.history.recall(this.historyPrefix, command.direction);
				if (recalled !== null) this.buffer.setText(recalled);
				break;
			}
			case "accept-suggestion": {
				const suggestion = this.history.suggest(this.buffer.text);
				if (suggestion !== null) this.buffer.setText(suggestion);
				this.historyPrefix = null;
				break;
			}
			case "reverse-search":
				this.search.open(this.history.entries());
				this.searchOpen = true;
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
		if (cursor === this.buffer.text.length) {
			const suggestion = this.history.suggest(this.buffer.text);
			if (suggestion !== null) {
				const ghost = document.createElement("span");
				ghost.className = "terminal-editor-ghost";
				ghost.textContent = suggestion.slice(this.buffer.text.length);
				nodes[nodes.length - 1]?.append(ghost);
			}
		}
		if (this.searchOpen) {
			const state = this.search.state();
			const search = document.createElement("div");
			search.className = "terminal-editor-search";
			search.dataset.matches = String(state.total);
			const match = state.match ?? this.strings.searchNoMatches;
			search.textContent = `${this.strings.searchHistory}: ${state.query} — ${match}`;
			nodes.unshift(search);
		}
		root.replaceChildren(...nodes);
	}

	private handleSearchKey(event: KeyboardEvent): boolean {
		if (!this.searchOpen) return false;
		if (this.core?.lineEditorState() !== "owned") {
			this.search.cancel();
			this.searchOpen = false;
			return false;
		}
		if (event.ctrlKey && !event.altKey && !event.metaKey && event.key.toLowerCase() === "r") {
			this.search.next();
		} else if (event.key === "Backspace") {
			this.search.backspace();
		} else if (event.key === "ArrowDown") {
			this.search.next();
		} else if (event.key === "ArrowUp") {
			this.search.previous();
		} else if (event.key === "Enter") {
			const match = this.search.accept();
			if (match !== null) this.buffer.setText(match);
			this.searchOpen = false;
		} else if (event.key === "Escape") {
			this.search.cancel();
			this.searchOpen = false;
		} else if (!event.ctrlKey && !event.altKey && !event.metaKey && event.key.length === 1) {
			this.search.type(event.key);
		} else {
			return true;
		}
		this.render();
		return true;
	}

	private ingestHistory(): void {
		const core = this.core;
		if (!core) return;
		this.history.ingest(
			decodeBlocks(core.snapshot())
				.map((block) => block.command)
				.filter((command) => command.length > 0),
		);
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
