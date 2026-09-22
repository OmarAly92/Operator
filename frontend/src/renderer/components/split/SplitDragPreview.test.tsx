import { act, render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import type { TabRef } from "../../lib/split-layout";
import { useSplitDragStore, type SplitDrag } from "./split-drag-store";
import { SplitDragPreview } from "./SplitDragPreview";

const s = (id: string): TabRef => ({ kind: "session", sessionId: id });
const dragOf = (tab: TabRef, label = "L"): SplitDrag => ({
	tab,
	label,
	source: { paneId: "p", index: 0, soleTab: true },
});

describe("SplitDragPreview", () => {
	it("shows the row label, then cross-fades to the chip over a target", () => {
		useSplitDragStore.setState({ drag: dragOf(s("b"), "beta"), target: null });
		const { rerender } = render(<SplitDragPreview />);
		expect(screen.getByTestId("split-drag-row")).toHaveClass("opacity-60");
		expect(screen.getByTestId("split-drag-chip")).toHaveClass("opacity-0");
		act(() =>
			useSplitDragStore.setState({
				target: { kind: "split", paneId: "p", edge: "right", box: { left: 0, top: 0, width: 1, height: 1 } },
			}),
		);
		rerender(<SplitDragPreview />);
		expect(screen.getByTestId("split-drag-row")).toHaveClass("opacity-0");
		expect(screen.getByTestId("split-drag-chip")).toHaveClass("opacity-100");
		expect(screen.getByText("Open in split view")).toBeInTheDocument();
	});
});
