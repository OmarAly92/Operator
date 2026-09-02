import {
	decodeBlocks,
	defaultStrings,
	type FontConfig,
	type TerminalCore,
	type TerminalStrings,
	type TerminalTheme,
} from "@operator/terminal-core";
import { EditorBuffer } from "./buffer.js";
import { CompletionsDropdown } from "./completions-dropdown.js";
import { tokenize, type TokenKind } from "./highlight.js";
import { HistoryModel } from "./history.js";
import { encodeKey } from "./encode-key.js";
import { mapKey, type EditorCommand } from "./keymap.js";
import { renderPromptRow } from "./prompt-row.js";
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
	private readonly dropdown = new CompletionsDropdown();
	private dropdownOpen = false;
	private strings: TerminalStrings = defaultStrings;
	private promptCwd = "";
	private promptBranch = "";
	private promptExitCode: number | null = null;
	private promptDurationMs: number | null = null;
	private core: TerminalCore | null = null;
	private host: EditorHost | null = null;
	private root: HTMLElement | null = null;
	private unsubscribe: (() => void) | null = null;
	private unsubscribeCompletions: (() => void) | null = null;

	mount(container: HTMLElement, core: TerminalCore, host: EditorHost): void {
		this.dispose();
		ensurePackageStyleTag();
		this.core = core;
		this.host = host;
		this.history = new HistoryModel();
		this.historyPrefix = null;
		this.promptCwd = "";
		this.promptBranch = "";
		this.promptExitCode = null;
		this.promptDurationMs = null;
		this.search.cancel();
		this.searchOpen = false;
		this.dropdownOpen = false;
		this.dropdown.close();
		const root = document.createElement("div");
		root.className = "terminal-editor";
		root.tabIndex = 0;
		root.setAttribute("role", "textbox");
		root.setAttribute("aria-multiline", "true");
		root.addEventListener("keydown", this.onKeyDown);
		container.append(root);
		this.root = root;
		this.dropdown.mount(root);
		this.unsubscribe = core.onChange(() => {
			this.ingestHistory();
			this.render();
		});
		this.unsubscribeCompletions = core.onCompletions((result) => {
			this.dropdown.setResult(result);
			this.dropdownOpen = this.dropdown.isOpen();
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
		this.unsubscribeCompletions?.();
		this.unsubscribeCompletions = null;
		this.dropdown.dispose();
		this.dropdownOpen = false;
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
		if (this.dropdown.isOpen() && this.handleDropdownKey(event)) return;
		if (this.passthrough(event) !== null) return;
		const command = mapKey(event);
		if (command) this.apply(command);
	}

	private readonly onKeyDown = (event: KeyboardEvent): void => {
		if (this.handleSearchKey(event)) {
			event.preventDefault();
			return;
		}
		if (this.dropdown.isOpen() && this.handleDropdownKey(event)) {
			event.preventDefault();
			return;
		}
		const sent = this.passthrough(event);
		if (sent !== null) {
			if (sent) event.preventDefault();
			return;
		}
		const command = mapKey(event);
		if (!command) return;
		event.preventDefault();
		this.apply(command);
	};

	// Returns null when the editor owns the line and should edit locally, and
	// otherwise the bytes handed to the child (empty when the key encodes to
	// nothing, which still counts as handled).
	private passthrough(event: KeyboardEvent): string | null {
		const core = this.core;
		if (!core || core.lineEditorState() === "owned") return null;
		const data = encodeKey(event, core.snapshot().applicationCursorKeys);
		if (data === null) return "";
		this.host?.sendRaw(data);
		return data;
	}

	private handleDropdownKey(event: KeyboardEvent): boolean {
		if (this.dropdown.handleKey(event)) {
			if (!this.dropdown.isOpen()) {
				this.dropdownOpen = false;
				this.core?.cancelCompletions();
				this.render();
			}
			return true;
		}
		return false;
	}

	private apply(command: EditorCommand): void {
		const host = this.host;
		if (!host) return;
		if (command.kind === "passthrough") {
			host.sendRaw(command.data);
			return;
		}
		const wasDropdownOpen = this.dropdownOpen;
		switch (command.kind) {
			case "insert":
				this.buffer.insert(command.text);
				this.historyPrefix = null;
				this.cancelDropdownIfOpen();
				break;
			case "newline":
				this.buffer.insert("\n");
				this.historyPrefix = null;
				this.cancelDropdownIfOpen();
				break;
			case "submit":
				if (wasDropdownOpen) {
					this.applySelectedCompletion();
					this.historyPrefix = null;
					this.render();
					return;
				}
				host.send(this.buffer.text);
				this.buffer.clear();
				this.historyPrefix = null;
				this.cancelDropdownIfOpen();
				break;
			case "delete-backward":
				this.buffer.deleteBackward();
				this.historyPrefix = null;
				this.cancelDropdownIfOpen();
				break;
			case "delete-forward":
				this.buffer.deleteForward();
				this.historyPrefix = null;
				this.cancelDropdownIfOpen();
				break;
			case "delete-word-backward":
				this.buffer.deleteWordBackward();
				this.historyPrefix = null;
				this.cancelDropdownIfOpen();
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
				if (this.buffer.cursor === this.buffer.text.length) {
					const suggestion = this.history.suggest(this.buffer.text);
					if (suggestion !== null) this.buffer.setText(suggestion);
					this.historyPrefix = null;
				} else {
					this.buffer.moveBy(1);
				}
				break;
			}
			case "complete":
				if (wasDropdownOpen) {
					this.applySelectedCompletion();
				} else {
					this.core?.requestCompletions(this.buffer.text, this.buffer.cursor);
				}
				break;
			case "reverse-search":
				this.search.open(this.history.entries());
				this.searchOpen = true;
				break;
		}
		this.render();
	}

	private cancelDropdownIfOpen(): void {
		if (!this.dropdownOpen) return;
		this.dropdownOpen = false;
		this.dropdown.close();
		this.core?.cancelCompletions();
	}

	private applySelectedCompletion(): void {
		const selected = this.dropdown.selected();
		const span = this.dropdown.currentResult()?.span;
		this.dropdownOpen = false;
		this.dropdown.close();
		this.core?.cancelCompletions();
		if (selected === null || span === undefined) return;
		const before = this.buffer.text.slice(0, span.start);
		const after = this.buffer.text.slice(span.end);
		const insertion = selected.value;
		const cursor = before.length + insertion.length;
		this.buffer.setText(before + insertion + after, cursor);
		this.historyPrefix = null;
		if (insertion.endsWith("/")) {
			this.core?.requestCompletions(this.buffer.text, this.buffer.cursor);
		}
	}

	private render(): void {
		const root = this.root;
		if (!root) return;
		const state = this.core?.lineEditorState() ?? "unknown";
		root.dataset.ownership = state;
		root.setAttribute("aria-readonly", String(state !== "owned"));
		// The child draws its own prompt and cursor while it owns the line. Drawing
		// ours underneath it leaves a second, dead caret at the bottom of the pane
		// that does not track what the user is typing. The root stays in the DOM
		// and focusable -- it is still what receives the keys.
		if (state !== "owned") {
			root.replaceChildren();
			return;
		}
		const cursor = this.buffer.cursor;
		const lines = this.buffer.lines();
		const tokens = tokenize(this.buffer.text);
		let offset = 0;
		const nodes: HTMLElement[] = lines.map((text) => {
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
		nodes.unshift(
			renderPromptRow(
				{
					cwd: this.promptCwd,
					gitBranch: this.promptBranch,
					lastExitCode: this.promptExitCode,
					lastDurationMs: this.promptDurationMs,
					state,
				},
				this.strings,
			),
		);
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
		const blocks = decodeBlocks(core.snapshot());
		this.history.ingest(blocks.map((block) => block.command).filter((command) => command.length > 0));
		const newest = blocks.at(-1);
		this.promptCwd = newest?.cwd ?? "";
		this.promptBranch = newest?.gitBranch ?? "";
		this.promptExitCode = newest?.exitCode ?? null;
		this.promptDurationMs = newest?.durationMs ?? null;
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

function ensurePackageStyleTag(): void {
	if (document.getElementById("operator-terminal-editor-styles")) return;
	const tag = document.createElement("style");
	tag.id = "operator-terminal-editor-styles";
	tag.textContent = editorStyles;
	document.head.append(tag);
}
