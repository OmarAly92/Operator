import type { BlockId, BlockView } from "@operator/terminal-core";
import { findNeighbourBlock } from "./viewport.js";

const CLASS_FOCUSED = "terminal-block-focused";

export type BlockNavDeps = Readonly<{
	container: HTMLElement;
	getBlocks: () => readonly BlockView[];
	getPinnedIndex: () => number;
	scrollToBlock: (id: BlockId, align: "start" | "center" | "end") => void;
	isAltScreenActive: () => boolean;
}>;

export type BlockNavOptions = Partial<BlockNavDeps> & Pick<BlockNavDeps, "container" | "scrollToBlock">;

export type BlockNavHandle = Readonly<{
	dispose: () => void;
	currentBlockId: () => BlockId | null;
	setPinnedIndex: (index: number) => void;
}>;

export function mountBlockNav(options: BlockNavOptions): BlockNavHandle {
	const container = options.container;
	const getBlocks = options.getBlocks ?? (() => [] as readonly BlockView[]);
	const getPinnedIndex = options.getPinnedIndex ?? (() => -1);
	const isAltScreenActive = options.isAltScreenActive ?? (() => false);
	const scrollToBlock = options.scrollToBlock;
	const align: "start" | "center" | "end" = "center";
	let overrideId: BlockId | null = null;
	let latestPinnedIndex = -1;

	const focusedBlocks = new Set<HTMLElement>();

	const applyFocus = (id: BlockId | null): void => {
		for (const element of focusedBlocks) {
			element.classList.remove(CLASS_FOCUSED);
		}
		focusedBlocks.clear();
		if (id === null) return;
		const target = container.querySelector<HTMLElement>(`[data-terminal-block-id="${cssEscape(id)}"]`);
		if (target) {
			target.classList.add(CLASS_FOCUSED);
			focusedBlocks.add(target);
		}
	};

	const onKeyDown = (event: KeyboardEvent): void => {
		if (isAltScreenActive()) return;
		if (!event.metaKey && !event.ctrlKey) return;
		if (event.altKey || event.shiftKey) return;
		const delta: -1 | 1 | null = event.key === "ArrowUp" ? -1 : event.key === "ArrowDown" ? 1 : null;
		if (delta === null) return;

		event.preventDefault();
		const blocks = getBlocks();
		if (blocks.length === 0) return;

		const currentIndex = overrideId
			? blocks.findIndex((block) => block.id === overrideId)
			: (latestPinnedIndex !== -1 ? latestPinnedIndex : getPinnedIndex());
		const nextIndex = findNeighbourBlock(blocks, currentIndex, delta);
		const next = blocks[nextIndex];
		if (!next) return;
		overrideId = next.id;
		applyFocus(next.id);
		scrollToBlock(next.id, align);
	};

	container.addEventListener("keydown", onKeyDown);
	return {
		dispose: () => {
			container.removeEventListener("keydown", onKeyDown);
			for (const element of focusedBlocks) {
				element.classList.remove(CLASS_FOCUSED);
			}
			focusedBlocks.clear();
		},
		currentBlockId: () => overrideId,
		setPinnedIndex: (index: number) => {
			latestPinnedIndex = index;
		},
	};
}

function cssEscape(value: string): string {
	if (typeof CSS !== "undefined" && typeof CSS.escape === "function") {
		return CSS.escape(value);
	}
	return value.replace(/[^a-zA-Z0-9_-]/g, (ch) => `\\${ch}`);
}

type RendererBlockNavSource = {
	container: HTMLElement;
	scrollToBlock: (id: BlockId, align: "start" | "center" | "end") => void;
	isAltScreenActive: () => boolean;
	getBlocks?: () => readonly BlockView[];
};

export function mountBlockNavFromRenderer(renderer: RendererBlockNavSource): BlockNavHandle {
	return mountBlockNav({
		container: renderer.container,
		scrollToBlock: renderer.scrollToBlock,
		isAltScreenActive: renderer.isAltScreenActive,
		...(renderer.getBlocks ? { getBlocks: renderer.getBlocks } : {}),
	});
}
