import type { BlockId, BlockView, TerminalStrings } from "@operator/terminal-core";

const CLASS_BUTTON = "terminal-jump-to-bottom";
const ATTR_BUTTON = "data-terminal-jump-to-bottom";
const ATTR_VISIBLE = "data-terminal-jump-to-bottom-visible";

const OVERHANG_THRESHOLD_PX = 70;
const ICON_TEXT = "⤓";
const ICON_SIZE_PX = 20;
const PADDING_PX = 4;
const CORNER_RADIUS_PX = 4;

export type JumpToBottomOptions = Readonly<{
	container: HTMLElement;
	getBlocks: () => readonly BlockView[];
	getCellHeight: () => number;
	getStickToBottom: () => boolean;
	scrollToLatest: () => void;
	isAltScreenActive: () => boolean;
	strings: TerminalStrings;
}>;

export type JumpToBottom = Readonly<{
	mount(): void;
	dispose(): void;
	isOverhanging: () => BlockId | null;
	isButtonVisible: () => boolean;
}>;

type Overhanging = Readonly<{
	blockId: BlockId;
	bottomOffsetPx: number;
}>;

export function mountJumpToBottom(options: JumpToBottomOptions): JumpToBottom {
	const container = options.container;
	const getBlocks = options.getBlocks;
	const getCellHeight = options.getCellHeight;
	const getStickToBottom = options.getStickToBottom;
	const scrollToLatest = options.scrollToLatest;
	const isAltScreenActive = options.isAltScreenActive;
	const strings = options.strings;

	let button: HTMLButtonElement | null = null;
	let overhanging: Overhanging | null = null;
	let hoverActive = false;

	const ensureButton = (): HTMLButtonElement => {
		if (button) return button;
		const node = document.createElement("button");
		node.type = "button";
		node.className = CLASS_BUTTON;
		node.setAttribute(ATTR_BUTTON, "");
		node.setAttribute("aria-label", strings.jumpToBottom);
		node.title = strings.jumpToBottom;
		node.tabIndex = 0;
		node.style.position = "absolute";
		node.style.bottom = "8px";
		node.style.right = "8px";
		node.style.zIndex = "10";
		node.style.padding = `${PADDING_PX}px`;
		node.style.borderRadius = `${CORNER_RADIUS_PX}px`;
		node.style.background = "transparent";
		node.style.border = "none";
		node.style.cursor = "pointer";
		node.style.color = "inherit";
		node.style.font = `${ICON_SIZE_PX}px ui-monospace, monospace`;
		node.style.lineHeight = "1";
		node.style.display = "inline-flex";
		node.style.alignItems = "center";
		node.style.justifyContent = "center";
		node.style.width = `${ICON_SIZE_PX + PADDING_PX * 2}px`;
		node.style.height = `${ICON_SIZE_PX + PADDING_PX * 2}px`;
		node.textContent = ICON_TEXT;
		node.addEventListener("click", (event) => {
			event.preventDefault();
			event.stopPropagation();
			scrollToLatest();
		});
		node.addEventListener("keydown", (event) => {
			if (event.key === "Enter" || event.key === " ") {
				event.preventDefault();
				event.stopPropagation();
				scrollToLatest();
			}
		});
		node.addEventListener("mouseenter", () => {
			hoverActive = true;
			updateVisibility();
		});
		node.addEventListener("mouseleave", () => {
			hoverActive = false;
			updateVisibility();
		});
		button = node;
		return node;
	};

	const computeOverhanging = (): Overhanging | null => {
		if (isAltScreenActive()) return null;
		if (getStickToBottom()) return null;
		const blocks = getBlocks();
		if (blocks.length === 0) return null;
		const cellHeight = getCellHeight();
		if (cellHeight <= 0) return null;
		const scrollTop = container.scrollTop;
		const viewportHeight = container.clientHeight;
		const viewportBottom = scrollTop + viewportHeight;
		let topSumRows = 0;
		for (const block of blocks) {
			const blockTop = topSumRows * cellHeight;
			const blockBottom = blockTop + block.rowCount * cellHeight;
			topSumRows += block.rowCount;
			if (blockBottom <= viewportBottom) continue;
			const overhangPx = blockBottom - viewportBottom;
			if (overhangPx >= OVERHANG_THRESHOLD_PX) {
				return { blockId: block.id, bottomOffsetPx: overhangPx };
			}
			return null;
		}
		return null;
	};

	const updateVisibility = (): void => {
		const node = button;
		if (!node) return;
		const next = overhanging !== null && hoverActive;
		const isInDom = node.parentElement === container;
		if (next && !isInDom) {
			container.append(node);
		} else if (!next && isInDom) {
			container.removeChild(node);
		}
		if (next) {
			node.setAttribute(ATTR_VISIBLE, "");
		} else {
			node.removeAttribute(ATTR_VISIBLE);
		}
	};

	const onScrollOrResize = (): void => {
		overhanging = computeOverhanging();
		updateVisibility();
	};

	const onMouseOver = (event: MouseEvent): void => {
		const target = event.target;
		if (!(target instanceof Element)) return;
		if (overhanging === null) return;
		const blockEl = target.closest<HTMLElement>(
			`[data-terminal-block-id="${cssEscape(overhanging.blockId)}"]`,
		);
		if (!blockEl) return;
		hoverActive = true;
		updateVisibility();
	};

	const onMouseOut = (event: MouseEvent): void => {
		const target = event.target;
		if (!(target instanceof Element)) return;
		if (overhanging === null) return;
		const blockEl = target.closest<HTMLElement>(
			`[data-terminal-block-id="${cssEscape(overhanging.blockId)}"]`,
		);
		if (!blockEl) return;
		const related = event.relatedTarget;
		if (related instanceof Node && blockEl.contains(related)) return;
		hoverActive = false;
		updateVisibility();
	};

	const onKeyDown = (event: KeyboardEvent): void => {
		if (isAltScreenActive()) return;
		if (!event.metaKey && !event.ctrlKey) return;
		if (event.altKey || event.shiftKey) return;
		const isCmdEnd = event.key === "End";
		const isCmdDown = event.key === "ArrowDown";
		if (!isCmdEnd && !isCmdDown) return;
		event.preventDefault();
		scrollToLatest();
	};

	function mountFn(): void {
		container.addEventListener("scroll", onScrollOrResize, { passive: true });
		container.addEventListener("mouseover", onMouseOver);
		container.addEventListener("mouseout", onMouseOut);
		container.addEventListener("keydown", onKeyDown);
		ensureButton();
		overhanging = computeOverhanging();
		updateVisibility();
	}

	function dispose(): void {
		container.removeEventListener("scroll", onScrollOrResize);
		container.removeEventListener("mouseover", onMouseOver);
		container.removeEventListener("mouseout", onMouseOut);
		container.removeEventListener("keydown", onKeyDown);
		if (button && button.parentElement === container) {
			container.removeChild(button);
		}
		button = null;
		overhanging = null;
		hoverActive = false;
	}

	return {
		mount: mountFn,
		dispose,
		isOverhanging: () => overhanging?.blockId ?? null,
		isButtonVisible: () => button !== null && button.parentElement === container,
	};
}

function cssEscape(value: string): string {
	if (typeof CSS !== "undefined" && typeof CSS.escape === "function") {
		return CSS.escape(value);
	}
	return value.replace(/[^a-zA-Z0-9_-]/g, (ch) => `\\${ch}`);
}
