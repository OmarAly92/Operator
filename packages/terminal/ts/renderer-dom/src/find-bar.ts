import {
	decodeBlocks,
	FIND_STEP_BUDGET,
	type BlockId,
	type BlockRenderer,
	type BlockView,
	type FindMatch,
	type RowRange,
	type TerminalCore,
	type TerminalStrings,
} from "@operator/terminal-core";

const CLASS_BAR = "terminal-find-bar";
const CLASS_INPUT = "terminal-find-input";
const CLASS_COUNT = "terminal-find-count";
const CLASS_ROW_MATCH = "terminal-find-row-match";
const CLASS_ROW_ACTIVE = "terminal-find-row-active";
const ATTR_BAR = "data-terminal-find-bar";
const ATTR_INPUT = "data-terminal-find-input";
const ATTR_COUNT = "data-terminal-find-count";
const ATTR_ROW_MATCH = "data-terminal-find-row-match";
const ATTR_ROW_ACTIVE = "data-terminal-find-row-active";

export type FindBarHost = Readonly<{
	scrollToBlock(id: BlockId, align: "start" | "center" | "end"): void;
	invalidate(range: RowRange): void;
	afterRepaint(listener: () => void): () => void;
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

type Step = "idle" | "open" | "step" | "done";

type Session = Readonly<{
	id: number;
	query: string;
	step: Step;
	results: readonly FindMatch[];
	currentIndex: number;
}>;

export function createFindBar(options: FindBarOptions): FindBar {
	const { core, host, strings } = options;
	let container: HTMLElement | null = null;
	let bar: HTMLElement | null = null;
	let input: HTMLInputElement | null = null;
	let countNode: HTMLElement | null = null;
	let session: Session | null = null;
	let rafHandle: number | null = null;
	let allBlocks: readonly BlockView[] = [];
	let repaintOff: (() => void) | null = null;
	let previousFocus: HTMLElement | null = null;
	let queryBeforeEdit: string = "";

	const cancelRaf = (): void => {
		if (rafHandle !== null && typeof cancelAnimationFrame === "function") {
			cancelAnimationFrame(rafHandle);
		}
		rafHandle = null;
	};

	const formatCount = (current: number, total: number): string => {
		const template = strings.findMatchCount;
		const currentStr = String(current);
		const totalStr = String(total);
		return template
			.replace("%1", currentStr)
			.replace("%2", totalStr);
	};

	const renderCount = (): void => {
		if (!countNode) return;
		if (!session) {
			countNode.textContent = "";
			return;
		}
		const total = session.results.length;
		if (total === 0) {
			countNode.textContent = strings.searchNoMatches;
			return;
		}
		countNode.textContent = formatCount(
			session.currentIndex + 1,
			total,
		);
	};

	const findBlockById = (id: BlockId): BlockView | undefined => {
		return allBlocks.find((block) => block.id === id);
	};

	const rowNodeFor = (block: BlockView, row: number): HTMLElement | null => {
		if (!container) return null;
		const blockNode = container.querySelector<HTMLElement>(
			`[data-terminal-block-id="${cssEscape(block.id)}"]`,
		);
		if (!blockNode) return null;
		const rowNode = blockNode.querySelector<HTMLElement>(
			`[data-terminal-row="${row}"]`,
		);
		return rowNode;
	};

	const isRowVisible = (block: BlockView, row: number): boolean => {
		if (!container) return false;
		const blockNode = container.querySelector<HTMLElement>(
			`[data-terminal-block-id="${cssEscape(block.id)}"]`,
		);
		if (!blockNode) return false;
		return blockNode.querySelector(`[data-terminal-row="${row}"]`) !== null;
	};

	const applyHighlights = (): void => {
		if (!container) return;
		container
			.querySelectorAll<HTMLElement>(`[${ATTR_ROW_MATCH}]`)
			.forEach((node) => {
				node.classList.remove(CLASS_ROW_MATCH);
				node.removeAttribute(ATTR_ROW_MATCH);
			});
		container
			.querySelectorAll<HTMLElement>(`[${ATTR_ROW_ACTIVE}]`)
			.forEach((node) => {
				node.classList.remove(CLASS_ROW_ACTIVE);
				node.removeAttribute(ATTR_ROW_ACTIVE);
			});

		if (!session) return;
		const current = session.results[session.currentIndex];
		for (let index = 0; index < session.results.length; index += 1) {
			const match = session.results[index]!;
			const block = findBlockById(match.blockId);
			if (!block) continue;
			if (!isRowVisible(block, match.row)) continue;
			const rowNode = rowNodeFor(block, match.row);
			if (!rowNode) continue;
			rowNode.classList.add(CLASS_ROW_MATCH);
			rowNode.setAttribute(ATTR_ROW_MATCH, "");
		}
		if (current) {
			const block = findBlockById(current.blockId);
			if (block) {
				const rowNode = rowNodeFor(block, current.row);
				if (rowNode) {
					rowNode.classList.add(CLASS_ROW_ACTIVE);
					rowNode.setAttribute(ATTR_ROW_ACTIVE, "");
				}
			}
		}
	};

	const tearDownHighlights = (): void => {
		if (!container) return;
		container
			.querySelectorAll<HTMLElement>(`[${ATTR_ROW_MATCH}]`)
			.forEach((node) => {
				node.classList.remove(CLASS_ROW_MATCH);
				node.removeAttribute(ATTR_ROW_MATCH);
			});
		container
			.querySelectorAll<HTMLElement>(`[${ATTR_ROW_ACTIVE}]`)
			.forEach((node) => {
				node.classList.remove(CLASS_ROW_ACTIVE);
				node.removeAttribute(ATTR_ROW_ACTIVE);
			});
	};

	const refreshBlocks = (): void => {
		allBlocks = decodeBlocks(core.snapshot());
	};

	const stopSession = (): void => {
		if (session) {
			try {
				core.findCancel(session.id);
			} catch {
				void 0;
			}
			session = null;
		}
	};

	const runStep = (): void => {
		rafHandle = null;
		if (!session) return;
		if (session.step === "done") {
			applyHighlights();
			renderCount();
			return;
		}
		try {
			core.findStep(session.id, FIND_STEP_BUDGET);
		} catch {
			session = { ...session, step: "done" };
			applyHighlights();
			renderCount();
			return;
		}
		const results = core.findResults();
		let nextStep: Step = session.step;
		try {
			if (core.findIsComplete(session.id)) {
				nextStep = "done";
			}
		} catch {
			nextStep = "done";
		}
		let currentIndex = session.currentIndex;
		if (currentIndex >= results.length) {
			currentIndex = results.length === 0 ? 0 : results.length - 1;
		}
		session = { ...session, results, step: nextStep, currentIndex };
		applyHighlights();
		renderCount();
		if (nextStep !== "done") {
			rafHandle = requestAnimationFrame(runStep);
		}
	};

	const scheduleStep = (): void => {
		if (rafHandle !== null) return;
		rafHandle = requestAnimationFrame(runStep);
	};

	const openSession = (query: string): void => {
		stopSession();
		if (query === "") {
			session = null;
			tearDownHighlights();
			renderCount();
			return;
		}
		const id = core.findOpen(query, false);
		session = {
			id,
			query,
			step: "open",
			results: [],
			currentIndex: 0,
		};
		scheduleStep();
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
			if (!field.value) {
				queryBeforeEdit = "";
			} else if (queryBeforeEdit === "") {
				queryBeforeEdit = field.value;
			}
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
		const counter = document.createElement("span");
		counter.className = CLASS_COUNT;
		counter.setAttribute(ATTR_COUNT, "");
		counter.setAttribute("aria-live", "polite");
		label.append(field);
		node.append(label, counter);
		bar = node;
		input = field;
		countNode = counter;
		return node;
	};

	const walk = (delta: number): void => {
		if (!session) return;
		const total = session.results.length;
		if (total === 0) return;
		let next = session.currentIndex + delta;
		if (next < 0) next = total - 1;
		if (next >= total) next = 0;
		session = { ...session, currentIndex: next };
		const match = session.results[next];
		if (!match) return;
		host.scrollToBlock(match.blockId, "center");
		applyHighlights();
		renderCount();
	};

	function open(): void {
		if (!container) return;
		refreshBlocks();
		previousFocus = document.activeElement as HTMLElement | null;
		const node = ensureBar();
		if (node.parentElement !== container) {
			container.append(node);
		}
		bar = node;
		if (repaintOff === null) {
			repaintOff = host.afterRepaint(() => {
				refreshBlocks();
				applyHighlights();
			});
		}
		if (input) {
			input.value = "";
			input.focus();
		}
		queryBeforeEdit = "";
		stopSession();
		session = null;
		renderCount();
	}

	function close(): void {
		if (!container) return;
		stopSession();
		tearDownHighlights();
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
		refreshBlocks();
	}

	function dispose(): void {
		cancelRaf();
		stopSession();
		tearDownHighlights();
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
		allBlocks = [];
		previousFocus = null;
	}

	return { mount, open, close, dispose };
}

function cssEscape(value: string): string {
	if (typeof CSS !== "undefined" && typeof CSS.escape === "function") {
		return CSS.escape(value);
	}
	return value.replace(/(["\\])/g, "\\$1");
}
