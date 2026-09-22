import type { DragMoveEvent, DragStartEvent } from "@dnd-kit/core";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { EMPTY_LAYOUT, listPanes, type TabRef } from "../../lib/split-layout";
import { useSplitLayoutStore } from "../../stores/split-layout-store";

vi.mock("./pane-registry", () => ({
	readPaneGeometry: (paneIds: string[]) =>
		paneIds.map((paneId) => ({
			paneId,
			pane: { left: 0, top: 0, width: 1000, height: 800 },
			strip: { left: 0, top: 0, width: 1000, height: 40 },
			tabs: [{ left: 0, top: 0, width: 100, height: 40 }],
		})),
}));

import { splitDragCancel, splitDragEnd, splitDragMove, splitDragStart } from "./split-drag-handlers";
import { useSplitDragStore } from "./split-drag-store";

const s = (id: string): TabRef => ({ kind: "session", sessionId: id });
const start = (tab: TabRef, x: number, y: number) =>
	({ active: { id: "d", data: { current: { splitTab: { tab, label: "L" } } } }, activatorEvent: { clientX: x, clientY: y } }) as unknown as DragStartEvent;
const move = (tab: TabRef, x: number, y: number, dx: number, dy: number) =>
	({
		active: { id: "d", data: { current: { splitTab: { tab, label: "L" } } } },
		activatorEvent: { clientX: x, clientY: y },
		delta: { x: dx, y: dy },
	}) as unknown as DragMoveEvent;

beforeEach(() => {
	window.localStorage.clear();
	useSplitLayoutStore.setState({ layout: EMPTY_LAYOUT });
	useSplitDragStore.getState().clear();
	useSplitLayoutStore.getState().openTab(s("a"));
});

describe("split-drag-handlers", () => {
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
});
