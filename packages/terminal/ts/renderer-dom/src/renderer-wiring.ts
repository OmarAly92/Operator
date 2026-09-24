import { defaultStrings, type BlockId, type BlockView, type TerminalCore } from "@operator/terminal-core";
import { bindActionEvents } from "./action-events.js";
import type { BlockFilter } from "./block-filter.js";
import { mountBlockNavFromRenderer, type BlockNavHandle } from "./block-nav.js";
import { listenScroll } from "./host-dom.js";
import { mountJumpToBottom } from "./jump-to-bottom.js";

export type RendererWiringHost = Readonly<{
	onScroll: () => void;
	onRowRemap: (remap: ReadonlyArray<readonly [number, number]> | null) => void;
	onChange: () => void;
	onVisibilityChange: () => void;
	getBlocks: () => readonly BlockView[];
	scrollToBlock: (id: BlockId, align: "start" | "center" | "end") => void;
	setFilter: (filter: BlockFilter | null) => void;
	scheduleRepaint: () => void;
	getCellHeight: () => number;
	getStickToBottom: () => boolean;
	scrollToLatest: () => void;
}>;

export type RendererWiring = Readonly<{ blockNav: BlockNavHandle; teardown: () => void }>;

export function wireRenderer(container: HTMLElement, core: TerminalCore, host: RendererWiringHost): RendererWiring {
	const scrollUnsubscribe = listenScroll(container, () => host.onScroll());
	const rowEventsUnsubscribe = core.onRowEvents((event) => host.onRowRemap(event.remap));
	const unsubscribe = core.onChange(() => host.onChange());
	document.addEventListener("visibilitychange", host.onVisibilityChange);
	const blockNav = mountBlockNavFromRenderer({ container, getBlocks: () => host.getBlocks(), scrollToBlock: (id, align) => host.scrollToBlock(id, align), isAltScreenActive: () => core.snapshot().altScreen !== null });
	bindActionEvents(container, { setBlockBookmarked: (id, b) => core.setBlockBookmarked(id, b), getBlockBookmarked: (id) => core.blockBookmarked(id), setFilter: (f) => host.setFilter(f), scrollToBlock: (id, a) => host.scrollToBlock(id, a), scheduleRepaint: () => host.scheduleRepaint() });
	const jumpToBottom = mountJumpToBottom({ container, getBlocks: () => host.getBlocks(), getCellHeight: () => host.getCellHeight(), getStickToBottom: () => host.getStickToBottom(), scrollToLatest: () => host.scrollToLatest(), isAltScreenActive: () => core.snapshot().altScreen !== null, strings: defaultStrings });
	jumpToBottom.mount();
	const teardown = () => {
		jumpToBottom.dispose();
		blockNav.dispose();
		unsubscribe();
		scrollUnsubscribe();
		rowEventsUnsubscribe();
	};
	return { blockNav, teardown };
}
