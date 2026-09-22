import { describe, expect, it } from "vitest";
import { paintBoxes, rangeBoxes } from "./decorations";
import type { RenderedRow } from "./selection-view";

function row(rowNumber: number, top: number): RenderedRow {
	const element = document.createElement("div");
	return { element, box: { blockId: "b", row: rowNumber, firstRow: 0, rowCount: 3, left: 100, top, bottom: top + 20, width: 400 } };
}

describe("rangeBoxes", () => {
	it("cuts the first and last rows by cell and covers whole rows between, in container coordinates", () => {
		const container = document.createElement("div");
		container.getBoundingClientRect = () => ({ left: 90, top: 40, right: 690, bottom: 640, width: 600, height: 600, x: 90, y: 40, toJSON: () => ({}) }) as DOMRect;
		Object.defineProperty(container, "scrollTop", { value: 300, configurable: true });
		Object.defineProperty(container, "scrollLeft", { value: 0, configurable: true });
		const rows = [row(0, 50), row(1, 70), row(2, 90)];
		const boxes = rangeBoxes({ blockId: "b", startRow: 0, startCell: 2, endRow: 2, endCell: 3 }, rows, 10, container);
		expect(boxes).toEqual([
			{ left: 30, top: 310, width: 380, height: 20 },
			{ left: 10, top: 330, width: 400, height: 20 },
			{ left: 10, top: 350, width: 30, height: 20 },
		]);
	});
	it("returns nothing for a row that is not rendered", () => {
		const container = document.createElement("div");
		expect(rangeBoxes({ blockId: "b", startRow: 7, startCell: 0, endRow: 7, endCell: 1 }, [row(0, 0)], 10, container)).toEqual([]);
	});
});

describe("paintBoxes", () => {
	it("reuses elements, sets geometry and labels, and removes the surplus", () => {
		const layer = document.createElement("div");
		paintBoxes(layer, "terminal-link-underline", [{ left: 1, top: 2, width: 3, height: 4 }, { left: 5, top: 6, width: 7, height: 8 }]);
		expect(layer.children).toHaveLength(2);
		const first = layer.children[0] as HTMLElement;
		expect(first.className).toBe("terminal-link-underline");
		expect(first.style.left).toBe("1px");
		expect(first.style.width).toBe("3px");
		paintBoxes(layer, "terminal-hint-label", [{ left: 0, top: 0, width: 10, height: 20 }], ["as"]);
		expect(layer.children).toHaveLength(1);
		expect(layer.children[0]).toBe(first);
		expect(first.className).toBe("terminal-hint-label");
		expect(first.textContent).toBe("as");
	});
});
