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
