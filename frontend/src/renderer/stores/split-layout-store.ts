import { create } from "zustand";
import {
	EMPTY_LAYOUT,
	assertLayout,
	closePane,
	closeTab,
	cycleTab,
	focusPane,
	focusTab,
	insertTabAfter,
	moveTab,
	openTab,
	parseLayout,
	pruneTabs,
	resizeSplit,
	splitPane,
	type Edge,
	type Layout,
	type TabRef,
} from "../lib/split-layout";

export const SPLIT_LAYOUT_STORAGE_KEY = "opr.splitLayout.v1";

export function loadStoredLayout(): Layout {
	try {
		const raw = window.localStorage?.getItem(SPLIT_LAYOUT_STORAGE_KEY);
		if (!raw) return EMPTY_LAYOUT;
		return parseLayout(JSON.parse(raw)) ?? EMPTY_LAYOUT;
	} catch {
		return EMPTY_LAYOUT;
	}
}

function persist(layout: Layout): void {
	try {
		window.localStorage?.setItem(SPLIT_LAYOUT_STORAGE_KEY, JSON.stringify(layout));
	} catch {
		return;
	}
}

type SplitLayoutState = {
	layout: Layout;
	openTab: (tab: TabRef) => void;
	focusTab: (tab: TabRef) => void;
	focusPane: (paneId: string) => void;
	insertTabAfter: (tab: TabRef, anchor: TabRef) => void;
	moveTab: (tab: TabRef, paneId: string, index?: number) => void;
	splitPane: (tab: TabRef, paneId: string, edge: Edge) => void;
	closeTab: (tab: TabRef) => void;
	closePane: (paneId: string) => void;
	cycleTab: (direction: -1 | 1) => void;
	resizeSplit: (splitId: string, sizes: number[]) => void;
	pruneTabs: (keep: (tab: TabRef) => boolean) => void;
};

export const useSplitLayoutStore = create<SplitLayoutState>((set, get) => {
	const apply = (next: Layout) => {
		if (next === get().layout) return;
		if (import.meta.env.DEV) assertLayout(next);
		persist(next);
		set({ layout: next });
	};
	return {
		layout: loadStoredLayout(),
		openTab: (tab) => apply(openTab(get().layout, tab)),
		focusTab: (tab) => apply(focusTab(get().layout, tab)),
		focusPane: (paneId) => apply(focusPane(get().layout, paneId)),
		insertTabAfter: (tab, anchor) => apply(insertTabAfter(get().layout, tab, anchor)),
		moveTab: (tab, paneId, index) => apply(moveTab(get().layout, tab, paneId, index)),
		splitPane: (tab, paneId, edge) => apply(splitPane(get().layout, tab, paneId, edge)),
		closeTab: (tab) => apply(closeTab(get().layout, tab)),
		closePane: (paneId) => apply(closePane(get().layout, paneId)),
		cycleTab: (direction) => apply(cycleTab(get().layout, direction)),
		resizeSplit: (splitId, sizes) => apply(resizeSplit(get().layout, splitId, sizes)),
		pruneTabs: (keep) => apply(pruneTabs(get().layout, keep)),
	};
});
