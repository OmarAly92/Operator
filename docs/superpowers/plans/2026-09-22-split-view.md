# Split View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drag session, shell and reviewer tabs — and sidebar sessions — into the session area to split it into any number of panes in any direction, matching Claude Code's split view in look, behaviour and motion.

**Architecture:** A pure, invariant-checked layout tree (`lib/split-layout.ts`) held in a persisted zustand store drives a recursive `SplitWorkspace` of `react-resizable-panels` groups. Drop targets are resolved geometrically by a pure function (`lib/split-drop.ts`), fed by one app-wide dnd-kit context (the ticket context, generalised). The retained-terminal cache moves from one live slot to one per pane.

**Tech Stack:** React 19, TypeScript, zustand 5, @dnd-kit/core 6, react-resizable-panels 4, motion 12, Vitest + Testing Library.

**Spec:** [`docs/superpowers/specs/2026-09-22-split-view-design.md`](../specs/2026-09-22-split-view-design.md) — read §1 (the measured Claude Code reference) before Tasks 7 and 9.

## Global Constraints

- Write **no code comments** (the user's global rule). Names carry the meaning.
- Do not touch `packages/terminal` (TERMINAL.md §3 rule 1). Read TERMINAL.md end to end before Task 4.
- UI follows DESIGN.md's "clone agent-orchestrator verbatim" banner; build from `components/ui/*` shadcn primitives where one fits.
- All user-facing copy goes in `frontend/src/renderer/i18n/en.json`; no inline strings in components.
- Minimum pane size: **320px wide** for a side-by-side split, **200px tall** for a stacked split.
- Drop-box slide: **120ms, `cubic-bezier(0.33, 1, 0.68, 1)`** (ease-out cubic; fits the measured 35/62/80/91/97/99.6% progress at 16ms steps). Box appears and disappears with **no fade**. Drop **snaps** (no animation). Drag-preview cross-fade **120ms**.
- `react-resizable-panels` v4: bare numbers are **pixels**, percentages are **strings** (`"50%"`).
- Commands run from `frontend/`: tests `npx vitest run <path>`, types `npx tsc --noEmit -p tsconfig.json`, lint `npx eslint <files>`. The full suite (`npx vitest run`) and typecheck must be green at the end of every task.
- Never stash in the shared checkout; commit only the files a task names.
- Baseline: `development` with the session-tab work (per-project tabs, tab ✕, Cmd+W, ⌥⌘←/→) committed. This plan replaces that per-project tab state.

## File map

| File | Responsibility |
|---|---|
| `src/renderer/lib/split-layout.ts` | Layout types, pure operations, `assertLayout`, `parseLayout`, geometry helpers |
| `src/renderer/lib/split-drop.ts` | `resolveDrop`: pointer + pane rects → split/move target and overlay box |
| `src/renderer/stores/split-layout-store.ts` | Persisted zustand store wrapping the operations |
| `src/renderer/components/split/pane-registry.ts` | Registry of pane and strip DOM elements; reads `PaneGeometry[]` |
| `src/renderer/components/split/split-drag-store.ts` | Current drag and resolved target |
| `src/renderer/components/split/split-drag-handlers.ts` | dnd-kit start/move/end/cancel handlers for tab drags |
| `src/renderer/components/split/useSplitTabDraggable.ts` | `useDraggable` wrapper for tabs and sidebar rows |
| `src/renderer/components/split/SessionPaneTab.tsx` | Session/reviewer tab (moved out of `CenterPane.tsx`) |
| `src/renderer/components/split/PaneTerminal.tsx` | A pane's terminal + agent-switch overlay (moved out of `CenterPane.tsx`) |
| `src/renderer/components/split/PaneTabStrip.tsx` | A pane's tab strip with overflow chevrons and drag handles |
| `src/renderer/components/split/SplitPane.tsx` | One pane: header (strip + actions + ✕), body, focus ring, registry |
| `src/renderer/components/split/SessionCompanions.tsx` | Adopts a session's shells/reviewer into the layout |
| `src/renderer/components/split/SplitWorkspace.tsx` | Renders the tree, syncs route ↔ focus, prunes, shortcuts |
| `src/renderer/components/split/SplitDropOverlay.tsx` | Dim layer, sliding blurred box, "Split view" pill |
| `src/renderer/components/split/SplitDragPreview.tsx` | Row ghost cross-fading to "Open in split view" chip |
| `src/renderer/components/dnd/AppDndProvider.tsx` | The one app-wide `DndContext` (tickets + tabs) — `git mv` of `tickets/TicketDndProvider.tsx` |
| `src/renderer/hooks/useSessionReviewer.ts` | Reviewer query moved out of `SessionView.tsx` |
| Modified | `TerminalPane.tsx`, `BlockTerminal.tsx`, `SessionView.tsx`, `Sidebar.tsx`, `routes/_shell.tsx`, `stores/ui-store.ts`, `i18n/en.json`, `TERMINAL.md` |
| Deleted | `CenterPane.tsx` (+test), `SessionTopbarPortal.tsx` |

---

### Task 1: Layout model

**Files:**
- Create: `frontend/src/renderer/lib/split-layout.ts`
- Test: `frontend/src/renderer/lib/split-layout.test.ts`

**Interfaces:**
- Produces (used by every later task):
  - `type TabRef`, `Pane`, `Split`, `LayoutNode`, `Layout`, `Edge`, `SplitDirection`, `NewId`
  - `EMPTY_LAYOUT: Layout`
  - `tabKey(tab): string`, `sameTab(a, b): boolean`, `tabSessionId(tab): string | undefined`
  - `listPanes(node): Pane[]`, `findPane(layout, id)`, `paneOfTab(layout, tab)`, `focusedPane(layout)`, `activeTabOf(pane): TabRef`
  - `focusPane(layout, paneId)`, `focusTab(layout, tab)`, `openTab(layout, tab, newId?)`, `insertTabAfter(layout, tab, anchor)`, `moveTab(layout, tab, paneId, index?)`, `splitPane(layout, tab, paneId, edge, newId?)`, `closeTab(layout, tab)`, `closePane(layout, paneId)`, `cycleTab(layout, direction)`, `resizeSplit(layout, splitId, sizes)`, `pruneTabs(layout, keep)` — all `=> Layout`, never mutating, returning the **same object** when nothing changes
  - `paneTouchesTop(layout, paneId): boolean`, `isTopLeftPane(layout, paneId): boolean`
  - `assertLayout(layout): void` (throws `Error("invalid split layout: …")`), `parseLayout(value: unknown): Layout | null`

- [ ] **Step 1: Write the failing example tests**

```ts
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/renderer/lib/split-layout.test.ts`
Expected: FAIL — `Failed to resolve import "./split-layout"`.

- [ ] **Step 3: Implement `split-layout.ts`**

```ts
export type TabRef =
	| { kind: "session"; sessionId: string }
	| { kind: "shell"; handleId: string; sessionId?: string }
	| { kind: "reviewer"; sessionId: string; handleId: string; harness: string };

export type SplitDirection = "row" | "column";
export type Edge = "left" | "right" | "top" | "bottom";
export type Pane = { type: "pane"; id: string; tabs: TabRef[]; activeTab: number };
export type Split = { type: "split"; id: string; direction: SplitDirection; children: LayoutNode[]; sizes: number[] };
export type LayoutNode = Pane | Split;
export type Layout = { root: LayoutNode | null; focusedPaneId: string | null };
export type NewId = () => string;

export const EMPTY_LAYOUT: Layout = { root: null, focusedPaneId: null };

const defaultId: NewId = () => crypto.randomUUID();

export function tabKey(tab: TabRef): string {
	switch (tab.kind) {
		case "session":
			return `session:${tab.sessionId}`;
		case "shell":
			return `shell:${tab.handleId}`;
		case "reviewer":
			return `reviewer:${tab.handleId}`;
	}
}

export function sameTab(left: TabRef, right: TabRef): boolean {
	return tabKey(left) === tabKey(right);
}

export function tabSessionId(tab: TabRef): string | undefined {
	return tab.sessionId;
}

export function listPanes(node: LayoutNode | null): Pane[] {
	if (!node) return [];
	if (node.type === "pane") return [node];
	return node.children.flatMap(listPanes);
}

export function findPane(layout: Layout, paneId: string | null): Pane | undefined {
	return paneId ? listPanes(layout.root).find((pane) => pane.id === paneId) : undefined;
}

export function paneOfTab(layout: Layout, tab: TabRef): Pane | undefined {
	return listPanes(layout.root).find((pane) => pane.tabs.some((candidate) => sameTab(candidate, tab)));
}

export function focusedPane(layout: Layout): Pane | undefined {
	return findPane(layout, layout.focusedPaneId);
}

export function activeTabOf(pane: Pane): TabRef {
	return pane.tabs[pane.activeTab];
}

function replacePane(node: LayoutNode, paneId: string, next: (pane: Pane) => LayoutNode | null): LayoutNode | null {
	if (node.type === "pane") return node.id === paneId ? next(node) : node;
	const children: LayoutNode[] = [];
	const sizes: number[] = [];
	node.children.forEach((child, index) => {
		const replaced = replacePane(child, paneId, next);
		if (!replaced) return;
		children.push(replaced);
		sizes.push(node.sizes[index]);
	});
	return { ...node, children, sizes };
}

function normalize(node: LayoutNode | null): LayoutNode | null {
	if (!node) return null;
	if (node.type === "pane") return node.tabs.length > 0 ? node : null;
	const children: LayoutNode[] = [];
	const sizes: number[] = [];
	node.children.forEach((child, index) => {
		const normalized = normalize(child);
		if (!normalized) return;
		const size = node.sizes[index];
		if (normalized.type === "split" && normalized.direction === node.direction) {
			normalized.children.forEach((grandchild, grandIndex) => {
				children.push(grandchild);
				sizes.push((size * normalized.sizes[grandIndex]) / 100);
			});
			return;
		}
		children.push(normalized);
		sizes.push(size);
	});
	if (children.length === 0) return null;
	if (children.length === 1) return children[0];
	const total = sizes.reduce((sum, size) => sum + size, 0);
	return { ...node, children, sizes: sizes.map((size) => (size * 100) / total) };
}

function finish(root: LayoutNode | null, focusedPaneId: string | null, fallbackIndex = 0): Layout {
	const normalized = normalize(root);
	const panes = listPanes(normalized);
	if (panes.length === 0) return EMPTY_LAYOUT;
	const focused =
		panes.find((pane) => pane.id === focusedPaneId) ?? panes[Math.max(0, Math.min(fallbackIndex, panes.length - 1))];
	return { root: normalized, focusedPaneId: focused.id };
}

function withoutTab(layout: Layout, tab: TabRef): LayoutNode | null {
	const pane = paneOfTab(layout, tab);
	if (!pane || !layout.root) return layout.root;
	const index = pane.tabs.findIndex((candidate) => sameTab(candidate, tab));
	const tabs = pane.tabs.filter((_, position) => position !== index);
	const activeTab = index < pane.activeTab ? pane.activeTab - 1 : Math.min(pane.activeTab, tabs.length - 1);
	return replacePane(layout.root, pane.id, () => ({ ...pane, tabs, activeTab: Math.max(0, activeTab) }));
}

export function focusPane(layout: Layout, paneId: string): Layout {
	if (layout.focusedPaneId === paneId || !findPane(layout, paneId)) return layout;
	return { ...layout, focusedPaneId: paneId };
}

export function focusTab(layout: Layout, tab: TabRef): Layout {
	const pane = paneOfTab(layout, tab);
	if (!pane || !layout.root) return layout;
	const index = pane.tabs.findIndex((candidate) => sameTab(candidate, tab));
	if (pane.activeTab === index && layout.focusedPaneId === pane.id) return layout;
	return { root: replacePane(layout.root, pane.id, () => ({ ...pane, activeTab: index })), focusedPaneId: pane.id };
}

export function moveTab(layout: Layout, tab: TabRef, paneId: string, index?: number): Layout {
	const source = paneOfTab(layout, tab);
	const sourceIndex = source ? source.tabs.findIndex((candidate) => sameTab(candidate, tab)) : -1;
	const root = source ? withoutTab(layout, tab) : layout.root;
	if (!root) return layout;
	const target = listPanes(root).find((pane) => pane.id === paneId);
	if (!target) return layout;
	let at = index ?? target.tabs.length + (source?.id === paneId ? 1 : 0);
	if (source?.id === paneId && sourceIndex < at) at -= 1;
	at = Math.max(0, Math.min(at, target.tabs.length));
	const tabs = [...target.tabs.slice(0, at), tab, ...target.tabs.slice(at)];
	return finish(
		replacePane(root, paneId, () => ({ ...target, tabs, activeTab: at })),
		paneId,
	);
}

export function openTab(layout: Layout, tab: TabRef, newId: NewId = defaultId): Layout {
	if (paneOfTab(layout, tab)) return focusTab(layout, tab);
	const target = focusedPane(layout) ?? listPanes(layout.root)[0];
	if (!target) {
		const pane: Pane = { type: "pane", id: newId(), tabs: [tab], activeTab: 0 };
		return { root: pane, focusedPaneId: pane.id };
	}
	return moveTab(layout, tab, target.id, target.activeTab + 1);
}

export function insertTabAfter(layout: Layout, tab: TabRef, anchor: TabRef): Layout {
	if (paneOfTab(layout, tab)) return layout;
	const pane = paneOfTab(layout, anchor);
	if (!pane || !layout.root) return layout;
	const anchorSession = tabSessionId(anchor);
	let at = pane.tabs.findIndex((candidate) => sameTab(candidate, anchor)) + 1;
	while (at < pane.tabs.length && pane.tabs[at].kind !== "session" && tabSessionId(pane.tabs[at]) === anchorSession) {
		at += 1;
	}
	const tabs = [...pane.tabs.slice(0, at), tab, ...pane.tabs.slice(at)];
	const activeTab = pane.activeTab >= at ? pane.activeTab + 1 : pane.activeTab;
	return { ...layout, root: replacePane(layout.root, pane.id, () => ({ ...pane, tabs, activeTab })) };
}

export function splitPane(layout: Layout, tab: TabRef, paneId: string, edge: Edge, newId: NewId = defaultId): Layout {
	const source = paneOfTab(layout, tab);
	if (source?.id === paneId && source.tabs.length === 1) return layout;
	const root = source ? withoutTab(layout, tab) : layout.root;
	if (!root) return layout;
	const target = listPanes(root).find((pane) => pane.id === paneId);
	if (!target) return layout;
	const pane: Pane = { type: "pane", id: newId(), tabs: [tab], activeTab: 0 };
	const first = edge === "left" || edge === "top";
	const split: Split = {
		type: "split",
		id: newId(),
		direction: edge === "left" || edge === "right" ? "row" : "column",
		children: first ? [pane, target] : [target, pane],
		sizes: [50, 50],
	};
	return finish(replacePane(root, paneId, () => split), pane.id);
}

export function closeTab(layout: Layout, tab: TabRef): Layout {
	const pane = paneOfTab(layout, tab);
	if (!pane) return layout;
	const order = listPanes(layout.root).map((candidate) => candidate.id);
	const focus = pane.tabs.length > 1 || layout.focusedPaneId !== pane.id ? layout.focusedPaneId : null;
	return finish(withoutTab(layout, tab), focus, order.indexOf(pane.id));
}

export function closePane(layout: Layout, paneId: string): Layout {
	if (!layout.root || !findPane(layout, paneId)) return layout;
	const order = listPanes(layout.root).map((pane) => pane.id);
	const focus = layout.focusedPaneId === paneId ? null : layout.focusedPaneId;
	return finish(replacePane(layout.root, paneId, () => null), focus, order.indexOf(paneId));
}

export function cycleTab(layout: Layout, direction: -1 | 1): Layout {
	const pane = focusedPane(layout);
	if (!pane || pane.tabs.length < 2 || !layout.root) return layout;
	const activeTab = (pane.activeTab + direction + pane.tabs.length) % pane.tabs.length;
	return { ...layout, root: replacePane(layout.root, pane.id, () => ({ ...pane, activeTab })) };
}

export function resizeSplit(layout: Layout, splitId: string, sizes: number[]): Layout {
	let changed = false;
	const visit = (node: LayoutNode): LayoutNode => {
		if (node.type === "pane") return node;
		if (node.id === splitId) {
			if (sizes.length !== node.children.length || sizes.some((size) => !(size > 0))) return node;
			const total = sizes.reduce((sum, size) => sum + size, 0);
			const next = sizes.map((size) => (size * 100) / total);
			if (next.every((size, index) => Math.abs(size - node.sizes[index]) < 0.001)) return node;
			changed = true;
			return { ...node, sizes: next };
		}
		return { ...node, children: node.children.map(visit) };
	};
	if (!layout.root) return layout;
	const root = visit(layout.root);
	return changed ? { ...layout, root } : layout;
}

export function pruneTabs(layout: Layout, keep: (tab: TabRef) => boolean): Layout {
	const panes = listPanes(layout.root);
	if (!layout.root || panes.every((pane) => pane.tabs.every(keep))) return layout;
	const visit = (node: LayoutNode): LayoutNode => {
		if (node.type === "split") return { ...node, children: node.children.map(visit) };
		const active = node.tabs[node.activeTab];
		const tabs = node.tabs.filter(keep);
		const kept = active ? tabs.findIndex((tab) => sameTab(tab, active)) : -1;
		return { ...node, tabs, activeTab: kept >= 0 ? kept : Math.min(node.activeTab, Math.max(0, tabs.length - 1)) };
	};
	const order = panes.map((pane) => pane.id);
	return finish(visit(layout.root), layout.focusedPaneId, Math.max(0, order.indexOf(layout.focusedPaneId ?? "")));
}

export function paneTouchesTop(layout: Layout, paneId: string): boolean {
	const visit = (node: LayoutNode, top: boolean): boolean => {
		if (node.type === "pane") return top && node.id === paneId;
		return node.children.some((child, index) => visit(child, top && (node.direction === "row" || index === 0)));
	};
	return layout.root ? visit(layout.root, true) : false;
}

export function isTopLeftPane(layout: Layout, paneId: string): boolean {
	let node = layout.root;
	while (node && node.type === "split") node = node.children[0];
	return node?.id === paneId;
}

export function assertLayout(layout: Layout): void {
	const seenTabs = new Set<string>();
	const seenIds = new Set<string>();
	const fail = (message: string): never => {
		throw new Error(`invalid split layout: ${message}`);
	};
	const visit = (node: LayoutNode, parent: SplitDirection | null) => {
		if (seenIds.has(node.id)) fail(`duplicate id ${node.id}`);
		seenIds.add(node.id);
		if (node.type === "pane") {
			if (node.tabs.length === 0) fail(`empty pane ${node.id}`);
			if (!Number.isInteger(node.activeTab) || node.activeTab < 0 || node.activeTab >= node.tabs.length) {
				fail(`active tab out of range in ${node.id}`);
			}
			for (const tab of node.tabs) {
				const key = tabKey(tab);
				if (seenTabs.has(key)) fail(`tab ${key} in two places`);
				seenTabs.add(key);
			}
			return;
		}
		if (node.children.length < 2) fail(`split ${node.id} has ${node.children.length} children`);
		if (node.direction === parent) fail(`split ${node.id} repeats its parent's direction`);
		if (node.sizes.length !== node.children.length) fail(`split ${node.id} sizes do not match children`);
		if (node.sizes.some((size) => !(size > 0))) fail(`split ${node.id} has a non-positive size`);
		if (Math.abs(node.sizes.reduce((sum, size) => sum + size, 0) - 100) > 0.01) fail(`split ${node.id} sizes do not sum to 100`);
		for (const child of node.children) visit(child, node.direction);
	};
	if (layout.root) visit(layout.root, null);
	if (layout.root === null ? layout.focusedPaneId !== null : !findPane(layout, layout.focusedPaneId)) {
		fail("focused pane missing");
	}
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null;
}

function isTab(value: unknown): value is TabRef {
	if (!isRecord(value)) return false;
	if (value.kind === "session") return typeof value.sessionId === "string";
	if (value.kind === "shell") {
		return typeof value.handleId === "string" && (value.sessionId === undefined || typeof value.sessionId === "string");
	}
	if (value.kind === "reviewer") {
		return typeof value.sessionId === "string" && typeof value.handleId === "string" && typeof value.harness === "string";
	}
	return false;
}

function isNode(value: unknown): value is LayoutNode {
	if (!isRecord(value) || typeof value.id !== "string") return false;
	if (value.type === "pane") {
		return Array.isArray(value.tabs) && value.tabs.every(isTab) && typeof value.activeTab === "number";
	}
	if (value.type === "split") {
		return (
			(value.direction === "row" || value.direction === "column") &&
			Array.isArray(value.children) &&
			value.children.every(isNode) &&
			Array.isArray(value.sizes) &&
			value.sizes.every((size) => typeof size === "number")
		);
	}
	return false;
}

export function parseLayout(value: unknown): Layout | null {
	if (!isRecord(value)) return null;
	const { root, focusedPaneId } = value;
	if (root !== null && !isNode(root)) return null;
	if (focusedPaneId !== null && typeof focusedPaneId !== "string") return null;
	const layout: Layout = { root: root as LayoutNode | null, focusedPaneId: focusedPaneId as string | null };
	try {
		assertLayout(layout);
		return layout;
	} catch {
		return null;
	}
}
```

- [ ] **Step 4: Run to verify the examples pass**

Run: `npx vitest run src/renderer/lib/split-layout.test.ts`
Expected: PASS (all example tests).

- [ ] **Step 5: Add the property test** — append to `split-layout.test.ts`:

```ts
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
```

Also add `tabKey` to the import list at the top of the file.

- [ ] **Step 6: Run the whole file**

Run: `npx vitest run src/renderer/lib/split-layout.test.ts`
Expected: PASS. If a seed fails, the message names the seed, step and last 12 operations; fix `split-layout.ts`, never the test.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/renderer/lib/split-layout.ts frontend/src/renderer/lib/split-layout.test.ts
git commit -m "feat(split): pure layout tree with checked invariants"
```

---

### Task 2: Drop resolution

**Files:**
- Create: `frontend/src/renderer/lib/split-drop.ts`
- Test: `frontend/src/renderer/lib/split-drop.test.ts`

**Interfaces:**
- Consumes: `Edge` from Task 1.
- Produces:
  - `type Rect = { left: number; top: number; width: number; height: number }`
  - `type PaneGeometry = { paneId: string; pane: Rect; strip: Rect; tabs: Rect[] }`
  - `type DraggedTab = { paneId: string | null; index: number | null; soleTab: boolean }`
  - `type DropResolution = { kind: "split"; paneId: string; edge: Edge; box: Rect } | { kind: "move"; paneId: string; index: number; box: Rect }`
  - `MIN_PANE_WIDTH = 320`, `MIN_PANE_HEIGHT = 200`, `CENTRE_FRACTION = 0.4`
  - `resolveDrop(pointer: { x: number; y: number }, geometry: PaneGeometry[], dragged: DraggedTab): DropResolution | null`
  - `sameResolution(a, b): boolean`

- [ ] **Step 1: Write the failing tests**

```ts
import { describe, expect, it } from "vitest";
import { resolveDrop, sameResolution, type PaneGeometry } from "./split-drop";

const pane: PaneGeometry = {
	paneId: "p1",
	pane: { left: 0, top: 0, width: 1000, height: 800 },
	strip: { left: 0, top: 0, width: 1000, height: 40 },
	tabs: [
		{ left: 0, top: 0, width: 100, height: 40 },
		{ left: 100, top: 0, width: 100, height: 40 },
	],
};
const outsider = { paneId: null, index: null, soleTab: false };

describe("resolveDrop", () => {
	it.each([
		["left", 100, 400, { left: 0, top: 0, width: 500, height: 800 }],
		["right", 900, 400, { left: 500, top: 0, width: 500, height: 800 }],
		["top", 500, 120, { left: 0, top: 0, width: 1000, height: 400 }],
		["bottom", 500, 780, { left: 0, top: 400, width: 1000, height: 400 }],
	] as const)("offers the %s half", (edge, x, y, box) => {
		expect(resolveDrop({ x, y }, [pane], outsider)).toEqual({ kind: "split", paneId: "p1", edge, box });
	});

	it("picks the nearer edge along the pane's diagonals", () => {
		expect(resolveDrop({ x: 150, y: 300 }, [pane], outsider)).toMatchObject({ edge: "left" });
		expect(resolveDrop({ x: 250, y: 60 }, [pane], outsider)).toMatchObject({ edge: "top" });
	});

	it("moves into the pane from its centre region", () => {
		expect(resolveDrop({ x: 500, y: 400 }, [pane], outsider)).toEqual({
			kind: "move",
			paneId: "p1",
			index: 2,
			box: pane.pane,
		});
	});

	it("computes the strip insertion index from tab midpoints", () => {
		expect(resolveDrop({ x: 40, y: 20 }, [pane], outsider)).toMatchObject({ kind: "move", index: 0 });
		expect(resolveDrop({ x: 160, y: 20 }, [pane], outsider)).toMatchObject({ kind: "move", index: 2 });
		expect(resolveDrop({ x: 120, y: 20 }, [pane], outsider)).toMatchObject({ kind: "move", index: 1 });
	});

	it("returns null for no-op drops of a tab on its own position or pane centre", () => {
		const own = { paneId: "p1", index: 0, soleTab: false };
		expect(resolveDrop({ x: 40, y: 20 }, [pane], own)).toBeNull();
		expect(resolveDrop({ x: 120, y: 20 }, [pane], own)).toBeNull();
		expect(resolveDrop({ x: 500, y: 400 }, [pane], own)).toBeNull();
		expect(resolveDrop({ x: 160, y: 20 }, [pane], own)).toMatchObject({ kind: "move", index: 2 });
	});

	it("never splits a pane by its own only tab", () => {
		expect(resolveDrop({ x: 900, y: 400 }, [pane], { paneId: "p1", index: 0, soleTab: true })).toBeNull();
	});

	it("refuses halves below the minimum pane size", () => {
		const narrow = { ...pane, pane: { left: 0, top: 0, width: 600, height: 380 } };
		expect(resolveDrop({ x: 590, y: 190 }, [narrow], outsider)).toBeNull();
		expect(resolveDrop({ x: 300, y: 370 }, [narrow], outsider)).toBeNull();
		const wide = { ...pane, pane: { left: 0, top: 0, width: 640, height: 400 } };
		expect(resolveDrop({ x: 630, y: 200 }, [wide], outsider)).toMatchObject({ edge: "right" });
		expect(resolveDrop({ x: 320, y: 390 }, [wide], outsider)).toMatchObject({ edge: "bottom" });
	});

	it("returns null outside every pane and resolves the pane under the pointer", () => {
		const second: PaneGeometry = { ...pane, paneId: "p2", pane: { left: 1000, top: 0, width: 1000, height: 800 }, strip: { left: 1000, top: 0, width: 1000, height: 40 }, tabs: [] };
		expect(resolveDrop({ x: 2500, y: 10 }, [pane, second], outsider)).toBeNull();
		expect(resolveDrop({ x: 1900, y: 400 }, [pane, second], outsider)).toMatchObject({ paneId: "p2", edge: "right" });
	});

	it("compares resolutions structurally", () => {
		const a = resolveDrop({ x: 900, y: 400 }, [pane], outsider);
		const b = resolveDrop({ x: 910, y: 410 }, [pane], outsider);
		expect(sameResolution(a, b)).toBe(true);
		expect(sameResolution(a, resolveDrop({ x: 100, y: 400 }, [pane], outsider))).toBe(false);
		expect(sameResolution(null, null)).toBe(true);
	});
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/renderer/lib/split-drop.test.ts`
Expected: FAIL — cannot resolve `./split-drop`.

- [ ] **Step 3: Implement `split-drop.ts`**

```ts
import type { Edge } from "./split-layout";

export type Rect = { left: number; top: number; width: number; height: number };
export type PaneGeometry = { paneId: string; pane: Rect; strip: Rect; tabs: Rect[] };
export type DraggedTab = { paneId: string | null; index: number | null; soleTab: boolean };
export type DropResolution =
	| { kind: "split"; paneId: string; edge: Edge; box: Rect }
	| { kind: "move"; paneId: string; index: number; box: Rect };

export const MIN_PANE_WIDTH = 320;
export const MIN_PANE_HEIGHT = 200;
export const CENTRE_FRACTION = 0.4;

function contains(rect: Rect, x: number, y: number): boolean {
	return x >= rect.left && x < rect.left + rect.width && y >= rect.top && y < rect.top + rect.height;
}

function moveTarget(paneId: string, index: number, box: Rect, dragged: DraggedTab): DropResolution | null {
	if (dragged.paneId === paneId && dragged.index !== null && (index === dragged.index || index === dragged.index + 1)) {
		return null;
	}
	return { kind: "move", paneId, index, box };
}

function halfBox(rect: Rect, edge: Edge): Rect {
	const halfWidth = rect.width / 2;
	const halfHeight = rect.height / 2;
	switch (edge) {
		case "left":
			return { left: rect.left, top: rect.top, width: halfWidth, height: rect.height };
		case "right":
			return { left: rect.left + halfWidth, top: rect.top, width: halfWidth, height: rect.height };
		case "top":
			return { left: rect.left, top: rect.top, width: rect.width, height: halfHeight };
		case "bottom":
			return { left: rect.left, top: rect.top + halfHeight, width: rect.width, height: halfHeight };
	}
}

export function resolveDrop(
	pointer: { x: number; y: number },
	geometry: PaneGeometry[],
	dragged: DraggedTab,
): DropResolution | null {
	const target = geometry.find((candidate) => contains(candidate.pane, pointer.x, pointer.y));
	if (!target) return null;
	const { pane, paneId } = target;
	if (contains(target.strip, pointer.x, pointer.y)) {
		const index = target.tabs.filter((tab) => tab.left + tab.width / 2 < pointer.x).length;
		return moveTarget(paneId, index, pane, dragged);
	}
	const u = (pointer.x - pane.left) / pane.width - 0.5;
	const v = (pointer.y - pane.top) / pane.height - 0.5;
	if (Math.abs(u) <= CENTRE_FRACTION / 2 && Math.abs(v) <= CENTRE_FRACTION / 2) {
		if (dragged.paneId === paneId) return null;
		return moveTarget(paneId, target.tabs.length, pane, dragged);
	}
	if (dragged.paneId === paneId && dragged.soleTab) return null;
	const edge: Edge = Math.abs(u) >= Math.abs(v) ? (u < 0 ? "left" : "right") : v < 0 ? "top" : "bottom";
	const sideways = edge === "left" || edge === "right";
	if (sideways ? pane.width / 2 < MIN_PANE_WIDTH : pane.height / 2 < MIN_PANE_HEIGHT) return null;
	return { kind: "split", paneId, edge, box: halfBox(pane, edge) };
}

export function sameResolution(left: DropResolution | null, right: DropResolution | null): boolean {
	if (left === null || right === null) return left === right;
	if (left.kind !== right.kind || left.paneId !== right.paneId) return false;
	if (left.kind === "split" && right.kind === "split") return left.edge === right.edge;
	if (left.kind === "move" && right.kind === "move") return left.index === right.index;
	return false;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `npx vitest run src/renderer/lib/split-drop.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/renderer/lib/split-drop.ts frontend/src/renderer/lib/split-drop.test.ts
git commit -m "feat(split): geometric drop resolution"
```

---

### Task 3: Persisted layout store

**Files:**
- Create: `frontend/src/renderer/stores/split-layout-store.ts`
- Test: `frontend/src/renderer/stores/split-layout-store.test.ts`

**Interfaces:**
- Consumes: Task 1 operations.
- Produces: `useSplitLayoutStore` (zustand) with state `{ layout: Layout }` and actions `openTab(tab)`, `focusTab(tab)`, `focusPane(paneId)`, `insertTabAfter(tab, anchor)`, `moveTab(tab, paneId, index?)`, `splitPane(tab, paneId, edge)`, `closeTab(tab)`, `closePane(paneId)`, `cycleTab(direction)`, `resizeSplit(splitId, sizes)`, `pruneTabs(keep)`; plus `SPLIT_LAYOUT_STORAGE_KEY = "opr.splitLayout.v1"` and `loadStoredLayout(): Layout`.

- [ ] **Step 1: Write the failing tests**

```ts
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/renderer/stores/split-layout-store.test.ts`
Expected: FAIL — cannot resolve `./split-layout-store`.

- [ ] **Step 3: Implement the store**

```ts
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `npx vitest run src/renderer/stores/split-layout-store.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/renderer/stores/split-layout-store.ts frontend/src/renderer/stores/split-layout-store.test.ts
git commit -m "feat(split): persisted layout store"
```

---

### Task 4: Terminal cache with one live terminal per pane

Read TERMINAL.md end to end first. This changes only `frontend/src/renderer/components/TerminalPane.tsx` and `BlockTerminal.tsx`; `packages/terminal` is untouched.

**Files:**
- Modify: `frontend/src/renderer/components/TerminalPane.tsx` (types at 45–79, provider at 296–603, `AttachedTerminal` focus effect at 901–905, `<BlockTerminal>` at 1002–1014)
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx` (props at 40–67, `onGeometry` at 252–258)
- Test: `frontend/src/renderer/components/TerminalPane.test.tsx`

**Interfaces:**
- Produces: `TerminalPaneProps.focused?: boolean` (default `true`). A pane with `focused={false}` shows and streams but never takes keyboard focus and never records the spawn grid. `BlockTerminalProps.recordsSpawnGrid?: boolean` (default `true`).

- [ ] **Step 1: Write the failing tests** — append to `TerminalPane.test.tsx`. First extend the `BlockTerminal` mock (line 65) to render `data-records-spawn-grid={String(props.recordsSpawnGrid ?? true)}` and add `recordsSpawnGrid?: boolean` to its props type. Then add:

```tsx
function renderSplitPanes(sessions: WorkspaceSession[]) {
	const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	queryClient.setQueryData(workspaceQueryKey, workspaceWithSessions(sessions));
	queryClient.setQueryData(shellTerminalsQueryKey, []);
	const previousAO = window.operator;
	window.operator = {} as typeof window.operator;
	const tree = (left: WorkspaceSession, right: WorkspaceSession, focusedRight = false) => (
		<QueryClientProvider client={queryClient}>
			<TerminalCacheProvider daemonReady theme="dark">
				<div data-testid="pane-left">
					<TerminalPane daemonReady fontSize={12} session={left} theme="dark" focused={!focusedRight} />
				</div>
				<div data-testid="pane-right">
					<TerminalPane daemonReady fontSize={12} session={right} theme="dark" focused={focusedRight} />
				</div>
			</TerminalCacheProvider>
		</QueryClientProvider>
	);
	const [first, second] = sessions;
	const result = render(tree(first, second));
	return {
		show: (left: WorkspaceSession, right: WorkspaceSession, focusedRight = false) =>
			result.rerender(tree(left, right, focusedRight)),
		restore: () => {
			window.operator = previousAO;
		},
	};
}

function attachmentIn(testId: string): HTMLElement | null {
	return screen.getByTestId(testId).querySelector('[data-testid="terminal-attachment"]');
}

describe("TerminalCacheProvider with several panes", () => {
	const a = { ...worker, id: "sess-a", title: "A", terminalHandleId: "handle-a" };
	const b = { ...worker, id: "sess-b", title: "B", terminalHandleId: "handle-b" };
	const c = { ...worker, id: "sess-c", title: "C", terminalHandleId: "handle-c" };

	it("keeps two terminals live side by side", async () => {
		const view = renderSplitPanes([a, b, c]);
		try {
			await waitFor(() => expect(attachmentIn("pane-left")).not.toBeNull());
			await waitFor(() => expect(attachmentIn("pane-right")).not.toBeNull());
			expect(screen.getByTestId("terminal-cache-parking").querySelector('[data-testid="terminal-attachment"]')).toBeNull();
		} finally {
			view.restore();
		}
	});

	it("parks only the terminal its own slot replaced", async () => {
		const view = renderSplitPanes([a, b, c]);
		try {
			const left = await waitFor(() => attachmentIn("pane-left") as HTMLElement);
			view.show(a, c);
			await waitFor(() =>
				expect(
					screen.getByTestId("pane-right").querySelector('[data-terminal-cache-key^="session:sess-c:worker|"]'),
				).not.toBeNull(),
			);
			expect(attachmentIn("pane-left")).toBe(left);
			expect(
				screen.getByTestId("terminal-cache-parking").querySelector('[data-terminal-cache-key^="session:sess-b:worker|"]'),
			).not.toBeNull();
		} finally {
			view.restore();
		}
	});

	it("moves a terminal between panes without remounting it", async () => {
		const view = renderSplitPanes([a, b, c]);
		try {
			const moving = await waitFor(() => attachmentIn("pane-right") as HTMLElement);
			view.show(b, c);
			await waitFor(() => expect(attachmentIn("pane-left")).toBe(moving));
			expect(attachmentUnmounts.value).toBe(0);
		} finally {
			view.restore();
		}
	});

	it("focuses only the focused pane and moves focus with it", async () => {
		const view = renderSplitPanes([a, b]);
		try {
			const token = (testId: string) =>
				screen.getByTestId(testId).querySelector("[data-testid=block-terminal]")?.getAttribute("data-focus-token");
			const records = (testId: string) =>
				screen.getByTestId(testId).querySelector("[data-testid=block-terminal]")?.getAttribute("data-records-spawn-grid");
			await waitFor(() => expect(token("pane-left")).toBe("1"));
			expect(token("pane-right")).toBeNull();
			expect(records("pane-left")).toBe("true");
			expect(records("pane-right")).toBe("false");
			view.show(a, b, true);
			await waitFor(() => expect(token("pane-right")).toBe("1"));
			expect(token("pane-left")).toBe("1");
			expect(records("pane-right")).toBe("true");
		} finally {
			view.restore();
		}
	});
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/renderer/components/TerminalPane.test.tsx`
Expected: the four new tests FAIL (second slot parks the first; `focused` is ignored). All existing tests PASS.

- [ ] **Step 3: Replace the single active slot with a slot map** in `TerminalPane.tsx`:

  1. Delete `type ActiveTerminalEntry` (lines 76–79).
  2. Add `focused?: boolean;` to `TerminalPaneProps` after `focusRequested`, and `left.focused === right.focused &&` to `terminalPropsMatch`.
  3. In `TerminalCacheProvider`, replace `const activeRef = useRef<ActiveTerminalEntry | null>(null);` with `const activeSlotsRef = useRef(new Map<string, HTMLDivElement>());`.
  4. `removeEntry`: replace the `activeRef` block with:

```ts
			if (activeSlotsRef.current.has(cacheKey)) {
				blurTerminal(entry.container);
				setTerminalPhase(entry, "parked");
				activeSlotsRef.current.delete(cacheKey);
			}
```

  5. `activate`: replace the `const previous = activeRef.current; …` block with:

```ts
			const slots = activeSlotsRef.current;
			for (const [key, activeSlot] of [...slots]) {
				if (activeSlot !== slot || key === descriptor.cacheKey) continue;
				const previousEntry = entriesRef.current.get(key);
				if (previousEntry) parkTerminal(previousEntry, parking);
				slots.delete(key);
			}
			const elsewhere = slots.get(descriptor.cacheKey);
			if (elsewhere && elsewhere !== slot && import.meta.env.DEV) {
				console.error(`terminal ${descriptor.cacheKey} activated in a second pane`);
			}
```

  In the owner-generation loop replace `if (activeRef.current?.key === entry.cacheKey) parkTerminal(entry, parking);` with:

```ts
					if (slots.has(entry.cacheKey)) {
						parkTerminal(entry, parking);
						slots.delete(entry.cacheKey);
					}
```

  and replace `activeRef.current = { key: entry.cacheKey, slot };` with `slots.set(entry.cacheKey, slot);`.

  6. `deactivate`: replace its first three lines with

```ts
			if (activeSlotsRef.current.get(cacheKey) !== slot) return;
			const entry = entriesRef.current.get(cacheKey);
			const parking = parkingRef.current;
			activeSlotsRef.current.delete(cacheKey);
```

  7. In `markPrepared`, `markReveal`, `markActivated` replace `activeRef.current?.key !== cacheKey` with `!activeSlotsRef.current.has(cacheKey)`.
  8. Unmount cleanup: replace `activeRef.current = null;` with `activeSlotsRef.current.clear();`.
  9. Portal list: `active={activeSlotsRef.current.has(entry.cacheKey)}`.

- [ ] **Step 4: Thread `focused`** through `TerminalPane` → `AttachedTerminal` → `BlockTerminal`:

  - `TerminalPane`: destructure `focused` and include it in `props` (the object passed to `CachedTerminalSlot`) and in the uncached `<AttachedTerminal focused={focused} …>`.
  - `AttachedTerminal`: destructure `focused`, change the focus effect to

```ts
	useLayoutEffect(() => {
		if (!isVisible || focused === false) return;
		setFocusToken((token) => (token ?? 0) + 1);
	}, [focusRequested, focused, isVisible]);
```

  and pass `recordsSpawnGrid={focused !== false}` to `<BlockTerminal>`.
  - `BlockTerminal.tsx`: add `recordsSpawnGrid?: boolean;` to `BlockTerminalProps`, destructure `recordsSpawnGrid = true`, add `const recordsSpawnGridRef = useRef(recordsSpawnGrid); recordsSpawnGridRef.current = recordsSpawnGrid;` beside `historyBlocksRef`, and in `onGeometry` replace `rememberPaneGrid(columns, rows);` with `if (recordsSpawnGridRef.current) rememberPaneGrid(columns, rows);`.

- [ ] **Step 5: Run the terminal tests**

Run: `npx vitest run src/renderer/components/TerminalPane.test.tsx src/renderer/components/BlockTerminal.test.tsx`
Expected: PASS, including every pre-existing cache test (single-pane behaviour is unchanged).

- [ ] **Step 6: Full suite and types**

Run: `npx vitest run && npx tsc --noEmit -p tsconfig.json`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/renderer/components/TerminalPane.tsx frontend/src/renderer/components/TerminalPane.test.tsx frontend/src/renderer/components/BlockTerminal.tsx
git commit -m "feat(terminal): one live retained terminal per pane"
```

---

### Task 5: Pane building blocks

Moves the tab and terminal pieces out of `CenterPane.tsx` into `components/split/` so a pane can render them; `CenterPane` imports them back so nothing changes on screen yet.

**Files:**
- Create: `frontend/src/renderer/components/split/SessionPaneTab.tsx`, `PaneTerminal.tsx`, `PaneTabStrip.tsx`, `SplitPane.tsx`, `pane-registry.ts`, `useSplitTabDraggable.ts`, `frontend/src/renderer/hooks/useSessionReviewer.ts`
- Modify: `frontend/src/renderer/components/CenterPane.tsx`, `frontend/src/renderer/components/SessionView.tsx`, `frontend/src/renderer/i18n/en.json`
- Test: `frontend/src/renderer/components/split/PaneTabStrip.test.tsx`, `frontend/src/renderer/components/split/SplitPane.test.tsx`

**Interfaces:**
- Consumes: Task 1 types; `TerminalPane` `focused` prop (Task 4).
- Produces:
  - `SessionPaneTab` props `{ label: string; isActive: boolean; onSelect?: () => void; session?: WorkspaceSession; icon?: ReactNode; title?: string; onClose?: () => void }` (unchanged from `CenterPane.tsx`)
  - `PaneTerminal({ session, target, theme, daemonReady, focused }: { session?: WorkspaceSession; target: TerminalTarget; theme: Theme; daemonReady: boolean; focused: boolean })`
  - `PaneTabStrip({ pane, sessions, shells, onSelect, onClose, onRenameShell }: { pane: Pane; sessions: Map<string, WorkspaceSession>; shells: Map<string, ShellTerminal>; onSelect: (tab: TabRef) => void; onClose: (tab: TabRef) => void; onRenameShell: (handleId: string, title: string) => void })`
  - `SplitPane` props in Step 6
  - `registerPaneElement(paneId: string, part: "pane" | "strip", element: HTMLElement | null): void`, `readPaneGeometry(paneIds: string[]): PaneGeometry[]`
  - `useSplitTabDraggable(tab: TabRef, label: string, origin: "strip" | "sidebar")` → `{ setNodeRef, listeners, isDragging }`; drag data shape `{ splitTab: { tab: TabRef; label: string } }`
  - `useSessionReviewer(session?: WorkspaceSession): { handleId: string; harness: string } | undefined`
  - `terminalTargetForTab(tab: TabRef, shell?: ShellTerminal): TerminalTarget` (exported from `PaneTerminal.tsx`)

- [ ] **Step 1: i18n keys** — add to `en.json` beside the `terminal.*` keys (keep the file's alphabetical order):

```json
	"split.closePane": "Close pane",
	"split.openHere": "Open here",
	"split.openInSplitView": "Open in split view",
	"split.splitView": "Split view",
```

- [ ] **Step 2: Move `SessionPaneTab`** — cut `type SessionPaneTabProps` and `function SessionPaneTab` (the whole block from `type SessionPaneTabProps = {` to the end of the file) out of `CenterPane.tsx` into `components/split/SessionPaneTab.tsx`, exported, with its imports (`useTranslation`, `useTruncatedText`, `getAgentActivityView`, `cn`, `AgentAvatar`, `SessionAgentTabMenu`, `X`, `ReactNode`, `WorkspaceSession`). Delete the explanatory comment above it (no comments). In `CenterPane.tsx` add `import { SessionPaneTab } from "./split/SessionPaneTab";` and drop the now-unused imports.

- [ ] **Step 3: Move the terminal body** — create `components/split/PaneTerminal.tsx` containing:
  - `AgentSwitchTerminalOverlay` and `SwitchingAgentMark`, moved verbatim from `CenterPane.tsx` (comments removed);
  - the agent-switch derivations from `CenterPane` (`useAgentSwitches` … `switchPermissionRequired`, and the refetch-interval `useEffect`);
  - this component and helper:

```tsx
export function terminalTargetForTab(tab: TabRef, shell?: ShellTerminal): TerminalTarget {
	if (tab.kind === "shell") {
		return {
			kind: "shell",
			handleId: tab.handleId,
			sessionId: tab.sessionId,
			title: shell?.title ?? "",
			generation: shell?.createdAt ?? "",
		};
	}
	if (tab.kind === "reviewer") {
		return { kind: "reviewer", handleId: tab.handleId, harness: tab.harness, sessionId: tab.sessionId };
	}
	return { kind: "worker" };
}

export function PaneTerminal({
	session,
	target,
	theme,
	daemonReady,
	focused,
}: {
	session?: WorkspaceSession;
	target: TerminalTarget;
	theme: Theme;
	daemonReady: boolean;
	focused: boolean;
}) {
	const { t } = useTranslation();
	const fontSize = useUiStore((state) => state.terminalFontSize);
	const label =
		target.kind === "reviewer"
			? `${t("terminal.reviewer")} · ${target.harness}`
			: target.kind === "shell"
				? target.title
				: (session?.title ?? t("terminal.noSession"));
	return (
		<div aria-label={t("terminal.panelAria", { title: label })} className="relative min-h-0 flex-1" role="tabpanel">
			<div
				className="h-full min-h-0"
				data-testid="terminal-interaction-surface"
				inert={(isSwitchingAgent || switchNeedsRecovery) && !switchPermissionRequired ? true : undefined}
			>
				<TerminalPane
					daemonReady={daemonReady}
					focused={focused}
					fontSize={fontSize}
					focusRequested={switchPermissionRequired && target.kind === "worker"}
					session={session}
					terminalTarget={target}
					theme={theme}
				/>
			</div>
			{(isSwitchingAgent || switchNeedsRecovery) && switchSource && switchTarget ? (
				<AgentSwitchTerminalOverlay
					permissionRequired={switchPermissionRequired}
					recoveryRequired={switchNeedsRecovery}
					source={switchSource}
					target={switchTarget}
				/>
			) : null}
		</div>
	);
}
```

  (the agent-switch derivations go at the top of `PaneTerminal`'s body, keyed on `session?.id ?? ""`, exactly as they are in `CenterPane` today). Replace the `role="tabpanel"` block in `CenterPane` with `<PaneTerminal daemonReady={daemonReady} focused session={session} target={target} theme={theme} />` and delete the moved derivations from `CenterPane`.

- [ ] **Step 4: Reviewer hook** — move `reviewerTerminalFromReviews` and the `reviewerQuery` `useQuery` out of `SessionView.tsx` into `hooks/useSessionReviewer.ts`:

```ts
export function useSessionReviewer(session?: WorkspaceSession): { handleId: string; harness: string } | undefined {
	const sessionId = session?.id ?? "";
	const query = useQuery({
		queryKey: ["session-reviews", sessionId],
		enabled: Boolean(nativeShellBridgePresent() && session && sessionIsActive(session) && session.prs.length > 0),
		refetchInterval: (current) => {
			const data = current.state.data as ReviewsResponse | undefined;
			return data?.reviews?.some((review) => review.status === "running") ? 2500 : false;
		},
		queryFn: async () => {
			const { data, error } = await apiClient.GET("/api/v1/sessions/{sessionId}/reviews", {
				params: { path: { sessionId } },
			});
			if (error) throw new Error(apiErrorMessage(error, "Unable to load reviews"));
			return data ?? ({ reviewerHandleId: "", reviews: [], runs: [] } satisfies ReviewsResponse);
		},
	});
	return session && sessionIsActive(session) ? reviewerTerminalFromReviews(query.data) : undefined;
}
```

  In `SessionView.tsx` replace the moved code with `const reviewerTerminal = useSessionReviewer(session);` and keep `availableReviewerTerminal` semantics by using `reviewerTerminal` where `availableReviewerTerminal` was read. Run `npx vitest run src/renderer/components/SessionView.test.tsx` — PASS.

- [ ] **Step 5: Registry and draggable hook**

`components/split/pane-registry.ts`:

```ts
import type { PaneGeometry, Rect } from "../../lib/split-drop";

const elements = new Map<string, { pane: HTMLElement | null; strip: HTMLElement | null }>();

export function registerPaneElement(paneId: string, part: "pane" | "strip", element: HTMLElement | null): void {
	const entry = elements.get(paneId) ?? { pane: null, strip: null };
	entry[part] = element;
	if (!entry.pane && !entry.strip) elements.delete(paneId);
	else elements.set(paneId, entry);
}

function toRect(rect: DOMRect): Rect {
	return { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
}

export function readPaneGeometry(paneIds: string[]): PaneGeometry[] {
	return paneIds.flatMap((paneId) => {
		const entry = elements.get(paneId);
		if (!entry?.pane || !entry.strip) return [];
		const tabs = [...entry.strip.querySelectorAll<HTMLElement>("[data-split-tab]")].map((tab) =>
			toRect(tab.getBoundingClientRect()),
		);
		return [{ paneId, pane: toRect(entry.pane.getBoundingClientRect()), strip: toRect(entry.strip.getBoundingClientRect()), tabs }];
	});
}
```

`components/split/useSplitTabDraggable.ts`:

```ts
import { useDraggable } from "@dnd-kit/core";
import { tabKey, type TabRef } from "../../lib/split-layout";

export type SplitTabDragData = { splitTab: { tab: TabRef; label: string } };

export function isSplitTabDragData(value: unknown): value is SplitTabDragData {
	return typeof value === "object" && value !== null && "splitTab" in value;
}

export function useSplitTabDraggable(tab: TabRef, label: string, origin: "strip" | "sidebar") {
	const { setNodeRef, listeners, isDragging } = useDraggable({
		id: `split-tab:${origin}:${tabKey(tab)}`,
		data: { splitTab: { tab, label } } satisfies SplitTabDragData,
	});
	return { setNodeRef, listeners, isDragging };
}
```

- [ ] **Step 6: `PaneTabStrip` and `SplitPane`** — write the failing tests first.

`components/split/PaneTabStrip.test.tsx` (wrap renders in `DndContext` from `@dnd-kit/core` and `TooltipProvider`; mock `./SessionPaneTab`'s menu dependencies the same way `CenterPane.test.tsx` mocks `useRelaunchAgent` and `useClaudeAccounts`, and mock `../../hooks/useSwitchAgentAction` as in `CenterPane.test.tsx`):

```tsx
const a: WorkspaceSession = { id: "a", workspaceId: "p", workspaceName: "app", title: "alpha", provider: "claude-code", status: "working", updatedAt: "2026-09-22T00:00:00Z", prs: [] };
const shell: ShellTerminal = { handleId: "h1", sessionId: "a", workingDir: "/tmp", title: "zsh", createdAt: "2026-09-22T00:00:00Z" };
const pane: Pane = {
	type: "pane",
	id: "p1",
	tabs: [{ kind: "session", sessionId: "a" }, { kind: "shell", handleId: "h1", sessionId: "a" }],
	activeTab: 0,
};

it("renders a draggable tab per TabRef and routes select and close", () => {
	const onSelect = vi.fn();
	const onClose = vi.fn();
	renderStrip({ pane, onSelect, onClose });
	expect(document.querySelectorAll("[data-split-tab]")).toHaveLength(2);
	expect(screen.getByRole("tab", { name: /alpha/ })).toHaveAttribute("aria-selected", "true");
	fireEvent.click(screen.getByRole("tab", { name: "zsh" }));
	expect(onSelect).toHaveBeenCalledWith(pane.tabs[1]);
	fireEvent.click(screen.getByRole("button", { name: "Close alpha" }));
	expect(onClose).toHaveBeenCalledWith(pane.tabs[0]);
});

it("labels a tab whose session is gone as having no session", () => {
	renderStrip({ pane: { ...pane, tabs: [{ kind: "session", sessionId: "gone" }] } });
	expect(screen.getByRole("tab", { name: "No session" })).toBeInTheDocument();
});
```

(`renderStrip` renders `<PaneTabStrip pane={…} sessions={new Map([["a", a]])} shells={new Map([["h1", shell]])} onSelect={…} onClose={…} onRenameShell={vi.fn()} />`; check the exact `terminal.noSession` string in `en.json` and use it.)

`PaneTabStrip.tsx`:

```tsx
export function PaneTabStrip({ pane, sessions, shells, onSelect, onClose, onRenameShell }: PaneTabStripProps) {
	const { t } = useTranslation();
	const overflow = useOverflowScroll<HTMLDivElement>(pane.tabs.map(tabKey).join(","));
	return (
		<div className="flex h-full min-w-flex-min flex-1 items-center">
			{overflow.canScrollLeft ? (
				<ScrollChevron direction={-1} label={t("terminal.scrollTabsLeft")} onClick={() => overflow.scrollByDirection(-1)} />
			) : null}
			<div
				ref={overflow.ref}
				aria-label={t("terminal.tabsAria")}
				className="scrollbar-none flex min-w-flex-min shrink self-stretch items-center overflow-x-auto"
				onKeyDown={handleTerminalTabListKeyDown}
				role="tablist"
			>
				{pane.tabs.map((tab, index) => (
					<DraggableTab key={tabKey(tab)} label={tabLabel(tab, sessions, shells, t)} tab={tab}>
						{renderTab(tab, index === pane.activeTab)}
					</DraggableTab>
				))}
			</div>
			{overflow.canScrollRight ? (
				<ScrollChevron direction={1} label={t("terminal.scrollTabsRight")} onClick={() => overflow.scrollByDirection(1)} />
			) : null}
		</div>
	);
}
```

  where:
  - `ScrollChevron` is the chevron `<button>` markup moved verbatim from `CenterPane` (class list unchanged), rendering `ChevronLeft`/`ChevronRight` by `direction`;
  - `DraggableTab` is

```tsx
function DraggableTab({ tab, label, children }: { tab: TabRef; label: string; children: ReactNode }) {
	const { setNodeRef, listeners, isDragging } = useSplitTabDraggable(tab, label, "strip");
	return (
		<div ref={setNodeRef} className={cn("flex self-stretch", isDragging && "opacity-50")} data-split-tab="" {...listeners}>
			{children}
		</div>
	);
}
```

  - `renderTab(tab, isActive)` passes `isActive={isActive}` to every tab and returns: for `session` → `<SessionPaneTab isActive={isActive} label={session?.title ?? t("terminal.noSession")} onClose={() => onClose(tab)} onSelect={() => onSelect(tab)} session={session} />`; for `shell` → `<ShellTerminalTab appearance="connected" isActive={isActive} onClose={() => onClose(tab)} onRename={(title) => onRenameShell(tab.handleId, title)} onSelect={() => onSelect(tab)} shell={shell} />` (skip the tab when the shell is not in `shells`, since prune will drop it); for `reviewer` → `<SessionPaneTab icon={<AgentAvatar className="size-icon-base" decorative provider={tab.harness} />} isActive={isActive} label={t("terminal.reviewer")} onSelect={() => onSelect(tab)} title={tab.harness} />`.
  - `tabLabel` returns the session title, shell title, or `t("terminal.reviewer")`.

`SplitPane.tsx` props and markup:

```tsx
type SplitPaneProps = {
	pane: Pane;
	focused: boolean;
	showFocusRing: boolean;
	touchesTop: boolean;
	topLeft: boolean;
	sessions: Map<string, WorkspaceSession>;
	shells: Map<string, ShellTerminal>;
	theme: Theme;
	daemonReady: boolean;
	onFocus: () => void;
	onSelect: (tab: TabRef) => void;
	onClose: (tab: TabRef) => void;
	onClosePane: () => void;
	onRenameShell: (handleId: string, title: string) => void;
};

export function SplitPane(props: SplitPaneProps) {
	const { t } = useTranslation();
	const isSidebarOpen = useUiStore((state) => state.isSidebarOpen);
	const tab = activeTabOf(props.pane);
	const sessionId = tabSessionId(tab);
	const session = sessionId ? props.sessions.get(sessionId) : undefined;
	const shell = tab.kind === "shell" ? props.shells.get(tab.handleId) : undefined;
	return (
		<section
			ref={(element) => registerPaneElement(props.pane.id, "pane", element)}
			className="relative flex h-full min-h-0 min-w-0 flex-col bg-background"
			data-split-pane={props.pane.id}
			onFocusCapture={props.onFocus}
			onPointerDownCapture={props.onFocus}
		>
			<header
				ref={(element) => registerPaneElement(props.pane.id, "strip", element)}
				className={cn(
					"flex h-inspector-tabs w-full shrink-0 items-stretch bg-sidebar",
					props.topLeft && !isSidebarOpen && isMac && "session-topbar-titlebar-clearance-mac",
					props.topLeft && !isSidebarOpen && isLinux && "session-topbar-titlebar-clearance-linux",
				)}
				data-tauri-drag-region={props.touchesTop ? dragRegion : undefined}
			>
				<PaneTabStrip
					onClose={props.onClose}
					onRenameShell={props.onRenameShell}
					onSelect={props.onSelect}
					pane={props.pane}
					sessions={props.sessions}
					shells={props.shells}
				/>
				<div className="ml-auto flex shrink-0 items-center gap-1.5 px-3">
					{session ? <PaneSessionActions session={session} onFocus={props.onFocus} /> : null}
					<TopbarButton
						aria-label={t("split.closePane")}
						onClick={props.onClosePane}
						title={t("split.closePane")}
						variant="icon"
					>
						<X aria-hidden="true" className="size-icon-md" />
					</TopbarButton>
				</div>
			</header>
			<PaneTerminal
				daemonReady={props.daemonReady}
				focused={props.focused}
				session={session}
				target={terminalTargetForTab(tab, shell)}
				theme={props.theme}
			/>
			{props.showFocusRing ? (
				<div aria-hidden="true" className="pointer-events-none absolute inset-0 z-10 rounded-lg border border-accent/60" />
			) : null}
		</section>
	);
}
```

  - `isMac`, `isLinux`, `dragRegion` come from `lib/platform` exactly as `CenterPane` computes them.
  - `TopbarButton` is the same component `ShellTopbar.tsx` imports; import it from where `ShellTopbar.tsx` does.
  - `PaneSessionActions` renders the Claude account menu and inspector toggle from `ShellTopbar.tsx:94-116`, but reads `session` from props instead of route params. The inspector toggle calls `onFocus()` first, then `toggleInspector(session.id)`, and reads `isOpen` via `inspectorState(state.inspectorSessions, session.id)`.

`SplitPane.test.tsx` (mock `./PaneTerminal` to `<div data-testid="pane-terminal" data-focused={String(focused)} data-target={target.kind} />` and `./PaneTabStrip` to a stub):

```tsx
it("focuses on pointer down, renders the ring only when asked, and closes the pane", () => {
	const onFocus = vi.fn();
	const onClosePane = vi.fn();
	const { rerender } = renderPane({ onFocus, onClosePane, showFocusRing: false });
	fireEvent.pointerDown(screen.getByTestId("pane-terminal"));
	expect(onFocus).toHaveBeenCalled();
	expect(document.querySelector(".border-accent\\/60")).toBeNull();
	rerender(paneTree({ onFocus, onClosePane, showFocusRing: true }));
	expect(document.querySelector(".border-accent\\/60")).not.toBeNull();
	fireEvent.click(screen.getByRole("button", { name: "Close pane" }));
	expect(onClosePane).toHaveBeenCalled();
});

it("hands the active tab's target to the terminal", () => {
	renderPane({ pane: { ...basePane, activeTab: 1 } });
	expect(screen.getByTestId("pane-terminal")).toHaveAttribute("data-target", "shell");
});
```

- [ ] **Step 7: Run**

Run: `npx vitest run src/renderer/components/split src/renderer/components/CenterPane.test.tsx src/renderer/components/SessionView.test.tsx && npx tsc --noEmit -p tsconfig.json`
Expected: PASS. `CenterPane` renders the same DOM as before (its tests are unchanged and green).

- [ ] **Step 8: Commit**

```bash
git add frontend/src/renderer/components/split frontend/src/renderer/hooks/useSessionReviewer.ts frontend/src/renderer/components/CenterPane.tsx frontend/src/renderer/components/SessionView.tsx frontend/src/renderer/i18n/en.json
git commit -m "refactor(split): pane tab strip, pane terminal and pane shell"
```

---

### Task 6: SplitWorkspace replaces the single pane

**Files:**
- Create: `frontend/src/renderer/components/split/SplitWorkspace.tsx`, `frontend/src/renderer/components/split/SessionCompanions.tsx`
- Modify: `frontend/src/renderer/components/SessionView.tsx`, `frontend/src/renderer/routes/_shell.tsx` (the three `SessionTopbarHost` blocks at 641–651, 653–666, 668–680), `frontend/src/renderer/stores/ui-store.ts`
- Delete: `frontend/src/renderer/components/CenterPane.tsx`, `CenterPane.test.tsx`, `frontend/src/renderer/components/SessionTopbarPortal.tsx`
- Test: `frontend/src/renderer/components/split/SplitWorkspace.test.tsx`; update `SessionView.test.tsx`

**Interfaces:**
- Consumes: Tasks 1, 3, 5.
- Produces: `SplitWorkspace({ routeSessionId }: { routeSessionId: string })`; `SessionCompanions({ session }: { session: WorkspaceSession })`.

- [ ] **Step 1: Write the failing `SplitWorkspace` tests.** Mock `@tanstack/react-router` (`useNavigate` → `navigateMock`), `../../hooks/useWorkspaceQuery` (two projects, sessions `a`,`b` in `proj-1`, `c` in `proj-2`), `../../hooks/useShellTerminals` (`useShellTerminals` → `{ data: shellsState, isSuccess: true }`, `useCloseShellTerminal` → `{ mutate: closeShell }`, `useRenameShellTerminal` → `{ mutate: vi.fn() }`), `../../hooks/useSessionReviewer` (→ `reviewerState.value`), `./SplitPane` (a stub rendering `data-testid={"pane-" + pane.id}`, the tab keys, `data-focused`, and buttons `focus`, `select <key>`, `close <key>`, `close pane` wired to its callbacks), and `../ui/resizable` (plain divs, recording `onLayoutChanged`). Use `vi.spyOn(operatorBridge.app, …)` for the shortcut hooks as in `SessionView.test.tsx`. Reset `useSplitLayoutStore.setState({ layout: EMPTY_LAYOUT })` and `window.localStorage.clear()` in `beforeEach`.

```tsx
it("opens the routed session and renders one pane", () => {
	render(<SplitWorkspace routeSessionId="a" />);
	expect(screen.getAllByTestId(/^pane-/)).toHaveLength(1);
	expect(screen.getByText("session:a")).toBeInTheDocument();
});

it("renders every pane of a split and navigates when another pane is focused", () => {
	useSplitLayoutStore.getState().openTab(s("a"));
	useSplitLayoutStore.getState().openTab(s("c"));
	const paneId = useSplitLayoutStore.getState().layout.focusedPaneId as string;
	useSplitLayoutStore.getState().splitPane(s("c"), paneId, "right");
	useSplitLayoutStore.getState().focusTab(s("a"));
	render(<SplitWorkspace routeSessionId="a" />);
	expect(screen.getAllByTestId(/^pane-/)).toHaveLength(2);
	fireEvent.click(within(paneContaining("session:c")).getByRole("button", { name: "focus" }));
	expect(navigateMock).toHaveBeenCalledWith({
		to: "/projects/$projectId/sessions/$sessionId",
		params: { projectId: "proj-2", sessionId: "c" },
	});
});

it("does not bounce the route back to a restored focus on mount", () => {
	useSplitLayoutStore.getState().openTab(s("b"));
	render(<SplitWorkspace routeSessionId="a" />);
	expect(navigateMock).not.toHaveBeenCalled();
	expect(useSplitLayoutStore.getState().layout.focusedPaneId).not.toBeNull();
	expect(screen.getByText(/session:a/)).toBeInTheDocument();
});

it("closes the focused tab with Cmd+W, a shell by closing the shell, and leaves for the kanban when empty", () => {
	shellsState.value = [{ handleId: "h1", sessionId: "a", workingDir: "/tmp", title: "zsh", createdAt: "t" }];
	const fire = captureShortcut("onCloseShellTerminalShortcut");
	render(<SplitWorkspace routeSessionId="a" />);
	useSplitLayoutStore.getState().focusTab({ kind: "shell", handleId: "h1", sessionId: "a" });
	act(() => fire());
	expect(closeShell).toHaveBeenCalledWith("h1");
	act(() => fire());
	expect(useSplitLayoutStore.getState().layout.root).toBeNull();
	expect(navigateMock).toHaveBeenLastCalledWith({ to: "/projects/$projectId", params: { projectId: "proj-1" }, replace: true });
});

it("cycles tabs of the focused pane with the tab shortcuts", () => {
	const next = captureShortcut("onNextTabShortcut");
	useSplitLayoutStore.getState().openTab(s("b"));
	render(<SplitWorkspace routeSessionId="a" />);
	act(() => next());
	expect(activeKey()).toBe("session:b");
});

it("adopts a session's shells and reviewer beside it", () => {
	shellsState.value = [{ handleId: "h1", sessionId: "a", workingDir: "/tmp", title: "zsh", createdAt: "t" }];
	reviewerState.value = { handleId: "r1", harness: "codex" };
	render(<SplitWorkspace routeSessionId="a" />);
	expect(listPanes(useSplitLayoutStore.getState().layout.root)[0].tabs.map(tabKey)).toEqual([
		"session:a",
		"shell:h1",
		"reviewer:r1",
	]);
});

it("prunes tabs whose session disappeared", () => {
	useSplitLayoutStore.getState().openTab(s("gone"));
	render(<SplitWorkspace routeSessionId="a" />);
	expect(listPanes(useSplitLayoutStore.getState().layout.root).flatMap((pane) => pane.tabs.map(tabKey))).toEqual(["session:a"]);
});

it("writes divider moves back to the layout", () => {
	useSplitLayoutStore.getState().openTab(s("a"));
	useSplitLayoutStore.getState().openTab(s("b"));
	useSplitLayoutStore.getState().splitPane(s("b"), useSplitLayoutStore.getState().layout.focusedPaneId as string, "right");
	render(<SplitWorkspace routeSessionId="a" />);
	const split = useSplitLayoutStore.getState().layout.root as Split;
	act(() => layoutChanged.value?.({ [split.children[0].id]: 30, [split.children[1].id]: 70 }));
	expect((useSplitLayoutStore.getState().layout.root as Split).sizes).toEqual([30, 70]);
});
```

  (`captureShortcut(name)` spies `operatorBridge.app[name]` and returns a function calling the captured listener; `paneContaining(text)` finds the `pane-*` stub containing the text; `activeKey()` reads the focused pane's active tab key from the store.)

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/renderer/components/split/SplitWorkspace.test.tsx`
Expected: FAIL — cannot resolve `./SplitWorkspace`.

- [ ] **Step 3: `SessionCompanions.tsx`**

```tsx
export function SessionCompanions({ session }: { session: WorkspaceSession }) {
	const shellsQuery = useShellTerminals();
	const reviewer = useSessionReviewer(session);
	const insertTabAfter = useSplitLayoutStore((state) => state.insertTabAfter);
	const closeTab = useSplitLayoutStore((state) => state.closeTab);
	const focusTab = useSplitLayoutStore((state) => state.focusTab);
	const requestedShell = useUiStore((state) => state.activeShellTerminalHandleId);
	const appliedShellRef = useRef<string | null>(null);
	const anchor = useMemo<TabRef>(() => ({ kind: "session", sessionId: session.id }), [session.id]);

	useEffect(() => {
		for (const shell of shellsQuery.data ?? []) {
			if (shell.sessionId !== session.id) continue;
			insertTabAfter({ kind: "shell", handleId: shell.handleId, sessionId: session.id }, anchor);
		}
	}, [anchor, insertTabAfter, session.id, shellsQuery.data]);

	useEffect(() => {
		const { layout } = useSplitLayoutStore.getState();
		for (const pane of listPanes(layout.root)) {
			for (const tab of pane.tabs) {
				if (tab.kind === "reviewer" && tab.sessionId === session.id && tab.handleId !== reviewer?.handleId) closeTab(tab);
			}
		}
		if (reviewer) insertTabAfter({ kind: "reviewer", sessionId: session.id, ...reviewer }, anchor);
	}, [anchor, closeTab, insertTabAfter, reviewer, session.id]);

	useEffect(() => {
		if (!requestedShell || appliedShellRef.current === requestedShell) return;
		const shell = (shellsQuery.data ?? []).find((candidate) => candidate.handleId === requestedShell);
		if (!shell || shell.sessionId !== session.id) return;
		appliedShellRef.current = requestedShell;
		focusTab({ kind: "shell", handleId: shell.handleId, sessionId: session.id });
	}, [focusTab, requestedShell, session.id, shellsQuery.data]);

	return null;
}
```

- [ ] **Step 4: `SplitWorkspace.tsx`**

```tsx
export function SplitWorkspace({ routeSessionId }: { routeSessionId: string }) {
	const navigate = useNavigate();
	const theme = useResolvedTheme();
	const { daemonStatus } = useShell();
	const workspaceQuery = useWorkspaceQuery();
	const shellsQuery = useShellTerminals();
	const closeShellTerminal = useCloseShellTerminal();
	const renameShellTerminal = useRenameShellTerminal();
	const layout = useSplitLayoutStore((state) => state.layout);
	const store = useSplitLayoutStore.getState;
	const setVisibleTerminalKind = useUiStore((state) => state.setVisibleTerminalKind);
	const clearVisibleTerminalKind = useUiStore((state) => state.clearVisibleTerminalKind);

	const sessions = useMemo(
		() => new Map((workspaceQuery.data ?? []).flatMap((workspace) => workspace.sessions.map((session) => [session.id, session] as const))),
		[workspaceQuery.data],
	);
	const shells = useMemo(
		() => new Map((shellsQuery.data ?? []).map((shell) => [shell.handleId, shell] as const)),
		[shellsQuery.data],
	);
	const panes = listPanes(layout.root);
	const focused = focusedPane(layout);
	const focusedSessionId = focused ? tabSessionId(activeTabOf(focused)) : undefined;

	useEffect(() => {
		const current = focusedPane(store().layout);
		if (current && tabSessionId(activeTabOf(current)) === routeSessionId) return;
		store().openTab({ kind: "session", sessionId: routeSessionId });
	}, [routeSessionId, store]);

	useEffect(() => {
		const current = focusedPane(store().layout);
		const sessionId = current ? tabSessionId(activeTabOf(current)) : undefined;
		if (!sessionId || sessionId === routeSessionId) return;
		const session = sessions.get(sessionId);
		if (!session) return;
		void navigate({ to: "/projects/$projectId/sessions/$sessionId", params: { projectId: session.workspaceId, sessionId } });
	}, [focusedSessionId, navigate, routeSessionId, sessions, store]);

	useEffect(() => {
		if (!workspaceQuery.isSuccess || !shellsQuery.isSuccess) return;
		store().pruneTabs((tab) => (tab.kind === "shell" ? shells.has(tab.handleId) : sessions.has(tab.sessionId)));
	}, [sessions, shells, shellsQuery.isSuccess, store, workspaceQuery.isSuccess]);

	useEffect(() => {
		const kinds = new Map<string, TerminalTarget["kind"]>();
		for (const pane of listPanes(layout.root)) {
			const tab = activeTabOf(pane);
			const sessionId = tabSessionId(tab);
			if (!sessionId || kinds.get(sessionId) === "worker") continue;
			kinds.set(sessionId, tab.kind === "session" ? "worker" : tab.kind);
		}
		for (const [sessionId, kind] of kinds) setVisibleTerminalKind(sessionId, kind);
		return () => {
			for (const sessionId of kinds.keys()) clearVisibleTerminalKind(sessionId);
		};
	}, [clearVisibleTerminalKind, layout, setVisibleTerminalKind]);

	const leaveIfEmpty = useCallback(
		(projectId: string | undefined) => {
			if (store().layout.root || !projectId) return;
			void navigate({ to: "/projects/$projectId", params: { projectId }, replace: true });
		},
		[navigate, store],
	);

	const closeTab = useCallback(
		(tab: TabRef) => {
			const sessionId = tabSessionId(tab);
			const projectId = sessionId ? sessions.get(sessionId)?.workspaceId : undefined;
			if (tab.kind === "shell") closeShellTerminal.mutate(tab.handleId);
			store().closeTab(tab);
			leaveIfEmpty(projectId);
		},
		[closeShellTerminal, leaveIfEmpty, sessions, store],
	);

	const closePane = useCallback(
		(pane: Pane) => {
			const sessionId = tabSessionId(activeTabOf(pane));
			const projectId = sessionId ? sessions.get(sessionId)?.workspaceId : undefined;
			store().closePane(pane.id);
			leaveIfEmpty(projectId);
		},
		[leaveIfEmpty, sessions, store],
	);

	useEffect(
		() =>
			operatorBridge.app.onCloseShellTerminalShortcut(() => {
				const current = focusedPane(store().layout);
				if (current) closeTab(activeTabOf(current));
			}),
		[closeTab, store],
	);

	useEffect(() => {
		operatorBridge.app.setCloseShellTerminalShortcutEnabled(true);
		return () => operatorBridge.app.setCloseShellTerminalShortcutEnabled(false);
	}, []);

	useEffect(() => {
		const disposePrevious = operatorBridge.app.onPreviousTabShortcut(() => store().cycleTab(-1));
		const disposeNext = operatorBridge.app.onNextTabShortcut(() => store().cycleTab(1));
		return () => {
			disposePrevious();
			disposeNext();
		};
	}, [store]);

	const sessionTabs = [...new Set(panes.flatMap((pane) => pane.tabs).filter((tab) => tab.kind === "session").map((tab) => tab.sessionId))];

	const renderNode = (node: LayoutNode): ReactNode => {
		if (node.type === "pane") {
			return (
				<SplitPane
					daemonReady={daemonStatus.state === "ready"}
					focused={node.id === layout.focusedPaneId}
					onClose={closeTab}
					onClosePane={() => closePane(node)}
					onFocus={() => store().focusPane(node.id)}
					onRenameShell={(handleId, title) => renameShellTerminal.mutate({ handleId, title })}
					onSelect={(tab) => store().focusTab(tab)}
					pane={node}
					sessions={sessions}
					shells={shells}
					showFocusRing={panes.length > 1 && node.id === layout.focusedPaneId}
					theme={theme}
					topLeft={isTopLeftPane(layout, node.id)}
					touchesTop={paneTouchesTop(layout, node.id)}
				/>
			);
		}
		const minSize = node.direction === "row" ? MIN_PANE_WIDTH : MIN_PANE_HEIGHT;
		return (
			<ResizablePanelGroup
				id={node.id}
				key={`${node.id}:${node.children.map((child) => child.id).join(",")}`}
				onLayoutChanged={(sizes) => store().resizeSplit(node.id, node.children.map((child) => sizes[child.id] ?? 0))}
				orientation={node.direction === "row" ? "horizontal" : "vertical"}
			>
				{node.children.map((child, index) => (
					<Fragment key={child.id}>
						{index > 0 ? <ResizableHandle /> : null}
						<ResizablePanel defaultSize={`${node.sizes[index]}%`} id={child.id} minSize={minSize} style={{ overflow: "hidden" }}>
							{renderNode(child)}
						</ResizablePanel>
					</Fragment>
				))}
			</ResizablePanelGroup>
		);
	};

	return (
		<div className="relative h-full min-h-0" data-testid="split-workspace">
			{sessionTabs.map((sessionId) => {
				const session = sessions.get(sessionId);
				return session ? <SessionCompanions key={sessionId} session={session} /> : null;
			})}
			{layout.root ? renderNode(layout.root) : null}
		</div>
	);
}
```

  Imports: `Fragment`, `useCallback`, `useEffect`, `useMemo`, `type ReactNode` from react; `useNavigate` from `@tanstack/react-router`; Task 1 helpers; `MIN_PANE_WIDTH`, `MIN_PANE_HEIGHT` from `../../lib/split-drop`; `ResizableHandle`, `ResizablePanel`, `ResizablePanelGroup` from `../ui/resizable`; `operatorBridge` from `../../lib/bridge`; `useShell` from `../../lib/shell-context`; `useResolvedTheme`, `useUiStore` from `../../stores/ui-store`; `TerminalTarget` type.

- [ ] **Step 5: Run the workspace tests**

Run: `npx vitest run src/renderer/components/split/SplitWorkspace.test.tsx`
Expected: PASS.

- [ ] **Step 6: Swap `SessionView` onto the workspace**
  - In `SessionView.tsx` replace the whole `<CenterPane … />` element with `<SplitWorkspace routeSessionId={sessionId} />`.
  - Delete everything that only fed `CenterPane`: `terminalTarget` state, `routedTerminalTarget`, `select*Terminal` callbacks, `sessionShells`, `appliedShellHandleRef`/`activeShellHandleId`, the open-session-tab state and handlers, `closeActiveTab`, `selectAdjacentTab`, and the shortcut effects (all now in `SplitWorkspace`), plus the `setVisibleTerminalKind` effect and the `sessionHeaderActions`/`ShellTopbar` embed.
  - Change `SessionInspector`'s `onOpenReviewerTerminal` to `(target) => useSplitLayoutStore.getState().openTab({ kind: "reviewer", sessionId, handleId: target.handleId, harness: target.harness })`.
  - Remove from `ui-store.ts` `openSessionTabsByProject`, `openSessionTab`, `closeSessionTab` (type, initial state and implementations).
  - In `_shell.tsx` delete the three `{routeParams.sessionId ? <SessionTopbarHost … /> : null}` blocks (in the `framedAppTopbar` branch keep `<ShellTopbar />` for non-session routes: `{routeParams.sessionId ? null : <ShellTopbar />}`) and remove `SessionTopbarProvider` from the tree and imports.
  - Delete `CenterPane.tsx`, `CenterPane.test.tsx`, `SessionTopbarPortal.tsx` (`git rm`). Run `grep -rn "CenterPane\|SessionTopbar" frontend/src` — expect no hits except `CenterPanelShell`.
  - `SessionView.test.tsx`: replace the `vi.mock("./CenterPane", …)` with `vi.mock("./split/SplitWorkspace", () => ({ SplitWorkspace: ({ routeSessionId }: { routeSessionId: string }) => <div data-testid="split-workspace">{routeSessionId}</div> }))`. Delete tests that exercised the moved tab/shell/reviewer/shortcut behaviour (each now has a `SplitWorkspace` test). Keep the inspector, preview and notFound tests green.

- [ ] **Step 7: Full suite, types, lint**

Run: `npx vitest run && npx tsc --noEmit -p tsconfig.json && npx eslint src/renderer/components/split src/renderer/components/SessionView.tsx src/renderer/routes/_shell.tsx src/renderer/stores/ui-store.ts`
Expected: green; no new lint warnings in `components/split`.

- [ ] **Step 8: Commit**

```bash
git add -A frontend/src/renderer/components/split frontend/src/renderer/components/SessionView.tsx frontend/src/renderer/components/SessionView.test.tsx frontend/src/renderer/routes/_shell.tsx frontend/src/renderer/stores/ui-store.ts
git rm -q frontend/src/renderer/components/CenterPane.tsx frontend/src/renderer/components/CenterPane.test.tsx frontend/src/renderer/components/SessionTopbarPortal.tsx
git commit -m "feat(split): SplitWorkspace renders the layout tree"
```

---

### Task 7: Drag and drop — one app context, overlay and preview

**Files:**
- Move: `frontend/src/renderer/components/tickets/TicketDndProvider.tsx` → `frontend/src/renderer/components/dnd/AppDndProvider.tsx` (and its test), `git mv`
- Create: `frontend/src/renderer/components/split/split-drag-store.ts`, `split-drag-handlers.ts`, `SplitDropOverlay.tsx`, `SplitDragPreview.tsx`
- Modify: every importer of `tickets/TicketDndProvider` (find with `grep -rln "TicketDndProvider" frontend/src`), `routes/_shell.tsx:17,600,685`, `components/Sidebar.tsx` (`SessionRow`)
- Test: `frontend/src/renderer/components/split/split-drag-handlers.test.ts`, `SplitDropOverlay.test.tsx`, `SplitDragPreview.test.tsx`, updated `dnd/AppDndProvider.test.tsx`

**Interfaces:**
- Consumes: `resolveDrop`, `sameResolution`, `readPaneGeometry`, `isSplitTabDragData`, layout store.
- Produces:
  - `useSplitDragStore`: `{ drag: SplitDrag | null; target: DropResolution | null; begin(drag): void; retarget(target): void; clear(): void }` with `type SplitDrag = { tab: TabRef; label: string; source: DraggedTab }`
  - `splitDragStart(event: DragStartEvent): boolean`, `splitDragMove(event: DragMoveEvent): void`, `splitDragEnd(event: DragEndEvent): boolean`, `splitDragCancel(): void` — each returns/acts only for split-tab payloads
  - `AppDndProvider` (was `TicketDndProvider`); `usePlanDraggable`, `useTicketDrag`, `useTicketDropTarget` keep their names and behaviour

- [ ] **Step 1: Write the failing handler tests** (`split-drag-handlers.test.ts`). Mock `./pane-registry` so `readPaneGeometry` maps each given pane id to `{ paneId, pane: { left: 0, top: 0, width: 1000, height: 800 }, strip: { left: 0, top: 0, width: 1000, height: 40 }, tabs: [{ left: 0, top: 0, width: 100, height: 40 }] }` (one tab, matching the seeded layout).

```ts
const s = (id: string): TabRef => ({ kind: "session", sessionId: id });
const start = (tab: TabRef, x: number, y: number) =>
	({ active: { id: "d", data: { current: { splitTab: { tab, label: "L" } } } }, activatorEvent: { clientX: x, clientY: y } }) as unknown as DragStartEvent;
const move = (tab: TabRef, x: number, y: number, dx: number, dy: number) =>
	({ active: { id: "d", data: { current: { splitTab: { tab, label: "L" } } } }, activatorEvent: { clientX: x, clientY: y }, delta: { x: dx, y: dy } }) as unknown as DragMoveEvent;

beforeEach(() => {
	window.localStorage.clear();
	useSplitLayoutStore.setState({ layout: EMPTY_LAYOUT });
	useSplitDragStore.getState().clear();
	useSplitLayoutStore.getState().openTab(s("a"));
});

it("ignores drags that are not split tabs", () => {
	expect(splitDragStart({ active: { id: "p", data: { current: { ticket: {}, plan: {} } } } } as never)).toBe(false);
	expect(useSplitDragStore.getState().drag).toBeNull();
});

it("records the dragged tab's source pane", () => {
	splitDragStart(start(s("a"), 10, 10));
	expect(useSplitDragStore.getState().drag?.source).toMatchObject({ index: 0, soleTab: true });
});

it("resolves a target from the pointer and splits on drop", () => {
	splitDragStart(start(s("b"), 0, 0));
	splitDragMove(move(s("b"), 0, 0, 900, 400));
	expect(useSplitDragStore.getState().target).toMatchObject({ kind: "split", edge: "right" });
	expect(splitDragEnd({ active: { data: { current: { splitTab: { tab: s("b"), label: "L" } } } } } as never)).toBe(true);
	expect(listPanes(useSplitLayoutStore.getState().layout.root)).toHaveLength(2);
	expect(useSplitDragStore.getState().drag).toBeNull();
});

it("moves into a pane from its centre", () => {
	splitDragStart(start(s("b"), 0, 0));
	splitDragMove(move(s("b"), 0, 0, 500, 400));
	splitDragEnd({ active: { data: { current: { splitTab: { tab: s("b"), label: "L" } } } } } as never);
	expect(listPanes(useSplitLayoutStore.getState().layout.root)[0].tabs).toEqual([s("a"), s("b")]);
});

it("does nothing on cancel or with no target", () => {
	splitDragStart(start(s("b"), 0, 0));
	splitDragCancel();
	expect(useSplitDragStore.getState().drag).toBeNull();
	splitDragStart(start(s("b"), 0, 0));
	splitDragMove(move(s("b"), 0, 0, 5000, 5000));
	splitDragEnd({ active: { data: { current: { splitTab: { tab: s("b"), label: "L" } } } } } as never);
	expect(listPanes(useSplitLayoutStore.getState().layout.root)).toHaveLength(1);
});

it("keeps the same target object while the pointer stays in one region", () => {
	splitDragStart(start(s("b"), 0, 0));
	splitDragMove(move(s("b"), 0, 0, 900, 400));
	const first = useSplitDragStore.getState().target;
	splitDragMove(move(s("b"), 0, 0, 910, 420));
	expect(useSplitDragStore.getState().target).toBe(first);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/renderer/components/split/split-drag-handlers.test.ts`
Expected: FAIL — missing modules.

- [ ] **Step 3: Implement the drag store and handlers**

`split-drag-store.ts`:

```ts
import { create } from "zustand";
import type { DraggedTab, DropResolution } from "../../lib/split-drop";
import type { TabRef } from "../../lib/split-layout";

export type SplitDrag = { tab: TabRef; label: string; source: DraggedTab };

type SplitDragState = {
	drag: SplitDrag | null;
	target: DropResolution | null;
	begin: (drag: SplitDrag) => void;
	retarget: (target: DropResolution | null) => void;
	clear: () => void;
};

export const useSplitDragStore = create<SplitDragState>((set) => ({
	drag: null,
	target: null,
	begin: (drag) => set({ drag, target: null }),
	retarget: (target) => set({ target }),
	clear: () => set({ drag: null, target: null }),
}));
```

`split-drag-handlers.ts`:

```ts
import type { DragEndEvent, DragMoveEvent, DragStartEvent } from "@dnd-kit/core";
import { resolveDrop, sameResolution } from "../../lib/split-drop";
import { listPanes, paneOfTab, sameTab } from "../../lib/split-layout";
import { useSplitLayoutStore } from "../../stores/split-layout-store";
import { readPaneGeometry } from "./pane-registry";
import { useSplitDragStore } from "./split-drag-store";
import { isSplitTabDragData } from "./useSplitTabDraggable";

type Activated = { activatorEvent: Event | null; active: { data: { current?: unknown } } };

function payload(event: { active: { data: { current?: unknown } } }) {
	const data = event.active.data.current;
	return isSplitTabDragData(data) ? data.splitTab : null;
}

function origin(event: Activated): { x: number; y: number } {
	const start = event.activatorEvent as { clientX?: number; clientY?: number } | null;
	return { x: start?.clientX ?? 0, y: start?.clientY ?? 0 };
}

export function splitDragStart(event: DragStartEvent): boolean {
	const data = payload(event);
	if (!data) return false;
	const layout = useSplitLayoutStore.getState().layout;
	const pane = paneOfTab(layout, data.tab);
	useSplitDragStore.getState().begin({
		tab: data.tab,
		label: data.label,
		source: {
			paneId: pane?.id ?? null,
			index: pane ? pane.tabs.findIndex((tab) => sameTab(tab, data.tab)) : null,
			soleTab: pane?.tabs.length === 1,
		},
	});
	return true;
}

export function splitDragMove(event: DragMoveEvent): void {
	const drag = useSplitDragStore.getState().drag;
	if (!drag || !payload(event)) return;
	const start = origin(event);
	const pointer = { x: start.x + event.delta.x, y: start.y + event.delta.y };
	const paneIds = listPanes(useSplitLayoutStore.getState().layout.root).map((pane) => pane.id);
	const next = resolveDrop(pointer, readPaneGeometry(paneIds), drag.source);
	const current = useSplitDragStore.getState().target;
	if (sameResolution(current, next)) return;
	useSplitDragStore.getState().retarget(next);
}

export function splitDragEnd(event: DragEndEvent): boolean {
	if (!payload(event)) return false;
	const { drag, target } = useSplitDragStore.getState();
	useSplitDragStore.getState().clear();
	if (!drag || !target) return true;
	const store = useSplitLayoutStore.getState();
	if (target.kind === "split") store.splitPane(drag.tab, target.paneId, target.edge);
	else store.moveTab(drag.tab, target.paneId, target.index);
	return true;
}

export function splitDragCancel(): void {
	useSplitDragStore.getState().clear();
}
```

  `sameResolution` keeps the store's target object while the region is unchanged, so the overlay only re-animates on a region change.

- [ ] **Step 4: Run the handler tests**

Run: `npx vitest run src/renderer/components/split/split-drag-handlers.test.ts`
Expected: PASS.

- [ ] **Step 5: Generalise the dnd context**
  - `git mv frontend/src/renderer/components/tickets/TicketDndProvider.tsx frontend/src/renderer/components/dnd/AppDndProvider.tsx` and the same for its `.test.tsx`; fix relative imports (`../../lib/…` → `../../lib/…` stays; `./AssignPlanSheet` → `../tickets/AssignPlanSheet`).
  - Rename the component to `AppDndProvider`. Add `onDragMove` and route every handler:

```tsx
	const onDragStart = (event: DragStartEvent) => {
		if (splitDragStart(event)) return;
		setActive(dragData(event));
	};
	const onDragMove = (event: DragMoveEvent) => splitDragMove(event);
	const onDragEnd = (event: DragEndEvent) => {
		if (splitDragEnd(event)) return;
		const data = dragData(event);
		setActive(null);
		if (!data || !event.over) return;
		if (dropAccepts(String(event.over.id), data)) setPending(data);
	};
	const onDragCancel = () => {
		splitDragCancel();
		setActive(null);
	};
```

  and render `<DragOverlay dropAnimation={null}>{active ? <PlanDragChip data={active} /> : <SplitDragPreview />}</DragOverlay>` plus `<SplitDropOverlay />` as a sibling after `{children}` inside the `DndContext`.
  - Update every importer (`grep -rln "TicketDndProvider" frontend/src`) to `components/dnd/AppDndProvider`; in `_shell.tsx` use `<AppDndProvider>`.
  - In `AppDndProvider.test.tsx` change only the import line and the component name; every existing ticket test must still pass unchanged.

- [ ] **Step 6: Overlay and preview** — failing tests first.

`SplitDropOverlay.test.tsx`:

```tsx
it("renders nothing without a target", () => {
	render(<SplitDropOverlay />);
	expect(screen.queryByTestId("split-drop-box")).toBeNull();
});

it("draws the inset box, blur and Split view pill for a split target", () => {
	useSplitDragStore.setState({ drag: dragOf(s("b")), target: { kind: "split", paneId: "p", edge: "right", box: { left: 500, top: 0, width: 500, height: 800 } } });
	render(<SplitDropOverlay />);
	const box = screen.getByTestId("split-drop-box");
	expect(box).toHaveStyle({ left: "508px", top: "8px", width: "484px", height: "784px" });
	expect(box.className).toContain("backdrop-blur");
	expect(screen.getByText("Split view")).toBeInTheDocument();
	expect(screen.getByTestId("split-drop-dim")).toBeInTheDocument();
});

it("labels a move target Open here", () => {
	useSplitDragStore.setState({ drag: dragOf(s("b")), target: { kind: "move", paneId: "p", index: 1, box: { left: 0, top: 0, width: 1000, height: 800 } } });
	render(<SplitDropOverlay />);
	expect(screen.getByText("Open here")).toBeInTheDocument();
});
```

  (`motion` renders its initial values synchronously with `initial={false}`, so `toHaveStyle` sees the target geometry.)

`SplitDropOverlay.tsx`:

```tsx
const BOX_INSET = 8;
const SLIDE = { duration: 0.12, ease: [0.33, 1, 0.68, 1] } as const;

export function SplitDropOverlay() {
	const { t } = useTranslation();
	const drag = useSplitDragStore((state) => state.drag);
	const target = useSplitDragStore((state) => state.target);
	if (!drag || !target) return null;
	const { box } = target;
	const geometry = {
		left: box.left + BOX_INSET,
		top: box.top + BOX_INSET,
		width: Math.max(0, box.width - BOX_INSET * 2),
		height: Math.max(0, box.height - BOX_INSET * 2),
	};
	return createPortal(
		<div aria-hidden="true" className="pointer-events-none fixed inset-0 z-overlay">
			<div className="absolute inset-0 bg-black/10" data-testid="split-drop-dim" />
			<motion.div
				animate={geometry}
				className="absolute flex items-center justify-center overflow-hidden rounded-xl border-2 border-accent/80 bg-background/10 backdrop-blur-[6px]"
				data-testid="split-drop-box"
				initial={false}
				style={geometry}
				transition={SLIDE}
			>
				<span className="rounded-full bg-accent px-3 py-1 text-control font-medium text-accent-foreground shadow-sm">
					{target.kind === "split" ? t("split.splitView") : t("split.openHere")}
				</span>
			</motion.div>
		</div>,
		document.body,
	);
}
```

  Check that the `z-overlay` utility exists (`grep -n "z-overlay\|--z-" src/renderer/styles.css`); if not, use the highest existing `z-*` token used by dialogs.

`SplitDragPreview.test.tsx`:

```tsx
it("shows the row label, then cross-fades to the chip over a target", () => {
	useSplitDragStore.setState({ drag: dragOf(s("b"), "beta"), target: null });
	const { rerender } = render(<SplitDragPreview />);
	expect(screen.getByTestId("split-drag-row")).toHaveClass("opacity-60");
	expect(screen.getByTestId("split-drag-chip")).toHaveClass("opacity-0");
	act(() => useSplitDragStore.setState({ target: { kind: "split", paneId: "p", edge: "right", box: { left: 0, top: 0, width: 1, height: 1 } } }));
	rerender(<SplitDragPreview />);
	expect(screen.getByTestId("split-drag-row")).toHaveClass("opacity-0");
	expect(screen.getByTestId("split-drag-chip")).toHaveClass("opacity-100");
	expect(screen.getByText("Open in split view")).toBeInTheDocument();
});
```

`SplitDragPreview.tsx`:

```tsx
export function SplitDragPreview() {
	const { t } = useTranslation();
	const drag = useSplitDragStore((state) => state.drag);
	const targeted = useSplitDragStore((state) => state.target !== null);
	if (!drag) return null;
	return (
		<div className="pointer-events-none relative">
			<div
				className={cn(
					"flex h-7 items-center gap-1.5 rounded-lg px-2.5 text-control text-foreground transition-opacity duration-[120ms]",
					targeted ? "opacity-0" : "opacity-60",
				)}
				data-testid="split-drag-row"
			>
				<span aria-hidden="true" className="size-1.5 shrink-0 rounded-full bg-passive" />
				<span className="max-w-56 truncate">{drag.label}</span>
			</div>
			<div
				className={cn(
					"absolute left-0 top-0 inline-flex h-7 items-center whitespace-nowrap rounded-lg border border-border bg-overlay px-2.5 text-control text-foreground shadow-md transition-opacity duration-[120ms]",
					targeted ? "opacity-100" : "opacity-0",
				)}
				data-testid="split-drag-chip"
			>
				{t("split.openInSplitView")}
			</div>
		</div>
	);
}
```

- [ ] **Step 7: Sidebar rows become drag sources** — in `Sidebar.tsx` `SessionRow`, call `const drag = useSplitTabDraggable({ kind: "session", sessionId: session.id }, session.title, "sidebar");` and on the `data-session-row` `<div>` add `ref={drag.setNodeRef}` and `{...drag.listeners}`. Add a Sidebar test: rendering a `SessionRow` inside `AppDndProvider` keeps the open button clickable (`onOpen` fires on click) — the 4px activation distance means a click never starts a drag.

- [ ] **Step 8: Run**

Run: `npx vitest run src/renderer/components/split src/renderer/components/dnd src/renderer/components/Sidebar.test.tsx && npx vitest run && npx tsc --noEmit -p tsconfig.json`
Expected: green, including every pre-existing ticket drag test.

- [ ] **Step 9: Commit**

```bash
git add -A frontend/src/renderer/components/dnd frontend/src/renderer/components/tickets frontend/src/renderer/components/split frontend/src/renderer/components/Sidebar.tsx frontend/src/renderer/components/Sidebar.test.tsx frontend/src/renderer/routes/_shell.tsx
git commit -m "feat(split): drag tabs and sessions to split, Claude Code overlay"
```

---

### Task 8: Sidebar shows every visible session

**Files:**
- Modify: `frontend/src/renderer/components/Sidebar.tsx` (selection at 129–137; `SessionRow` callers at 285–289 and 724–728)
- Test: `frontend/src/renderer/components/Sidebar.test.tsx`

**Interfaces:**
- Consumes: layout store.
- Produces: `useVisibleSessionIds(): Set<string>` (exported from `Sidebar.tsx`), the sessions shown as the active tab of some pane, empty when the route is not a session route.

- [ ] **Step 1: Failing test** — seed the layout store with a two-pane split (`a` | `b`), render the sidebar on the `a` session route, and assert both rows' open buttons carry `aria-current="page"`; on the project board route neither does.

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/renderer/components/Sidebar.test.tsx`
Expected: the new test FAILS (only `a` is current).

- [ ] **Step 3: Implement**

```ts
export function useVisibleSessionIds(routeSessionId: string | undefined): Set<string> {
	const layout = useSplitLayoutStore((state) => state.layout);
	return useMemo(() => {
		if (!routeSessionId) return new Set<string>();
		const ids = listPanes(layout.root)
			.map((pane) => tabSessionId(activeTabOf(pane)))
			.filter((id): id is string => Boolean(id));
		return new Set([routeSessionId, ...ids]);
	}, [layout, routeSessionId]);
}
```

  Call it once in the component that owns `selection` with `selection.activeSessionId` and pass `active={visibleSessionIds.has(session.id)}` at both `SessionRow` call sites.

- [ ] **Step 4: Run and commit**

Run: `npx vitest run src/renderer/components/Sidebar.test.tsx && npx vitest run && npx tsc --noEmit -p tsconfig.json`
Expected: green.

```bash
git add frontend/src/renderer/components/Sidebar.tsx frontend/src/renderer/components/Sidebar.test.tsx
git commit -m "feat(split): highlight every session shown in a pane"
```

---

### Task 9: Real-app verification against the recording, and TERMINAL.md

**Files:**
- Modify: `TERMINAL.md` (§1 pipeline: the cache now keeps one live terminal per pane slot; §3: "one place per terminal" is enforced by the layout invariant and a dev assertion in `activate`)

- [ ] **Step 1: Browser pass** — follow memory `verify-renderer-in-browser-against-isolated-daemon`: build the daemon, start it isolated on 39311, create a throwaway project with **two real sessions**, serve the renderer with `OPERATOR_DEV_API_TARGET`, open `http://127.0.0.1:<port>` (hash routes). Then, by real pointer drags in the browser pane (`computer` `left_click_drag`):
  1. drag sidebar session B to the right half of A → two panes, equal, 1px divider, B focused with the blue ring;
  2. drag a tab to the bottom half of the right pane → three panes;
  3. drag a tab onto another pane's strip between two tabs → lands at the caret;
  4. drag a divider → both terminals reflow live; the network log shows **one** resize per pty after release;
  5. Cmd+W on each pane until empty → kanban;
  6. reload → the layout is restored.
  Take a screenshot after each step.

- [ ] **Step 2: Motion comparison** — record the Operator window at 120fps (`⌘⇧5`) doing the same drag as the reference (`video/Screen Recording 2026-09-22 at 10.13.17 PM.mov`, 0.5–5.2s). Extract frames with `ffmpeg -ss <t> -t 1 -i <mov> -vf fps=60,scale=1400:-1` and measure the box's left edge per frame with the same hue test used for the spec (a pixel is outline if `b > r + 18 and b > 70`). Pass criteria: slide completes in 100–140ms with the leftmost third of the distance covered in the first frame; no fade frames; drop changes layout within one frame; no terminal flicker, blank frame or duplicated transcript. Tune `backdrop-blur-[6px]`, `bg-black/10` and `BOX_INSET` against the reference frames `assets/2026-09-22-split-view/03-target-box-blur-pill.jpg` and `01-drag-row-ghost.jpg`, then re-run Task 7's tests.

- [ ] **Step 3: Tauri pass** — per RUN_APP_COMMANDS.md and memory `scrub-claude-env-before-running-operator-dev`, run `npm run tauri:dev` with the scrubbed env, repeat Step 1's 1–5 with Claude Code sessions, and confirm per TERMINAL.md §6 that each pane's agent keeps its transcript after splits, moves and divider drags.

- [ ] **Step 4: TERMINAL.md** — update §1 and §3 as listed under **Files**, citing `TerminalPane.tsx` `activeSlotsRef`.

- [ ] **Step 5: Final gates and commit**

Run: `npx vitest run && npx tsc --noEmit -p tsconfig.json && npx eslint src/renderer`
Expected: green, no new warnings.

```bash
git add TERMINAL.md frontend/src/renderer/components/split
git commit -m "docs(terminal): several live panes; split view verified against Claude Code"
```
