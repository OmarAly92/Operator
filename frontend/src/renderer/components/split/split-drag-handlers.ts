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
