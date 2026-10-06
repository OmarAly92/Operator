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
