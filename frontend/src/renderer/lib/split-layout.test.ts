import { describe, expect, it } from "vitest";
import {
	EMPTY_LAYOUT,
	assertLayout,
	closePane,
	closeTab,
	cycleTab,
	focusPane,
	insertTabAfter,
	isTopLeftPane,
	listPanes,
	moveTab,
	openTab,
	paneTouchesTop,
	parseLayout,
	pruneTabs,
	resizeSplit,
	splitPane,
	tabKey,
	type Layout,
	type Pane,
	type TabRef,
} from "./split-layout";

const s = (id: string): TabRef => ({ kind: "session", sessionId: id });
const sh = (id: string, sessionId = "a"): TabRef => ({ kind: "shell", handleId: id, sessionId });

function ids() {
	let n = 0;
	return () => `id${++n}`;
}

function single(tabs: TabRef[], next = ids()): Layout {
	return tabs.reduce((layout, tab) => openTab(layout, tab, next), EMPTY_LAYOUT);
}

describe("split layout operations", () => {
	it("opens the first tab as a single pane and focuses it", () => {
		const layout = openTab(EMPTY_LAYOUT, s("a"), ids());
		expect(layout.root).toEqual({ type: "pane", id: "id1", tabs: [s("a")], activeTab: 0 });
		expect(layout.focusedPaneId).toBe("id1");
	});

	it("opens further tabs after the active tab of the focused pane", () => {
		const layout = single([s("a"), s("b"), s("c")]);
		const [pane] = listPanes(layout.root);
		expect(pane.tabs).toEqual([s("a"), s("b"), s("c")]);
		expect(pane.activeTab).toBe(2);
	});

	it("focuses an already open tab instead of duplicating it", () => {
		const layout = openTab(single([s("a"), s("b")]), s("a"));
		const [pane] = listPanes(layout.root);
		expect(pane.tabs).toHaveLength(2);
		expect(pane.activeTab).toBe(0);
	});

	it("splits a pane into equal halves with the new pane first for left and top", () => {
		const next = ids();
		const base = single([s("a"), s("b")], next);
		const paneId = base.focusedPaneId as string;
		const left = splitPane(base, s("b"), paneId, "left", next);
		expect(left.root).toMatchObject({ type: "split", direction: "row", sizes: [50, 50] });
		const [first, second] = listPanes(left.root);
		expect(first.tabs).toEqual([s("b")]);
		expect(second.tabs).toEqual([s("a")]);
		expect(left.focusedPaneId).toBe(first.id);
		const top = splitPane(base, s("b"), paneId, "bottom", next);
		expect(top.root).toMatchObject({ type: "split", direction: "column" });
		expect(listPanes(top.root)[1].tabs).toEqual([s("b")]);
	});

	it("halves only the target pane when splitting inside a same-direction split", () => {
		const next = ids();
		const two = splitPane(single([s("a"), s("b")], next), s("b"), "id1", "right", next);
		const rightPane = listPanes(two.root)[1];
		const three = splitPane(openTab(two, s("c"), next), s("c"), rightPane.id, "right", next);
		expect(three.root).toMatchObject({ type: "split", direction: "row", sizes: [50, 25, 25] });
		assertLayout(three);
	});

	it("refuses to split a pane by its own only tab", () => {
		const base = single([s("a")]);
		expect(splitPane(base, s("a"), base.focusedPaneId as string, "right")).toBe(base);
	});

	it("removes a pane emptied by a move and gives its space to the sibling", () => {
		const next = ids();
		const two = splitPane(single([s("a"), s("b")], next), s("b"), "id1", "right", next);
		const [left] = listPanes(two.root);
		const merged = moveTab(two, s("b"), left.id);
		expect(merged.root).toMatchObject({ type: "pane", tabs: [s("a"), s("b")], activeTab: 1 });
	});

	it("reorders within a pane using pre-removal indices", () => {
		const layout = single([s("a"), s("b"), s("c")]);
		const paneId = layout.focusedPaneId as string;
		expect(listPanes(moveTab(layout, s("a"), paneId, 3).root)[0].tabs).toEqual([s("b"), s("c"), s("a")]);
		expect(listPanes(moveTab(layout, s("c"), paneId, 0).root)[0].tabs).toEqual([s("c"), s("a"), s("b")]);
	});

	it("closing the active tab activates its right neighbour, else its left", () => {
		const layout = focusPane(single([s("a"), s("b"), s("c")]), "id1");
		const middle = closeTab({ ...layout, root: { ...(layout.root as Pane), activeTab: 1 } }, s("b"));
		expect(listPanes(middle.root)[0]).toMatchObject({ tabs: [s("a"), s("c")], activeTab: 1 });
		const last = closeTab(layout, s("c"));
		expect(listPanes(last.root)[0]).toMatchObject({ tabs: [s("a"), s("b")], activeTab: 1 });
	});

	it("closing a pane's last tab removes the pane and focuses the next pane", () => {
		const next = ids();
		const two = splitPane(single([s("a"), s("b")], next), s("b"), "id1", "right", next);
		const closed = closeTab(two, s("b"));
		expect(closed.root).toMatchObject({ type: "pane", tabs: [s("a")] });
		expect(closed.focusedPaneId).toBe("id1");
		expect(closeTab(closed, s("a"))).toEqual(EMPTY_LAYOUT);
	});

	it("closes a whole pane", () => {
		const next = ids();
		const two = splitPane(single([s("a"), s("b")], next), s("b"), "id1", "right", next);
		expect(closePane(two, listPanes(two.root)[1].id).root).toMatchObject({ type: "pane", tabs: [s("a")] });
	});

	it("inserts companions after the anchor and after earlier companions, without stealing focus", () => {
		const layout = single([s("a"), s("b")]);
		const one = insertTabAfter(layout, sh("x"), s("a"));
		const two = insertTabAfter(one, sh("y"), s("a"));
		const [pane] = listPanes(two.root);
		expect(pane.tabs).toEqual([s("a"), sh("x"), sh("y"), s("b")]);
		expect(pane.activeTab).toBe(3);
		expect(insertTabAfter(two, sh("x"), s("a"))).toBe(two);
		expect(insertTabAfter(two, sh("z"), s("missing"))).toBe(two);
	});

	it("cycles tabs in the focused pane with wrap-around", () => {
		const layout = single([s("a"), s("b")]);
		expect(listPanes(cycleTab(layout, 1).root)[0].activeTab).toBe(0);
		expect(listPanes(cycleTab(layout, -1).root)[0].activeTab).toBe(0);
		expect(cycleTab(single([s("a")]), 1)).toEqual(single([s("a")]));
	});

	it("resizes a split and ignores mismatched sizes", () => {
		const next = ids();
		const two = splitPane(single([s("a"), s("b")], next), s("b"), "id1", "right", next);
		const splitId = (two.root as { id: string }).id;
		expect(resizeSplit(two, splitId, [30, 70]).root).toMatchObject({ sizes: [30, 70] });
		expect(resizeSplit(two, splitId, [100])).toBe(two);
	});

	it("prunes missing tabs and collapses emptied panes; keeps identity when nothing is pruned", () => {
		const next = ids();
		const two = splitPane(single([s("a"), s("b")], next), s("b"), "id1", "right", next);
		expect(pruneTabs(two, () => true)).toBe(two);
		const pruned = pruneTabs(two, (tab) => tab.kind === "session" && tab.sessionId === "a");
		expect(pruned.root).toMatchObject({ type: "pane", tabs: [s("a")] });
	});

	it("reports which panes touch the top edge and which is top-left", () => {
		const next = ids();
		const base = single([s("a"), s("b"), s("c")], next);
		const columns = splitPane(base, s("b"), "id1", "right", next);
		const [left, right] = listPanes(columns.root);
		const stacked = splitPane(columns, s("c"), right.id, "bottom", next);
		const panes = listPanes(stacked.root);
		expect(panes.map((pane) => paneTouchesTop(stacked, pane.id))).toEqual([true, true, false]);
		expect(isTopLeftPane(stacked, left.id)).toBe(true);
		expect(isTopLeftPane(stacked, right.id)).toBe(false);
	});

	it("parses only valid stored layouts", () => {
		const layout = single([s("a"), s("b")]);
		expect(parseLayout(JSON.parse(JSON.stringify(layout)))).toEqual(layout);
		expect(parseLayout(null)).toBeNull();
		expect(parseLayout({ root: { type: "pane", id: "p", tabs: [], activeTab: 0 }, focusedPaneId: "p" })).toBeNull();
		expect(parseLayout({ root: null, focusedPaneId: null })).toEqual(EMPTY_LAYOUT);
		expect(parseLayout({ root: { type: "pane", id: "p", tabs: [{ kind: "bogus" }], activeTab: 0 }, focusedPaneId: "p" })).toBeNull();
	});
});

function mulberry32(seed: number) {
	let state = seed;
	return () => {
		state = (state + 0x6d2b79f5) | 0;
		let t = Math.imul(state ^ (state >>> 15), 1 | state);
		t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

const pool: TabRef[] = [
	...["a", "b", "c", "d", "e", "f", "g", "h"].map(s),
	sh("x", "a"),
	sh("y", "a"),
	sh("z", "c"),
	sh("w"),
	{ kind: "reviewer", sessionId: "a", handleId: "r1", harness: "codex" },
	{ kind: "reviewer", sessionId: "d", handleId: "r2", harness: "codex" },
];
const edges = ["left", "right", "top", "bottom"] as const;

describe("split layout invariants under random operations", () => {
	it.each([1, 2, 3, 4, 5])("holds for 2000 operations with seed %i", (seed) => {
		const random = mulberry32(seed);
		const pick = <T,>(items: readonly T[]): T => items[Math.floor(random() * items.length)];
		const next = ids();
		let layout: Layout = EMPTY_LAYOUT;
		const history: string[] = [];
		for (let step = 0; step < 2000; step += 1) {
			const panes = listPanes(layout.root);
			const tab = pick(pool);
			const paneId = panes.length ? pick(panes).id : "none";
			const roll = random();
			let label: string;
			if (roll < 0.25) {
				label = `openTab ${JSON.stringify(tab)}`;
				layout = openTab(layout, tab, next);
			} else if (roll < 0.4) {
				const edge = pick(edges);
				label = `splitPane ${JSON.stringify(tab)} ${paneId} ${edge}`;
				layout = splitPane(layout, tab, paneId, edge, next);
			} else if (roll < 0.52) {
				const index = Math.floor(random() * 6);
				label = `moveTab ${JSON.stringify(tab)} ${paneId} ${index}`;
				layout = moveTab(layout, tab, paneId, index);
			} else if (roll < 0.64) {
				label = `closeTab ${JSON.stringify(tab)}`;
				layout = closeTab(layout, tab);
			} else if (roll < 0.68) {
				label = `closePane ${paneId}`;
				layout = closePane(layout, paneId);
			} else if (roll < 0.74) {
				label = `focusPane ${paneId}`;
				layout = focusPane(layout, paneId);
			} else if (roll < 0.8) {
				label = "cycleTab";
				layout = cycleTab(layout, random() < 0.5 ? -1 : 1);
			} else if (roll < 0.86) {
				const anchor = pick(pool);
				label = `insertTabAfter ${JSON.stringify(tab)} ${JSON.stringify(anchor)}`;
				layout = insertTabAfter(layout, tab, anchor);
			} else if (roll < 0.92) {
				const split = layout.root?.type === "split" ? layout.root : null;
				const sizes = split ? split.children.map(() => 1 + random() * 99) : [];
				label = `resizeSplit ${split?.id} ${sizes.join(",")}`;
				layout = split ? resizeSplit(layout, split.id, sizes) : layout;
			} else {
				const gone = pick(pool);
				label = `pruneTabs -${JSON.stringify(gone)}`;
				layout = pruneTabs(layout, (candidate) => tabKey(candidate) !== tabKey(gone));
			}
			history.push(label);
			try {
				assertLayout(layout);
				expect(parseLayout(JSON.parse(JSON.stringify(layout)))).toEqual(layout);
			} catch (error) {
				throw new Error(
					`seed ${seed} step ${step}: ${(error as Error).message}\n${history.slice(-12).join("\n")}\n${JSON.stringify(layout)}`,
				);
			}
		}
	});
});
