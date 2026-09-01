import type { PaletteCommand, TerminalStrings } from "@operator/terminal-core";

const CLASS_PALETTE = "terminal-palette";
const CLASS_INPUT = "terminal-palette-input";
const CLASS_LIST = "terminal-palette-list";
const CLASS_OPTION = "terminal-palette-option";
const CLASS_OPTION_ACTIVE = "terminal-palette-option-active";
const CLASS_EMPTY = "terminal-palette-empty";
const ATTR_PALETTE = "data-terminal-palette";
const ATTR_INPUT = "data-terminal-palette-input";
const ATTR_LIST = "data-terminal-palette-list";
const ATTR_OPTION = "data-terminal-palette-option";
const ATTR_ACTIVE = "data-terminal-palette-option-active";
const ATTR_COMMAND_ID = "data-terminal-palette-command-id";
const ATTR_EMPTY = "data-terminal-palette-empty";

const OPEN_KEY = "p";

export type PaletteHost = Readonly<{
	container: HTMLElement;
	getCommands: () => readonly PaletteCommand[];
	isAltScreenActive: () => boolean;
	strings: TerminalStrings;
}>;

export type PaletteOptions = Omit<Partial<PaletteHost>, "container" | "getCommands" | "strings"> & Pick<PaletteHost, "container" | "getCommands" | "strings">;

export type Palette = Readonly<{
	mount(): void;
	dispose(): void;
	open(): void;
	close(): void;
	isOpen: () => boolean;
}>;

export function mountPalette(options: PaletteOptions): Palette {
	const container = options.container;
	const getCommands = options.getCommands;
	const strings = options.strings;
	const isAltScreenActive = options.isAltScreenActive ?? (() => false);
	let open_ = false;
	let palette: HTMLElement | null = null;
	let input: HTMLInputElement | null = null;
	let list: HTMLElement | null = null;
	let previousFocus: HTMLElement | null = null;
	let activeIndex = 0;
	let query = "";
	let filtered: readonly PaletteCommand[] = [];

	const rerenderList = (): void => {
		if (!list || !palette) return;
		const target = list;
		target.replaceChildren();
		if (filtered.length === 0) {
			activeIndex = 0;
			const empty = document.createElement("li");
			empty.className = CLASS_EMPTY;
			empty.setAttribute(ATTR_EMPTY, "");
			empty.textContent = strings.paletteNoMatches;
			empty.setAttribute("role", "option");
			empty.setAttribute("aria-disabled", "true");
			target.append(empty);
			return;
		}
		if (activeIndex >= filtered.length) activeIndex = filtered.length - 1;
		if (activeIndex < 0) activeIndex = 0;
		filtered.forEach((command, index) => {
			const option = document.createElement("li");
			option.className = CLASS_OPTION;
			option.setAttribute(ATTR_OPTION, "");
			option.setAttribute(ATTR_COMMAND_ID, command.id);
			option.setAttribute("role", "option");
			option.setAttribute("aria-selected", index === activeIndex ? "true" : "false");
			option.id = `${ATTR_PALETTE}-option-${index}`;
			option.textContent = command.label;
			if (index === activeIndex) {
				option.classList.add(CLASS_OPTION_ACTIVE);
				option.setAttribute(ATTR_ACTIVE, "");
			}
			target.append(option);
		});
	};

	const refresh = (): void => {
		query = input ? input.value : "";
		const all = getCommands();
		const needle = query.toLowerCase();
		if (needle === "") {
			filtered = all;
		} else {
			filtered = all.filter((c) => c.label.toLowerCase().includes(needle));
		}
		activeIndex = 0;
		rerenderList();
	};

	const runCommand = (command: PaletteCommand): void => {
		close();
		command.run();
	};

	const onInputKey = (event: KeyboardEvent): void => {
		if (event.key === "Escape") {
			event.preventDefault();
			event.stopPropagation();
			close();
			return;
		}
		if (event.key === "Enter") {
			event.preventDefault();
			event.stopPropagation();
			const command = filtered[activeIndex];
			if (command) runCommand(command);
			return;
		}
		if (event.key === "ArrowDown") {
			event.preventDefault();
			event.stopPropagation();
			if (filtered.length === 0) return;
			activeIndex = (activeIndex + 1) % filtered.length;
			rerenderList();
			return;
		}
		if (event.key === "ArrowUp") {
			event.preventDefault();
			event.stopPropagation();
			if (filtered.length === 0) return;
			activeIndex = (activeIndex - 1 + filtered.length) % filtered.length;
			rerenderList();
			return;
		}
	};

	const onListClick = (event: MouseEvent): void => {
		const target = event.target;
		if (!(target instanceof HTMLElement)) return;
		const option = target.closest<HTMLElement>(`[${ATTR_OPTION}]`);
		if (!option) return;
		const id = option.getAttribute(ATTR_COMMAND_ID);
		if (!id) return;
		const command = filtered.find((c) => c.id === id);
		if (command) runCommand(command);
	};

	const ensurePalette = (): HTMLElement => {
		if (palette) return palette;
		const node = document.createElement("div");
		node.className = CLASS_PALETTE;
		node.setAttribute(ATTR_PALETTE, "");
		node.setAttribute("role", "dialog");
		node.setAttribute("aria-label", strings.paletteLabel);
		const field = document.createElement("input");
		field.type = "text";
		field.className = CLASS_INPUT;
		field.setAttribute(ATTR_INPUT, "");
		field.placeholder = strings.palettePlaceholder;
		field.setAttribute("aria-label", strings.paletteLabel);
		field.spellcheck = false;
		field.autocomplete = "off";
		field.addEventListener("input", () => refresh());
		field.addEventListener("keydown", onInputKey);
		const listNode = document.createElement("ul");
		listNode.className = CLASS_LIST;
		listNode.setAttribute(ATTR_LIST, "");
		listNode.setAttribute("role", "listbox");
		listNode.addEventListener("click", onListClick);
		node.append(field, listNode);
		palette = node;
		input = field;
		list = listNode;
		return node;
	};

	function open(): void {
		if (isAltScreenActive()) return;
		if (open_) return;
		open_ = true;
		previousFocus = document.activeElement as HTMLElement | null;
		const node = ensurePalette();
		if (node.parentElement !== container) {
			container.append(node);
		}
		if (input) {
			input.value = "";
			input.focus();
		}
		refresh();
	}

	function close(): void {
		if (!open_) return;
		open_ = false;
		if (palette && palette.parentElement === container) {
			container.removeChild(palette);
		}
		if (previousFocus && previousFocus.focus) {
			previousFocus.focus();
		}
		previousFocus = null;
		query = "";
		filtered = [];
		activeIndex = 0;
	}

	const onContainerKeyDown = (event: KeyboardEvent): void => {
		if (open_) return;
		if (isAltScreenActive()) return;
		if (event.altKey) return;
		if (event.key.toLowerCase() !== OPEN_KEY) return;
		if (!event.shiftKey) return;
		if (!event.metaKey && !event.ctrlKey) return;
		event.preventDefault();
		open();
	};

	function mountFn(): void {
		container.addEventListener("keydown", onContainerKeyDown);
	}

	function dispose(): void {
		container.removeEventListener("keydown", onContainerKeyDown);
		close();
		palette = null;
		input = null;
		list = null;
	}

	return {
		mount: mountFn,
		dispose,
		open,
		close,
		isOpen: () => open_,
	};
}
