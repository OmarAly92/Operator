import { useDraggable } from "@dnd-kit/core";
import { tabKey, type TabRef } from "../../lib/split-layout";

export type SplitTabDragData = { splitTab: { tab: TabRef; label: string } };

export function isSplitTabDragData(value: unknown): value is SplitTabDragData {
	return typeof value === "object" && value !== null && "splitTab" in value;
}

export function useSplitTabDraggable(tab: TabRef, label: string, origin: "strip" | "sidebar" | "sidebar-pinned") {
	const { setNodeRef, listeners, isDragging } = useDraggable({
		id: `split-tab:${origin}:${tabKey(tab)}`,
		data: { splitTab: { tab, label } } satisfies SplitTabDragData,
	});
	return { setNodeRef, listeners, isDragging };
}
