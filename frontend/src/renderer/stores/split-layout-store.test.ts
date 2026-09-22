import { beforeEach, describe, expect, it } from "vitest";
import { EMPTY_LAYOUT, listPanes, type TabRef } from "../lib/split-layout";
import { SPLIT_LAYOUT_STORAGE_KEY, loadStoredLayout, useSplitLayoutStore } from "./split-layout-store";

const s = (id: string): TabRef => ({ kind: "session", sessionId: id });

beforeEach(() => {
	window.localStorage.clear();
	useSplitLayoutStore.setState({ layout: EMPTY_LAYOUT });
});

describe("split layout store", () => {
	it("applies operations and persists every change", () => {
		const store = useSplitLayoutStore.getState();
		store.openTab(s("a"));
		store.openTab(s("b"));
		const paneId = useSplitLayoutStore.getState().layout.focusedPaneId as string;
		useSplitLayoutStore.getState().splitPane(s("b"), paneId, "right");
		const layout = useSplitLayoutStore.getState().layout;
		expect(listPanes(layout.root)).toHaveLength(2);
		expect(JSON.parse(window.localStorage.getItem(SPLIT_LAYOUT_STORAGE_KEY) ?? "null")).toEqual(layout);
		expect(loadStoredLayout()).toEqual(layout);
	});

	it("does not write when an operation changes nothing", () => {
		useSplitLayoutStore.getState().openTab(s("a"));
		const before = useSplitLayoutStore.getState().layout;
		window.localStorage.removeItem(SPLIT_LAYOUT_STORAGE_KEY);
		useSplitLayoutStore.getState().focusTab(s("a"));
		expect(useSplitLayoutStore.getState().layout).toBe(before);
		expect(window.localStorage.getItem(SPLIT_LAYOUT_STORAGE_KEY)).toBeNull();
	});

	it("discards corrupt or invalid stored layouts", () => {
		window.localStorage.setItem(SPLIT_LAYOUT_STORAGE_KEY, "{not json");
		expect(loadStoredLayout()).toEqual(EMPTY_LAYOUT);
		window.localStorage.setItem(
			SPLIT_LAYOUT_STORAGE_KEY,
			JSON.stringify({ root: { type: "pane", id: "p", tabs: [], activeTab: 0 }, focusedPaneId: "p" }),
		);
		expect(loadStoredLayout()).toEqual(EMPTY_LAYOUT);
	});

	it("prunes tabs whose session is gone", () => {
		const store = useSplitLayoutStore.getState();
		store.openTab(s("a"));
		store.openTab(s("b"));
		useSplitLayoutStore.getState().pruneTabs((tab) => tab.kind === "session" && tab.sessionId === "a");
		expect(listPanes(useSplitLayoutStore.getState().layout.root)[0].tabs).toEqual([s("a")]);
	});
});
