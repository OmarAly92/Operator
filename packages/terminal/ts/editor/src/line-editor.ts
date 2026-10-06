import {
	createCompositionTarget,
	decodeBlocks,
	defaultStrings,
	type CompositionAnchor,
	type CompositionTarget,
	type FontConfig,
	type TerminalCore,
	type TerminalStrings,
	type TerminalTheme,
} from "@operator/terminal-core";
import { EditorBuffer } from "./buffer.js";
import { CompletionsDropdown } from "./completions-dropdown.js";
import { EditorHistory } from "./editor-history.js";
import type { CommandHistorySource } from "./history.js";
import { encodeKey } from "./encode-key.js";
import { clipboardHasImage, deliverPaste, planPaste, type PasteConfirm } from "./paste.js";
import { mapKey, type EditorCommand } from "./keymap.js";
import { renderPromptRow } from "./prompt-row.js";
import { ReverseSearch } from "./reverse-search.js";
import { ensurePackageStyleTag, renderBufferRows } from "./line-editor-dom.js";
import { QuickFixOffer, renderQuickFixRow } from "./quick-fix-offer.js";
import type { QuickFixRule } from "./quick-fix.js";
import { CLEAR_SHELL_LINE, TypeaheadGate } from "./typeahead.js";

const INTERRUPT = "\x03";

export type EditorHost = {
	send(text: string): void;
	sendRaw(data: string): void;
	beforePassthrough?(event: KeyboardEvent): void;
	compositionAnchor?: (parent: HTMLElement) => CompositionAnchor | null;
	onDraftChange?(draft: string): void;
};

export class LineEditor {
	private readonly buffer = new EditorBuffer();
	private readonly history = new EditorHistory(() => this.historyChanged());
	private readonly quickFix = new QuickFixOffer();
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
	private content: HTMLElement | null = null;
	private composition: CompositionTarget | null = null;
	private unsubscribe: (() => void) | null = null;
	private unsubscribeCompletions: (() => void) | null = null;
	private visible = true;
	private staleWhileHidden = false;
	private reportedDraft = "";
	private pasteConfirm: PasteConfirm | null = null;
	private readonly typeahead = new TypeaheadGate();
	private typeaheadLineState: string | null = null;
	private textWhenOwned = "";

	mount(container: HTMLElement, core: TerminalCore, host: EditorHost): void {
		this.dispose();
		ensurePackageStyleTag();
		this.core = core;
		this.host = host;
		this.quickFix.reset(core);
		this.promptCwd = "";
		this.promptBranch = "";
		this.promptExitCode = null;
		this.promptDurationMs = null;
		this.reportedDraft = "";
		this.typeahead.reset();
		this.typeaheadLineState = null;
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
		root.addEventListener("paste", this.onPaste);
		container.append(root);
		this.root = root;
		const content = document.createElement("div");
		content.className = "terminal-editor-content";
		root.append(content);
		this.content = content;
		this.composition = createCompositionTarget({
			parent: root,
			onCommit: (text) => this.commitComposedText(text),
			anchor: host.compositionAnchor,
		});
		this.dropdown.mount(root);
		this.unsubscribe = core.onChange(() => {
			this.ingestHistory();
			this.adoptTypeahead();
			if (!this.visible) {
				this.staleWhileHidden = true;
				return;
			}
			this.render();
		});
		this.unsubscribeCompletions = core.onCompletions((result) => {
			this.dropdown.setResult(result);
			this.dropdownOpen = this.dropdown.isOpen();
			this.render();
		});
		this.ingestHistory();
		this.adoptTypeahead();
		this.render();
	}

	setTheme(theme: TerminalTheme): void {
		const style = this.root?.style;
		if (!style) return;
		style.setProperty("--terminal-foreground", theme.foreground);
		style.setProperty("--terminal-background", theme.background);
		style.setProperty("--terminal-cursor", theme.cursor);
		style.setProperty("--terminal-selection", theme.selection);
		style.setProperty("--terminal-block-border", theme.blockBorder);
		for (const [index, color] of theme.ansi.entries()) {
			style.setProperty(`--terminal-ansi-${index}`, color);
		}
	}

	setFont(font: FontConfig): void {
		const style = this.root?.style;
		if (!style) return;
		style.setProperty("--terminal-font-family", font.family);
		style.setProperty("--terminal-font-size", `${font.sizePx}px`);
		style.setProperty("--terminal-line-height", `${font.lineHeight * font.sizePx}px`);
		style.setProperty("--terminal-font-weight", String(font.weight));
		style.setProperty("--terminal-letter-spacing", `${font.letterSpacingPx}px`);
		style.setProperty("--terminal-ligatures", font.ligatures ? "normal" : "none");
	}

	setText(text: string): void {
		this.buffer.setText(text);
		this.history.endWalk();
		this.render();
	}

	setStrings(strings: TerminalStrings): void {
		this.strings = strings;
		this.render();
	}

	setPasteConfirm(confirm: PasteConfirm | null): void {
		this.pasteConfirm = confirm;
	}

	setHistorySource(source: CommandHistorySource | null): void {
		this.history.setSource(source);
		this.render();
	}

	setQuickFixRules(rules: readonly QuickFixRule[]): void {
		this.quickFix.setRules(rules);
		this.render();
	}

	setVisible(visible: boolean): void {
		this.visible = visible;
		if (!visible || !this.staleWhileHidden) return;
		this.staleWhileHidden = false;
		this.render();
	}

	focus(): void {
		this.composition?.focus();
	}

	noteSent(data: string): void {
		this.typeahead.noteSent(data);
	}

	dispose(): void {
		this.unsubscribe?.();
		this.unsubscribe = null;
		this.unsubscribeCompletions?.();
		this.unsubscribeCompletions = null;
		this.history.dispose();
		this.quickFix.dismiss();
		this.dropdown.dispose();
		this.dropdownOpen = false;
		this.composition?.dispose();
		this.composition = null;
		this.content = null;
		if (this.root) {
			this.root.removeEventListener("keydown", this.onKeyDown);
			this.root.remove();
		}
		this.root = null;
		this.core = null;
		if (this.reportedDraft !== "") this.host?.onDraftChange?.("");
		this.reportedDraft = "";
		this.host = null;
		this.visible = true;
		this.staleWhileHidden = false;
	}

	private commitComposedText(text: string): void {
		if (this.core?.lineEditorState() !== "owned") {
			this.host?.sendRaw(text);
			this.typeahead.noteSent(text);
			return;
		}
		this.apply({ kind: "insert", text });
	}

	handleKey(event: KeyboardEvent): void {
		if (this.handleSearchKey(event)) return;
		if (this.dropdown.isOpen() && this.handleDropdownKey(event)) return;
		if (this.passthrough(event) !== null) return;
		const command = mapKey(event);
		if (command) this.apply(command);
	}

	private readonly onKeyDown = (event: KeyboardEvent): void => {
		if (this.composition?.isComposing() || event.isComposing || event.keyCode === 229) {
			return;
		}
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

	// The browser has nowhere to put a paste on a div that is not editable, so
	// without this the clipboard reaches neither the buffer nor the child and
	// the key looks dead.
	private readonly onPaste = (event: ClipboardEvent): void => {
		event.preventDefault();
		const core = this.core;
		if (!core) return;
		const data = event.clipboardData;
		const plan = planPaste({
			text: data?.getData("text/plain") ?? "",
			hasImage: clipboardHasImage(data),
			owned: core.lineEditorState() === "owned",
			bracketedPaste: core.snapshot().bracketedPaste,
		});
		if (plan.kind === "insert") {
			this.apply({ kind: "insert", text: plan.text });
			return;
		}
		const host = this.host;
		const root = this.root;
		if (!host) return;
		void deliverPaste(
			plan,
			(data) => {
				if (this.root !== root) return;
				host.sendRaw(data);
				this.typeahead.noteSent(data);
			},
			this.pasteConfirm ?? undefined,
		);
	};

	// Returns null when the editor owns the line and should edit locally, and
	// otherwise the bytes handed to the child (empty when the key encodes to
	// nothing, which still counts as handled).
	private passthrough(event: KeyboardEvent): string | null {
		const core = this.core;
		if (!core || core.lineEditorState() === "owned") return null;
		const data = encodeKey(event, core.snapshot().applicationCursorKeys);
		if (data === null) return "";
		this.host?.beforePassthrough?.(event);
		this.host?.sendRaw(data);
		this.typeahead.noteSent(data);
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
			if (command.data === INTERRUPT) this.discardLine();
			return;
		}
		const wasDropdownOpen = this.dropdownOpen;
		switch (command.kind) {
			case "insert":
				this.buffer.insert(command.text);
				this.history.endWalk();
				this.cancelDropdownIfOpen();
				break;
			case "newline":
				this.buffer.insert("\n");
				this.history.endWalk();
				this.cancelDropdownIfOpen();
				break;
			case "submit":
				if (wasDropdownOpen) {
					this.applySelectedCompletion();
					this.history.endWalk();
					this.render();
					return;
				}
				host.send(this.buffer.text);
				this.buffer.clear();
				this.quickFix.dismiss();
				this.history.endWalk();
				this.cancelDropdownIfOpen();
				break;
			case "delete-backward":
				this.buffer.deleteBackward();
				this.history.endWalk();
				this.cancelDropdownIfOpen();
				break;
			case "delete-forward":
				this.buffer.deleteForward();
				this.history.endWalk();
				this.cancelDropdownIfOpen();
				break;
			case "delete-word-backward":
				this.buffer.deleteWordBackward();
				this.history.endWalk();
				this.cancelDropdownIfOpen();
				break;
			case "delete-line-backward":
				this.buffer.deleteToLineStart();
				this.history.endWalk();
				this.cancelDropdownIfOpen();
				break;
			case "delete-line-forward":
				this.buffer.deleteToLineEnd();
				this.history.endWalk();
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
				const recalled = this.history.recall(this.buffer.text, command.direction);
				if (recalled !== null) this.buffer.setText(recalled);
				break;
			}
			case "accept-suggestion":
				if (this.buffer.cursor === this.buffer.text.length) this.acceptSuggestion();
				else this.buffer.moveBy(1);
				break;
			case "end-or-accept-suggestion":
				if (this.buffer.cursor === this.buffer.text.length) this.acceptSuggestion();
				else this.buffer.moveEnd();
				break;
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

	private acceptSuggestion(): void {
		const fix = this.buffer.text.length === 0 ? this.quickFix.fix() : null;
		const suggestion = fix?.command ?? this.history.suggest(this.buffer.text);
		if (suggestion !== null) this.buffer.setText(suggestion);
		if (fix) this.quickFix.dismiss();
		this.history.endWalk();
	}

	private useQuickFix(): void {
		const fix = this.quickFix.fix();
		if (!fix || this.buffer.text.length > 0 || this.core?.lineEditorState() !== "owned") return;
		this.buffer.setText(fix.command);
		this.quickFix.dismiss();
		this.history.endWalk();
		this.cancelDropdownIfOpen();
		this.render();
		this.focus();
	}

	private historyChanged(): void {
		if (!this.visible) {
			this.staleWhileHidden = true;
			return;
		}
		this.render();
	}

	private discardLine(): void {
		this.buffer.clear();
		this.history.endWalk();
		this.cancelDropdownIfOpen();
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
		this.history.endWalk();
		if (insertion.endsWith("/")) {
			this.core?.requestCompletions(this.buffer.text, this.buffer.cursor);
		}
	}

	private reportDraft(): void {
		const draft = this.buffer.text;
		if (draft === this.reportedDraft) return;
		this.reportedDraft = draft;
		this.host?.onDraftChange?.(draft);
	}

	private render(): void {
		this.reportDraft();
		const root = this.root;
		const content = this.content;
		if (!root || !content) return;
		const state = this.core?.lineEditorState() ?? "unknown";
		root.dataset.ownership = state;
		root.setAttribute("aria-readonly", String(state !== "owned"));
		// The child draws its own prompt and cursor while it owns the line. Drawing
		// ours underneath it leaves a second, dead caret at the bottom of the pane
		// that does not track what the user is typing. The root stays in the DOM
		// and focusable -- it is still what receives the keys.
		if (state !== "owned") {
			content.replaceChildren();
			return;
		}
		const text = this.buffer.text;
		const fix = text.length === 0 ? this.quickFix.fix() : null;
		const ghost = fix ? fix.command : (this.history.suggest(text)?.slice(text.length) ?? null);
		const nodes = renderBufferRows(text, this.buffer.lines(), this.buffer.cursor, ghost);
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
		if (fix) nodes.unshift(renderQuickFixRow(fix, this.strings.quickFixLabel, this.strings.quickFixUse, () => this.useQuickFix()));
		content.replaceChildren(...nodes);
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
			// The same chord kills the whole line in the buffer, so it clears the
			// whole query here rather than one character of it.
			if (event.metaKey) this.search.clearQuery();
			else this.search.backspace();
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

	private adoptTypeahead(): void {
		const core = this.core;
		if (!core) return;
		const state = core.lineEditorState();
		if (state !== "owned" && this.typeaheadLineState === "owned") this.typeahead.reset();
		if (state === "owned" && this.typeaheadLineState !== "owned") this.textWhenOwned = this.buffer.text;
		this.typeaheadLineState = state;
		const typed = this.typeahead.take(core);
		if (typed === null) return;
		const text = this.buffer.text;
		const head = text.startsWith(this.textWhenOwned) ? this.textWhenOwned : text;
		const tail = text.slice(head.length);
		const cursor = this.buffer.cursor;
		this.buffer.setText(head + typed + tail, cursor >= head.length ? cursor + typed.length : cursor);
		this.history.endWalk();
		this.host?.sendRaw(CLEAR_SHELL_LINE);
	}

	private ingestHistory(): void {
		const core = this.core;
		if (!core) return;
		const blocks = decodeBlocks(core.snapshot());
		this.history.ingest(blocks);
		this.quickFix.observe(core);
		const newest = blocks.at(-1);
		this.promptCwd = newest?.cwd ?? "";
		this.promptBranch = newest?.gitBranch ?? "";
		this.promptExitCode = newest?.exitCode ?? null;
		this.promptDurationMs = newest?.durationMs ?? null;
	}
}
