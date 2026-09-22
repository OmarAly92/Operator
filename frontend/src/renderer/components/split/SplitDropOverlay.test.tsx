import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import type { TabRef } from "../../lib/split-layout";
import { useSplitDragStore, type SplitDrag } from "./split-drag-store";
import { SplitDropOverlay } from "./SplitDropOverlay";

const s = (id: string): TabRef => ({ kind: "session", sessionId: id });
const dragOf = (tab: TabRef, label = "L"): SplitDrag => ({
	tab,
	label,
	source: { paneId: "p", index: 0, soleTab: true },
});

describe("SplitDropOverlay", () => {
	it("renders nothing without a drag", () => {
		render(<SplitDropOverlay />);
		expect(screen.queryByTestId("split-drop-dim")).toBeNull();
		expect(screen.queryByTestId("split-drop-box")).toBeNull();
	});

	it("dims the window for the whole drag, before a target resolves", () => {
		useSplitDragStore.setState({ drag: dragOf(s("b")), target: null });
		render(<SplitDropOverlay />);
		expect(screen.getByTestId("split-drop-dim")).toBeInTheDocument();
		expect(screen.queryByTestId("split-drop-box")).toBeNull();
	});

	it("draws the inset box, blur and Split view pill for a split target", () => {
		useSplitDragStore.setState({
			drag: dragOf(s("b")),
			target: { kind: "split", paneId: "p", edge: "right", box: { left: 500, top: 0, width: 500, height: 800 } },
		});
		render(<SplitDropOverlay />);
		const box = screen.getByTestId("split-drop-box");
		expect(box).toHaveStyle({ left: "508px", top: "8px", width: "484px", height: "784px" });
		expect(box.className).toContain("backdrop-blur");
		expect(screen.getByText("Split view")).toBeInTheDocument();
		expect(screen.getByTestId("split-drop-dim")).toBeInTheDocument();
	});

	it("labels a move target Open here", () => {
		useSplitDragStore.setState({
			drag: dragOf(s("b")),
			target: { kind: "move", paneId: "p", index: 1, box: { left: 0, top: 0, width: 1000, height: 800 } },
		});
		render(<SplitDropOverlay />);
		expect(screen.getByText("Open here")).toBeInTheDocument();
	});
});
