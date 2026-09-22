import { act, fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { EMPTY_LAYOUT, listPanes, type TabRef } from "../../lib/split-layout";
import { useSplitLayoutStore } from "../../stores/split-layout-store";
import { AppDndProvider } from "../dnd/AppDndProvider";
import { useSplitDragStore } from "./split-drag-store";
import { SplitPane } from "./SplitPane";

vi.mock("../tickets/AssignPlanSheet", () => ({
	AssignPlanSheet: () => null,
}));

vi.mock("./PaneTerminal", () => ({
	PaneTerminal: () => <div data-testid="terminal-stub" />,
	terminalTargetForTab: () => ({ kind: "worker" }) as const,
}));

function stubRect(element: Element, rect: { left: number; top: number; width: number; height: number }): void {
	vi.spyOn(element, "getBoundingClientRect").mockReturnValue({
		...rect,
		right: rect.left + rect.width,
		bottom: rect.top + rect.height,
		x: rect.left,
		y: rect.top,
		toJSON: () => ({}),
	} as DOMRect);
}

const noop = () => undefined;

function renderPanes() {
	const panes = listPanes(useSplitLayoutStore.getState().layout.root);
	return render(
		<AppDndProvider>
			{panes.map((pane, index) => (
				<SplitPane
					key={pane.id}
					daemonReady
					focused={index === 0}
					onClose={noop}
					onClosePane={noop}
					onFocus={noop}
					onRenameShell={noop}
					onSelect={noop}
					pane={pane}
					sessions={new Map()}
					shells={new Map()}
					showFocusRing={false}
					theme="dark"
					topLeft={index === 0}
					touchesTop={false}
				/>
			))}
		</AppDndProvider>,
	);
}

function s(id: string): TabRef {
	return { kind: "session", sessionId: id };
}

beforeEach(() => {
	window.localStorage.clear();
	useSplitLayoutStore.setState({ layout: EMPTY_LAYOUT });
	useSplitDragStore.getState().clear();
});

describe("split-tab drag, end to end through AppDndProvider", () => {
	it("drags a tab from one pane onto the right edge of the other and splits it there", () => {
		useSplitLayoutStore.getState().openTab(s("a"));
		const firstPaneId = useSplitLayoutStore.getState().layout.focusedPaneId as string;
		useSplitLayoutStore.getState().splitPane(s("b"), firstPaneId, "right");

		renderPanes();

		const paneElements = screen
			.getAllByRole("tablist", { name: "Open terminals" })
			.map((tablist) => tablist.closest("[data-split-pane]") as HTMLElement);
		expect(paneElements).toHaveLength(2);
		stubRect(paneElements[0], { left: 0, top: 0, width: 800, height: 800 });
		stubRect(paneElements[1], { left: 800, top: 0, width: 800, height: 800 });

		const sourceTab = screen.getAllByRole("tab", { name: "No session" })[0];
		const handle = sourceTab.closest("[data-split-tab]") as HTMLElement;
		expect(handle).not.toBeNull();

		act(() => {
			fireEvent.pointerDown(handle, { pointerId: 1, isPrimary: true, button: 0, clientX: 100, clientY: 20 });
			fireEvent.pointerMove(handle, { pointerId: 1, isPrimary: true, clientX: 200, clientY: 40 });
			fireEvent.pointerMove(handle, { pointerId: 1, isPrimary: true, clientX: 1500, clientY: 400 });
		});
		expect(useSplitDragStore.getState().target).toEqual({
			kind: "split",
			paneId: expect.any(String),
			edge: "right",
			box: { left: 1200, top: 0, width: 400, height: 800 },
		});

		act(() => {
			fireEvent.pointerUp(handle, { pointerId: 1, isPrimary: true, clientX: 1500, clientY: 400 });
		});

		expect(useSplitDragStore.getState().drag).toBeNull();
		expect(useSplitDragStore.getState().target).toBeNull();

		const finalPanes = listPanes(useSplitLayoutStore.getState().layout.root);
		expect(finalPanes).toHaveLength(2);
		const bPane = finalPanes.find((pane) => pane.tabs.some((tab) => tab.kind === "session" && tab.sessionId === "b"));
		expect(bPane?.tabs).toEqual([{ kind: "session", sessionId: "b" }]);
		const movedPane = finalPanes.find((pane) => pane.tabs.some((tab) => tab.kind === "session" && tab.sessionId === "a"));
		expect(movedPane?.tabs).toEqual([{ kind: "session", sessionId: "a" }]);
		expect(movedPane?.id).not.toBe(firstPaneId);
		expect(movedPane?.id).not.toBe(bPane?.id);
		expect(finalPanes.map((pane) => pane.id)).toEqual([bPane?.id, movedPane?.id]);
	});
});
