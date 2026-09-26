import {
	FIND_UPDATE_BUDGET_BYTES,
	type BlockId,
	type BlockRenderer,
	type FindMatch,
	type FindUpdate,
	type RowRange,
	type TerminalCore,
	type TerminalStrings,
} from "@operator/terminal-core";
import type { FindHighlights } from "./renderer-highlights.js";

const CLASS_BAR = "terminal-find-bar";
const CLASS_INPUT = "terminal-find-input";
const CLASS_COUNT = "terminal-find-count";
const CLASS_REGEX = "terminal-find-regex";
const ATTR_BAR = "data-terminal-find-bar";
const ATTR_INPUT = "data-terminal-find-input";
const ATTR_COUNT = "data-terminal-find-count";
const ATTR_REGEX = "data-terminal-find-regex";

export type FindBarHost = Readonly<{
	scrollToBlock(id: BlockId, align: "start" | "center" | "end"): void;
	scrollToRow?(row: number, align: "start" | "center" | "end"): boolean;
	invalidate(range: RowRange): void;
	afterRepaint(listener: () => void): () => void;
	highlightFind(find: FindHighlights | null): void;
}>;

export type FindBarOptions = Readonly<{
	core: TerminalCore;
	renderer: BlockRenderer;
	host: FindBarHost;
	strings: TerminalStrings;
}>;

export type FindBar = Readonly<{
	mount(container: HTMLElement): void;
	open(): void;
	close(): void;
	dispose(): void;
}>;

type Session = {
	readonly id: number;
	results: readonly FindMatch[];
	rows: ReadonlySet<number>;
	current: number;
	loaded: boolean;
};

export function createFindBar(options: FindBarOptions): FindBar {
	const { core, host, strings } = options;
	let container: HTMLElement | null = null;
	let bar: HTMLElement | null = null;
	let input: HTMLInputElement | null = null;
	let countNode: HTMLElement | null = null;
	let session: Session | null = null;
	let regex = false;
	let invalid = false;
	let rafHandle: number | null = null;
	let repaintOff: (() => void) | null = null;
	let previousFocus: HTMLElement | null = null;

	const cancelRaf = (): void => {
		if (rafHandle !== null && typeof cancelAnimationFrame === "function") {
			cancelAnimationFrame(rafHandle);
		}
		rafHandle = null;
	};

	const renderCount = (): void => {
		if (!countNode) return;
		if (invalid) {
			countNode.textContent = strings.searchNoMatches;
			return;
		}
		if (!session) {
			countNode.textContent = "";
			return;
		}
		const total = session.results.length;
		if (total === 0) {
			countNode.textContent = strings.searchNoMatches;
			return;
		}
		countNode.textContent = strings.findMatchCount
			.replace("%1", String(session.current + 1))
			.replace("%2", String(total));
	};

	const clearMarks = (): void => {
		host.highlightFind(null);
	};

	const applyHighlights = (): void => {
		const active = session;
		if (!active || active.results.length === 0) {
			clearMarks();
			return;
		}
		const current = active.results[active.current];
		host.highlightFind({ rows: active.rows, current: current ? { row: current.row, endRow: current.endRow } : null });
	};

	const stopSession = (): void => {
		cancelRaf();
		if (session) {
			try {
				core.findCancel(session.id);
			} catch {
				void 0;
			}
			session = null;
		}
	};

	const indexNear = (results: readonly FindMatch[], anchor: FindMatch | undefined): number => {
		if (!anchor || results.length === 0) return 0;
		let low = 0;
		let high = results.length;
		while (low < high) {
			const mid = (low + high) >> 1;
			const hit = results[mid]!;
			if (hit.row < anchor.row || (hit.row === anchor.row && hit.startByte < anchor.startByte)) {
				low = mid + 1;
			} else {
				high = mid;
			}
		}
		return Math.min(low, results.length - 1);
	};

	const rowsOf = (results: readonly FindMatch[]): Set<number> => {
		const rows = new Set<number>();
		for (const hit of results) {
			for (let row = hit.row; row <= hit.endRow; row += 1) rows.add(row);
		}
		return rows;
	};

	const refresh = (active: Session): void => {
		const anchor = active.loaded ? active.results[active.current] : undefined;
		const results = core.findResults(active.id);
		active.results = results;
		active.rows = rowsOf(results);
		active.current = indexNear(results, anchor);
		active.loaded = true;
	};

	const reveal = (match: FindMatch): void => {
		if (!host.scrollToRow?.(match.row, "center")) {
			host.scrollToBlock(match.blockId, "center");
		}
	};

	const pump = (): void => {
		rafHandle = null;
		const active = session;
		if (!active) return;
		let update: FindUpdate;
		let revealed: FindMatch | undefined;
		try {
			update = core.findUpdate(active.id, FIND_UPDATE_BUDGET_BYTES);
			if (!active.loaded || update.added > 0 || update.removed > 0) {
				const hadHit = active.results.length > 0;
				refresh(active);
				applyHighlights();
				renderCount();
				if (!hadHit) revealed = active.results[active.current];
			}
		} catch {
			stopSession();
			clearMarks();
			renderCount();
			return;
		}
		if (revealed) {
			try {
				reveal(revealed);
			} catch {
				void 0;
			}
		}
		if (!update.complete) schedulePump();
	};

	const schedulePump = (): void => {
		if (rafHandle !== null) return;
		rafHandle = requestAnimationFrame(pump);
	};

	const openSession = (query: string): void => {
		stopSession();
		invalid = false;
		input?.removeAttribute("aria-invalid");
		if (query === "") {
			clearMarks();
			renderCount();
			return;
		}
		let id: number;
		try {
			id = core.findOpen(query, regex);
		} catch {
			invalid = true;
			input?.setAttribute("aria-invalid", "true");
			clearMarks();
			renderCount();
			return;
		}
		session = { id, results: [], rows: new Set(), current: 0, loaded: false };
		schedulePump();
	};

	const walk = (delta: number): void => {
		const active = session;
		if (!active) return;
		const total = active.results.length;
		if (total === 0) return;
		active.current = (active.current + delta + total) % total;
		reveal(active.results[active.current]!);
		applyHighlights();
		renderCount();
	};

	const ensureBar = (): HTMLElement => {
		if (bar) return bar;
		const node = document.createElement("div");
		node.className = CLASS_BAR;
		node.setAttribute(ATTR_BAR, "");
		const label = document.createElement("label");
		label.className = "terminal-find-label";
		label.setAttribute("aria-label", strings.findLabel);
		const field = document.createElement("input");
		field.type = "text";
		field.className = CLASS_INPUT;
		field.setAttribute(ATTR_INPUT, "");
		field.placeholder = strings.findPlaceholder;
		field.setAttribute("aria-label", strings.findLabel);
		field.spellcheck = false;
		field.autocomplete = "off";
		field.addEventListener("input", () => {
			openSession(field.value);
		});
		field.addEventListener("keydown", (event) => {
			if (event.key === "Enter") {
				event.preventDefault();
				walk(event.shiftKey ? -1 : 1);
			} else if (event.key === "Escape") {
				event.preventDefault();
				close();
			}
		});
		const toggle = document.createElement("button");
		toggle.type = "button";
		toggle.className = CLASS_REGEX;
		toggle.setAttribute(ATTR_REGEX, "");
		toggle.setAttribute("aria-label", strings.findRegexLabel);
		toggle.setAttribute("aria-pressed", String(regex));
		toggle.title = strings.findRegexLabel;
		toggle.textContent = ".*";
		toggle.addEventListener("mousedown", (event) => event.preventDefault());
		toggle.addEventListener("click", () => {
			regex = !regex;
			toggle.setAttribute("aria-pressed", String(regex));
			openSession(field.value);
			field.focus();
		});
		const counter = document.createElement("span");
		counter.className = CLASS_COUNT;
		counter.setAttribute(ATTR_COUNT, "");
		counter.setAttribute("aria-live", "polite");
		label.append(field);
		node.append(label, toggle, counter);
		bar = node;
		input = field;
		countNode = counter;
		return node;
	};

	function open(): void {
		if (!container) return;
		previousFocus = document.activeElement as HTMLElement | null;
		const node = ensureBar();
		if (node.parentElement !== container) {
			container.append(node);
		}
		bar = node;
		if (repaintOff === null) {
			repaintOff = host.afterRepaint(() => {
				if (session) schedulePump();
			});
		}
		if (input) {
			input.value = "";
			input.removeAttribute("aria-invalid");
			input.focus();
		}
		invalid = false;
		stopSession();
		renderCount();
	}

	function close(): void {
		if (!container) return;
		stopSession();
		invalid = false;
		clearMarks();
		if (repaintOff) {
			repaintOff();
			repaintOff = null;
		}
		if (bar && bar.parentElement === container) {
			container.removeChild(bar);
		}
		bar = null;
		input = null;
		countNode = null;
		if (previousFocus && previousFocus.focus) {
			previousFocus.focus();
		}
		previousFocus = null;
	}

	function mount(target: HTMLElement): void {
		container = target;
	}

	function dispose(): void {
		stopSession();
		clearMarks();
		if (repaintOff) {
			repaintOff();
			repaintOff = null;
		}
		if (bar && container && bar.parentElement === container) {
			container.removeChild(bar);
		}
		bar = null;
		input = null;
		countNode = null;
		container = null;
		previousFocus = null;
	}

	return { mount, open, close, dispose };
}
